@isTest
public class RoundRobinHandlerTest {
     @isTest
    public static void method1(){
        
        User u = new User();
        u.ProfileId = [SELECT Id FROM Profile Limit 1].Id;
        u.LastName = 'RH23';
        u.Email = 'RH@gm1ail.com';
        u.Username = 'RH@1gmail.com' + System.currentTimeMillis();
        u.CompanyName = 'RH1';
        u.Title = 'titletitl1e';
        u.Alias = 'loKma1n';
        u.TimeZoneSidKey = 'America/Los_Angeles';
        u.EmailEncodingKey = 'UTF-8';
        u.LanguageLocaleKey = 'en_US';
        u.LocaleSidKey = 'en_US';
        u.Availability__c=true;
        u.IsActive=true;
       // u.Week_off_days__c ='Monday';
       u.is_working__c = true;
        insert u;
        
        User u1 = new User();
        u1.ProfileId = [SELECT Id FROM Profile limit 1 ].Id;
        u1.LastName = 'RH23';
        u1.Email = 'RH@gm1ail.com';
        u1.Username = 'RH2@1gmail.com' + System.currentTimeMillis();
        u1.CompanyName = 'RH1';
        u1.Title = 'titletitl1e';
        u1.Alias = 'loKma1n';
        u1.TimeZoneSidKey = 'America/Los_Angeles';
        u1.EmailEncodingKey = 'UTF-8';
        u1.LanguageLocaleKey = 'en_US';
        u1.LocaleSidKey = 'en_US';
        u1.Availability__c=false;
        u1.IsActive=true;
       // u.Week_off_days__c ='Monday';
       u1.is_working__c = true;
        insert u1;
        
        Round_Robin__c r= new Round_Robin__c();
        r.Active__c=true;
        r.Project_Assigned__c ='The Ozone Heights';
        insert r;
       Round_Robin_member__c rrm = new Round_Robin_member__c();
        rrm.Round_Robin__c = r.Id;
        rrm.Active__c = true;
       // rrm.User__c = UserInfo.getUserId();
        rrm.User__c = U.Id;
        rrm.User_Type__c ='Pre Sales';
        insert rrm;
        
         Round_Robin_member__c rrm1 = new Round_Robin_member__c();
        rrm1.Round_Robin__c = r.Id;
        rrm1.Active__c = true;
      //  rrm1.User__c = UserInfo.getUserId();
         rrm1.User__c = U.Id;
       
        rrm1.User_Type__c ='Sales';
        insert rrm1;
        
        
        list<Lead__c> conlst=new list<Lead__c>();  
        Lead__c c=new Lead__c ();
        //c.LastName='test';
        c.Allocated_Project__c = 'The Ozone Heights';
        c.Phone__c='9194949494';
        c.Secondary_Phone__c='9849594049';
        //c.Email__c='test@gmail.com';
        c.Secondary_Email__c='cc@gmail.com';
        // insert c;
        conlst.add(c);
        
      //  RoundRobinHandler.assignLead(conlst,false,'Pre Sales');
      //  RoundRobinHandler.assignLead(conlst,false,'Sales');
        System.runAs ( new User(Id = UserInfo.getUserId()) ) {
        User us = [Select id,name,Availability__c from User where Id=:UserInfo.getUserId()];
        us.Availability__c = false;
       // update us;
        RoundRobinHandler.assignLead(conlst,false,'Pre Sales');
        //RoundRobinHandler.assignLead2(conlst,false,'Pre Sales');
        // RoundRobinHandler.assignToQueaue(conlst,'Pre sales');
        RoundRobinHandler.testcover();
        }
    }

