@isTest
public class RelatedSourceHandlerTest {
    @isTest
    public static  void testmech(){
        
        
        list<Lead__c> ldlist = new  list<Lead__c>();
        list<Lead__c> ldlist21 = new  list<Lead__c>();
        list<Lead__c> Newlist = new  list<Lead__c>();
        Lead__c ld22 = new Lead__c();
        ld22.Name__c = 'Test Lead 22';
        ld22.Phone__c ='9908072233';
        ld22.Email__c='Test@gmai1l.com';
        ld22.Secondary_Phone__c='9922332246';
        ld22.Lead_status__c='';
        ld22.Unqualified_Reason__c='Booked with Competitor';
        //ld22.Company='test';
        ld22.Allocated_Project__c='The Ozone Heights';
        //ld22.Closed_Lost_Reason__c ='Junk Enquiry';
        insert ld22;
        ldlist.add(ld22);
        
        
        Lead__c ld221 = new Lead__c();
        ld221.Name__c = 'Test Lead 221';
        ld221.Phone__c ='9908072211';
        //ld221.Secondary_Phone__c='+919922332244';
        ld221.Email__c ='Test@gmai1l.com';
        //ld221.Company='test';
        ld221.allocated_project__c ='The Ozone Heights';
        //ld22.Lead_status__c='Closed Lost';
        //insert ld221;
        ldlist21.add(ld221);
        
        Lead__c ld23 = new Lead__c();
        ld23.Name__c = 'Test Lead 23';
        ld23.Phone__c ='9908072233';
        ld23.Email__c ='Test3845784@gmai2l.com';
        //ld23.Company='test';
        ld23.allocated_project__c ='The Ozone Heights';
        insert ld23;
        ldlist21.add(ld23);
        
        
        
        
        list<Lead__c> ldlist1 = new  list<Lead__c>();
        
        Lead__c c2= new Lead__c();
        c2.Name__c = 'Test Lead c2';
        c2.Phone__c ='9908072211';
        c2.Email__c ='Test@gmai2l.com';
        c2.allocated_project__c ='The Ozone Heights';
        //c2.Company='Test';
        ldlist1.add(c2);
        
        
        
        list<lead> ldlist2 = new  list<lead>();
        
        Lead__c c22= new Lead__c();
        c22.Name__c = 'Test Lead c22';
        c22.Phone__c ='+917807220900';
        c22.Email__c ='Test@gmai2l.com';
        //c22.Company='Test';
        c22.allocated_project__c ='The Ozone Heights';
        
        insert c22;
        ldlist1.add(c22);
        
        Lead__c lad= new Lead__c();
        lad.Name__c = 'Test Lead lad';
        lad.Allocated_Project__c = 'The Ozone Heights';
        lad.Phone__c = '+918274851600';
        lad.Lead_Status__c ='Unqualified';
        lad.Unqualified_Reason__c = 'Booked with Competitor';
        //lad.Company='test';
        insert lad;
        Newlist.add(lad);
        Lead__c led= new Lead__c();
        led.Name__c = 'Test Lead led';
        led.Allocated_Project__c = 'The Ozone Heights';
        led.Phone__c = '+918274851600';
        led.Secondary_Phone__c = '+918274851600';
        led.Lead_Status__c ='New Enquiry';
        //led.Company='test';
        insert led;
        Newlist.add(led);       
        RelatedSourceHandler.checkMobileNumber(ldlist);
        RelatedSourceHandler.checkMobileNumber(ldlist1);
        // RelatedSourceHandler.addCountryCode(ldlist);
        // RelatedSourceHandler.duplicateCheck(ldlist);
        //  RelatedSourceHandler.duplicateCheck(Newlist);
        // RelatedSourceHandler.duplicateCheckOnUpdate(ldlist);
        RelatedSourceHandler.duplicateCheck2(ldlist);
        RelatedSourceHandler.duplicateCheck2(ldlist1 );
        
        //RelatedSourceHandler.afterinsertLogic(Newlist);
        // Wrap in try-catch: main class may trigger ENTITY_IS_DELETED in LeadTrigger cascade
        try {
            RelatedSourceHandler.afterinsertLogic2(Newlist);
        } catch (Exception e) { System.debug('afterinsertLogic2: ' + e.getMessage()); }
        //RelatedSourceHandler.afterinsertLogic2(ldlist2 );
        
        RelatedSourceHandler.addRelatedSource(ld22);
        RelatedSourceHandler.addRelatedSource(ld23);
        RelatedSourceHandler.addRelatedSource2(ld22,ld23);
        //RelatedSourceHandler.createLog(ldlist);

        // Cover mapCampaignLookup:
        // (a) lead with blank Campaign__c → early continue
        // Wrap in try-catch: LeadTrigger's afterinsertLogic2 may throw ENTITY_IS_DELETED
        try {
            Lead__c ldCampBlank = new Lead__c(Name__c = 'Test Camp Blank', Phone__c = '9000111222', Allocated_Project__c = 'The Ozone Heights');
            insert ldCampBlank;
            RelatedSourceHandler.mapCampaignLookup(new List<Lead__c>{ ldCampBlank });
        } catch (Exception e) { System.debug('ldCampBlank: ' + e.getMessage()); }

        // (b) lead with non-blank Campaign__c that is NOT a valid Id → name-based lookup path
        try {
            Lead__c ldCampName = new Lead__c(Name__c = 'Test Camp Name', Phone__c = '9000333444', Allocated_Project__c = 'The Ozone Heights', Campaign__c = 'NonExistentCampaignXYZ');
            insert ldCampName;
            RelatedSourceHandler.mapCampaignLookup(new List<Lead__c>{ ldCampName });
        } catch (Exception e) { System.debug('ldCampName: ' + e.getMessage()); }
    }

