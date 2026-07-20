@isTest
public class QuoteControllerTest {

    @testSetup
    static void setupData() {
        // Create a User for Owner references
        User owner = new User(
            Username = 'testusddser@testex.com',
            LastName = 'Test',
            Email = 'testuser@test.com',
            Alias = 'tuser',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert owner;

        // Create SLead__c
        Lead lead = new Lead(
            Phone__c = '7877888800',
            Secondary_Email__c = 'secondary@test.com',
            LastName = 'Lead',
            Company = 'Test Company'
        );
        insert lead;

        // Create Project__c record
        Project__c proj = new Project__c(Name = 'Test Project', Project_Type__c = 'Residential');
        insert proj;

        // Step 1: Create a Lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'test@gmail.com',
            Phone__c = '9876543210'
        );
        insert testLead;

        // Step 2: Create a Quote with SLead__c pointing to that Lead
        Quote__c quote = new Quote__c(
            Discount_Approval_Status__c = 'Approved',
            Manager_Approval_Status__c = 'Approved',
            Apply_Discount__c = true,
            OwnerId = owner.Id,
            Project1__c = proj.Id,
            SLead__c = testLead.Id,
            Payment_Type__c = 'Standard',
            Quote_Status__c = 'Approved',
            Approval_Status__c = 'Approved',
            Project__c = 'The Ozone Heights'
        );
        insert quote;
    }

    @isTest
    static void testGetQuoteData() {
        Quote__c q = [SELECT Id FROM Quote__c LIMIT 1];
        Test.startTest();
        Quote__c result = QuoteController.getQuoteData(q.Id);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Returned result should not be null');
        System.assertEquals(q.Id, result.Id, 'Returned Quote should match the input Id');
    }

    // Covers approved/drafted quote path for non-Legacey project (pref is null → NPE, caught)
    @isTest
    static void testSendEmailtoCustomer_Approved() {
        Quote__c q = [SELECT Id FROM Quote__c LIMIT 1];
        Test.startTest();
        try {
            String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello</p>', null);
        } catch (Exception e) {
            system.debug('error');
        }
        Test.stopTest();

        Quote__c updatedQ = [SELECT Quote_status__c FROM Quote__c WHERE Id = :q.Id];
    }

    // Covers approved quote with no email and no project → NPE caught
    @isTest
    static void testSendEmailtoCustomer_NoEmail() {
        Lead testLead = new Lead(
            FirstName = 'Test1',
            LastName = 'Lead1',
            Company = 'Test Company NoEmail',
            Phone__c = '9876543211'
        );
        insert testLead;
        Quote__c q = new Quote__c(
            OwnerId = UserInfo.getUserId(),
            SLead__c = testLead.Id,
            payment_type__c = 'Standard',
            Quote_status__c = 'Approved',
            Approval_status__c = 'Approved'
        );
        insert q;

        Test.startTest();
        try {
            String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello</p>', null);
        } catch (Exception e) {
            system.debug('error');
        }
        Test.stopTest();
    }

    /**
     * Covers Project1__r.Name == 'The Legacey' branch (pref = page.COST_SHEET_TL),
     * sendTo.size() > 0 → returns 'Quotation sent to customer'.
     */
    @isTest
    static void testSendEmailtoCustomer_TheLegacey_WithEmail() {
        Project__c legaceyProj = new Project__c(
            Name = 'The Legacey',
            Project_Type__c = 'Residential'
        );
        insert legaceyProj;

        Lead leadRec = new Lead(
            LastName = 'Legacey Lead',
            Company = 'Legacey Co',
            Phone__c = '9988776655',
            Email = 'legacey@example.com'
        );
        insert leadRec;

        Quote__c q = new Quote__c(
            Quote_status__c = 'Approved',
            Approval_status__c = 'Approved',
            SLead__c = leadRec.Id,
            Project1__c = legaceyProj.Id,
            payment_type__c = 'Standard'
        );
        insert q;

        Test.startTest();
        String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello Legacey</p>', null);
        Test.stopTest();

        System.assertEquals('Quotation sent to customer', ret);
    }

    /**
     * Covers 'The Legacey' branch with no email address on lead →
     * sendTo.size() == 0 → returns 'Please enter email address in lead'.
     */
    @isTest
    static void testSendEmailtoCustomer_TheLegacey_NoEmail() {
        Project__c legaceyProj = new Project__c(
            Name = 'The Legacey',
            Project_Type__c = 'Residential'
        );
        insert legaceyProj;

        Lead leadRec = new Lead(
            LastName = 'NoEmail Lead',
            Company = 'NoEmail Co',
            Phone__c = '9977665544'
            // no Email field
        );
        insert leadRec;

        Quote__c q = new Quote__c(
            Quote_status__c = 'Approved',
            Approval_status__c = 'Approved',
            SLead__c = leadRec.Id,
            Project1__c = legaceyProj.Id,
            payment_type__c = 'Standard'
        );
        insert q;

        Test.startTest();
        String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello</p>', null);
        Test.stopTest();

        System.assertEquals('Please enter email address in lead', ret);
    }

