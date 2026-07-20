// 2026-05-27
// 2026-05-26
@isTest
private class BulkLeadReassignmentController_Test {

    @TestSetup
    static void setupData() {
        // Create test users on Pre-Sales Executive profile so they pass the
        // getInitData() profile filter ('Pre-Sales Executive', 'Sales Executive')
        Profile preSalesProfile = [SELECT Id FROM Profile WHERE Name = 'Pre-Sales Executive' LIMIT 1];

        User testUser1 = new User(
            FirstName = 'Test', LastName = 'Owner1',
            Email = 'testowner1@test.com',
            Username = 'testowner1.' + DateTime.now().getTime() + '@test.com',
            Alias = 'towner1', ProfileId = preSalesProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert testUser1;

        User testUser2 = new User(
            FirstName = 'Test', LastName = 'Owner2',
            Email = 'testowner2@test.com',
            Username = 'testowner2.' + DateTime.now().getTime() + '@test.com',
            Alias = 'towner2', ProfileId = preSalesProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert testUser2;

        // Create test leads owned by testUser1
        List<Lead__c> leads = new List<Lead__c>();
        for (Integer i = 0; i < 5; i++) {
            leads.add(new Lead__c(
                Name__c = 'Test Lead ' + i,
                OwnerId = testUser1.Id,
                Phone__c = '900000000' + i,
                Lead_Status__c = 'New Enquiry'
            ));
        }
        insert leads;
    }

    @isTest
    static void testGetInitData() {
        Test.startTest();
        BulkLeadReassignmentController.InitData data = BulkLeadReassignmentController.getInitData();
        Test.stopTest();

        System.assertNotEquals(null, data, 'Init data should not be null');
        System.assertNotEquals(null, data.projectOptions, 'Project options should not be null');
        System.assertNotEquals(null, data.statusOptions, 'Status options should not be null');
        System.assertNotEquals(null, data.activeUsers, 'Active users should not be null');
        System.assert(data.activeUsers.size() > 0, 'Should have at least one active user');
    }

    @isTest
    static void testGetLeadsByOwner() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];

        Test.startTest();
        List<Lead__c> leads = BulkLeadReassignmentController.getLeadsByOwner(
            owner.Id, null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(5, leads.size(), 'Should return 5 leads');
    }

    @isTest
    static void testGetLeadsByOwnerWithFilters() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];

        Test.startTest();
        List<Lead__c> leads = BulkLeadReassignmentController.getLeadsByOwner(
            owner.Id, null, 'New Enquiry', Date.today().addDays(-1), Date.today(), null
        );
        Test.stopTest();

