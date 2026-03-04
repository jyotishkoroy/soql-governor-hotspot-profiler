public with sharing class PH_DashboardService {

    public class TopTxn {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public String signature;
        @AuraEnabled public Integer cpuMs;
        @AuraEnabled public Integer soqlCount;
        @AuraEnabled public Integer soqlMs;
        @AuraEnabled public String userName;
        @AuraEnabled public String operation;
    }

    public class TopQuery {
        @AuraEnabled public Id id;
        @AuraEnabled public Date statDate;
        @AuraEnabled public String fingerprintHash;
        @AuraEnabled public Decimal avgMs;
        @AuraEnabled public Decimal p95Ms;
        @AuraEnabled public Integer countVal;
        @AuraEnabled public String sobjectName;
        @AuraEnabled public String fields;
        @AuraEnabled public String sampleSoql;
        @AuraEnabled public Decimal suspectScore;
    }

    public class Regression {
        @AuraEnabled public String kind; // Query
        @AuraEnabled public String key;  // hash
        @AuraEnabled public Decimal recentAvg;
        @AuraEnabled public Decimal baselineAvg;
        @AuraEnabled public Decimal ratio;
        @AuraEnabled public String sample;
    }

    public class TxnRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public String signature;
        @AuraEnabled public Integer cpuMs;
        @AuraEnabled public Integer soqlCount;
        @AuraEnabled public Integer soqlMs;
        @AuraEnabled public String userName;
    }

    public class QueryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String fingerprintHash;
        @AuraEnabled public Integer durationMs;
        @AuraEnabled public Integer rows;
        @AuraEnabled public String soqlText;
    }

    public class AlertRuleRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public String ruleType;
        @AuraEnabled public String metric;
        @AuraEnabled public Decimal threshold;
        @AuraEnabled public Integer windowDays;
    }

    public class AlertEventRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime firedAt;
        @AuraEnabled public String severity;
        @AuraEnabled public String message;
        @AuraEnabled public String reference;
        @AuraEnabled public String ruleName;
        @AuraEnabled public Boolean resolved;
    }

    public static PH_AppController.Summary getSummary() {
        PH_AppController.Summary s = new PH_AppController.Summary();
        s.runs = Database.countQuery('SELECT COUNT() FROM PH_Run__c');
        s.txns = Database.countQuery('SELECT COUNT() FROM PH_Transaction__c');
        s.queries = Database.countQuery('SELECT COUNT() FROM PH_Query__c');
        List<PH_Run__c> last = [
            SELECT Mode__c, Started_At__c, Finished_At__c, Status__c, Message__c
            FROM PH_Run__c
            ORDER BY Started_At__c DESC
            LIMIT 1
        ];
        if (!last.isEmpty()) {
            PH_Run__c r = last[0];
            s.lastRunMode = r.Mode__c;
            s.lastRunStartedAt = r.Started_At__c;
            s.lastRunFinishedAt = r.Finished_At__c;
            s.lastRunStatus = r.Status__c;
            s.lastRunMessage = r.Message__c;
        }
        return s;
    }

    public static List<TopTxn> getTopTransactions(Integer days) {
        Integer d = (days == null || days <= 0 || days > 90) ? 7 : days;
        Datetime minDt = Datetime.now().addDays(-d);

        List<PH_Transaction__c> rows = [
            SELECT Id, Start_Time__c, Signature__c, Cpu_Ms__c, Soql_Count__c, Soql_Ms__c, Operation__c, User__r.Name
            FROM PH_Transaction__c
            WHERE Start_Time__c >= :minDt
            ORDER BY Cpu_Ms__c DESC NULLS LAST
            LIMIT 15
        ];

        List<TopTxn> out = new List<TopTxn>();
        for (PH_Transaction__c t : rows) {
            TopTxn x = new TopTxn();
            x.id = t.Id;
            x.startTime = t.Start_Time__c;
            x.signature = t.Signature__c;
            x.cpuMs = t.Cpu_Ms__c == null ? 0 : Integer.valueOf(String.valueOf(t.Cpu_Ms__c));
            x.soqlCount = t.Soql_Count__c == null ? 0 : Integer.valueOf(String.valueOf(t.Soql_Count__c));
            x.soqlMs = t.Soql_Ms__c == null ? 0 : Integer.valueOf(String.valueOf(t.Soql_Ms__c));
            x.userName = t.User__r == null ? null : t.User__r.Name;
            x.operation = t.Operation__c;
            out.add(x);
        }
        return out;
    }

    public static List<TopQuery> getTopQueries(Integer days) {
        Integer d = (days == null || days <= 0 || days > 90) ? 7 : days;
        Date minDate = Date.today().addDays(-d);

        List<PH_Daily_Query_Stat__c> rows = [
            SELECT Id, Date__c, Fingerprint_Hash__c, Avg_Ms__c, P95_Ms__c, Count__c, SObject__c, Fields__c, Sample_Soql__c, Suspect_Score__c
            FROM PH_Daily_Query_Stat__c
            WHERE Date__c >= :minDate
            ORDER BY Avg_Ms__c DESC NULLS LAST
            LIMIT 15
        ];

        List<TopQuery> out = new List<TopQuery>();
        for (PH_Daily_Query_Stat__c s : rows) {
            TopQuery q = new TopQuery();
            q.id = s.Id;
            q.statDate = s.Date__c;
            q.fingerprintHash = s.Fingerprint_Hash__c;
            q.avgMs = s.Avg_Ms__c;
            q.p95Ms = s.P95_Ms__c;
            q.countVal = s.Count__c == null ? 0 : Integer.valueOf(String.valueOf(s.Count__c));
            q.sobjectName = s.SObject__c;
            q.fields = s.Fields__c;
            q.sampleSoql = s.Sample_Soql__c;
            q.suspectScore = s.Suspect_Score__c;
            out.add(q);
        }
        return out;
    }

    public static List<Regression> getRegressions() {
        Date minDate = Date.today().addDays(-30);
        List<PH_Daily_Query_Stat__c> qStats = [
            SELECT Date__c, Fingerprint_Hash__c, Avg_Ms__c, Sample_Soql__c
            FROM PH_Daily_Query_Stat__c
            WHERE Date__c >= :minDate
        ];

        Map<String, List<PH_Daily_Query_Stat__c>> byHash = new Map<String, List<PH_Daily_Query_Stat__c>>();
        for (PH_Daily_Query_Stat__c s : qStats) {
            if (String.isBlank(s.Fingerprint_Hash__c) || s.Avg_Ms__c == null) continue;
            if (!byHash.containsKey(s.Fingerprint_Hash__c)) byHash.put(s.Fingerprint_Hash__c, new List<PH_Daily_Query_Stat__c>());
            byHash.get(s.Fingerprint_Hash__c).add(s);
        }

        Date cutoff = Date.today().addDays(-7);
        List<Regression> out = new List<Regression>();

        for (String h : byHash.keySet()) {
            Decimal recent = 0, base = 0;
            Integer rc = 0, bc = 0;
            String sample = null;

            for (PH_Daily_Query_Stat__c s : byHash.get(h)) {
                if (sample == null && !String.isBlank(s.Sample_Soql__c)) sample = s.Sample_Soql__c;
                if (s.Date__c >= cutoff) {
                    recent += s.Avg_Ms__c;
                    rc++;
                } else {
                    base += s.Avg_Ms__c;
                    bc++;
                }
            }
            if (rc < 3 || bc < 5) continue;
            Decimal recentAvg = recent / rc;
            Decimal baseAvg = base / bc;
            if (baseAvg <= 0) continue;

            Decimal ratio = recentAvg / baseAvg;
            if (ratio >= 1.5 && recentAvg >= 25) {
                Regression r = new Regression();
                r.kind = 'Query';
                r.key = h;
                r.recentAvg = recentAvg.setScale(1);
                r.baselineAvg = baseAvg.setScale(1);
                r.ratio = ratio.setScale(2);
                r.sample = sample;
                out.add(r);
            }
        }

        out.sort(new RegressionSort());
        if (out.size() > 12) out = out.subList(0, 12);
        return out;
    }

    public static List<TxnRow> searchTransactions(Datetime startTime, Datetime endTime, String userId, Integer limitSize) {
        Integer lim = (limitSize == null || limitSize <= 0 || limitSize > 200) ? 50 : limitSize;
        Datetime start = startTime == null ? Datetime.now().addDays(-7) : startTime;
        Datetime endDt = endTime == null ? Datetime.now() : endTime;

        List<PH_Transaction__c> rows;
        if (String.isBlank(userId)) {
            rows = [
                SELECT Id, Start_Time__c, Signature__c, Cpu_Ms__c, Soql_Count__c, Soql_Ms__c, User__r.Name
                FROM PH_Transaction__c
                WHERE Start_Time__c >= :start AND Start_Time__c <= :endDt
                ORDER BY Cpu_Ms__c DESC NULLS LAST
                LIMIT :lim
            ];
        } else {
            rows = [
                SELECT Id, Start_Time__c, Signature__c, Cpu_Ms__c, Soql_Count__c, Soql_Ms__c, User__r.Name
                FROM PH_Transaction__c
                WHERE Start_Time__c >= :start AND Start_Time__c <= :endDt AND User__c = :userId
                ORDER BY Cpu_Ms__c DESC NULLS LAST
                LIMIT :lim
            ];
        }

        List<TxnRow> out = new List<TxnRow>();
        for (PH_Transaction__c t : rows) {
            TxnRow r = new TxnRow();
            r.id = t.Id;
            r.startTime = t.Start_Time__c;
            r.signature = t.Signature__c;
            r.cpuMs = t.Cpu_Ms__c == null ? 0 : Integer.valueOf(String.valueOf(t.Cpu_Ms__c));
            r.soqlCount = t.Soql_Count__c == null ? 0 : Integer.valueOf(String.valueOf(t.Soql_Count__c));
            r.soqlMs = t.Soql_Ms__c == null ? 0 : Integer.valueOf(String.valueOf(t.Soql_Ms__c));
            r.userName = t.User__r == null ? null : t.User__r.Name;
            out.add(r);
        }
        return out;
    }

    public static List<QueryRow> getTransactionQueries(Id transactionId) {
        if (transactionId == null) return new List<QueryRow>();
        List<PH_Query__c> rows = [
            SELECT Id, Fingerprint_Hash__c, Duration_Ms__c, Rows__c, Soql_Text__c
            FROM PH_Query__c
            WHERE Transaction__c = :transactionId
            ORDER BY Duration_Ms__c DESC NULLS LAST
            LIMIT 200
        ];

        List<QueryRow> out = new List<QueryRow>();
        for (PH_Query__c q : rows) {
            QueryRow r = new QueryRow();
            r.id = q.Id;
            r.fingerprintHash = q.Fingerprint_Hash__c;
            r.durationMs = q.Duration_Ms__c == null ? 0 : Integer.valueOf(String.valueOf(q.Duration_Ms__c));
            r.rows = q.Rows__c == null ? 0 : Integer.valueOf(String.valueOf(q.Rows__c));
            r.soqlText = q.Soql_Text__c;
            out.add(r);
        }
        return out;
    }

    public static List<AlertRuleRow> getAlertRules() {
        List<PH_Alert_Rule__c> rows = [
            SELECT Id, Name, Enabled__c, Rule_Type__c, Metric__c, Threshold__c, Window_Days__c
            FROM PH_Alert_Rule__c
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        List<AlertRuleRow> out = new List<AlertRuleRow>();
        for (PH_Alert_Rule__c r : rows) {
            AlertRuleRow x = new AlertRuleRow();
            x.id = r.Id;
            x.name = r.Name;
            x.enabled = r.Enabled__c;
            x.ruleType = r.Rule_Type__c;
            x.metric = r.Metric__c;
            x.threshold = r.Threshold__c;
            x.windowDays = Integer.valueOf(String.valueOf(r.Window_Days__c));
            out.add(x);
        }
        return out;
    }

    public static List<AlertEventRow> getRecentAlerts(Integer limitSize) {
        Integer lim = (limitSize == null || limitSize <= 0 || limitSize > 50) ? 15 : limitSize;
        List<PH_Alert_Event__c> rows = [
            SELECT Id, Fired_At__c, Severity__c, Message__c, Reference__c, Resolved__c, Alert_Rule__r.Name
            FROM PH_Alert_Event__c
            ORDER BY Fired_At__c DESC
            LIMIT :lim
        ];
        List<AlertEventRow> out = new List<AlertEventRow>();
        for (PH_Alert_Event__c e : rows) {
            AlertEventRow r = new AlertEventRow();
            r.id = e.Id;
            r.firedAt = e.Fired_At__c;
            r.severity = e.Severity__c;
            r.message = e.Message__c;
            r.reference = e.Reference__c;
            r.ruleName = e.Alert_Rule__r == null ? null : e.Alert_Rule__r.Name;
            r.resolved = e.Resolved__c;
            out.add(r);
        }
        return out;
    }

    private class RegressionSort implements Comparator<Regression> {
        public Integer compare(Regression a, Regression b) {
            Decimal ra = a == null || a.ratio == null ? 0 : a.ratio;
            Decimal rb = b == null || b.ratio == null ? 0 : b.ratio;
            if (ra == rb) return 0;
            return ra > rb ? -1 : 1;
        }
    }
}
