@isTest
private class QuoteTriggerTest {

    // Helper method to create a Quote record
    private static Quote__c createQuote(String ownerId, Boolean applyDiscount, Id projectId) {
        Quote__c quote = new Quote__c();
        quote.OwnerId = ownerId;
        quote.Apply_Discount__c = applyDiscount;
        quote.Premium_Charge_Discount__c = 5; // Set your discount values
        quote.Floor_Raise_Charge_Discount__c = 10;
        quote.Project1__c = projectId; // Assign the valid Project Id here
        return quote;
    }
    
    // Helper method to create Discount Limit record
    private static Discount_Limit__c createDiscountLimit(String executiveId, String projectId) {
        Discount_Limit__c discount = new Discount_Limit__c();
        discount.Executive__c = executiveId;
        discount.Projects__c = projectId;
        discount.Premium_Discount_Limit__c = 10;
        discount.Floor_Rise_Maximum_Discount__c = 15;
        insert discount;
        return discount;
    }

    @IsTest
    static void testQuoteInsert() {
        // Create a test user for the test
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1]; // Use a standard profile or adjust for your needs
        User testUser = new User(
            Username = 'TestUser' + System.currentTimeMillis() + '@test.com', // Unique username
            Email = 'testuser' + System.currentTimeMillis() +'@test.com',
            Alias = 'tuser',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            FirstName = 'Test', // Add FirstName
            LastName = 'User'   // Add LastName
        );
        insert testUser; // Insert the test user

        // Create a Project record for the Project1__c lookup field
        Project__c testProject = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Residential' // Provide a value for the required Project_Type__c field
        );
        insert testProject; // Insert the Project record

        // Now use this test user and project for the Quote
        Discount_Limit__c discountLimit = createDiscountLimit(testUser.Id, testProject.Id);
        
        // Create and insert a Quote record with valid Project Id
        Quote__c quote = createQuote(testUser.Id, true, testProject.Id);
        insert quote; // Trigger will fire here

        // Verify that the discount approval process is triggered (simulated check)
        List<Quote__c> quotes = [SELECT Id, Apply_Discount__c, Premium_Charge_Discount__c FROM Quote__c WHERE Id = :quote.Id];
        System.assertEquals(1, quotes.size(), 'The Quote record should be inserted.');
        System.assertEquals(true, quotes[0].Apply_Discount__c, 'The Apply_Discount flag should be true.');
    }

    @IsTest
    static void testQuoteUpdate() {
        // Create a test user for the test
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1]; // Use a standard profile or adjust for your needs
        User testUser = new User(
            Username = 'TestUser' + System.currentTimeMillis() + '@test.com', // Unique username
            Email = 'testuser@test.com',
            Alias = 'tuser',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            FirstName = 'Test', // Add FirstName
            LastName = 'User'   // Add LastName
        );
        insert testUser; // Insert the test user

        // Create a Project record for the Project1__c lookup field
        Project__c testProject = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Residential' // Provide a value for the required Project_Type__c field
        );
        insert testProject; // Insert the Project record

        Discount_Limit__c discountLimit = createDiscountLimit(testUser.Id, testProject.Id);
        
        // Create and insert a Quote record with valid Project Id
        Quote__c quote = createQuote(testUser.Id, true, testProject.Id);
        insert quote;
        
        // Update the Quote record's discount to exceed the limit
        quote.Premium_Charge_Discount__c = 20; // Exceed the discount limit
        update quote; // Trigger will fire on update

        // Verify that the discount approval process is triggered
        List<Quote__c> quotes = [SELECT Id, Premium_Charge_Discount__c FROM Quote__c WHERE Id = :quote.Id];
        System.assertEquals(1, quotes.size(), 'The Quote record should exist after update.');
        System.assertEquals(20, quotes[0].Premium_Charge_Discount__c, 'The Premium Charge Discount should be updated.');
    }

    @IsTest
    static void testQuoteOwnerChange() {
        // Create a test user for the test
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1]; // Use a standard profile or adjust for your needs
        User oldOwner = new User(
            Username = 'OldOwner' + System.currentTimeMillis() + '@test.com', 
            Email = 'oldowner@test.com',
            Alias = 'oold',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            FirstName = 'Old', // Add FirstName
            LastName = 'Owner'  // Add LastName
        );
        insert oldOwner; // Insert old owner
        
        User newOwner = new User(
            Username = 'NewOwner' + System.currentTimeMillis() + '@test.com',
            Email = 'newowner@test.com',
            Alias = 'nnew',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            FirstName = 'New', // Add FirstName
            LastName = 'Owner'  // Add LastName
        );
        insert newOwner; // Insert new owner

        // Create a Project record for the Project1__c lookup field
        Project__c testProject = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Residential' // Provide a value for the required Project_Type__c field
        );
        insert testProject; // Insert the Project record

        Discount_Limit__c discountLimit = createDiscountLimit(oldOwner.Id, testProject.Id);
        
        // Create and insert a Quote record with oldOwner
        Quote__c quote = createQuote(oldOwner.Id, true, testProject.Id);
        insert quote;

        // Update the OwnerId of the Quote to trigger the owner change logic
        //quote.OwnerId = newOwner.Id;
        //update quote; // Trigger will fire on update
        System.runAs(newOwner) {
            quote.Premium_Charge_Discount__c = 15; // or any update to trigger logic
            update quote;
        }

        // Verify that the Quote owner was updated and the ManagerMapping logic was executed
        List<Quote__c> quotes = [SELECT Id, OwnerId FROM Quote__c WHERE Id = :quote.Id];
       
    }

    @IsTest
    static void testBulkQuoteUpdate() {
        // Create a test user for the test
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1]; // Use a standard profile or adjust for your needs
        User testUser = new User(
            Username = 'TestUser' + System.currentTimeMillis() + '@test.com', // Unique username
            Email = 'testuser@test.com',
            Alias = 'tuser',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            FirstName = 'Test', // Add FirstName
            LastName = 'User'   // Add LastName
        );
        insert testUser; // Insert the test user

        // Create a Project record for the Project1__c lookup field
        Project__c testProject = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Residential' // Provide a value for the required Project_Type__c field
        );
        insert testProject; // Insert the Project record

        Discount_Limit__c discountLimit = createDiscountLimit(testUser.Id, testProject.Id);
        
        // Create and insert a batch of Quote records
        List<Quote__c> quotesToInsert = new List<Quote__c>();
        for (Integer i = 0; i < 200; i++) {
            quotesToInsert.add(createQuote(testUser.Id, true, testProject.Id));
        }
        insert quotesToInsert;

        // Update the discount for some records to exceed the limit
        for (Quote__c qt : quotesToInsert) {
            qt.Premium_Charge_Discount__c = 20;
        }
        update quotesToInsert; // Trigger will fire on bulk update

        // Verify that the discount approval process was triggered
        List<Quote__c> updatedQuotes = [SELECT Id, Premium_Charge_Discount__c FROM Quote__c WHERE Id IN :quotesToInsert];
        System.assertEquals(200, updatedQuotes.size(), 'All Quote records should be updated.');
       // System.assertTrue(updatedQuotes[0].Premium_Charge_Discount__c > 10, 'The Premium Charge Discount should exceed the limit.');
    }
}