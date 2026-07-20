@isTest
private class LeadMergeControllerTest {

    @TestSetup
    static void setupData() {

        Lead__c actualLead = new Lead__c(
            Name__c = 'John Doe',
            Phone__c = '9876543210',
            Lead_Status__c = 'New Enquiry'
        );
        insert actualLead;

        Lead__c duplicateLead = new Lead__c(
            Name__c = 'John D',
            Phone__c = '9876500000',
            Lead_Status__c = 'New Enquiry'
        );
        insert duplicateLead;

        insert new Enquiry_Source__c(
            Lead__c = duplicateLead.Id,
            Source__c = 'Digital'
        );

        insert new Follow_up__c(
            CLead__c = duplicateLead.Id,
            Status__c = 'Pending'
        );

        insert new Site_Visit__c(
            CLead__c = duplicateLead.Id
        );

        insert new Related_Source__c(
            CLead__c = duplicateLead.Id
        );
    }

    // ✅ SEARCH TESTS
    @isTest
    static void testSearchLeads() {

        Lead__c duplicateLead = [SELECT Id FROM Lead__c WHERE Name__c = 'John D' LIMIT 1];

        Test.startTest();
        List<LeadMergeController.LeadWrapper> results =
            LeadMergeController.searchLeads('John', duplicateLead.Id);
        Test.stopTest();

        System.assert(results.size() > 0);
        for (LeadMergeController.LeadWrapper lw : results) {
            System.assertNotEquals(duplicateLead.Id, lw.leadId);
        }
    }

    @isTest
    static void testSearchLeads_Blank() {

        Test.startTest();
        List<LeadMergeController.LeadWrapper> results =
            LeadMergeController.searchLeads('', null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testSearchLeads_ShortTerm() {

        Test.startTest();
        List<LeadMergeController.LeadWrapper> results =
            LeadMergeController.searchLeads('A', null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    // ✅ GET DETAILS
    @isTest
    static void testGetLeadDetails() {

        Lead__c duplicateLead = [SELECT Id FROM Lead__c WHERE Name__c = 'John D' LIMIT 1];

        Test.startTest();
        LeadMergeController.LeadDetailWrapper result =
            LeadMergeController.getLeadDetails(duplicateLead.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.enquirySourceCount >= 1);
        System.assert(result.followUpCount >= 1);
        System.assert(result.siteVisitCount >= 1);
        System.assert(result.relatedSourceCount >= 1);
    }

    
    // ✅ MERGE SUCCESS
    @isTest
    static void testMergeLeads() {

        Lead__c actualLead = [SELECT Id, OwnerId FROM Lead__c WHERE Name__c = 'John Doe' LIMIT 1];
        Lead__c duplicateLead = [SELECT Id FROM Lead__c WHERE Name__c = 'John D' LIMIT 1];

        Test.startTest();
        String result = LeadMergeController.mergeLeads(duplicateLead.Id, actualLead.Id);
        Test.stopTest();

        System.assert(result.contains('Lead merged successfully'));

        // Verify transfer
        System.assert([SELECT COUNT() FROM Enquiry_Source__c WHERE Lead__c = :actualLead.Id] > 0);
        System.assert([SELECT COUNT() FROM Follow_up__c WHERE CLead__c = :actualLead.Id] > 0);
        System.assert([SELECT COUNT() FROM Site_Visit__c WHERE CLead__c = :actualLead.Id] > 0);
        System.assert([SELECT COUNT() FROM Related_Source__c WHERE CLead__c = :actualLead.Id] > 0);

        // Verify delete
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Lead__c WHERE Id = :duplicateLead.Id]
        );
    }

    

    /** Covers searchLeads early-return path when searchTerm is blank (null/empty). */
    @isTest
    static void testSearchLeads_BlankTerm() {
        Lead__c duplicateLead = [SELECT Id FROM Lead__c WHERE Name__c = 'John D' LIMIT 1];

        Test.startTest();
        List<LeadMergeController.LeadWrapper> r1 = LeadMergeController.searchLeads('', duplicateLead.Id);
        List<LeadMergeController.LeadWrapper> r2 = LeadMergeController.searchLeads(null, duplicateLead.Id);
        Test.stopTest();

        System.assert(r1.isEmpty(), 'Empty search term should return empty list');
        System.assert(r2.isEmpty(), 'Null search term should return empty list');
    }

    /** Covers searchLeads matching by phone number. */
    @isTest
    static void testSearchLeads_ByPhone() {
        Lead__c duplicateLead = [SELECT Id FROM Lead__c WHERE Name__c = 'John D' LIMIT 1];

        Test.startTest();
        // '9876543' matches actual lead's phone '9876543210' but not duplicate's '9876500000'
        List<LeadMergeController.LeadWrapper> results = LeadMergeController.searchLeads('9876543', duplicateLead.Id);
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should find lead by phone number');
        // Verify wrapper fields populated
        LeadMergeController.LeadWrapper lw = results[0];
        System.assertNotEquals(null, lw.leadId, 'leadId should be populated');
        System.assertNotEquals(null, lw.phone, 'phone should be populated');
    }

    /** Covers mergeLeads success path with lead that has NO child enquiry/follow-up/SV/related-source records,
     *  exercising all empty-list branches in mergeLeads. */
    @isTest
    static void testMergeLeads_NoChildRecords() {
        Lead__c actualLead = [SELECT Id, OwnerId FROM Lead__c WHERE Name__c = 'John Doe' LIMIT 1];

        // Create a fresh duplicate lead without any child records
        Lead__c emptyDuplicate = new Lead__c(
            Name__c = 'Empty Dup',
            Phone__c = '8888800001',
            Lead_Status__c = 'New Enquiry'
        );
        insert emptyDuplicate;

        Test.startTest();
        String result = LeadMergeController.mergeLeads(emptyDuplicate.Id, actualLead.Id);
        Test.stopTest();

        System.assert(result.contains('Lead merged successfully'), 'Should return success message even with no child records');

        // Verify duplicate deleted
        List<Lead__c> deleted = [SELECT Id FROM Lead__c WHERE Id = :emptyDuplicate.Id];
        System.assert(deleted.isEmpty(), 'Duplicate should be deleted even with no child records');
    }

    /** Covers getLeadDetails returning the wrapper with fully-populated fields, including Owner.Name. */
    @isTest
    static void testGetLeadDetails_FullWrapper() {
        Lead__c duplicateLead = [SELECT Id FROM Lead__c WHERE Name__c = 'John D' LIMIT 1];

        Test.startTest();
        LeadMergeController.LeadDetailWrapper detail = LeadMergeController.getLeadDetails(duplicateLead.Id);
        Test.stopTest();

        System.assertNotEquals(null, detail, 'Wrapper should not be null');
        System.assertEquals(duplicateLead.Id, detail.leadId, 'leadId should match');
        System.assertEquals('John D', detail.customerName, 'customerName should match');
    }
}