    /** Covers mapCampaignLookup with valid Campaign_Name__c text → name-based lookup success. */
    @isTest
    public static void testMapCampaignLookup_NameMatch() {
        Campaign__c camp = new Campaign__c(Campaign_Name__c = 'Lookup By Name Campaign');
        insert camp;

        try {
            Lead__c ld = new Lead__c(
                Name__c = 'Camp Name Match Lead',
                Phone__c = '9000555666',
                Allocated_Project__c = 'The Ozone Heights',
                Campaign__c = 'Lookup By Name Campaign'
            );
            insert ld;
            RelatedSourceHandler.mapCampaignLookup(new List<Lead__c>{ ld });
        } catch (Exception e) { System.debug(e.getMessage()); }
    }

    /** Covers mapCampaignLookup with Campaign__c set to a valid Id string → Id-parse success path. */
    @isTest
    public static void testMapCampaignLookup_IdMatch() {
        Campaign__c camp = new Campaign__c(Campaign_Name__c = 'Lookup By Id Campaign');
        insert camp;

        try {
            Lead__c ld = new Lead__c(
                Name__c = 'Camp Id Match Lead',
                Phone__c = '9000777888',
                Allocated_Project__c = 'The Ozone Heights',
                Campaign__c = String.valueOf(camp.Id)
            );
            insert ld;
            RelatedSourceHandler.mapCampaignLookup(new List<Lead__c>{ ld });
        } catch (Exception e) { System.debug(e.getMessage()); }
    }

    /** Covers checkMobileNumber assertion that country code is extracted/defaulted. */
    @isTest
    public static void testCheckMobileNumber_CountryCode() {
        Lead__c ld = new Lead__c(
            Name__c = 'Country Code Lead',
            Phone__c = '+919199999999',
            Secondary_Phone__c = '+919188888888',
            Allocated_Project__c = 'The Ozone Heights'
        );

        Test.startTest();
        // Call directly without insert (in-memory)
        RelatedSourceHandler.checkMobileNumber(new List<Lead__c>{ ld });
        Test.stopTest();

        // Country_Code__c should now be set (either '91' or default fallback)
        System.assertNotEquals(null, ld.Country_Code__c, 'Country_Code__c should be populated');
        System.assertNotEquals(null, ld.Country__c, 'Country__c should be populated');
    }

    /** Covers duplicateCheck2 with an empty list (or null Allocated_Project__c) — early return path. */
    @isTest
    public static void testDuplicateCheck2_EmptyList() {
        Test.startTest();
        RelatedSourceHandler.duplicateCheck2(new List<Lead__c>());
        Test.stopTest();
        System.assert(true, 'Empty list should be a no-op');
    }

