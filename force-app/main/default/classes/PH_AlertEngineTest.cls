@IsTest
private class PH_AlertEngineTest {
    @IsTest
    static void testAlertEvaluationCreatesEvents() {
        PH_TestDataFactory.makeDailyQueryStat('hashX', 80, 50);

        PH_Alert_Rule__c rule = new PH_Alert_Rule__c(
            Name = 'High AvgMs',
            Enabled__c = true,
            Rule_Type__c = 'Query',
            Metric__c = 'AvgMs',
            Threshold__c = 50,
            Window_Days__c = '7'
        );
        insert rule;

        Test.startTest();
        PH_AlertEngine.evaluateNow();
        Test.stopTest();

        System.assert([SELECT COUNT() FROM PH_Alert_Event__c] >= 1);
    }
}
