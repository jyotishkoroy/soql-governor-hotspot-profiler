@IsTest
public class PH_TestDataFactory {
    public static PH_Run__c makeRun() {
        PH_Run__c r = new PH_Run__c(
            Name = 'Run',
            Mode__c = 'Light',
            Started_At__c = Datetime.now(),
            Status__c = 'Running'
        );
        insert r;
        return r;
    }

    public static PH_Transaction__c makeTxn(Id runId, String extLogId, Integer cpuMs, String sig) {
        PH_Transaction__c t = new PH_Transaction__c(
            Name = sig,
            External_Log_Id__c = extLogId,
            Run__c = runId,
            Start_Time__c = Datetime.now(),
            Signature__c = sig,
            Cpu_Ms__c = cpuMs,
            Soql_Count__c = 2,
            Soql_Ms__c = 20
        );
        insert t;
        return t;
    }

    public static void makeQuery(Id txnId, String extId, String hash, Integer ms) {
        PH_Query__c q = new PH_Query__c(
            Name = hash,
            External_Id__c = extId,
            Transaction__c = txnId,
            Fingerprint_Hash__c = hash,
            Duration_Ms__c = ms,
            Rows__c = 1,
            Soql_Text__c = 'SELECT Id FROM Account'
        );
        insert q;
    }

    public static void makeDailyQueryStat(String hash, Decimal avgMs, Integer countVal) {
        PH_Daily_Query_Stat__c s = new PH_Daily_Query_Stat__c(
            Name = hash,
            External_Id__c = String.valueOf(Date.today()) + ':' + hash,
            Date__c = Date.today(),
            Fingerprint_Hash__c = hash,
            Avg_Ms__c = avgMs,
            P95_Ms__c = avgMs,
            Count__c = countVal
        );
        insert s;
    }

    public static void makeDailyTxnStat(String sig, Decimal avgCpu, Integer countVal) {
        PH_Daily_Txn_Stat__c s = new PH_Daily_Txn_Stat__c(
            Name = sig.left(80),
            External_Id__c = String.valueOf(Date.today()) + ':' + sig,
            Date__c = Date.today(),
            Signature__c = sig,
            Avg_Cpu_Ms__c = avgCpu,
            P95_Cpu_Ms__c = avgCpu,
            Count__c = countVal
        );
        insert s;
    }
}
