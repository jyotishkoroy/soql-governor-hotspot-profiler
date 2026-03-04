import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getSummary from '@salesforce/apex/PH_AppController.getSummary';
import getDashboard from '@salesforce/apex/PH_AppController.getDashboard';
import startRun from '@salesforce/apex/PH_AppController.startRun';
import ingestBatch from '@salesforce/apex/PH_AppController.ingestBatch';
import finishRun from '@salesforce/apex/PH_AppController.finishRun';
import searchUsers from '@salesforce/apex/PH_AppController.searchUsers';
import searchTransactions from '@salesforce/apex/PH_AppController.searchTransactions';
import getTransactionQueries from '@salesforce/apex/PH_AppController.getTransactionQueries';
import getAlertRules from '@salesforce/apex/PH_AppController.getAlertRules';
import upsertAlertRule from '@salesforce/apex/PH_AppController.upsertAlertRule';
import runAlertEvaluationNow from '@salesforce/apex/PH_AppController.runAlertEvaluationNow';
import scheduleNightlyAlerts from '@salesforce/apex/PH_AppController.scheduleNightlyAlerts';

import { parseApexLogBody } from 'c/phParser';

const API_VERSION = '55.0';

const MODE_OPTIONS = [
    { label: 'Light (sample recent logs)', value: 'Light' },
    { label: 'Deep (trace + collect)', value: 'Deep' }
];

const WINDOW_OPTIONS = [
    { label: '1 day', value: '1' },
    { label: '3 days', value: '3' },
    { label: '7 days', value: '7' },
    { label: '30 days', value: '30' }
];

const RULE_TYPE_OPTIONS = [
    { label: 'Query', value: 'Query' },
    { label: 'Transaction', value: 'Transaction' }
];

const RULE_METRIC_OPTIONS = [
    { label: 'AvgMs', value: 'AvgMs' },
    { label: 'P95Ms', value: 'P95Ms' },
    { label: 'AvgCpu', value: 'AvgCpu' },
    { label: 'P95Cpu', value: 'P95Cpu' },
    { label: 'Count', value: 'Count' }
];

export default class PhApp extends LightningElement {
    @track summary;
    @track dashboard;

    busy = false;
    progress = 0;
    progressLabel = '';

    mode = 'Light';
    windowDays = '1';
    maxLogs = 200;

    dashboardDays = 7;

    userSearch = '';
    @track userSuggestions = [];
    pickedUser = null;

    // Explorer
    expStartDate = null;
    expEndDate = null;
    expUserSearch = '';
    expUserId = null;
    @track expUserSuggestions = [];
    @track explorerRows = [];
    @track selectedTxnQueries = [];

    // Alert rules
    @track alertRules = [];
    ruleName = 'High Avg SOQL (ms)';
    ruleType = 'Query';
    ruleMetric = 'AvgMs';
    ruleThreshold = 50;
    ruleWindowDays = '7';
    ruleEnabled = true;

    connectedCallback() {
        this.bootstrap();
    }

    async bootstrap() {
        await this.refreshSummary();
        await this.refreshDashboard();
        await this.loadAlertRules();
    }

    get modeOptions() { return MODE_OPTIONS; }
    get windowOptions() { return WINDOW_OPTIONS; }
    get ruleTypeOptions() { return RULE_TYPE_OPTIONS; }
    get ruleMetricOptions() { return RULE_METRIC_OPTIONS; }

    get windowLabel() {
        const o = WINDOW_OPTIONS.find(x => x.value === this.windowDays);
        return o ? o.label : `${this.windowDays} days`;
    }

    get traceDisabled() {
        return this.busy || this.mode !== 'Deep' || !this.pickedUser;
    }

    // ===== Simple actions =====
    async refreshSummary() {
        try {
            this.summary = await getSummary();
        } catch (e) {
            this.toast('Error', this.humanError(e), 'error');
        }
    }

    async refreshDashboard() {
        try {
            const d = await getDashboard({ days: this.dashboardDays });
            d.recentAlerts = (d.recentAlerts || []).map(a => {
                const sev = (a.severity || 'INFO').toLowerCase();
                return { ...a, className: `alertRow ${sev}` };
            });
            this.dashboard = d;
        } catch (e) {
            this.toast('Error', this.humanError(e), 'error');
        }
    }

