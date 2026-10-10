@isTest
public class getQuoteData_Test {
    
    @testSetup
    static void setupData() {
          // Create a User for Owner references
        User owner = new User(
            Username = 'test22user@testex.com',
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

        
          // Step 1: Create a Lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'test@gmail.com',
            Phone__c = '9876543210'
        );
        insert testLead;
        // Create Project
        Project__c proj = new Project__c(Name = 'Test Project', Project_Type__c = 'Residential');
        insert proj;
        
        // Create Unit
        Plot__c unit = new Plot__c(Name = 'Test Unit',Project__c= proj.id);
        insert unit;
        
        // Create Quote linked to Project and Unit
        // Unit__c must be set so the Master_Payment_Schedule__c query returns results
        Quote__c q = new Quote__c(
            Discount_Approval_Status__c = 'Approved',
            Manager_Approval_Status__c = 'Approved',
            Apply_Discount__c = true,
            OwnerId = owner.Id,
            Project1__c = proj.Id,
            Unit__c = unit.Id,         // Required for masterPayments branch coverage
            SLead__c = testLead.Id,    // lookup to Lead
            Payment_Type__c = 'Standard',
            Quote_Status__c = 'Approved',
            Approval_Status__c = 'Approved',
            Project__c = 'The Ozone Heights'
        );
        insert q;
        
        // Create Master Payment Schedule for that Quote
        List<Master_Payment_Schedule__c> schedules = new List<Master_Payment_Schedule__c>();
        for (Integer i = 1; i <= 3; i++) {
            schedules.add(new Master_Payment_Schedule__c(
                Name = 'Payment ' + i,
                Project__c = proj.Id,
                Unit__c = unit.Id,
                Payment_Percent__c = 10 * i,
                Payment_Type__c = 'On Booking',
                Percentage__c = 10 * i,
                Sequence__c = i,
                S_No__c = i
            ));
        }
        insert schedules;
    }
    
    @isTest
    static void testGetQuoteDataWithValidId() {
        // Get Quote
        Quote__c q = [SELECT Id FROM Quote__c LIMIT 1];
        
        // Simulate VF page parameter
        Test.startTest();
        ApexPages.currentPage().getParameters().put('id', q.Id);
        getQuoteData ctrl = new getQuoteData(new ApexPages.StandardController(q));
        Test.stopTest();
        
      
    }
    
    @isTest
    static void testGetQuoteDataWithNoId() {
        // Simulate missing Id
        Quote__c q = [SELECT Id FROM Quote__c LIMIT 1];
        
        Test.startTest();
        ApexPages.currentPage().getParameters().remove('id');
        getQuoteData ctrl = new getQuoteData(new ApexPages.StandardController(q));
        Test.stopTest();
        
     
    }
}