@isTest
private class SLeadTriggerHandlerTest {

    @isTest
    static void testAfterInsert_FirstAndLastName_FullNameComposed() {
        Lead std = new Lead(
            FirstName             = 'Alice',
            LastName              = 'Smith',
            Company               = 'Acme',
            Phone__c              = '9000000001',
            Secondary_Phone__c    = '9000000010',
            Email                 = 'alice@example.invalid',
            Secondary_Email__c    = 'alice2@example.invalid',
            Lead_source__c        = 'Website',
            Campaign__c           = 'Spring Launch'
        );

        Test.startTest();
        insert std;
        Test.stopTest();

        Lead__c custom = [
            SELECT Name__c, Lead_First_Name__c, Lead_Last_Name__c,
                   Phone__c, Secondary_Phone__c, Email__c, Secondary_Email__c,
                   Lead_source__c, Allocated_Project__c, Campaign__c
            FROM Lead__c WHERE Phone__c = '9000000001' LIMIT 1
        ];
        System.assertEquals('Alice Smith', custom.Name__c, 'Full name built from FirstName + LastName');
        System.assertEquals('Alice', custom.Lead_First_Name__c, 'FirstName mapped');
        System.assertEquals('Smith', custom.Lead_Last_Name__c, 'LastName mapped');
        System.assertEquals('9000000001', custom.Phone__c, 'Phone copied');
        System.assertEquals('9000000010', custom.Secondary_Phone__c, 'Secondary phone copied');
        System.assertEquals('alice@example.invalid', custom.Email__c, 'Email copied');
        System.assertEquals('alice2@example.invalid', custom.Secondary_Email__c, 'Secondary email copied');
        System.assertEquals('Website', custom.Lead_source__c, 'Lead source copied');
        System.assertEquals(null, custom.Allocated_Project__c, 'Allocated project mapping line executed (null in -> null out)');
        System.assertEquals('Spring Launch', custom.Campaign__c, 'Campaign text copied');

        Integer remainingStd = [SELECT COUNT() FROM Lead WHERE Phone__c = '9000000001'];
        System.assertEquals(0, remainingStd, 'Standard Lead deleted asynchronously');
    }

    @isTest
    static void testAfterInsert_LastNameOnly_UsesLastName() {
        Lead std = new Lead(
            LastName       = 'Jones',
            Company        = 'Acme',
            Phone__c       = '9000000002',
            Lead_source__c = 'Website'
        );

        Test.startTest();
        insert std;
        Test.stopTest();

        Lead__c custom = [SELECT Name__c FROM Lead__c WHERE Phone__c = '9000000002' LIMIT 1];
        System.assertEquals('Jones', custom.Name__c, 'Last name used as full name when FirstName is blank');
    }

    @isTest
    static void testAfterInsert_BlankNames_FallsBackToPhone() {
        Lead mocked = new Lead(LastName = '', Phone__c = '9000000003');

        Test.startTest();
        SLeadTriggerHandler.pushToCustomLead(new List<Lead>{ mocked });
        Test.stopTest();

        Lead__c custom = [SELECT Name__c FROM Lead__c WHERE Phone__c = '9000000003' LIMIT 1];
        System.assertEquals('9000000003', custom.Name__c, 'Phone used as fallback when names are blank');
    }

    @isTest
    static void testAfterInsert_BulkInsert_HandlesAllRecords() {
        List<Lead> bulkLeads = new List<Lead>();
        for (Integer i = 0; i < 200; i++) {
            bulkLeads.add(new Lead(
                FirstName      = 'Bulk',
                LastName       = 'Lead' + i,
                Company        = 'Acme',
                Phone__c       = '9100000' + String.valueOf(i).leftPad(3, '0'),
                Lead_source__c = 'Website'
            ));
        }

        Test.startTest();
        insert bulkLeads;
        Test.stopTest();

        Integer customCount = [SELECT COUNT() FROM Lead__c WHERE Phone__c LIKE '9100000%'];
        System.assertEquals(200, customCount, 'All 200 Lead__c rows created from bulk insert');

        Integer remainingStd = [SELECT COUNT() FROM Lead WHERE Phone__c LIKE '9100000%'];
        System.assertEquals(0, remainingStd, 'All 200 standard Leads deleted asynchronously');
    }

    @isTest
    static void testPushToCustomLead_EmptyList_IsNoop() {
        Test.startTest();
        SLeadTriggerHandler.pushToCustomLead(new List<Lead>());
        Test.stopTest();

        Integer customCount = [SELECT COUNT() FROM Lead__c];
        System.assertEquals(0, customCount, 'Empty list does not insert any Lead__c');
    }

    @isTest
    static void testDeleteStandardLeads_NonexistentIds_NoDelete() {
        String keyPrefix = Lead.SObjectType.getDescribe().getKeyPrefix();
        Set<Id> fakeIds = new Set<Id>{ Id.valueOf(keyPrefix + '000000000000') };

        Test.startTest();
        SLeadTriggerHandler.deleteStandardLeads(fakeIds);
        Test.stopTest();

        // No exception expected. Nothing to assert beyond that.
        System.assert(true, 'deleteStandardLeads handles unknown Ids without throwing');
    }
}