    // ===== UI Handlers =====
    handleMode(e) { this.mode = e.detail.value; }
    handleWindow(e) { this.windowDays = e.detail.value; }
    handleMaxLogs(e) { this.maxLogs = Number(e.target.value) || 200; }

    handleUserSearch(e) { this.userSearch = e.target.value; }
    async handleUserKeyUp() {
        const term = (this.userSearch || '').trim();
        if (term.length < 2) { this.userSuggestions = []; return; }
        try {
            this.userSuggestions = await searchUsers({ term });
        } catch {
            // ignore while typing
        }
    }
    pickUser(e) {
        const id = e.currentTarget.dataset.id;
        const name = e.currentTarget.dataset.name;
        const u = (this.userSuggestions || []).find(x => x.id === id);
        this.pickedUser = { id, name, username: u?.username };
        this.userSuggestions = [];
    }
    clearPickedUser() { this.pickedUser = null; }

    // Explorer
    handleExpStart(e) { this.expStartDate = e.target.value; }
    handleExpEnd(e) { this.expEndDate = e.target.value; }
    handleExpUserSearch(e) { this.expUserSearch = e.target.value; }
    async handleExpUserKeyUp() {
        const term = (this.expUserSearch || '').trim();
        if (term.length < 2) { this.expUserSuggestions = []; return; }
        try {
            this.expUserSuggestions = await searchUsers({ term });
        } catch { /* ignore */ }
    }
    pickExpUser(e) {
        const id = e.currentTarget.dataset.id;
        const name = e.currentTarget.dataset.name;
        this.expUserId = id;
        this.expUserSearch = name;
        this.expUserSuggestions = [];
    }

    async searchExplorer() {
        try {
            const startTime = this.expStartDate ? new Date(this.expStartDate).toISOString() : null;
            const endTime = this.expEndDate ? new Date(this.expEndDate).toISOString() : null;
            this.explorerRows = await searchTransactions({ startTime, endTime, userId: this.expUserId, limitSize: 50 });
        } catch (e) {
            this.toast('Explorer error', this.humanError(e), 'error');
        }
    }

    async selectTransaction(e) {
        const id = e.currentTarget.dataset.id;
        try {
            this.selectedTxnQueries = await getTransactionQueries({ transactionId: id });
        } catch (err) {
            this.toast('Query load failed', this.humanError(err), 'error');
        }
    }

    // ===== Profiler core =====
    async runProfiler() {
        if (this.busy) return;
        this.busy = true;
        this.progress = 1;
        this.progressLabel = 'Starting run...';

        let run;
        try {
            run = await startRun({ mode: this.mode });
        } catch (e) {
            this.busy = false;
            this.toast('Run failed', this.humanError(e), 'error');
            return;
        }

        try {
            const logs = await this.fetchApexLogs(this.mode);
            if (!logs.length) {
                await finishRun({ runId: run.runId, status: 'Success', message: 'No logs matched your filter.' });
                this.toast('No logs', 'No ApexLogs found in the selected window.', 'warning');
                return;
            }

            await this.processLogs(run.runId, logs, run.maxLogBytes);

            await finishRun({ runId: run.runId, status: 'Success', message: `Processed ${logs.length} logs.` });
            this.toast('Run complete', `Processed ${logs.length} logs.`, 'success');
        } catch (e) {
            await finishRun({ runId: run.runId, status: 'Failed', message: this.humanError(e) });
            this.toast('Run failed', this.humanError(e), 'error');
        } finally {
            this.busy = false;
            this.progress = 0;
            this.progressLabel = '';
            await this.bootstrap();
        }
    }

    async fetchApexLogs(mode) {
        const days = Number(this.windowDays) || 1;
        const limit = Math.min(500, Math.max(10, Number(this.maxLogs) || 200));
        const deepDays = Math.min(1, days);

        const where = [];
        where.push(`StartTime = LAST_N_DAYS:${mode === 'Deep' ? deepDays : days}`);
        if (mode === 'Deep' && this.pickedUser?.id) {
            where.push(`LogUserId = '${this.pickedUser.id}'`);
        }

        const soql =
            `SELECT Id, LogLength, StartTime, LogUserId, Operation, Request, Status ` +
            `FROM ApexLog WHERE ${where.join(' AND ')} ORDER BY StartTime DESC LIMIT ${limit}`;

        const url = `/services/data/v${API_VERSION}/tooling/query?q=${encodeURIComponent(soql)}`;
        const data = await this.fetchJson(url);
        return data.records || [];
    }

