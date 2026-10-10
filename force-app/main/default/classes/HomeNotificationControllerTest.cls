// Last Modified: 2026-03-31
@isTest
public class HomeNotificationControllerTest {

    @isTest
    public static void testAllMethods() {
        // Create custom Lead record
        Lead__c testLead = new Lead__c(
            Name__c = 'Test Lead',
            Lead_Status__c = 'New Enquiry',
            Phone__c = '9876543210'
        );
        insert testLead;

        // Create Follow_Up linked to custom Lead
        Follow_up__c fu = new Follow_up__c();
        fu.Status__c = 'Scheduled';
        fu.Comments__c = 'test';
        fu.Scheduled_Date__c = System.now().addMinutes(5);
        fu.CLead__c = testLead.Id;
        insert fu;

        // Create Site_Visit linked to custom Lead
        Site_Visit__c sv = new Site_Visit__c();
        sv.Status__c = 'Scheduled';
        sv.Date__c = System.now().addDays(1);
        sv.CLead__c = testLead.Id;
        insert sv;

        List<Follow_Up__c> followUps = HomeNotificationController.getFollowUpInformation();
        List<Site_Visit__c> siteVisits = HomeNotificationController.getSiteVistInformation();
        List<Follow_Up__c> pendingFollowUps = HomeNotificationController.getPendingFollowUpInformation();
        List<Site_Visit__c> pendingSiteVisits = HomeNotificationController.getPendingSiteVistInformation();

        System.assertNotEquals(null, followUps, 'followUps list returned');
        System.assertNotEquals(null, siteVisits, 'siteVisits list returned');
        System.assertNotEquals(null, pendingFollowUps, 'pendingFollowUps list returned');
        System.assertNotEquals(null, pendingSiteVisits, 'pendingSiteVisits list returned');

        // Move Scheduled_Date into the past (allowed on update — Schedule_Date rule is insert-only)
        // so the controller's Completed_Date__c = now stamp passes Completed_Date_after_the_Schedule_Date.
        fu.Scheduled_Date__c = System.now().addMinutes(-5);
        update fu;

        String updateFollowupResult = HomeNotificationController.updateFollowupDetails(fu.Id, 'Completed', 'testing');
        System.assertNotEquals(null, updateFollowupResult, 'updateFollowupDetails returned status');

        Follow_up__c afterFu = [SELECT Status__c FROM Follow_up__c WHERE Id = :fu.Id];
        System.assertEquals('Completed', afterFu.Status__c, 'Follow-up status updated');

        HomeNotificationController.datawrapper leadsData = HomeNotificationController.todaysLeads(10, 1);
        System.assertNotEquals(null, leadsData, 'todaysLeads returned wrapper');

        String userName = HomeNotificationController.getUserName();
        System.assertNotEquals(null, userName, 'getUserName returned a value');
    }

    // Covers todaysLeads 'Pre-Sales Executive' profile branch.
    // Skipped gracefully if the profile does not exist in this org.
    @isTest
    static void testTodaysLeads_PreSalesExecutiveProfile() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Pre-Sales Executive' LIMIT 1];
        if (profiles.isEmpty()) return;

        User testUser = new User(
            FirstName = 'PreSales', LastName = 'ExecUser',
            Username = 'presalesexec' + System.currentTimeMillis() + '@test.com',
            Email = 'presalesexec@test.com', Alias = 'psexec',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = profiles[0].Id
        );
        insert testUser;

