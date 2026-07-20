@isTest
public class SendLeadDetailsToPulseTeleSystem_Test {

    // Mock for HTTP callouts
    private class MockHttpResponse200 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"message":"success"}');
            return res;
        }
    }
    
    private class MockHttpResponse500 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }
    
    @isTest
    static void testEmptyRelatedSources() {
        Boolean threw = false;
        Test.startTest();
        try {
            SendLeadDetailsToPulseTeleSystem.sendLeadDetailsInBulk(new Set<Id>());
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(false, threw, 'Empty input should not raise');
    }
    
    @isTest
    static void testSuccessCallout_withLeadPhone() {
        Lead__c ld = new Lead__c(
            Name__c = 'Test Lead',
            Phone__c = '9988776655',
            OwnerId = UserInfo.getUserId()
        );
        insert ld;
        
        Related_Source__c rs = new Related_Source__c(
            CLead__c = ld.Id,
            Phone__c = '9999999999'
        );
        insert rs;
        
        // Re-query to populate relationship
        rs = [SELECT Id, CLead__r.Id, CLead__r.Extension__c FROM Related_Source__c WHERE Id = :rs.Id];

        Test.setMock(HttpCalloutMock.class, new MockHttpResponse200());
        Test.startTest();
        Boolean threw = false;
        try {
            SendLeadDetailsToPulseTeleSystem.sendLeadDetailsInBulk(new Set<Id>{rs.Id});
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(false, threw, '200 response should complete without throw');
    }

    @isTest
    static void testSuccessCallout_withSecondaryPhone() {
        Lead__c ld = new Lead__c(
            Name__c = 'Test Lead',
            Phone__c = '9988776655',
            OwnerId = UserInfo.getUserId()
        );
        insert ld;
        
        Related_Source__c rs = new Related_Source__c(
            CLead__c = ld.Id,
            Secondary_Phone__c = '8888888888'
        );
        insert rs;

        // Re-query to populate relationship
        rs = [SELECT Id, CLead__r.Id, CLead__r.Extension__c FROM Related_Source__c WHERE Id = :rs.Id];

        Test.setMock(HttpCalloutMock.class, new MockHttpResponse200());
        Test.startTest();
        Boolean threw = false;
        try {
            SendLeadDetailsToPulseTeleSystem.sendLeadDetailsInBulk(new Set<Id>{rs.Id});
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(false, threw, 'Secondary-phone payload should complete without throw');
    }

    @isTest
    static void testErrorResponseCallout() {
        Lead__c ld = new Lead__c(
            Name__c = 'Test Lead',
            Phone__c = '9988776655',
            OwnerId = UserInfo.getUserId()
        );
        insert ld;
        
        Related_Source__c rs = new Related_Source__c(
            CLead__c = ld.Id,
            Phone__c = '7777777777'
        );
        insert rs;

        // Re-query to populate relationship
        rs = [SELECT Id, CLead__r.Id, CLead__r.Extension__c FROM Related_Source__c WHERE Id = :rs.Id];

        Test.setMock(HttpCalloutMock.class, new MockHttpResponse500());
        Test.startTest();
        Boolean threw = false;
        try {
            SendLeadDetailsToPulseTeleSystem.sendLeadDetailsInBulk(new Set<Id>{rs.Id});
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(false, threw, '500 response is handled internally');
    }
}