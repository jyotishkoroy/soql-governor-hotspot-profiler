public with sharing class PH_AlertEngine {

    public static void evaluateNow() {
        evaluate(Date.today());
    }

    public static void evaluate(Date asOfDate) {
        if (asOfDate == null) asOfDate = Date.today();

        List<PH_Alert_Rule__c> rules = [
            SELECT Id, Name, Enabled__c, Rule_Type__c, Metric__c, Threshold__c, Window_Days__c
            FROM PH_Alert_Rule__c
            WHERE Enabled__c = true
            LIMIT 200
        ];
        if (rules.isEmpty()) return;

        for (PH_Alert_Rule__c r : rules) {
            Integer windowDays = Integer.valueOf(String.valueOf(r.Window_Days__c));
            if (windowDays <= 0) windowDays = 7;

            if (r.Rule_Type__c == 'Query') {
                evaluateQueryRule(r, asOfDate, windowDays);
            } else if (r.Rule_Type__c == 'Transaction') {
                evaluateTxnRule(r, asOfDate, windowDays);
            }
        }
    }

    private static void evaluateQueryRule(PH_Alert_Rule__c rule, Date asOfDate, Integer windowDays) {
        Date minDate = asOfDate.addDays(-windowDays);

        List<AggregateResult> aggs = [
            SELECT Fingerprint_Hash__c h,
                   AVG(Avg_Ms__c) avgMs,
                   AVG(P95_Ms__c) p95Ms,
                   SUM(Count__c) cnt
            FROM PH_Daily_Query_Stat__c
            WHERE Date__c >= :minDate AND Date__c <= :asOfDate
            GROUP BY Fingerprint_Hash__c
        ];

        Decimal threshold = rule.Threshold__c == null ? 0 : rule.Threshold__c;

        List<PH_Alert_Event__c> events = new List<PH_Alert_Event__c>();
        for (AggregateResult a : aggs) {
            String h = (String) a.get('h');
            Decimal avgMs = (Decimal) a.get('avgMs');
            Decimal p95Ms = (Decimal) a.get('p95Ms');
            Decimal cnt = (Decimal) a.get('cnt');

            Decimal metricVal = 0;
            if (rule.Metric__c == 'AvgMs') metricVal = avgMs;
            else if (rule.Metric__c == 'P95Ms') metricVal = p95Ms;
            else if (rule.Metric__c == 'Count') metricVal = cnt;

            if (metricVal != null && metricVal >= threshold) {
                PH_Alert_Event__c e = new PH_Alert_Event__c();
                e.Name = 'Alert ' + Datetime.now().getTime();
                e.Alert_Rule__c = rule.Id;
                e.Fired_At__c = Datetime.now();
                e.Severity__c = metricVal >= (threshold * 2) ? 'HIGH' : 'WARN';
                e.Reference__c = h;
                e.Message__c = 'Query fingerprint ' + h + ' breached ' + rule.Metric__c +
                               ' threshold (' + String.valueOf(metricVal.setScale(1)) + ' >= ' +
                               String.valueOf(threshold) + ') over last ' + String.valueOf(windowDays) + ' days.';
                events.add(e);
            }
        }

        if (events.size() > 5) events = events.subList(0, 5);
        if (!events.isEmpty()) insert events;
    }

    private static void evaluateTxnRule(PH_Alert_Rule__c rule, Date asOfDate, Integer windowDays) {
        Date minDate = asOfDate.addDays(-windowDays);

        List<AggregateResult> aggs = [
            SELECT Signature__c sig,
                   AVG(Avg_Cpu_Ms__c) avgCpu,
                   AVG(P95_Cpu_Ms__c) p95Cpu,
                   SUM(Count__c) cnt
            FROM PH_Daily_Txn_Stat__c
            WHERE Date__c >= :minDate AND Date__c <= :asOfDate
            GROUP BY Signature__c
        ];

        Decimal threshold = rule.Threshold__c == null ? 0 : rule.Threshold__c;

        List<PH_Alert_Event__c> events = new List<PH_Alert_Event__c>();
        for (AggregateResult a : aggs) {
            String sig = (String) a.get('sig');
            Decimal avgCpu = (Decimal) a.get('avgCpu');
            Decimal p95Cpu = (Decimal) a.get('p95Cpu');
            Decimal cnt = (Decimal) a.get('cnt');

            Decimal metricVal = 0;
            if (rule.Metric__c == 'AvgCpu') metricVal = avgCpu;
            else if (rule.Metric__c == 'P95Cpu') metricVal = p95Cpu;
            else if (rule.Metric__c == 'Count') metricVal = cnt;

            if (metricVal != null && metricVal >= threshold) {
                PH_Alert_Event__c e = new PH_Alert_Event__c();
                e.Name = 'Alert ' + Datetime.now().getTime();
                e.Alert_Rule__c = rule.Id;
                e.Fired_At__c = Datetime.now();
                e.Severity__c = metricVal >= (threshold * 2) ? 'HIGH' : 'WARN';
                e.Reference__c = sig;
                e.Message__c = 'Transaction signature "' + sig + '" breached ' + rule.Metric__c +
                               ' threshold (' + String.valueOf(metricVal.setScale(1)) + ' >= ' +
                               String.valueOf(threshold) + ') over last ' + String.valueOf(windowDays) + ' days.';
                events.add(e);
            }
        }

        if (events.size() > 5) events = events.subList(0, 5);
        if (!events.isEmpty()) insert events;
    }
}