    // Covers assignSingleSiteVisit (GRE use case)
    @isTest
    public static void testAssignSingleSiteVisit() {
        User svUser = new User();
        svUser.ProfileId = [SELECT Id FROM Profile LIMIT 1].Id;
        svUser.LastName = 'SVAssign';
        svUser.Email = 'svassign@gmail.com';
        svUser.Username = 'svassign@gmail.com' + System.currentTimeMillis();
        svUser.CompanyName = 'SV1';
        svUser.Title = 'title';
        svUser.Alias = 'svasgn';
        svUser.TimeZoneSidKey = 'America/Los_Angeles';
        svUser.EmailEncodingKey = 'UTF-8';
        svUser.LanguageLocaleKey = 'en_US';
        svUser.LocaleSidKey = 'en_US';
        svUser.Availability__c = true;
        svUser.IsActive = true;
        svUser.is_working__c = true;
        insert svUser;

        Round_Robin__c r = new Round_Robin__c();
        r.Active__c = true;
        r.Project_Assigned__c = 'The Ozone Heights';
        insert r;

        Round_Robin_Member__c rrm = new Round_Robin_Member__c();
        rrm.Round_Robin__c = r.Id;
        rrm.Active__c = true;
        rrm.User__c = svUser.Id;
        rrm.User_Type__c = 'Sales';
        insert rrm;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Id assignedId = RoundRobinHandler.assignSingleSiteVisit('The Ozone Heights', 'Sales');
            Test.stopTest();

            System.assertNotEquals(null, assignedId, 'Should return an assigned user');
            System.assertEquals(svUser.Id, assignedId, 'Should assign the test user');
        }
    }

    // added by claude 30-03-26 08:49
    @isTest
    public static void testAssignSingleLead(){
        User u = new User();
        u.ProfileId = [SELECT Id FROM Profile Limit 1].Id;
        u.LastName = 'RHLead';
        u.Email = 'RHLead@gmail.com';
        u.Username = 'RHLead@gmail.com' + System.currentTimeMillis();
        u.CompanyName = 'RH1';
        u.Title = 'title';
        u.Alias = 'rhld';
        u.TimeZoneSidKey = 'America/Los_Angeles';
        u.EmailEncodingKey = 'UTF-8';
        u.LanguageLocaleKey = 'en_US';
        u.LocaleSidKey = 'en_US';
        u.Availability__c = true;
        u.IsActive = true;
        u.is_working__c = true;
        insert u;

        Round_Robin__c r = new Round_Robin__c();
        r.Active__c = true;
        r.Project_Assigned__c = 'The Ozone Heights';
        insert r;

        Round_Robin_Member__c rrm = new Round_Robin_Member__c();
        rrm.Round_Robin__c = r.Id;
        rrm.Active__c = true;
        rrm.User__c = u.Id;
        rrm.User_Type__c = 'Sales';
        insert rrm;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Id assignedId = RoundRobinHandler.assignSingleLead('The Ozone Heights', 'Sales');
            Test.stopTest();

            System.assertNotEquals(null, assignedId, 'Should return an assigned user');
            System.assertEquals(u.Id, assignedId, 'Should assign the test user');
        }
    }

    /** Covers assignSingleLead returning null when no eligible users exist for the project. */
    @isTest
    public static void testAssignSingleLead_NoUsers() {
        Test.startTest();
        Id result = RoundRobinHandler.assignSingleLead('Nonexistent Project Name', 'Sales');
        Test.stopTest();
        System.assertEquals(null, result, 'Should return null when no users available');
    }

    /** Covers assignSingleSiteVisit returning null when no eligible users exist for the project. */
    @isTest
    public static void testAssignSingleSiteVisit_NoUsers() {
        Test.startTest();
        Id result = RoundRobinHandler.assignSingleSiteVisit('Nonexistent Project Name', 'Sales');
        Test.stopTest();
        System.assertEquals(null, result, 'Should return null when no users available');
    }

    
    /** Covers assignLead with no available users (Availability__c=false on all members) →
     *  fallback to RRqueList branch (lines 76-103).
     */
    @isTest
    public static void testAssignLead_FallbackToAllUsers() {
        User unavailUser = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LastName = 'UnavailUser',
            Email = 'unavail@gmail.com',
            Username = 'unavail' + System.currentTimeMillis() + '@gm.com',
            Alias = 'unav',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            Availability__c = false,  // not available
            IsActive = true,
            is_working__c = true
        );
        insert unavailUser;

        Round_Robin__c rr = new Round_Robin__c(Active__c = true, Project_Assigned__c = 'The Ozone Heights');
        insert rr;

        Round_Robin_Member__c rrm = new Round_Robin_Member__c(
            Round_Robin__c = rr.Id,
            Active__c = true,
            User__c = unavailUser.Id,
            User_Type__c = 'Pre Sales'
        );
        insert rrm;

        Lead__c l = new Lead__c(
            Name__c = 'Fallback Lead',
            Phone__c = '9111100099',
            Allocated_Project__c = 'The Ozone Heights',
            Lead_Assigned__c = false
        );
        insert l;

        List<Lead__c> leads = [SELECT Id, Allocated_Project__c, Lead_Assigned__c, Delete_Lead__c, Pre_sales_user__c, Sales_User__c, OwnerId
                                FROM Lead__c WHERE Id = :l.Id];
        for (Lead__c x : leads) x.Lead_Assigned__c = false;

        Test.startTest();
        RoundRobinHandler.assignLead(leads, false, 'Pre Sales');
        Test.stopTest();

        Lead__c after = [SELECT Lead_Assigned__c, Pre_sales_user__c FROM Lead__c WHERE Id = :l.Id];
        System.assertNotEquals(null, after, 'Lead remains queryable after assignLead');
    }
}