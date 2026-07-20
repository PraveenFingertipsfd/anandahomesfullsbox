@istest
public class pushToSalesControllerTest {
 @isTest
    public static void method() {
      
          Lead__c lad= new Lead__c();
        lad.Name__c='test';
        lad.Allocated_Project__c = 'The Ozone Heights';
        lad.Phone__c = '9182748514';
        lad.Source_Type__c='Digital';
        lad.Primary_Source__c = 'Digital';
        lad.Lead_Status__c ='New Enquiry';
        lad.OwnerId = UserInfo.getUserId();
        lad.Lead_Assigned__c = false;
        lad.IsPushed__c = true;
        lad.Source_Type__c='Website';
        lad.Allocated_Project__c='The Ozone Heights';
        insert lad;
		
        Site_Visit__c sv=new Site_Visit__c();
        sv.Date__c=System.now()+3;
        sv.Status__c='Scheduled';
        sv.Project__c='The Ozone Heights';
        sv.CLead__c=lad.id;
        insert sv;

        Follow_up__c fup = new Follow_up__c();
        fup.Status__c = 'Scheduled';
        fup.Scheduled_Date__c = System.now() + 3;
        fup.CLead__c = lad.Id;
        insert fup;

        Test.startTest();
        pushToSalesController.moveToSales(lad.Id, 'The Ozone Heights', UserInfo.getUserId());
        pushToSalesController.isSiteVisitScheduled(lad.Id);
        pushToSalesController.CheckFollowups(lad.Id);
        Test.stopTest();

        // Verify lead was pushed
        Lead__c updatedLead = [SELECT Id, IsPushed__c, Lead_Status__c FROM Lead__c WHERE Id = :lad.Id];
        System.assertEquals(true, updatedLead.IsPushed__c, 'Lead should be marked as pushed');
        System.assertEquals('Site Visit Scheduled', updatedLead.Lead_Status__c, 'Lead status should be Site Visit Scheduled when SV exists');

        // Verify follow-up reassigned to sales user
        Follow_up__c updatedFup = [SELECT Id, OwnerId FROM Follow_up__c WHERE Id = :fup.Id];
        System.assertEquals(UserInfo.getUserId(), updatedFup.OwnerId, 'Follow-up should be reassigned to sales user');

        // Verify site visit reassigned to sales user
        Site_Visit__c updatedSv = [SELECT Id, OwnerId, Owner_Changed__c FROM Site_Visit__c WHERE Id = :sv.Id];
        System.assertEquals(UserInfo.getUserId(), updatedSv.OwnerId, 'Site visit should be reassigned to sales user');
        System.assertEquals(true, updatedSv.Owner_Changed__c, 'Owner_Changed__c should be true');
    }

    // Covers the else branch (salesUser blank → Lead_Assigned__c = false)
    // and the Pre_Sales_User__c != null → Lead__Share creation branch
    @isTest
    public static void testMoveToSales_NoSalesUser_WithPreSalesUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User preSalesUser = new User(
            FirstName = 'Pre', LastName = 'SalesUser',
            Username = 'presalesuser' + System.currentTimeMillis() + '@test.com',
            Email = 'presalesuser@test.com', Alias = 'psusr',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert preSalesUser;

        Lead__c lad = new Lead__c();
        lad.Name__c = 'No Sales User Lead';
        lad.Allocated_Project__c = 'The Ozone Heights';
        lad.Phone__c = '9182748515';
        lad.Lead_Status__c = 'New Enquiry';
        lad.OwnerId = UserInfo.getUserId();
        lad.Lead_Assigned__c = false;
        lad.IsPushed__c = false;
        lad.Pre_Sales_User__c = preSalesUser.Id; // triggers Lead__Share creation
        insert lad;

        Test.startTest();
        // Pass blank salesUser → else branch: Lead_Assigned__c = false
        pushToSalesController.moveToSales(lad.Id, 'Note for no sales user', '');
        Test.stopTest();

        Lead__c updatedLead = [SELECT Id, Lead_Assigned__c, IsPushed__c FROM Lead__c WHERE Id = :lad.Id];
        System.assertEquals(false, updatedLead.Lead_Assigned__c, 'Lead should NOT be assigned when salesUser is blank');
        System.assertEquals(true, updatedLead.IsPushed__c, 'IsPushed__c should be true');
    }

    
    
    /** Covers CheckFollowups with no follow-ups for the lead. */
    @isTest
    public static void testCheckFollowups_Empty() {
        Lead__c lad = new Lead__c();
        lad.Name__c = 'No Followups Lead';
        lad.Phone__c = '9182748522';
        lad.Lead_Status__c = 'New Enquiry';
        insert lad;

        Test.startTest();
        Integer count = pushToSalesController.CheckFollowups(lad.Id);
        Test.stopTest();

        System.assertEquals(0, count, 'Should return 0 when no follow-ups exist');
    }

    /** Covers isSiteVisitScheduled false branch (no scheduled SVs). */
    @isTest
    public static void testIsSiteVisitScheduled_False() {
        Lead__c lad = new Lead__c();
        lad.Name__c = 'No SV Scheduled Lead';
        lad.Phone__c = '9182748523';
        lad.Lead_Status__c = 'New Enquiry';
        insert lad;

        Test.startTest();
        Boolean result = pushToSalesController.isSiteVisitScheduled(lad.Id);
        Test.stopTest();

        System.assertEquals(false, result, 'Should return false when no scheduled SV exists');
    }
}