    async processLogs(runId, logs, maxLogBytes) {
        const dailyQueryAgg = new Map(); // date|hash -> agg
        const dailyTxnAgg = new Map();   // date|sig -> agg

        const txns = [];
        const queries = [];
        let logsProcessed = 0;

        for (let i = 0; i < logs.length; i++) {
            const l = logs[i];
            this.progress = Math.min(98, Math.round((i / logs.length) * 100));
            this.progressLabel = `Parsing log ${i + 1} of ${logs.length}...`;

            if (Number(l.LogLength) > Number(maxLogBytes || 0)) {
                continue;
            }

            const body = await this.fetchLogBody(l.Id);
            const parsed = parseApexLogBody(body, { operation: l.Operation });

            const txn = parsed.transaction;
            const txnExternal = l.Id;

            const startTime = l.StartTime;
            const statDate = startTime ? new Date(startTime).toISOString().slice(0, 10) : new Date().toISOString().slice(0, 10);

            txns.push({
                externalLogId: txnExternal,
                startTime: startTime,
                userId: l.LogUserId,
                operation: l.Operation,
                request: l.Request,
                status: l.Status,
                entryPoint: txn.entryPoint,
                signature: txn.signature,
                cpuMs: txn.cpuMs,
                soqlCount: txn.soqlCount,
                soqlMs: txn.soqlMs,
                rows: txn.rowsTotal,
                dmlCount: txn.dmlCount,
                heapBytes: txn.heapBytes,
                calloutCount: txn.calloutCount
            });

            // Daily txn aggregation
            const txnKey = `${statDate}:${(txn.signature || 'Transaction')}`.slice(0, 79);
            const ta = dailyTxnAgg.get(txnKey) || { count: 0, sumCpu: 0, maxCpu: 0, sumSoqlCount: 0, sumSoqlMs: 0, signature: txn.signature || 'Transaction', date: statDate };
            ta.count += 1;
            ta.sumCpu += Number(txn.cpuMs || 0);
            ta.maxCpu = Math.max(ta.maxCpu, Number(txn.cpuMs || 0));
            ta.sumSoqlCount += Number(txn.soqlCount || 0);
            ta.sumSoqlMs += Number(txn.soqlMs || 0);
            dailyTxnAgg.set(txnKey, ta);

            // Query occurrences + daily query agg
            const qs = parsed.queries || [];
            for (let qi = 0; qi < qs.length; qi++) {
                const q = qs[qi];

                const suspect =
                    (q.durationMs >= 50 ? 1.0 : 0.0) +
                    (q.rows >= 1000 ? 1.0 : 0.0) +
                    (/like\s+'%/i.test(q.soqlText || '') ? 1.0 : 0.0);

                queries.push({
                    externalId: `${txnExternal}:${qi + 1}`,
                    transactionExternalLogId: txnExternal,
                    fingerprintHash: q.fingerprintHash,
                    fingerprint: q.normalized,
                    sobjectName: q.sobjectName,
                    fields: (q.fields || []).join(','),
                    durationMs: q.durationMs,
                    rows: q.rows,
                    soqlText: (q.soqlText || '').slice(0, 32700)
                });

                const key = `${statDate}:${q.fingerprintHash}`;
                const a = dailyQueryAgg.get(key) || {
                    count: 0, sumMs: 0, maxMs: 0, rowsSum: 0, rowsMax: 0,
                    sample: q.soqlText, sobjectName: q.sobjectName, fields: (q.fields || []).join(','), suspectSum: 0
                };
                a.count += 1;
                a.sumMs += Number(q.durationMs || 0);
                a.maxMs = Math.max(a.maxMs, Number(q.durationMs || 0));
                a.rowsSum += Number(q.rows || 0);
                a.rowsMax = Math.max(a.rowsMax, Number(q.rows || 0));
                a.suspectSum += suspect;
                if (!a.sample) a.sample = q.soqlText;
                dailyQueryAgg.set(key, a);
            }

            logsProcessed++;

            if (txns.length >= 20 || queries.length >= 150) {
                await this.flush(runId, logsProcessed, txns, queries, dailyQueryAgg, dailyTxnAgg, false);
                txns.length = 0;
                queries.length = 0;
                logsProcessed = 0;
            }
        }

        await this.flush(runId, logsProcessed, txns, queries, dailyQueryAgg, dailyTxnAgg, true);
    }

    async flush(runId, logsProcessed, txns, queries, dailyQueryAgg, dailyTxnAgg, includeDaily) {
        const dailyQueryStats = [];
        const dailyTxnStats = [];

        if (includeDaily === true) {
            for (const [key, a] of (dailyQueryAgg || new Map()).entries()) {
                const [dateStr, hash] = key.split(':');
                const avgMs = a.count ? (a.sumMs / a.count) : 0;
                const avgRows = a.count ? (a.rowsSum / a.count) : 0;
                const suspectScore = a.count ? (a.suspectSum / a.count) : 0;

                dailyQueryStats.push({
                    externalId: `${dateStr}:${hash}`,
                    statDate: dateStr,
                    fingerprintHash: hash,
                    sampleSoql: (a.sample || '').slice(0, 32700),
                    sobjectName: a.sobjectName,
                    fields: (a.fields || '').slice(0, 255),
                    countVal: a.count,
                    avgMs: Number(avgMs.toFixed(1)),
                    p95Ms: Number(a.maxMs.toFixed(1)), // lightweight p95 approximation
                    avgRows: Number(avgRows.toFixed(1)),
                    maxRows: a.rowsMax,
                    suspectScore: Number(suspectScore.toFixed(1))
                });
            }

            for (const [key, a] of (dailyTxnAgg || new Map()).entries()) {
                const [dateStr, ...sigParts] = key.split(':');
                const sig = sigParts.join(':');
                const avgCpu = a.count ? (a.sumCpu / a.count) : 0;
                const avgSoqlCount = a.count ? (a.sumSoqlCount / a.count) : 0;
                const avgSoqlMs = a.count ? (a.sumSoqlMs / a.count) : 0;

                dailyTxnStats.push({
                    externalId: `${dateStr}:${sig}`.slice(0, 79),
                    statDate: dateStr,
                    signature: sig.slice(0, 255),
                    countVal: a.count,
                    avgCpuMs: Number(avgCpu.toFixed(1)),
                    p95CpuMs: Number(a.maxCpu.toFixed(1)),
                    avgSoqlCount: Number(avgSoqlCount.toFixed(1)),
                    avgSoqlMs: Number(avgSoqlMs.toFixed(1))
                });
            }
        }

        const payload = {
            logsProcessed,
            transactions: txns,
            queries: queries,
            dailyQueryStats,
            dailyTxnStats
        };

        await ingestBatch({ runId, batchJson: JSON.stringify(payload) });
    }

async fetchLogBody(apexLogId) {
        const url = `/services/data/v${API_VERSION}/tooling/sobjects/ApexLog/${apexLogId}/Body`;
        const res = await fetch(url, { method: 'GET' });
        if (!res.ok) {
            const t = await res.text();
            throw new Error(`Failed to download log body (${res.status}): ${t}`);
        }
        return res.text();
    }

    async fetchJson(url) {
        const res = await fetch(url, { method: 'GET', headers: { 'Content-Type': 'application/json' } });
        if (!res.ok) {
            const t = await res.text();
            throw new Error(`HTTP ${res.status} ${res.statusText}: ${t}`);
        }
        return res.json();
    }

    // ===== Deep mode: enable trace =====
    async enableTrace() {
        if (!this.pickedUser?.id) return;
        if (this.busy) return;

        this.busy = true;
        this.progress = 5;
        this.progressLabel = 'Preparing debug level...';
        try {
            const debugLevelId = await this.ensureDebugLevel();
            this.progressLabel = 'Creating trace flag...';
            await this.createTraceFlag(this.pickedUser.id, debugLevelId, 30);
            this.toast('Trace enabled', 'TraceFlag created for 30 minutes. Run your flow, then click Run Now to collect logs.', 'success');
        } catch (e) {
            this.toast('Trace enable failed', this.humanError(e), 'error');
        } finally {
            this.busy = false;
            this.progress = 0;
            this.progressLabel = '';
        }
    }

    async ensureDebugLevel() {
        const q = `SELECT Id, DeveloperName FROM DebugLevel WHERE DeveloperName = 'PH_Deep' LIMIT 1`;
        const data = await this.fetchJson(`/services/data/v${API_VERSION}/tooling/query?q=${encodeURIComponent(q)}`);
        const rec = (data.records || [])[0];
        if (rec?.Id) return rec.Id;

        }

        const payload = {
            DeveloperName: 'PH_Deep',
            MasterLabel: 'PH Deep Trace',
            ApexCode: 'FINE',
            ApexProfiling: 'FINE',
            Callout: 'INFO',
            Database: 'FINE',
            System: 'ERROR',
            Validation: 'ERROR',
            Visualforce: 'ERROR',
            Workflow: 'ERROR'
        };

        const res = await fetch(`/services/data/v${API_VERSION}/tooling/sobjects/DebugLevel`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const out = await res.json();
        if (!res.ok) throw new Error(out?.[0]?.message || 'Failed to create DebugLevel.');
        return out.id;
    }

    async createTraceFlag(userId, debugLevelId, minutes) {
        const now = new Date();
        const exp = new Date(now.getTime() + (minutes * 60 * 1000));
        }

        const payload = {
            TracedEntityId: userId,
            DebugLevelId: debugLevelId,
            StartDate: now.toISOString(),
            ExpirationDate: exp.toISOString(),
            LogType: 'DEVELOPER_LOG'
        };

        const res = await fetch(`/services/data/v${API_VERSION}/tooling/sobjects/TraceFlag`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const out = await res.json();
        if (!res.ok) throw new Error(out?.[0]?.message || 'Failed to create TraceFlag.');
        return out.id;
    }

    // ===== Alerts =====
    async loadAlertRules() {
        try {
            this.alertRules = await getAlertRules();
        } catch {
            // non-fatal
        }
    }

    handleRuleName(e) { this.ruleName = e.target.value; }
    handleRuleType(e) { this.ruleType = e.detail.value; }
    handleRuleMetric(e) { this.ruleMetric = e.detail.value; }
    handleRuleThreshold(e) { this.ruleThreshold = Number(e.target.value) || 0; }
    handleRuleWindow(e) { this.ruleWindowDays = e.detail.value; }
    handleRuleEnabled(e) { this.ruleEnabled = e.target.checked; }

    async saveRule() {
        try {
            const id = await upsertAlertRule({
                ruleJson: JSON.stringify({
                    name: this.ruleName,
                    enabled: this.ruleEnabled,
                    ruleType: this.ruleType,
                    metric: this.ruleMetric,
                    threshold: this.ruleThreshold,
                    windowDays: this.ruleWindowDays
                })
            });
            this.toast('Saved', `Rule saved (${id}).`, 'success');
            await this.loadAlertRules();
            await this.refreshDashboard();
        } catch (e) {
            this.toast('Save failed', this.humanError(e), 'error');
        }
    }

    async evaluateNow() {
        try {
            await runAlertEvaluationNow();
            this.toast('Evaluated', 'Alert evaluation executed.', 'success');
            await this.refreshDashboard();
        } catch (e) {
            this.toast('Evaluation failed', this.humanError(e), 'error');
        }
    }

    async scheduleNightly() {
        try {
            await scheduleNightlyAlerts({ cronExpr: '0 10 2 * * ?' });
            this.toast('Scheduled', 'Nightly alert evaluation scheduled at 02:10.', 'success');
        } catch (e) {
            this.toast('Scheduling failed', this.humanError(e), 'error');
        }
    }

    // ===== Helpers =====
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    humanError(e) {
        try {
            if (e?.body?.message) return e.body.message;
            if (Array.isArray(e?.body) && e.body[0]?.message) return e.body[0].message;
            if (e?.message) return e.message;
            return JSON.stringify(e);
        } catch {
            return String(e);
        }
    }
}
