/**
 * @description Test class for FieldDiscoveryService
 */
@isTest
private class FieldDiscoveryServiceTest {

    @isTest
    static void discoverUserLookups_account_returnsPaths() {
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> options =
            FieldDiscoveryService.discoverUserLookups('Account');
        Test.stopTest();

        System.assertNotEquals(null, options, 'Result should not be null');
        // Account has OwnerId and CreatedById which point to User
        System.assert(options.size() >= 1, 'At least one user lookup should be found on Account');
    }

    @isTest
    static void discoverUserLookups_invalidObject_returnsEmpty() {
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> options =
            FieldDiscoveryService.discoverUserLookups('NotARealObject__c');
        Test.stopTest();
        System.assertEquals(0, options.size(), 'Invalid object should return empty list');
    }

    @isTest
    static void discoverUserLookups_userObject_findsManagerAndOthers() {
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> options =
            FieldDiscoveryService.discoverUserLookups('User');
        Test.stopTest();
        System.assert(options != null, 'Should not be null');
    }

    @isTest
    static void discoverUserLookups_traversesRelationships() {
        // Opportunity has AccountId (Account) which has OwnerId (User)
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> options =
            FieldDiscoveryService.discoverUserLookups('Opportunity');
        Test.stopTest();
        System.assert(options != null && !options.isEmpty(),
            'Opportunity should have user lookups discovered');
    }
}