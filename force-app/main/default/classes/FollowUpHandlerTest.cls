@isTest
private class FollowUpHandlerTest {

    private static Lead__c createLead(String phone) {
        Lead__c ld = new Lead__c(
            Name__c = 'FU Handler Lead',
            Phone__c = phone,
            Secondary_Phone__c = '9000000099',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;
        return ld;
    }

    // MapPhoneNumbers — maps Lead phone fields to Follow_up__c
    @isTest
    static void testMapPhoneNumbers() {
        Lead__c ld = createLead('9000000001');

        Follow_up__c fu = new Follow_up__c(CLead__c = ld.Id, Status__c = 'Scheduled');
        List<Follow_up__c> fuList = new List<Follow_up__c>{ fu };

        Test.startTest();
        FollowUpHandler.MapPhoneNumbers(fuList);
        Test.stopTest();

        System.assertEquals('9000000001', fuList[0].Primary_Phone__c, 'Primary phone should be mapped');
        System.assertEquals('9000000099', fuList[0].Secondary_Phone__c, 'Secondary phone should be mapped');
    }

    // MapPhoneNumbers — null/empty list guard
    @isTest
    static void testMapPhoneNumbers_NullAndEmpty() {
        Test.startTest();
        FollowUpHandler.MapPhoneNumbers(null);
        FollowUpHandler.MapPhoneNumbers(new List<Follow_up__c>());
        Test.stopTest();
    }

    // MapPhoneNumbers — CLead__c is null (no phone mapping)
    @isTest
    static void testMapPhoneNumbers_NoCLead() {
        Follow_up__c fu = new Follow_up__c(Status__c = 'Scheduled');
        List<Follow_up__c> fuList = new List<Follow_up__c>{ fu };

        Test.startTest();
        FollowUpHandler.MapPhoneNumbers(fuList);
        Test.stopTest();

        System.assertEquals(null, fuList[0].Primary_Phone__c, 'No phone mapping when CLead is null');
    }

    // validateSingleScheduledFollowup — no duplicate (insert succeeds)
    @isTest
    static void testValidateSingleScheduled_NoDuplicate() {
        Lead__c ld = createLead('9000000002');

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            OwnerId = UserInfo.getUserId()
        );

        Test.startTest();
        FollowUpHandler.validateSingleScheduledFollowup(new List<Follow_up__c>{ fu });
        Test.stopTest();
    }

    // validateSingleScheduledFollowup — duplicate exists (addError)
    @isTest
    static void testValidateSingleScheduled_Duplicate() {
        Lead__c ld = createLead('9000000003');

        Follow_up__c existing = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Scheduled_Date__c = System.now().addDays(1)
        );
        insert existing;

        Follow_up__c newFu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            OwnerId = UserInfo.getUserId()
        );

        Test.startTest();
        FollowUpHandler.validateSingleScheduledFollowup(new List<Follow_up__c>{ newFu });
        Test.stopTest();
    }

    // validateSingleScheduledFollowup — empty leadIds (early return)
    @isTest
    static void testValidateSingleScheduled_Empty() {
        Follow_up__c fu = new Follow_up__c(Status__c = 'Completed');
        Test.startTest();
        FollowUpHandler.validateSingleScheduledFollowup(new List<Follow_up__c>{ fu });
        Test.stopTest();
    }

    // updateLeadFollowupDates
    @isTest
    static void testUpdateLeadFollowupDates() {
        Lead__c ld = createLead('9000000004');

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Scheduled_Date__c = System.now().addDays(2)
        );
        insert fu;

        Test.startTest();
        FollowUpHandler.updateLeadFollowupDates(new List<Follow_up__c>{ fu });
        Test.stopTest();

        Lead__c updated = [SELECT Next_Followup_Date__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertNotEquals(null, updated.Next_Followup_Date__c, 'Next followup date should be set');
    }

    // updateLeadFollowupDates — CLead__c null (no update)
    @isTest
    static void testUpdateLeadFollowupDates_NoCLead() {
        Follow_up__c fu = new Follow_up__c(Status__c = 'Scheduled');
        Integer leadCountBefore = [SELECT COUNT() FROM Lead__c];

        Test.startTest();
        FollowUpHandler.updateLeadFollowupDates(new List<Follow_up__c>{ fu });
        Test.stopTest();

        Integer leadCountAfter = [SELECT COUNT() FROM Lead__c];
        System.assertEquals(leadCountBefore, leadCountAfter, 'Null CLead path should not change leads');
    }

    // updateLatestFollowupSubject — status changes to Completed
    @isTest
    static void testUpdateLatestFollowupSubject() {
        Lead__c ld = createLead('9000000005');

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Subject__c = 'Initial Call',
            Scheduled_Date__c = System.now().addDays(1)
        );
        insert fu;

        Map<Id, Follow_up__c> oldMap = new Map<Id, Follow_up__c>{
            fu.Id => new Follow_up__c(Id = fu.Id, CLead__c = ld.Id, Status__c = 'Scheduled', Subject__c = 'Initial Call')
        };
        fu.Status__c = 'Completed';

        Test.startTest();
        FollowUpHandler.updateLatestFollowupSubject(new List<Follow_up__c>{ fu }, oldMap);
        Test.stopTest();

        Lead__c updated = [SELECT Latest_Followup_Subject__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals('Initial Call', updated.Latest_Followup_Subject__c);
    }

    // updateLatestFollowupSubject — status NOT changing to Completed (early return)
    @isTest
    static void testUpdateLatestFollowupSubject_NoChange() {
        Lead__c ld = createLead('9000000006');

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Subject__c = 'Call',
            Scheduled_Date__c = System.now().addDays(1)
        );
        insert fu;

        Map<Id, Follow_up__c> oldMap = new Map<Id, Follow_up__c>{
            fu.Id => new Follow_up__c(Id = fu.Id, CLead__c = ld.Id, Status__c = 'Scheduled', Subject__c = 'Call')
        };

        Test.startTest();
        FollowUpHandler.updateLatestFollowupSubject(new List<Follow_up__c>{ fu }, oldMap);
        Test.stopTest();

        Lead__c unchanged = [SELECT Latest_Followup_Subject__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertNotEquals('Call', unchanged.Latest_Followup_Subject__c,
            'No status change to Completed should NOT update the lead subject');
    }
}