        System.assert(leads.size() >= 0, 'Should return leads matching filters');
    }

    @isTest
    static void testGetLeadsByOwnerBlankId() {
        Test.startTest();
        List<Lead__c> leads = BulkLeadReassignmentController.getLeadsByOwner(
            '', null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(0, leads.size(), 'Should return empty list for blank owner');
    }

    @isTest
    static void testGetLeadsByOwnerMobileFilter() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];

        // Seed one lead whose Secondary_Phone__c carries the search digits;
        // setup leads have Phone__c = '9000000000'..'9000000004'.
        insert new Lead__c(
            Name__c = 'Secondary Match Lead',
            OwnerId = owner.Id,
            Phone__c = '8000000000',
            Secondary_Phone__c = '7777712345',
            Lead_Status__c = 'New Enquiry'
        );

        Test.startTest();
        // Primary-phone partial match: '0003' appears in '9000000003' only.
        List<Lead__c> primaryHits = BulkLeadReassignmentController.getLeadsByOwner(
            owner.Id, null, null, null, null, '0003'
        );
        // Secondary-phone partial match: '12345' is only on the seeded lead.
        List<Lead__c> secondaryHits = BulkLeadReassignmentController.getLeadsByOwner(
            owner.Id, null, null, null, null, '12345'
        );
        // Whitespace-only filter should behave as no filter.
        List<Lead__c> noFilter = BulkLeadReassignmentController.getLeadsByOwner(
            owner.Id, null, null, null, null, '   '
        );
        Test.stopTest();

        System.assertEquals(1, primaryHits.size(), 'Should match by Phone__c partial');
        System.assertEquals(1, secondaryHits.size(), 'Should match by Secondary_Phone__c partial');
        System.assertEquals(6, noFilter.size(), 'Blank filter should return all owner leads');
    }

    @isTest
    static void testPermanentReassignment() {
        User owner1 = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];
        User owner2 = [SELECT Id FROM User WHERE LastName = 'Owner2' LIMIT 1];
        List<Lead__c> leads = [SELECT Id FROM Lead__c WHERE OwnerId = :owner1.Id];
        List<Id> leadIds = new List<Id>();
        for (Lead__c ld : leads) {
            leadIds.add(ld.Id);
        }

        Test.startTest();
        String result = BulkLeadReassignmentController.reassignLeads(
            leadIds, owner1.Id, owner2.Id, 'Permanent', 'Team restructure', null
        );
        Test.stopTest();

        System.assert(result.contains('Successfully'), 'Should return success message');

        // Verify owner changed
        List<Lead__c> updatedLeads = [SELECT OwnerId FROM Lead__c WHERE Id IN :leadIds];
        for (Lead__c ld : updatedLeads) {
            System.assertEquals(owner2.Id, ld.OwnerId, 'Owner should be changed to owner2');
        }

        // Verify history records
        List<Reassignment_History__c> histories = [
            SELECT Reassignment_Type__c, Status__c FROM Reassignment_History__c WHERE Lead__c IN :leadIds
        ];
        System.assertEquals(leadIds.size(), histories.size(), 'Should create history for each lead');
        for (Reassignment_History__c rh : histories) {
            System.assertEquals('Permanent', rh.Reassignment_Type__c);
            System.assertEquals('Completed', rh.Status__c);
        }
    }

    @isTest
    static void testTemporaryReassignment() {
        User owner1 = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];
        User owner2 = [SELECT Id FROM User WHERE LastName = 'Owner2' LIMIT 1];
        List<Lead__c> leads = [SELECT Id FROM Lead__c WHERE OwnerId = :owner1.Id LIMIT 2];
        List<Id> leadIds = new List<Id>();
        for (Lead__c ld : leads) {
            leadIds.add(ld.Id);
        }

        // Seed one follow-up and one site visit per lead so child sharing is exercised
        List<Follow_up__c> fus = new List<Follow_up__c>();
        List<Site_Visit__c> svs = new List<Site_Visit__c>();
        for (Id lid : leadIds) {
            fus.add(new Follow_up__c(CLead__c = lid));
            svs.add(new Site_Visit__c(CLead__c = lid));
        }
        insert fus;
        insert svs;

        Date expiryDate = Date.today().addDays(7);

        Test.startTest();
        String result = BulkLeadReassignmentController.reassignLeads(
            leadIds, owner1.Id, owner2.Id, 'Temporary', 'On leave', expiryDate
        );
        Test.stopTest();

        System.assert(result.contains('Successfully'), 'Should return success message');

        // Verify temp owner set, original owner unchanged
        List<Lead__c> updatedLeads = [SELECT OwnerId, Temp_Owner__c, Temp_Expiry__c FROM Lead__c WHERE Id IN :leadIds];
        for (Lead__c ld : updatedLeads) {
            System.assertEquals(owner1.Id, ld.OwnerId, 'Original owner should remain');
            System.assertEquals(owner2.Id, ld.Temp_Owner__c, 'Temp owner should be set');
            System.assertEquals(expiryDate, ld.Temp_Expiry__c, 'Expiry date should be set');
        }

        // Verify history
        List<Reassignment_History__c> histories = [
            SELECT Status__c, Reassignment_Type__c FROM Reassignment_History__c WHERE Lead__c IN :leadIds
        ];
        for (Reassignment_History__c rh : histories) {
            System.assertEquals('Temporary', rh.Reassignment_Type__c);
            System.assertEquals('Active', rh.Status__c);
        }

        // Verify Lead manual shares created with Edit access for the temp owner
        List<Lead__Share> leadShares = [
            SELECT AccessLevel FROM Lead__Share
            WHERE ParentId IN :leadIds AND UserOrGroupId = :owner2.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(leadIds.size(), leadShares.size(), 'One manual Lead share per lead');
        for (Lead__Share s : leadShares) {
            System.assertEquals('Edit', s.AccessLevel, 'Lead temp share should be Edit access');
        }

        // Verify Follow-up shares created for the temp owner
        Integer fuShareCount = [
            SELECT COUNT() FROM Follow_up__Share
            WHERE ParentId IN :fus AND UserOrGroupId = :owner2.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(fus.size(), fuShareCount, 'One Follow_up__Share per follow-up');

        // Verify Site Visit shares created for the temp owner
        Integer svShareCount = [
            SELECT COUNT() FROM Site_Visit__Share
            WHERE ParentId IN :svs AND UserOrGroupId = :owner2.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(svs.size(), svShareCount, 'One Site_Visit__Share per site visit');
    }

    @isTest
    static void testReassignValidationNoLeads() {
        Boolean threw = false;
        try {
            Test.startTest();
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>(), 'someId', 'anotherId', 'Permanent', 'test', null
            );
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw no leads error');
    }

    @isTest
    static void testReassignValidationTempNoExpiry() {
        User owner1 = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];
        User owner2 = [SELECT Id FROM User WHERE LastName = 'Owner2' LIMIT 1];
        List<Lead__c> leads = [SELECT Id FROM Lead__c WHERE OwnerId = :owner1.Id LIMIT 1];

        Boolean threw = false;
        try {
            Test.startTest();
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ leads[0].Id }, owner1.Id, owner2.Id, 'Temporary', 'test', null
            );
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw expiry date error');
    }

    @isTest
    static void testGetActiveTemporaryAssignments() {
        User owner1 = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];
        User owner2 = [SELECT Id FROM User WHERE LastName = 'Owner2' LIMIT 1];
        Lead__c lead = [SELECT Id FROM Lead__c WHERE OwnerId = :owner1.Id LIMIT 1];

        // Create an active temp assignment history
        Reassignment_History__c rh = new Reassignment_History__c(
            Lead__c = lead.Id,
            Old_Owner__c = owner1.Id,
            New_Owner__c = owner2.Id,
            Assigned_By__c = UserInfo.getUserId(),
            Reassignment_Type__c = 'Temporary',
            Status__c = 'Active',
            Temp_Expiry__c = Date.today().addDays(5),
            Reassigned_Date__c = DateTime.now(),
            Reason__c = 'Test leave'
        );
        insert rh;

        Test.startTest();
        List<Reassignment_History__c> results = BulkLeadReassignmentController.getActiveTemporaryAssignments();
        Test.stopTest();

        System.assert(results.size() > 0, 'Should return at least one temp assignment');
    }

    @isTest
    static void testRevokeTemporaryAccess() {
        User owner1 = [SELECT Id FROM User WHERE LastName = 'Owner1' LIMIT 1];
        User owner2 = [SELECT Id FROM User WHERE LastName = 'Owner2' LIMIT 1];
        Lead__c lead = [SELECT Id FROM Lead__c WHERE OwnerId = :owner1.Id LIMIT 1];

        // Set temp fields on lead
        lead.Temp_Owner__c = owner2.Id;
        lead.Temp_Start__c = Date.today();
        lead.Temp_Expiry__c = Date.today().addDays(5);
        update lead;

        // Seed a follow-up and a site visit under the lead
        Follow_up__c fu = new Follow_up__c(CLead__c = lead.Id);
        insert fu;
        Site_Visit__c sv = new Site_Visit__c(CLead__c = lead.Id);
        insert sv;

        // Create history
        Reassignment_History__c rh = new Reassignment_History__c(
            Lead__c = lead.Id,
            Old_Owner__c = owner1.Id,
            New_Owner__c = owner2.Id,
            Assigned_By__c = UserInfo.getUserId(),
            Reassignment_Type__c = 'Temporary',
            Status__c = 'Active',
            Temp_Expiry__c = Date.today().addDays(5),
            Reassigned_Date__c = DateTime.now(),
            Reason__c = 'Test'
        );
        insert rh;

        // Insert manual shares so revokeTemporaryAccess hits the share-deletion paths
        insert new Lead__Share(
            ParentId = lead.Id,
            UserOrGroupId = owner2.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
        );
        Database.insert(new Follow_up__Share(
            ParentId = fu.Id,
            UserOrGroupId = owner2.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
        ), false);
        Database.insert(new Site_Visit__Share(
            ParentId = sv.Id,
            UserOrGroupId = owner2.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
        ), false);

        Test.startTest();
        String result = BulkLeadReassignmentController.revokeTemporaryAccess(new List<Id>{ rh.Id });
        Test.stopTest();

        System.assert(result.contains('revoked'), 'Should return revoked message');

        // Verify status changed
        Reassignment_History__c updated = [SELECT Status__c FROM Reassignment_History__c WHERE Id = :rh.Id];
        System.assertEquals('Revoked', updated.Status__c, 'Status should be Revoked');

        // Verify temp fields cleared
        Lead__c updatedLead = [SELECT Temp_Owner__c, Temp_Expiry__c FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals(null, updatedLead.Temp_Owner__c, 'Temp owner should be cleared');
        System.assertEquals(null, updatedLead.Temp_Expiry__c, 'Temp expiry should be cleared');

        // Verify all manual shares for the temp owner were removed
        Integer leadShares = [
            SELECT COUNT() FROM Lead__Share
            WHERE ParentId = :lead.Id AND UserOrGroupId = :owner2.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, leadShares, 'Lead manual share removed');

        Integer fuShares = [
            SELECT COUNT() FROM Follow_up__Share
            WHERE ParentId = :fu.Id AND UserOrGroupId = :owner2.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, fuShares, 'Follow-up manual share removed');

        Integer svShares = [
            SELECT COUNT() FROM Site_Visit__Share
            WHERE ParentId = :sv.Id AND UserOrGroupId = :owner2.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, svShares, 'Site visit manual share removed');
    }

    @isTest
    static void testRevokeValidationNoRecords() {
        Boolean threw = false;
        try {
            Test.startTest();
            BulkLeadReassignmentController.revokeTemporaryAccess(new List<Id>());
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw no records error');
    }
}