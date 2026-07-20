/**
 * @description Test class for ReportConfigController
 */
@isTest
private class ReportConfigControllerTest {

    @testSetup
    static void setup() {
        Report_Configuration__c r = new Report_Configuration__c(
            Name = 'Test Report',
            Description__c = 'desc',
            Active__c = true,
            Configuration_JSON__c = '{}'
        );
        insert r;
    }

    @isTest
    static void getAllReportConfigs_returnsList() {
        List<Report_Configuration__c> list1 = ReportConfigController.getAllReportConfigs();
        System.assert(list1.size() >= 1, 'Should return list');
    }

    @isTest
    static void getReportConfig_returnsRecord() {
        Report_Configuration__c r = [SELECT Id FROM Report_Configuration__c LIMIT 1];
        Report_Configuration__c result = ReportConfigController.getReportConfig(r.Id);
        System.assertEquals(r.Id, result.Id, 'Should match');
    }

    @isTest
    static void saveReportConfig_createAndUpdate() {
        Test.startTest();
        String newId = ReportConfigController.saveReportConfig(
            null, 'Created', 'desc', true, '{}'
        );
        String updated = ReportConfigController.saveReportConfig(
            newId, 'Updated', 'desc2', false, '{}'
        );
        Test.stopTest();
        System.assertEquals(newId, updated, 'Update should return same Id');
    }

    @isTest
    static void deleteReportConfig_removes() {
        Report_Configuration__c r = [SELECT Id FROM Report_Configuration__c LIMIT 1];
        ReportConfigController.deleteReportConfig(r.Id);
        Integer count = [SELECT COUNT() FROM Report_Configuration__c WHERE Id = :r.Id];
        System.assertEquals(0, count, 'Should be deleted');
    }

    @isTest
    static void cloneReportConfig_returnsNewId() {
        Report_Configuration__c r = [SELECT Id FROM Report_Configuration__c LIMIT 1];
        Test.startTest();
        String cloneId = ReportConfigController.cloneReportConfig(r.Id);
        Test.stopTest();
        System.assertNotEquals(null, cloneId, 'Should return clone Id');
    }

    @isTest
    static void getAvailableReports_returnsList() {
        List<Map<String, String>> list1 = ReportConfigController.getAvailableReports();
        System.assertNotEquals(null, list1, 'Should return list');
    }

    @isTest
    static void schemaMethods_returnLists() {
        List<Map<String, String>> objs = ReportConfigController.getAllObjects();
        List<Map<String, String>> fields = ReportConfigController.getObjectFields('Account');
        List<Map<String, String>> lookupFields = ReportConfigController.getLookupObjectFields('Contact', 'AccountId');
        List<Map<String, String>> rels = ReportConfigController.getChildRelationships('Account');
        List<Map<String, String>> picks = ReportConfigController.getPicklistValues('Account', 'Industry');
        List<Map<String, String>> profiles = ReportConfigController.getAllProfiles();
        List<Map<String, String>> roles = ReportConfigController.getAllRoles();
        List<Map<String, String>> users = ReportConfigController.searchUsers('Test');

        System.assert(objs.size() > 0, 'Objects');
        System.assert(fields.size() > 0, 'Fields');
        System.assertNotEquals(null, lookupFields, 'Lookup fields not null');
        System.assertNotEquals(null, rels, 'Rels not null');
        System.assertNotEquals(null, picks, 'Picks not null');
        System.assertNotEquals(null, profiles, 'Profiles not null');
        System.assertNotEquals(null, roles, 'Roles not null');
        System.assertNotEquals(null, users, 'Users not null');
    }

    @isTest
    static void schemaMethods_invalidObject_returnsEmpty() {
        List<Map<String, String>> f = ReportConfigController.getObjectFields('NotAnObj');
        List<Map<String, String>> r = ReportConfigController.getChildRelationships('NotAnObj');
        List<Map<String, String>> l = ReportConfigController.getLookupObjectFields('NotAnObj', 'Account');
        System.assertEquals(0, f.size(), 'Empty');
        System.assertEquals(0, r.size(), 'Empty');
        System.assertEquals(0, l.size(), 'Empty');
    }
}