        System.runAs(testUser) {
            Test.startTest();
            HomeNotificationController.datawrapper result = HomeNotificationController.todaysLeads(10, 1);
            Test.stopTest();
            System.assertNotEquals(null, result);
        }
    }

    // Covers todaysLeads 'Sales' profile branch.
    // Skipped gracefully if the profile does not exist in this org.
    @isTest
    static void testTodaysLeads_SalesProfile() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Sales' LIMIT 1];
        if (profiles.isEmpty()) return;

        User testUser = new User(
            FirstName = 'SalesProf', LastName = 'TestUser',
            Username = 'salesprof' + System.currentTimeMillis() + '@test.com',
            Email = 'salesprof@test.com', Alias = 'salpr',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = profiles[0].Id
        );
        insert testUser;

        System.runAs(testUser) {
            Test.startTest();
            HomeNotificationController.datawrapper result = HomeNotificationController.todaysLeads(10, 1);
            Test.stopTest();
            System.assertNotEquals(null, result);
        }
    }

    /** Covers the Completed path: ensures Completed_Date__c is auto-stamped so the
     *  Follow_ups_Completed_Date validation rule doesn't block the dashboard's
     *  Change-Status flow.
     */
    @isTest
    static void testUpdateFollowupDetails_CompletedStampsDate() {
        Lead__c testLead = new Lead__c(
            Name__c = 'Completed Lead',
            Lead_Status__c = 'New Enquiry',
            Phone__c = '9876500000'
        );
        insert testLead;

        Follow_up__c fu = new Follow_up__c();
        fu.Status__c = 'Scheduled';
        fu.Comments__c = 'initial';
        fu.Scheduled_Date__c = System.now().addMinutes(5);
        fu.CLead__c = testLead.Id;
        fu.Call_Duration_In_Mins__c = 0;
        insert fu;

        // Move Scheduled_Date into the past (allowed on update — Schedule_Date rule is insert-only)
        // so the controller's Completed_Date__c = now stamp passes Completed_Date_after_the_Schedule_Date.
        fu.Scheduled_Date__c = System.now().addMinutes(-5);
        update fu;

        Test.startTest();
        String result = HomeNotificationController.updateFollowupDetails(fu.Id, 'Completed', 'Done');
        Test.stopTest();

        System.assertEquals('Updated', result, 'Completed update should succeed');
        Follow_up__c after = [
            SELECT Status__c, Comments__c, Completed_Date__c, Call_Duration_In_Mins__c
            FROM Follow_up__c
            WHERE Id = :fu.Id
        ];
        System.assertEquals('Completed', after.Status__c);
        System.assertEquals('Done', after.Comments__c);
        System.assertNotEquals(null, after.Completed_Date__c, 'Completed_Date__c should be stamped');
        System.assertNotEquals(null, after.Call_Duration_In_Mins__c, 'Call_Duration_In_Mins__c should be set');
    }

    /** Covers the catch branch: DML failure should be rethrown as AuraHandledException
     *  so the Aura helper can surface a real error toast. Trips
     *  Follow_Ups_Remarks_Mandatory by clearing Comments__c on a Completed flip.
     */
    @isTest
    static void testUpdateFollowupDetails_DmlFailureSurfacesError() {
        Lead__c testLead = new Lead__c(
            Name__c = 'DML Failure Lead',
            Lead_Status__c = 'New Enquiry',
            Phone__c = '9876500001'
        );
        insert testLead;

        Follow_up__c fu = new Follow_up__c();
        fu.Status__c = 'Scheduled';
        fu.Comments__c = 'initial';
        fu.Scheduled_Date__c = System.now().addMinutes(5);
        fu.CLead__c = testLead.Id;
        fu.Call_Duration_In_Mins__c = 0;
        insert fu;

        Boolean threw = false;
        Test.startTest();
        try {
            // Passing null Remarks clears Comments__c, tripping Follow_Ups_Remarks_Mandatory.
            HomeNotificationController.updateFollowupDetails(fu.Id, 'Completed', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Validation failure should surface as AuraHandledException');
    }

    /** Covers the Cancelled path used by the dashboard's Change-Status modal:
     *  status is persisted as-is with remarks, and the Completed-only defaults
     *  (Completed_Date__c / Call_Duration_In_Mins__c) are NOT stamped.
     */
    @isTest
    static void testUpdateFollowupDetails_Cancelled() {
        Lead__c testLead = new Lead__c(
            Name__c = 'Cancelled Lead',
            Lead_Status__c = 'New Enquiry',
            Phone__c = '9876500002'
        );
        insert testLead;

        Follow_up__c fu = new Follow_up__c();
        fu.Status__c = 'Scheduled';
        fu.Comments__c = 'initial';
        fu.Scheduled_Date__c = System.now().addMinutes(5);
        fu.CLead__c = testLead.Id;
        insert fu;

        Test.startTest();
        String result = HomeNotificationController.updateFollowupDetails(fu.Id, 'Cancelled', 'Customer not reachable');
        Test.stopTest();

        System.assertEquals('Updated', result, 'Cancelled update should succeed');
        Follow_up__c after = [
            SELECT Status__c, Comments__c, Completed_Date__c
            FROM Follow_up__c
            WHERE Id = :fu.Id
        ];
        System.assertEquals('Cancelled', after.Status__c);
        System.assertEquals('Customer not reachable', after.Comments__c);
        System.assertEquals(null, after.Completed_Date__c, 'Completed_Date__c should not be stamped for Cancelled');
    }

    /** Covers updateFollowupDetails 'Record not found' branch (line 49). */
    @isTest
    static void testUpdateFollowupDetails_NotFound() {
        // Synthetic non-existent Follow_Up__c Id
        String fakeIdStr = Follow_Up__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';

        Test.startTest();
        String result = HomeNotificationController.updateFollowupDetails(fakeIdStr, 'Completed', 'remarks');
        Test.stopTest();

        System.assertEquals('Record not found', result, 'Should return Record not found for non-existent Id');
    }

    /** Covers todaysLeads default branch (profile != Pre-Sales Executive AND != Sales).
     *  Standard User profile is the fallback in tests run as the test user.
     */
    @isTest
    static void testTodaysLeads_DefaultBranch() {
        // The test runner user typically has 'System Administrator' or 'Standard User'
        // profile, which falls through to the else branch (line 84).
        Test.startTest();
        HomeNotificationController.datawrapper result = HomeNotificationController.todaysLeads(10, 1);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.todaysldCount, 'todaysldCount should be set');
    }

    
}