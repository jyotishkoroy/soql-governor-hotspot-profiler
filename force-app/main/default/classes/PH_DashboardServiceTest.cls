@IsTest
private class PH_DashboardServiceTest {
    @IsTest
    static void testDashboardQueries() {
        PH_Run__c run = PH_TestDataFactory.makeRun();
        PH_Transaction__c txn = PH_TestDataFactory.makeTxn(run.Id, '07L000000000002AAA', 120, 'MyClass.doWork');
        PH_TestDataFactory.makeQuery(txn.Id, '07L000000000002AAA:1', 'hash1', 30);

        PH_TestDataFactory.makeDailyQueryStat('hash1', 25, 10);
        PH_TestDataFactory.makeDailyTxnStat('MyClass.doWork', 200, 4);

        Test.startTest();
        PH_AppController.Summary s = PH_DashboardService.getSummary();
        List<PH_DashboardService.TopTxn> topT = PH_DashboardService.getTopTransactions(7);
        List<PH_DashboardService.TopQuery> topQ = PH_DashboardService.getTopQueries(7);
        Test.stopTest();

        System.assert(s.txns >= 1);
        System.assert(!topT.isEmpty());
        System.assert(!topQ.isEmpty());
    }
}
