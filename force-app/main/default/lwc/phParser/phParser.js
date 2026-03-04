// Lightweight parser for Apex debug log bodies (Tooling API ApexLog/Body).
//
// Heuristic focus:
// - SOQL occurrences: SOQL_EXECUTE_BEGIN/END pairing, rows, and duration from log ticks.
// - Governor usage: CPU, SOQL count/time, heap, DML, callouts (from limit usage lines).
// - Transaction signature: first METHOD_ENTRY or CODE_UNIT_STARTED.

const RE_SOQL_BEGIN = /\((\d+)\)\|SOQL_EXECUTE_BEGIN\|\[(\d+)\]\|.*\|(SELECT[\s\S]+)$/i;
const RE_SOQL_END = /\((\d+)\)\|SOQL_EXECUTE_END\|\[(\d+)\]\|Rows:(\d+)/i;

const RE_CPU = /CPU time:\s*(\d+)/i;
const RE_SOQL_COUNT = /Number of SOQL queries:\s*(\d+)/i;
const RE_DML_COUNT = /Number of DML statements:\s*(\d+)/i;
const RE_CALLOUT_COUNT = /Number of callouts:\s*(\d+)/i;
const RE_HEAP = /Maximum heap size:\s*(\d+)/i;
const RE_SOQL_TIME = /SOQL query time:\s*(\d+)/i;
const RE_SOQL_ROWS = /Number of query rows:\s*(\d+)/i;

const RE_CODE_UNIT = /\|CODE_UNIT_STARTED\|\[[^\]]*\]\|([^\|]+)$/i;
const RE_METHOD_ENTRY = /\|METHOD_ENTRY\|\[[^\]]*\]\|([^\|]+)$/i;

function normalizeSoql(soql) {
    let s = String(soql || '').trim();
    s = s.replace(/\s+/g, ' ').trim();

    // Replace literals
    s = s.replace(/'([^']|'')*'/g, "'?'")
         .replace(/\b\d+(?:\.\d+)?\b/g, "?");

    // Replace SF IDs
    s = s.replace(/\b[a-zA-Z0-9]{15,18}\b/g, "?");

    // Normalize IN lists
    s = s.replace(/\bIN\s*\(([^\)]*)\)/gi, "IN (?)");

    s = s.toLowerCase().replace(/\s+/g, ' ').trim();
    return s;
}

function hash8(str) {
    // Deterministic small hash (non-crypto).
    let h = 0;
    for (let i = 0; i < str.length; i++) {
        h = ((h << 5) - h) + str.charCodeAt(i);
        h |= 0;
    }
    return (h >>> 0).toString(16).padStart(8, '0');
}

function extractSobject(soql) {
    const m = /\bfrom\s+([a-zA-Z0-9_\.]+)\b/i.exec(soql || '');
    return m ? m[1] : null;
}

function extractWhereFields(soql) {
    const s = String(soql || '');
    const whereIdx = s.toLowerCase().indexOf(' where ');
    if (whereIdx < 0) return [];

    const where = s.slice(whereIdx + 7);
    const re = /\b([a-zA-Z0-9_\.]+)\s*(=|<|>|<=|>=|!=|like|in)\b/gi;
    const fields = new Set();
    let m;
    while ((m = re.exec(where))) {
        const f = m[1];
        if (!f || f.startsWith(':')) continue;
        fields.add(f);
    }
    return Array.from(fields).slice(0, 12);
}

function ticksToMs(deltaTicks) {
    // Heuristic: ticks are usually nanoseconds. If absurdly large, assume microseconds.
    const msNano = deltaTicks / 1e6;
    if (msNano > 10 * 60 * 1000) return Math.round(deltaTicks / 1e3);
    return Math.round(msNano);
}

export function parseApexLogBody(bodyText, context = {}) {
    const text = String(bodyText || '');
    const lines = text.split(/\r?\n/);

    const beginById = new Map();
    const queries = [];

    let entryPoint = null;
    let signature = null;

    let cpuMs = null;
    let soqlCount = null;
    let soqlMs = null;
    let heapBytes = null;
    let dmlCount = null;
    let calloutCount = null;
    let rowsTotal = null;

    for (const line of lines) {
        if (!entryPoint) {
            const cu = RE_CODE_UNIT.exec(line);
            if (cu) entryPoint = cu[1].trim();
        }
        if (!signature) {
            const me = RE_METHOD_ENTRY.exec(line);
            if (me) signature = me[1].trim();
        }

        const c = RE_CPU.exec(line); if (c) cpuMs = Number(c[1]);
        const sc = RE_SOQL_COUNT.exec(line); if (sc) soqlCount = Number(sc[1]);
        const st = RE_SOQL_TIME.exec(line); if (st) soqlMs = Number(st[1]);
        const hb = RE_HEAP.exec(line); if (hb) heapBytes = Number(hb[1]);
        const dc = RE_DML_COUNT.exec(line); if (dc) dmlCount = Number(dc[1]);
        const cc = RE_CALLOUT_COUNT.exec(line); if (cc) calloutCount = Number(cc[1]);
        const rt = RE_SOQL_ROWS.exec(line); if (rt) rowsTotal = Number(rt[1]);

        const b = RE_SOQL_BEGIN.exec(line);
        if (b) {
            const tick = Number(b[1]);
            const id = b[2];
            const soql = b[3]?.trim();
            beginById.set(id, { tick, soql });
            continue;
        }

        const e = RE_SOQL_END.exec(line);
        if (e) {
            const tickEnd = Number(e[1]);
            const id = e[2];
            const rows = Number(e[3]);
            const begin = beginById.get(id);

            if (begin?.soql) {
                const durationMs = ticksToMs(tickEnd - begin.tick);
                const fingerprint = normalizeSoql(begin.soql);
                const fingerprintHash = hash8(fingerprint);

                const sobjectName = extractSobject(begin.soql);
                const fields = extractWhereFields(begin.soql);

                queries.push({
                    soqlText: begin.soql,
                    normalized: fingerprint,
                    fingerprintHash,
                    sobjectName,
                    fields,
                    durationMs,
                    rows
                });
            }
            beginById.delete(id);
        }
    }

    const fallback = signature || entryPoint || context.operation || 'Transaction';

    return {
        transaction: {
            entryPoint: entryPoint || fallback,
            signature: signature || entryPoint || fallback,
            cpuMs: cpuMs ?? 0,
            soqlCount: soqlCount ?? queries.length,
            soqlMs: soqlMs ?? sum(queries.map(q => q.durationMs)),
            heapBytes: heapBytes ?? 0,
            dmlCount: dmlCount ?? 0,
            calloutCount: calloutCount ?? 0,
            rowsTotal: rowsTotal ?? sum(queries.map(q => q.rows))
        },
        queries
    };
}

function sum(arr) {
    return (arr || []).reduce((a, b) => a + (Number(b) || 0), 0);
}
