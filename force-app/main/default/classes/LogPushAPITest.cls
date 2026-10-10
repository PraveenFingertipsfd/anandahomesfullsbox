/**
 * @description Tests for LogPushAPI (/services/apexrest/LogPush).
 */
@isTest
private class LogPushAPITest {

    private static LogPushAPI.LogPushResponse post(String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/LogPush';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return LogPushAPI.pushLog();
    }

    private static String validBody(String uuid) {
        return JSON.serialize(new Map<String, String>{
            'call_date' => '2026-08-06',
            'call_time' => '14:32:10',
            'caller_number' => '+919876501234',
            'call_direction' => 'inbound',
            'called_number' => '+917290021407',
            'call_status' => 'answered',
            'agent_number' => '+918447513895',
            'call_transfer_status' => 'transferred',
            'caller_duration' => '185',
            'recording_url' => 'https://recordings.example.com/' + uuid + '.mp3',
            'call_uuid' => uuid,
            'hangup_cause' => 'NORMAL_CLEARING',
            'menu_extension' => '2'
        });
    }

    @isTest
    static void pushLog_valid_createsCallDetailLinkedToLead() {
        Lead__c ld = new Lead__c(Name__c = 'Caller Test', Phone__c = '9876501234');
        insert ld;

        Test.startTest();
        LogPushAPI.LogPushResponse res = post(validBody('uuid-001'));
        Test.stopTest();

        System.assertEquals('SUCCESS', res.status, res.message);
        Call_Detail__c cd = [
            SELECT Call_From__c, Call_To__c, Call_Type__c, Call_Status__c, Agent_Number__c,
                   Call_Transfer_Status__c, Hangup_Cause__c, Extension__c, Duration__c,
                   Recording_File__c, ucid__c, Lead__c, Call_Start_Time__c, Call_End_Time__c
            FROM Call_Detail__c WHERE ucid__c = 'uuid-001'
        ];
        System.assertEquals('+919876501234', cd.Call_From__c);
        System.assertEquals('inbound', cd.Call_Type__c);
        System.assertEquals('answered', cd.Call_Status__c);
        System.assertEquals('transferred', cd.Call_Transfer_Status__c);
        System.assertEquals('NORMAL_CLEARING', cd.Hangup_Cause__c);
        System.assertEquals('2', cd.Extension__c);
        System.assertEquals(185, cd.Duration__c);
        System.assertEquals(ld.Id, cd.Lead__c, 'Caller number should link to the matching lead');
        System.assertNotEquals(null, cd.Call_Start_Time__c);
        System.assertEquals(cd.Call_Start_Time__c.addSeconds(185), cd.Call_End_Time__c);
    }

    @isTest
    static void pushLog_duplicateUuid_returnsExistingRecord() {
        post(validBody('uuid-dup'));

        Test.startTest();
        LogPushAPI.LogPushResponse res = post(validBody('uuid-dup'));
        Test.stopTest();

        System.assertEquals('SUCCESS', res.status);
        System.assertEquals(1, [SELECT COUNT() FROM Call_Detail__c WHERE ucid__c = 'uuid-dup'],
            'A retried push must not create a second call detail');
    }

    @isTest
    static void pushLog_missingUuid_fails() {
        LogPushAPI.LogPushResponse res = post('{"caller_number":"9876501234"}');
        System.assertEquals('FAIL', res.status);
        System.assert(res.message.contains('call_uuid'), res.message);
    }

    @isTest
    static void pushLog_missingCaller_fails() {
        LogPushAPI.LogPushResponse res = post('{"call_uuid":"u1"}');
        System.assertEquals('FAIL', res.status);
        System.assert(res.message.contains('caller_number'), res.message);
    }

    @isTest
    static void pushLog_invalidJson_fails() {
        LogPushAPI.LogPushResponse res = post('not-json');
        System.assertEquals('FAIL', res.status);
    }

    @isTest
    static void pushLog_badDateAndDuration_stillCreates() {
        String body = JSON.serialize(new Map<String, String>{
            'call_uuid' => 'uuid-bad',
            'caller_number' => '12345',
            'call_date' => 'not-a-date',
            'caller_duration' => 'NaN'
        });

        Test.startTest();
        LogPushAPI.LogPushResponse res = post(body);
        Test.stopTest();

        System.assertEquals('SUCCESS', res.status, res.message);
        Call_Detail__c cd = [SELECT Call_Start_Time__c, Duration__c FROM Call_Detail__c WHERE ucid__c = 'uuid-bad'];
        System.assertEquals(null, cd.Call_Start_Time__c, 'Unparseable date is stored as null');
        System.assertEquals(null, cd.Duration__c, 'Non-numeric duration is stored as null');
    }
}
