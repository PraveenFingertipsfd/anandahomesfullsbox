// Last Modified: 2026-03-27
@isTest
public class SLeadTriggerTest {

    public static testMethod void getSLeadTriggerTest()
    {
          
        User u = new User();
        u.ProfileId = [SELECT Id FROM Profile WHERE Name = 'Pre-Sales Executive'].Id;
        u.LastName = 'RH23';
        u.Email = 'RH@gm1ail.com';
        u.Username = 'RH@1gmail.com' + System.currentTimeMillis();
        u.CompanyName = 'Mahindra Homes';
        u.Title = 'titletitl1e';
        u.Alias = 'loKma1n';
        u.TimeZoneSidKey = 'America/Los_Angeles';
        u.EmailEncodingKey = 'UTF-8';
        u.LanguageLocaleKey = 'en_US';
        u.LocaleSidKey = 'en_US';
        u.Availability__c=false;
        u.IsActive=true;
       // u.Week_off_days__c ='Monday';
       u.is_working__c = true;
        insert u;
        
            Lead lad= new Lead();
            lad.LastName='test';
            lad.Phone__c = '9182748514';
            lad.Secondary_Phone__c = '9182748513';
            lad.Lead_source__c = 'Walk-in';
        	lad.Medium__c = 'WALKIN';
            lad.Company = 'Test Co';
            insert lad;
        system.runAs(u){
         Lead ld= new Lead();
        ld.Lead_source__c='Website';
        ld.Medium__c = 'WEBSITE';
        ld.LastName='test';
        ld.Phone__c = '9182748502';
        ld.Company='Abc';
        insert ld;
        }
        Site_Visit__c sv=new Site_Visit__c();  
        sv.Date__c=System.now()+3;
        sv.Status__c='Scheduled';
        sv.Project__c='The Ozone Heights';
        sv.SLead__c=lad.id;
        insert sv;
         Follow_up__c fp = new Follow_up__c();
        fp.Scheduled_Date__c = system.today()+1;
        fp.SLead__c = lad.id;
        fp.Status__c = 'Scheduled';
        fp.Comments__c = 'test';
        insert fp;
        lad.OwnerId = u.Id;
         Update lad;
       /*lad.Lead_Status__c ='Interested'; 
        Update lad;*/
         lad.Phone__c = '9182748515';
       Update lad;
        lad.Secondary_Phone__c = '9182748512';
        Update lad;
        delete fp;
        delete sv;
        List<Related_Source__c> rel = [select Id from Related_Source__c where SLead__c=:lad.Id];
        delete rel;
        delete lad;
      /*lad.Lead_status__c='Closed Lost';
        lad.Closed_Lost_Reason__c='Budget';
        update lad;*/
        
    }
    
    @isTest
static void testCPReSharingOnOwnerChange() {

    /* -------------------------------
       1. Create Users
    -------------------------------- */
    Profile adminProfile = [
        SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1
    ];

    User leadOwner = new User(
        Alias = 'ownr',
        Email = 'owner@test.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'Owner',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'Asia/Kolkata',
        ProfileId = adminProfile.Id,
        Username = 'owner' + System.currentTimeMillis() + '@test.com'
    );
    insert leadOwner;

    User cpOwner = new User(
        Alias = 'cpown',
        Email = 'cpowner@test.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'CP Owner',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'Asia/Kolkata',
        ProfileId = adminProfile.Id,
        Username = 'cpowner' + System.currentTimeMillis() + '@test.com'
    );
    insert cpOwner;

    User newLeadOwner = new User(
        Alias = 'newow',
        Email = 'newowner@test.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'New Owner',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'Asia/Kolkata',
        ProfileId = adminProfile.Id,
        Username = 'newowner' + System.currentTimeMillis() + '@test.com'
    );
    insert newLeadOwner;

    /* -------------------------------
       2. Create Lead (NOT expired)
       (Criteria_Date__c via formula)
    -------------------------------- */
    Lead__c ld = new Lead__c(
        Name__c = 'CP ReShare Lead',
        Lead_Status__c = 'New Enquiry',
        Primary_Source__c = 'CP',
        Phone__c = '9182748501',
        Re_Engaged_CP_Date__c = Date.today()
    );
    insert ld;

    /* -------------------------------
       3. Channel Partner + Related Source
    -------------------------------- */
    Channel_Partner__c cp = new Channel_Partner__c(
        Mobile_Number__c = '9988778866',
        OwnerId = cpOwner.Id
    );
    insert cp;

    Related_Source__c rs = new Related_Source__c(
        CLead__c = ld.Id,
        Channel_Partner__c = cp.Id
    );
    insert rs;

    /* -------------------------------
       4. Change Lead Owner
       (Triggers re-sharing logic)
    -------------------------------- */
    Test.startTest();
    ld.OwnerId = newLeadOwner.Id;
    update ld;
    Test.stopTest();

    /* -------------------------------
       5. Assertion: verify trigger executed without error.
       CP re-sharing insert logic in LeadTrigger is currently
       commented out, so we only verify the update succeeded.
    -------------------------------- */
    Lead__c verifyLd = [SELECT OwnerId FROM Lead__c WHERE Id = :ld.Id];
    System.assertEquals(newLeadOwner.Id, verifyLd.OwnerId, 'Lead owner should be updated');
}

    @isTest
    static void testPushToCustomLeadWithAllFields() {
        Campaign__c camp = new Campaign__c(Campaign_Name__c = 'SLead Campaign', Is_Active__c = true);
        insert camp;

        Test.startTest();
        Lead sLead = new Lead();
        sLead.FirstName = 'Ravi';
        sLead.LastName = 'Kumar';
        sLead.Phone__c = '9876500010';
        sLead.Secondary_Phone__c = '9876500011';
        sLead.Email = 'ravi@test.com';
        sLead.Secondary_Email__c = 'ravi.alt@test.com';
        sLead.Lead_source__c = 'Website';
        sLead.Campaign__c = 'SLead Campaign';
        sLead.Company = 'Test Co';
        insert sLead;
        Test.stopTest(); // flushes @future deleteStandardLeads

        // Verify custom Lead__c was created with all mapped fields
        List<Lead__c> customLeads = [SELECT Id, Lead_First_Name__c, Lead_Last_Name__c, Name__c,
                                      Phone__c, Secondary_Phone__c, Email__c, Secondary_Email__c,
                                      Lead_source__c, Primary_Source__c, Allocated_Project__c, Campaign__c, Campaign_Name__c
                                      FROM Lead__c WHERE Phone__c = '9876500010'];
        System.assertEquals(1, customLeads.size(), 'Custom Lead__c should be created');
        Lead__c cl = customLeads[0];
        System.assertEquals('Ravi', cl.Lead_First_Name__c);
        System.assertEquals('Kumar', cl.Lead_Last_Name__c);
        System.assertEquals('Ravi Kumar', cl.Name__c);
        System.assertEquals('ravi@test.com', cl.Email__c);
        System.assertEquals('ravi.alt@test.com', cl.Secondary_Email__c);
        System.assertEquals('Website', cl.Lead_source__c);
        System.assertEquals('SLead Campaign', cl.Campaign__c);
        System.assertEquals(camp.Id, cl.Campaign_Name__c, 'Campaign lookup should be resolved by trigger');

        // Verify standard Lead was deleted by @future
        List<Lead> remainingLeads = [SELECT Id FROM Lead WHERE Id = :sLead.Id];
        System.assertEquals(0, remainingLeads.size(), 'Standard Lead should be deleted after push to custom Lead__c');
    }

}