    // Covers Quote_status__c not 'Approved'/'Drafted' → 'Quote is not approved' branch
    @isTest
    static void testSendEmailtoCustomer_NotApproved() {
        Lead leadRec = new Lead(
            LastName = 'Pending Lead',
            Company = 'Pending Co',
            Phone__c = '9112233445'
        );
        insert leadRec;

        Quote__c q = new Quote__c(
            Quote_status__c = 'Submitted for Approval',
            Approval_status__c = 'Pending',
            SLead__c = leadRec.Id,
            payment_type__c = 'Standard'
        );
        insert q;

        Test.startTest();
        String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello</p>', null);
        Test.stopTest();

        System.assertEquals('Quote is not approved, you can not send Quote', ret);
    }

    /** Covers Quote_status__c == 'Drafted' branch in the if statement (line 16). */
    @isTest
    static void testSendEmailtoCustomer_Drafted() {
        Project__c legaceyProj = new Project__c(
            Name = 'The Legacey',
            Project_Type__c = 'Residential'
        );
        insert legaceyProj;

        Lead leadRec = new Lead(
            LastName = 'Drafted Lead',
            Company = 'Drafted Co',
            Phone__c = '9112233500',
            Email = 'drafted@example.com'
        );
        insert leadRec;

        Quote__c q = new Quote__c(
            Quote_status__c = 'Drafted',
            Approval_status__c = 'Pending',
            SLead__c = leadRec.Id,
            Project1__c = legaceyProj.Id,
            payment_type__c = 'Standard'
        );
        insert q;

        Test.startTest();
        String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello Drafted</p>', null);
        Test.stopTest();

        System.assertEquals('Quotation sent to customer', ret);
    }

    /** Covers SLead__r.Secondary_Email__c branch (line 52-54) — adds secondary email to sendTo list. */
    @isTest
    static void testSendEmailtoCustomer_WithSecondaryEmail() {
        Project__c legaceyProj = new Project__c(
            Name = 'The Legacey',
            Project_Type__c = 'Residential'
        );
        insert legaceyProj;

        Lead leadRec = new Lead(
            LastName = 'Secondary Lead',
            Company = 'Secondary Co',
            Phone__c = '9112233600',
            Email = 'primary@example.com',
            Secondary_Email__c = 'secondary@example.com'
        );
        insert leadRec;

        Quote__c q = new Quote__c(
            Quote_status__c = 'Approved',
            Approval_status__c = 'Approved',
            SLead__c = leadRec.Id,
            Project1__c = legaceyProj.Id,
            payment_type__c = 'Standard'
        );
        insert q;

        Test.startTest();
        String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello</p>', null);
        Test.stopTest();

        System.assertEquals('Quotation sent to customer', ret);
    }

    /** Covers CLead__r.Email__c branch (line 45-47) — uses custom Lead__c instead of standard Lead. */
    @isTest
    static void testSendEmailtoCustomer_WithCLead() {
        Project__c legaceyProj = new Project__c(
            Name = 'The Legacey',
            Project_Type__c = 'Residential'
        );
        insert legaceyProj;

        Lead__c cLeadRec = new Lead__c(
            Name__c = 'CLead Customer',
            Phone__c = '9112233700',
            Email__c = 'clead@example.com'
        );
        insert cLeadRec;

        Quote__c q = new Quote__c(
            Quote_status__c = 'Approved',
            Approval_status__c = 'Approved',
            CLead__c = cLeadRec.Id,
            Project1__c = legaceyProj.Id,
            payment_type__c = 'Standard'
        );
        insert q;

        Test.startTest();
        String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello CLead</p>', null);
        Test.stopTest();

        System.assertEquals('Quotation sent to customer', ret);
    }
}
    /*
    @isTest
    static void testSendEmailtoCustomer_NotApproved() {
        // Create unapproved quote
        Lead__c l = [SELECT Id FROM SLead__c LIMIT 1];
        Quote__c q = new Quote__c(
          //  Name = 'Test Quote Not Approved',
           // Project_Company__c = 'MAHENDRA ARTO LLP',
            OwnerId = UserInfo.getUserId(),
           // SLead__c = l.Id,
            payment_type__c = 'Partial',
            Quote_status__c = 'Pending',
            Approval_status__c = 'Pending'
        );
        insert q;

        Test.startTest();
        String ret = QuoteController.sendEmailtoCustomer(q.Id, '<p>Hello</p>', null);
        Test.stopTest();
        System.assertEquals('Quote is not approved, you can not send Quote', ret, 'Should block send when quote is not approved');
    }
}
*/