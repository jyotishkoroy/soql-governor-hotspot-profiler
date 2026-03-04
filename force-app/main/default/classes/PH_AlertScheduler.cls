public with sharing class PH_AlertScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        PH_AlertEngine.evaluateNow();
    }

    @AuraEnabled
    public static void schedule(String cronExpr) {
        if (String.isBlank(cronExpr)) cronExpr = '0 10 2 * * ?'; // 02:10 daily
        System.schedule('PH_NightlyAlerts', cronExpr, new PH_AlertScheduler());
    }
}