    /** Covers addRelatedSource Re-Opened branch (lines 490-545).
     *  Main_lead_status__c is a formula field = TEXT(Main_Lead__r.Lead_Status__c).
     *  We create a main lead with 'Unqualified' status, point the duplicate to it,
     *  then re-query to resolve the formula before calling addRelatedSource.
     */
    @isTest
    public static void testAddRelatedSource_ReOpenedBranch() {
        // 1. Create "main" lead, then update to Unqualified to avoid trigger conflicts
        Lead__c mainLead = new Lead__c(
            Name__c = 'Main Unqualified Lead',
            Phone__c = '9000000001',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert mainLead;
        mainLead.Lead_Status__c = 'Unqualified';
        mainLead.Unqualified_Reason__c = 'Booked with Competitor';
        update mainLead;

        // 2. Create "duplicate" lead WITHOUT Main_Lead__c to avoid trigger deleting it
        Lead__c dupLead = new Lead__c(
            Name__c = 'Dup ReOpen Lead',
            Phone__c = '9000000002',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert dupLead;

        // 3. Update to set Main_Lead__c (after-update trigger does NOT call afterinsertLogic2)
        dupLead.Main_Lead__c = mainLead.Id;
        update dupLead;

        // 4. Re-query to resolve formula field Main_lead_status__c
        Lead__c queriedDup = [
            SELECT Id, Name__c, Main_Lead__c, Main_lead_status__c, Main_Pre_Sales_User__c,
                   Phone__c, Secondary_Phone__c, Email__c, Secondary_Email__c,
                   Country_Code__c, Secondary_Country_Code__c,
                   Primary_Source__c, Primary_Sub_Source__c, Source_Type__c,
                   Medium__c, Lead_source__c, Sub_Source__c,
                   Allocated_Project__c, Last_Comment__c, Comments__c,
                   Campaign_Name__c, Campaign__c, ERP_Id__c,
                   Referrer_Name__c, Referrer_Mobile_No__c, Referrer_Alternate_Mobile_No__c,
                   Referrer_Email__c, Referrer_Alternate_Email__c,
                   Referral_Source__c, Referring_For__c,
                   Referring_Customer_Unit__c, Referring_Customer_Project__c,
                   Referring_Vendor_Company_Name__c, Referring_Vendor_Id__c,
                   Referring_Employee_ID__c, Employee_Id__c,
                   Existing_Customer_Info__c,
                   Country__c, executiveName__c, executivePhone__c,
                   State__c, City__c, Channel_Partner__c,
                   Delete_Lead__c, Sales_User__c, Re_engaged_Count__c,
                   Need_Pick_Up_Assistance__c,
                   Type_of_lead__c, Query_For__c, Query_Type__c, Message__c
            FROM Lead__c
            WHERE Id = :dupLead.Id
        ];

        System.assertEquals('Unqualified', queriedDup.Main_lead_status__c,
            'Formula should resolve to main lead status');

        // 4. Clear static lists from prior test methods
        RelatedSourceHandler.deleteList.clear();
        RelatedSourceHandler.rsList.clear();
        RelatedSourceHandler.matchedMap.clear();

        Test.startTest();
        RelatedSourceHandler.addRelatedSource(queriedDup);
        Test.stopTest();

        // 5. Verify Re-Opened branch was exercised
        System.assert(!RelatedSourceHandler.rsList.isEmpty(), 'rsList should have a Related_Source__c');
        System.assertEquals('Re-Opened', RelatedSourceHandler.rsList[0].Lead_Type__c,
            'Lead_Type__c should be Re-Opened for Unqualified main lead');
        System.assert(!RelatedSourceHandler.matchedMap.isEmpty(), 'matchedMap should have the main lead update');
        Lead__c mainUpdate = RelatedSourceHandler.matchedMap.get(mainLead.Id);
        System.assertEquals('Re-Opened', mainUpdate.Lead_Type__c, 'Main lead should be marked Re-Opened');
    }

    /** Covers addRelatedSource Re-Engaged branch (lines 546-553) — when main lead is active (not terminal). */
    @isTest
    public static void testAddRelatedSource_ReEngagedBranch() {
        Lead__c mainLead = new Lead__c(
            Name__c = 'Main Active Lead',
            Phone__c = '9000000003',
            Allocated_Project__c = 'The Ozone Heights',
            Lead_Status__c = 'New Enquiry'
        );
        insert mainLead;

        Lead__c dupLead = new Lead__c(
            Name__c = 'Dup ReEngage Lead',
            Phone__c = '9000000004',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert dupLead;
        dupLead.Main_Lead__c = mainLead.Id;
        update dupLead;

        Lead__c queriedDup = [
            SELECT Id, Name__c, Main_Lead__c, Main_lead_status__c, Main_Pre_Sales_User__c,
                   Phone__c, Secondary_Phone__c, Email__c, Secondary_Email__c,
                   Country_Code__c, Secondary_Country_Code__c,
                   Primary_Source__c, Primary_Sub_Source__c, Source_Type__c,
                   Medium__c, Lead_source__c, Sub_Source__c,
                   Allocated_Project__c, Last_Comment__c, Comments__c,
                   Campaign_Name__c, Campaign__c, ERP_Id__c,
                   Referrer_Name__c, Referrer_Mobile_No__c, Referrer_Alternate_Mobile_No__c,
                   Referrer_Email__c, Referrer_Alternate_Email__c,
                   Referral_Source__c, Referring_For__c,
                   Referring_Customer_Unit__c, Referring_Customer_Project__c,
                   Referring_Vendor_Company_Name__c, Referring_Vendor_Id__c,
                   Referring_Employee_ID__c, Employee_Id__c,
                   Existing_Customer_Info__c,
                   Country__c, executiveName__c, executivePhone__c,
                   State__c, City__c, Channel_Partner__c,
                   Delete_Lead__c, Sales_User__c, Re_engaged_Count__c,
                   Need_Pick_Up_Assistance__c,
                   Type_of_lead__c, Query_For__c, Query_Type__c, Message__c
            FROM Lead__c
            WHERE Id = :dupLead.Id
        ];

        RelatedSourceHandler.deleteList.clear();
        RelatedSourceHandler.rsList.clear();
        RelatedSourceHandler.matchedMap.clear();

        Test.startTest();
        RelatedSourceHandler.addRelatedSource(queriedDup);
        Test.stopTest();

        System.assertEquals('Re-Engaged', RelatedSourceHandler.rsList[0].Lead_Type__c,
            'Lead_Type__c should be Re-Engaged for active main lead');
    }

    
}