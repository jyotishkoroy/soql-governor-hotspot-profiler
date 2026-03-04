public with sharing class PH_AppController {

    // ===== DTOs =====
    public class Summary {
        @AuraEnabled public Integer runs;
        @AuraEnabled public Integer txns;
        @AuraEnabled public Integer queries;
        @AuraEnabled public Datetime lastRunStartedAt;
        @AuraEnabled public Datetime lastRunFinishedAt;
        @AuraEnabled public String lastRunMode;
        @AuraEnabled public String lastRunStatus;
        @AuraEnabled public String lastRunMessage;
    }

    public class RunStart {
        @AuraEnabled public String runId;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Integer maxLogBytes;
        @AuraEnabled public Integer maxLogsPerRun;
    }

    public class IngestResult {
        @AuraEnabled public Integer transactionsUpserted;
        @AuraEnabled public Integer queriesUpserted;
        @AuraEnabled public Integer dailyStatsUpserted;
    }

    public class RunFinish {
        @AuraEnabled public Datetime finishedAt;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }

    public class DashboardPayload {
        @AuraEnabled public List<PH_DashboardService.TopTxn> topTxns;
        @AuraEnabled public List<PH_DashboardService.TopQuery> topQueries;
        @AuraEnabled public List<PH_DashboardService.Regression> regressions;
        @AuraEnabled public List<PH_DashboardService.AlertEventRow> recentAlerts;
    }

    public class UserPick {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
    }

    // ===== API =====

    @AuraEnabled(cacheable=true)
    public static Summary getSummary() {
        return PH_DashboardService.getSummary();
    }

    @AuraEnabled(cacheable=true)
    public static DashboardPayload getDashboard(Integer days) {
        DashboardPayload p = new DashboardPayload();
        p.topTxns = PH_DashboardService.getTopTransactions(days);
        p.topQueries = PH_DashboardService.getTopQueries(days);
        p.regressions = PH_DashboardService.getRegressions();
        p.recentAlerts = PH_DashboardService.getRecentAlerts(15);
        return p;
    }

    @AuraEnabled
    public static RunStart startRun(String mode) {
        PH_StoreService.assertAccess();

        PH_Run__c run = new PH_Run__c(
            Name = 'Profiler Run ' + String.valueOf(Datetime.now().getTime()),
            Mode__c = String.isBlank(mode) ? 'Light' : mode,
            Started_At__c = Datetime.now(),
            Status__c = 'Running',
            Logs_Processed__c = 0,
            Transactions_Upserted__c = 0,
            Queries_Upserted__c = 0,
            Daily_Stats_Upserted__c = 0
        );
        insert run;

        RunStart out = new RunStart();
        out.runId = run.Id;
        out.startedAt = run.Started_At__c;
        out.maxLogBytes = PH_Settings.maxLogBytes();
        out.maxLogsPerRun = PH_Settings.maxLogsPerRun();
        return out;
    }

    @AuraEnabled
    public static IngestResult ingestBatch(String runId, String batchJson) {
        PH_StoreService.assertAccess();
        if (String.isBlank(runId)) throw new AuraHandledException('Missing runId.');
        if (String.isBlank(batchJson)) throw new AuraHandledException('Missing batch payload.');
        return PH_StoreService.ingestBatch(runId, batchJson);
    }

    @AuraEnabled
    public static RunFinish finishRun(String runId, String status, String message) {
        PH_StoreService.assertAccess();
        if (String.isBlank(runId)) throw new AuraHandledException('Missing runId.');
        return PH_StoreService.finishRun(runId, status, message);
    }

    @AuraEnabled(cacheable=true)
    public static List<PH_DashboardService.TxnRow> searchTransactions(Datetime startTime, Datetime endTime, String userId, Integer limitSize) {
        return PH_DashboardService.searchTransactions(startTime, endTime, userId, limitSize);
    }

    @AuraEnabled(cacheable=true)
    public static List<PH_DashboardService.QueryRow> getTransactionQueries(Id transactionId) {
        return PH_DashboardService.getTransactionQueries(transactionId);
    }

    @AuraEnabled(cacheable=true)
    public static List<UserPick> searchUsers(String term) {
        String t = String.isBlank(term) ? '%' : ('%' + term.trim() + '%');
        List<User> users = [
            SELECT Id, Name, Username
            FROM User
            WHERE (Name LIKE :t OR Username LIKE :t)
            AND IsActive = true
            ORDER BY Name
            LIMIT 20
        ];

        List<UserPick> out = new List<UserPick>();
        for (User u : users) {
            UserPick p = new UserPick();
            p.id = u.Id;
            p.name = u.Name;
            p.username = u.Username;
            out.add(p);
        }
        return out;
    }

    // Alert rules / scheduling
    @AuraEnabled(cacheable=true)
    public static List<PH_DashboardService.AlertRuleRow> getAlertRules() {
        return PH_DashboardService.getAlertRules();
    }

    @AuraEnabled
    public static Id upsertAlertRule(String ruleJson) {
        PH_StoreService.assertAccess();
        return PH_StoreService.upsertAlertRule(ruleJson);
    }

    @AuraEnabled
    public static void scheduleNightlyAlerts(String cronExpr) {
        PH_AlertScheduler.schedule(cronExpr);
    }

    @AuraEnabled
    public static void runAlertEvaluationNow() {
        PH_AlertEngine.evaluateNow();
    }
}
