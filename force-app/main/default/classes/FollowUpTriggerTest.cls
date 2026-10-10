@isTest
private class FollowUpTriggerTest {

    @TestSetup
    static void setup() {
        Lead__c ld = new Lead__c(
            Name__c = 'FU Trigger Lead',
            Phone__c = '9000100001',
            Secondary_Phone__c = '9000100002',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;
    }

    // Before insert: MapPhoneNumbers + validateSingleScheduledFollowup
    // After insert: updateLeadFollowupDates
    @isTest
    static void testInsertFollowUp() {
        Lead__c ld = [SELECT Id FROM Lead__c WHERE Phone__c = '9000100001' LIMIT 1];

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Scheduled_Date__c = System.now().addDays(1),
            Comments__c = 'Test insert',
            Mode_of_Communication__c = 'Whatsapp'
        );

        Test.startTest();
        insert fu;
        Test.stopTest();

        Follow_up__c inserted = [SELECT Primary_Phone__c, Secondary_Phone__c FROM Follow_up__c WHERE Id = :fu.Id];
        System.assertEquals('9000100001', inserted.Primary_Phone__c, 'Primary phone should be mapped from lead');

        Lead__c updatedLd = [SELECT Next_Followup_Date__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertNotEquals(null, updatedLd.Next_Followup_Date__c, 'Lead followup date should be set');
    }

    // After update: updateLatestFollowupSubject (Scheduled → Completed)
    @isTest
    static void testUpdateFollowUp_ToCompleted() {
        Lead__c ld = [SELECT Id FROM Lead__c WHERE Phone__c = '9000100001' LIMIT 1];

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Subject__c = 'Discovery Call',
            Scheduled_Date__c = System.now().addDays(1),
            Mode_of_Communication__c = 'Whatsapp'
        );
        insert fu;

        fu.Status__c = 'Completed';
        // Completed_Date must not be earlier than Scheduled_Date (Completed_Date_after_the_Schedule_Date rule)
        fu.Completed_Date__c = System.now().addDays(3);
        fu.Comments__c = 'Completed remark for validation';
        fu.Call_Duration_In_Mins__c = 30;

        Test.startTest();
        update fu;
        Test.stopTest();

        Lead__c updatedLd = [SELECT Latest_Followup_Subject__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals('Discovery Call', updatedLd.Latest_Followup_Subject__c);
    }

    // After update: status does NOT change to Completed (no subject update)
    @isTest
    static void testUpdateFollowUp_NoStatusChange() {
        Lead__c ld = [SELECT Id FROM Lead__c WHERE Phone__c = '9000100001' LIMIT 1];

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Subject__c = 'Pricing Discussion',
            Scheduled_Date__c = System.now().addDays(1),
            Mode_of_Communication__c = 'Whatsapp'
        );
        insert fu;

        fu.Comments__c = 'Updated comments only';

        Test.startTest();
        update fu;
        Test.stopTest();

        Lead__c unchanged = [SELECT Latest_Followup_Subject__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertNotEquals('Pricing Discussion', unchanged.Latest_Followup_Subject__c,
            'Subject should NOT propagate when status did not change to Completed');
    }

    // Bulk insert — one follow-up per lead to avoid duplicate Id in updateLeadFollowupDates
    @isTest
    static void testBulkInsert() {
        List<Lead__c> leads = new List<Lead__c>();
        for (Integer i = 0; i < 50; i++) {
            leads.add(new Lead__c(
                Name__c = 'Bulk Lead ' + i,
                Phone__c = '90001100' + String.valueOf(i).leftPad(2, '0'),
                Allocated_Project__c = 'The Ozone Heights'
            ));
        }
        insert leads;

        List<Follow_up__c> fuList = new List<Follow_up__c>();
        for (Integer i = 0; i < 50; i++) {
            fuList.add(new Follow_up__c(
                CLead__c = leads[i].Id,
                Status__c = 'Scheduled',
                Scheduled_Date__c = System.now().addDays(i + 1)
            ));
        }

        Test.startTest();
        insert fuList;
        Test.stopTest();

        System.assertEquals(50, fuList.size());
        Integer inserted = [SELECT COUNT() FROM Follow_up__c WHERE Status__c = 'Scheduled'];
        System.assertEquals(50, inserted, 'All 50 bulk follow-ups persisted');
    }

    // Update to Completed without Subject — verifies subject update guard
    @isTest
    static void testUpdateFollowUp_CompletedWithoutSubject() {
        Lead__c ld = [SELECT Id FROM Lead__c WHERE Phone__c = '9000100001' LIMIT 1];

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Scheduled',
            Scheduled_Date__c = System.now().addDays(1),
            Mode_of_Communication__c = 'Whatsapp'
        );
        insert fu;

        fu.Status__c = 'Completed';
        // Completed_Date must not be earlier than Scheduled_Date (Completed_Date_after_the_Schedule_Date rule)
        fu.Completed_Date__c = System.now().addDays(3);
        fu.Call_Duration_In_Mins__c = 25;
        fu.Comments__c = 'Completion without subject';

        Test.startTest();
        update fu;
        Test.stopTest();

        Lead__c unchangedLd = [SELECT Latest_Followup_Subject__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals(null, unchangedLd.Latest_Followup_Subject__c,
            'Latest subject should remain null when follow-up subject is blank');
    }

    // Status change from Pending to Completed — covers oldStatus != 'Completed' check
    @isTest
    static void testUpdateFollowUp_StatusChangedFromPending() {
        Lead__c ld = [SELECT Id FROM Lead__c WHERE Phone__c = '9000100001' LIMIT 1];

        Follow_up__c fu = new Follow_up__c(
            CLead__c = ld.Id,
            Status__c = 'Pending',
            Subject__c = 'Resolution Call',
            Scheduled_Date__c = System.now().addDays(2),
            Mode_of_Communication__c = 'Phone'
        );
        insert fu;

        fu.Status__c = 'Completed';
        // Completed_Date must not be earlier than Scheduled_Date (Completed_Date_after_the_Schedule_Date rule)
        fu.Completed_Date__c = System.now().addDays(3);
        fu.Call_Duration_In_Mins__c = 45;
        fu.Comments__c = 'Resolved pending issue';

        Test.startTest();
        update fu;
        Test.stopTest();

        Lead__c updatedLd = [SELECT Latest_Followup_Subject__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals('Resolution Call', updatedLd.Latest_Followup_Subject__c,
            'Subject should update when status changes from Pending to Completed');
    }

    // Insert Follow_up without CLead — verifies null CLead guard in handlers
    @isTest
    static void testInsertFollowUp_WithoutCLead() {
        Follow_up__c fu = new Follow_up__c(
            Status__c = 'Scheduled',
            Subject__c = 'Orphaned Follow-up',
            Scheduled_Date__c = System.now().addDays(1),
            Mode_of_Communication__c = 'WhatsApp'
        );

        Test.startTest();
        insert fu;
        Test.stopTest();

        Follow_up__c inserted = [SELECT Primary_Phone__c, Secondary_Phone__c FROM Follow_up__c WHERE Id = :fu.Id];
        System.assertEquals(null, inserted.Primary_Phone__c, 'Phone should remain null for orphaned follow-up');
        System.assertEquals(null, inserted.Secondary_Phone__c, 'Secondary phone should remain null for orphaned follow-up');
    }
}