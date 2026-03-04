@IsTest
private class PH_StoreServiceTest {
    @IsTest
    static void testIngestBatchAndFinish() {
        PH_Run__c run = PH_TestDataFactory.makeRun();

        String batch = JSON.serialize(new Map<String, Object>{
            'logsProcessed' => 1,
            'transactions' => new List<Object>{
                new Map<String, Object>{
                    'externalLogId' => '07L000000000001AAA',
                    'startTime' => Datetime.now(),
                    'userId' => UserInfo.getUserId(),
                    'operation' => 'ExecuteAnonymous',
                    'request' => 'ExecuteAnonymous',
                    'status' => 'Success',
                    'entryPoint' => 'Anonymous',
                    'signature' => 'Anonymous',
                    'cpuMs' => 50,
                    'soqlCount' => 2,
                    'soqlMs' => 10,
                    'rows' => 3,
                    'dmlCount' => 1,
                    'heapBytes' => 12345,
                    'calloutCount' => 0
                }
            },
            'queries' => new List<Object>{
                new Map<String, Object>{
                    'externalId' => '07L000000000001AAA:1',
                    'transactionExternalLogId' => '07L000000000001AAA',
                    'fingerprintHash' => 'abc123',
                    'fingerprint' => 'select id from account where name = ?',
                    'sobjectName' => 'Account',
                    'fields' => 'Name',
                    'durationMs' => 5,
                    'rows' => 1,
                    'soqlText' => 'SELECT Id FROM Account WHERE Name=\'X\''
                }
            },
            'dailyQueryStats' => new List<Object>{
                new Map<String, Object>{
                    'externalId' => String.valueOf(Date.today()) + ':abc123',
                    'statDate' => Date.today(),
                    'fingerprintHash' => 'abc123',
                    'sampleSoql' => 'SELECT Id FROM Account WHERE Name=\'X\'',
                    'sobjectName' => 'Account',
                    'fields' => 'Name',
                    'countVal' => 1,
                    'avgMs' => 5.0,
                    'p95Ms' => 5.0,
                    'avgRows' => 1.0,
                    'maxRows' => 1,
                    'suspectScore' => 1.0
                }
            },
            'dailyTxnStats' => new List<Object>{
                new Map<String, Object>{
                    'externalId' => String.valueOf(Date.today()) + ':Anonymous',
                    'statDate' => Date.today(),
                    'signature' => 'Anonymous',
                    'countVal' => 1,
                    'avgCpuMs' => 50.0,
                    'p95CpuMs' => 50.0,
                    'avgSoqlCount' => 2.0,
                    'avgSoqlMs' => 10.0
                }
            }
        });

        Test.startTest();
        PH_AppController.IngestResult res = PH_StoreService.ingestBatch(run.Id, batch);
        PH_AppController.RunFinish fin = PH_StoreService.finishRun(run.Id, 'Success', 'OK');
        Test.stopTest();

        System.assertNotEquals(null, res);
        System.assert(res.transactionsUpserted >= 1);
        System.assertEquals('Success', fin.status);

        System.assertEquals(1, [SELECT COUNT() FROM PH_Transaction__c]);
        System.assertEquals(1, [SELECT COUNT() FROM PH_Query__c]);
        System.assertEquals(1, [SELECT COUNT() FROM PH_Daily_Query_Stat__c]);
        System.assertEquals(1, [SELECT COUNT() FROM PH_Daily_Txn_Stat__c]);
    }
}
