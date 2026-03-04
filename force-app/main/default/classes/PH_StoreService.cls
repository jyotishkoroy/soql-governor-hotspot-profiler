public with sharing class PH_StoreService {

    // ===== Incoming payload models =====
    public class BatchPayload {
        public Integer logsProcessed;
        public List<TransactionPayload> transactions;
        public List<QueryPayload> queries;
        public List<DailyQueryStatPayload> dailyQueryStats;
        public List<DailyTxnStatPayload> dailyTxnStats;
    }

    public class TransactionPayload {
        public String externalLogId;
        public Datetime startTime;
        public Id userId;
        public String operation;
        public String request;
        public String status;
        public String entryPoint;
        public String signature;
        public Integer cpuMs;
        public Integer soqlCount;
        public Integer soqlMs;
        public Integer rows;
        public Integer dmlCount;
        public Integer heapBytes;
        public Integer calloutCount;
    }

    public class QueryPayload {
        public String externalId;
        public String transactionExternalLogId;
        public String fingerprintHash;
        public String fingerprint;
        public String sobjectName;
        public String fields;
        public Integer durationMs;
        public Integer rows;
        public String soqlText;
    }

    public class DailyQueryStatPayload {
        public String externalId;
        public Date statDate;
        public String fingerprintHash;
        public String sampleSoql;
        public String sobjectName;
        public String fields;
        public Integer countVal;
        public Decimal avgMs;
        public Decimal p95Ms;
        public Decimal avgRows;
        public Integer maxRows;
        public Decimal suspectScore;
    }

    public class DailyTxnStatPayload {
        public String externalId;
        public Date statDate;
        public String signature;
        public Integer countVal;
        public Decimal avgCpuMs;
        public Decimal p95CpuMs;
        public Decimal avgSoqlCount;
        public Decimal avgSoqlMs;
    }

    public static void assertAccess() {
        if (!Schema.sObjectType.PH_Run__c.isAccessible()
            || !Schema.sObjectType.PH_Transaction__c.isAccessible()
            || !Schema.sObjectType.PH_Query__c.isAccessible()) {
            throw new AuraHandledException('Missing access to profiler objects. Assign SOQL_Governor_Hotspot_Profiler permission set.');
        }
        if (!Schema.sObjectType.PH_Run__c.isCreateable()
            || !Schema.sObjectType.PH_Transaction__c.isCreateable()
            || !Schema.sObjectType.PH_Query__c.isCreateable()) {
            throw new AuraHandledException('Missing create access. Assign SOQL_Governor_Hotspot_Profiler permission set.');
        }
    }

    public static PH_AppController.IngestResult ingestBatch(String runId, String batchJson) {
        BatchPayload payload = (BatchPayload) JSON.deserialize(batchJson, BatchPayload.class);
        if (payload == null) throw new AuraHandledException('Unable to parse batch JSON.');

        Integer txUp = 0;
        Integer qUp = 0;
        Integer dUp = 0;

        // Upsert transactions
        Map<String, Id> txnExtToId = new Map<String, Id>();
        List<PH_Transaction__c> txns = new List<PH_Transaction__c>();
        if (payload.transactions != null) {
            for (TransactionPayload t : payload.transactions) {
                if (t == null || String.isBlank(t.externalLogId)) continue;

                PH_Transaction__c row = new PH_Transaction__c();
                row.External_Log_Id__c = t.externalLogId;
                row.Run__c = (Id) runId;
                row.Start_Time__c = t.startTime == null ? Datetime.now() : t.startTime;
                row.User__c = t.userId;
                row.Operation__c = t.operation;
                row.Request__c = t.request;
                row.Status__c = t.status;
                row.Entry_Point__c = t.entryPoint;
                row.Signature__c = t.signature;
                row.Cpu_Ms__c = t.cpuMs;
                row.Soql_Count__c = t.soqlCount;
                row.Soql_Ms__c = t.soqlMs;
                row.Rows__c = t.rows;
                row.Dml_Count__c = t.dmlCount;
                row.Heap_Bytes__c = t.heapBytes;
                row.Callout_Count__c = t.calloutCount;
                row.Name = (t.signature == null ? 'Txn' : t.signature).left(80);
                txns.add(row);
            }
        }

        if (!txns.isEmpty()) {
            txns = (List<PH_Transaction__c>) Security.stripInaccessible(AccessType.CREATABLE, txns).getRecords();
            Database.UpsertResult[] res = Database.upsert(txns, PH_Transaction__c.External_Log_Id__c, false);
            txUp += countSuccess(res);

            Set<String> extIds = new Set<String>();
            for (PH_Transaction__c t : txns) extIds.add(t.External_Log_Id__c);
            for (PH_Transaction__c t : [
                SELECT Id, External_Log_Id__c
                FROM PH_Transaction__c
                WHERE External_Log_Id__c IN :extIds
            ]) {
                txnExtToId.put(t.External_Log_Id__c, t.Id);
            }
        }

        // Upsert query occurrences
        List<PH_Query__c> queries = new List<PH_Query__c>();
        if (payload.queries != null) {
            for (QueryPayload q : payload.queries) {
                if (q == null || String.isBlank(q.externalId) || String.isBlank(q.transactionExternalLogId)) continue;
                Id txnId = txnExtToId.get(q.transactionExternalLogId);
                if (txnId == null) continue;

                PH_Query__c row = new PH_Query__c();
                row.External_Id__c = q.externalId;
                row.Transaction__c = txnId;
                row.Fingerprint_Hash__c = q.fingerprintHash;
                row.Fingerprint__c = q.fingerprint;
                row.SObject__c = q.sobjectName;
                row.Fields__c = q.fields;
                row.Duration_Ms__c = q.durationMs;
                row.Rows__c = q.rows;
                row.Soql_Text__c = q.soqlText;
                row.Name = (q.fingerprintHash == null ? 'Query' : q.fingerprintHash).left(80);
                queries.add(row);
            }
        }
        if (!queries.isEmpty()) {
            queries = (List<PH_Query__c>) Security.stripInaccessible(AccessType.CREATABLE, queries).getRecords();
            Database.UpsertResult[] res = Database.upsert(queries, PH_Query__c.External_Id__c, false);
            qUp += countSuccess(res);
        }

        // Daily stats
        dUp += upsertDailyQueryStats(payload.dailyQueryStats);
        dUp += upsertDailyTxnStats(payload.dailyTxnStats);

        // Update run counters (best-effort)
        Integer lp = payload.logsProcessed == null ? 0 : payload.logsProcessed;
        try {
            PH_Run__c run = [
                SELECT Id, Logs_Processed__c, Transactions_Upserted__c, Queries_Upserted__c, Daily_Stats_Upserted__c
                FROM PH_Run__c
                WHERE Id = :runId
                LIMIT 1
                FOR UPDATE
            ];
            run.Logs_Processed__c = (run.Logs_Processed__c == null ? 0 : run.Logs_Processed__c) + lp;
            run.Transactions_Upserted__c = (run.Transactions_Upserted__c == null ? 0 : run.Transactions_Upserted__c) + txUp;
            run.Queries_Upserted__c = (run.Queries_Upserted__c == null ? 0 : run.Queries_Upserted__c) + qUp;
            run.Daily_Stats_Upserted__c = (run.Daily_Stats_Upserted__c == null ? 0 : run.Daily_Stats_Upserted__c) + dUp;
            update run;
        } catch (Exception ignore) {}

        PH_AppController.IngestResult out = new PH_AppController.IngestResult();
        out.transactionsUpserted = txUp;
        out.queriesUpserted = qUp;
        out.dailyStatsUpserted = dUp;
        return out;
    }

    public static PH_AppController.RunFinish finishRun(String runId, String status, String message) {
        PH_Run__c run = [SELECT Id FROM PH_Run__c WHERE Id = :runId LIMIT 1];
        run.Finished_At__c = Datetime.now();
        run.Status__c = String.isBlank(status) ? 'Success' : status;
        run.Message__c = message;
        update run;

        PH_AppController.RunFinish out = new PH_AppController.RunFinish();
        out.finishedAt = run.Finished_At__c;
        out.status = run.Status__c;
        out.message = String.isBlank(message) ? 'Done.' : message;
        return out;
    }

    public static Id upsertAlertRule(String ruleJson) {
        if (String.isBlank(ruleJson)) throw new AuraHandledException('Missing rule payload.');
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(ruleJson);

        Id rid = (Id) m.get('id');

        PH_Alert_Rule__c r = new PH_Alert_Rule__c();
        if (rid != null) r.Id = rid;

        r.Name = (String) m.get('name');
        r.Enabled__c = (Boolean) m.get('enabled');
        r.Rule_Type__c = (String) m.get('ruleType');
        r.Metric__c = (String) m.get('metric');

        Object th = m.get('threshold');
        if (th != null) r.Threshold__c = Decimal.valueOf(String.valueOf(th));

        r.Window_Days__c = String.valueOf(m.get('windowDays'));

        upsert r;
        return r.Id;
    }

    private static Integer upsertDailyQueryStats(List<DailyQueryStatPayload> stats) {
        if (stats == null || stats.isEmpty()) return 0;
        List<PH_Daily_Query_Stat__c> rows = new List<PH_Daily_Query_Stat__c>();

        for (DailyQueryStatPayload s : stats) {
            if (s == null || String.isBlank(s.externalId)) continue;
            PH_Daily_Query_Stat__c r = new PH_Daily_Query_Stat__c();
            r.External_Id__c = s.externalId;
            r.Date__c = s.statDate;
            r.Fingerprint_Hash__c = s.fingerprintHash;
            r.Sample_Soql__c = s.sampleSoql;
            r.SObject__c = s.sobjectName;
            r.Fields__c = s.fields;
            r.Count__c = s.countVal;
            r.Avg_Ms__c = s.avgMs;
            r.P95_Ms__c = s.p95Ms;
            r.Avg_Rows__c = s.avgRows;
            r.Max_Rows__c = s.maxRows;
            r.Suspect_Score__c = s.suspectScore;
            r.Name = (s.fingerprintHash == null ? 'QueryStat' : s.fingerprintHash).left(80);
            rows.add(r);
        }

        if (rows.isEmpty()) return 0;
        rows = (List<PH_Daily_Query_Stat__c>) Security.stripInaccessible(AccessType.CREATABLE, rows).getRecords();
        Database.UpsertResult[] res = Database.upsert(rows, PH_Daily_Query_Stat__c.External_Id__c, false);
        return countSuccess(res);
    }

    private static Integer upsertDailyTxnStats(List<DailyTxnStatPayload> stats) {
        if (stats == null || stats.isEmpty()) return 0;
        List<PH_Daily_Txn_Stat__c> rows = new List<PH_Daily_Txn_Stat__c>();

        for (DailyTxnStatPayload s : stats) {
            if (s == null || String.isBlank(s.externalId) || String.isBlank(s.signature)) continue;
            PH_Daily_Txn_Stat__c r = new PH_Daily_Txn_Stat__c();
            r.External_Id__c = s.externalId;
            r.Date__c = s.statDate;
            r.Signature__c = s.signature;
            r.Count__c = s.countVal;
            r.Avg_Cpu_Ms__c = s.avgCpuMs;
            r.P95_Cpu_Ms__c = s.p95CpuMs;
            r.Avg_Soql_Count__c = s.avgSoqlCount;
            r.Avg_Soql_Ms__c = s.avgSoqlMs;
            r.Name = s.signature.left(80);
            rows.add(r);
        }

        if (rows.isEmpty()) return 0;
        rows = (List<PH_Daily_Txn_Stat__c>) Security.stripInaccessible(AccessType.CREATABLE, rows).getRecords();
        Database.UpsertResult[] res = Database.upsert(rows, PH_Daily_Txn_Stat__c.External_Id__c, false);
        return countSuccess(res);
    }

    private static Integer countSuccess(Database.UpsertResult[] res) {
        Integer c = 0;
        for (Database.UpsertResult r : res) {
            if (r != null && r.isSuccess()) c++;
        }
        return c;
    }
}
