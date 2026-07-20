/**
 * @description Test class for DashboardConfigController
 */
@isTest
private class DashboardConfigControllerTest {

    @testSetup
    static void setup() {
        Dashboard_Configuration__c d = new Dashboard_Configuration__c(
            Name = 'Test Dashboard',
            Description__c = 'Desc',
            Active__c = true,
            Configuration_JSON__c = '{"visibilityRules":[]}'
        );
        insert d;
    }

    @isTest
    static void getAllDashboardConfigs_returnsList() {
        List<Dashboard_Configuration__c> list1 = DashboardConfigController.getAllDashboardConfigs();
        System.assertNotEquals(null, list1, 'Should return list');
        System.assert(list1.size() >= 1, 'Should contain at least one config');
    }

    @isTest
    static void getDashboardConfig_returnsRecord() {
        Dashboard_Configuration__c d = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Dashboard_Configuration__c result = DashboardConfigController.getDashboardConfig(d.Id);
        System.assertEquals(d.Id, result.Id, 'Should return record');
    }

    @isTest
    static void saveDashboardConfig_createAndUpdate() {
        Test.startTest();
        String newId = DashboardConfigController.saveDashboardConfig(
            null, 'New Dashboard', 'desc', true, '{}'
        );
        String updated = DashboardConfigController.saveDashboardConfig(
            newId, 'Updated Name', 'desc2', false, '{}'
        );
        Test.stopTest();

        System.assertNotEquals(null, newId, 'Should return new Id');
        System.assertEquals(newId, updated, 'Update should return same Id');
    }

    @isTest
    static void deleteDashboardConfig_removesRecord() {
        Dashboard_Configuration__c d = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Test.startTest();
        DashboardConfigController.deleteDashboardConfig(d.Id);
        Test.stopTest();
        Integer count = [SELECT COUNT() FROM Dashboard_Configuration__c WHERE Id = :d.Id];
        System.assertEquals(0, count, 'Should be deleted');
    }

    @isTest
    static void cloneDashboardConfig_returnsNewId() {
        Dashboard_Configuration__c d = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Test.startTest();
        String cloneId = DashboardConfigController.cloneDashboardConfig(d.Id);
        Test.stopTest();
        System.assertNotEquals(null, cloneId, 'Should return clone Id');
    }

    @isTest
    static void getAvailableDashboards_returnsList() {
        List<Map<String, String>> list1 = DashboardConfigController.getAvailableDashboards();
        System.assertNotEquals(null, list1, 'Should return list');
    }

    @isTest
    static void schemaMethods_workForAccount() {
        List<Map<String, String>> fields = DashboardConfigController.getObjectFields('Account');
        List<Map<String, String>> objs = DashboardConfigController.getAllObjects();
        List<Map<String, String>> profiles = DashboardConfigController.getAllProfiles();
        List<Map<String, String>> roles = DashboardConfigController.getAllRoles();
        List<Map<String, String>> users = DashboardConfigController.searchUsers('Test');

        System.assertNotEquals(null, fields, 'Fields not null');
        System.assert(objs.size() > 0, 'Should return objects');
        System.assertNotEquals(null, profiles, 'Profiles not null');
        System.assertNotEquals(null, roles, 'Roles not null');
        System.assertNotEquals(null, users, 'Users not null');
    }

    @isTest
    static void getPicklistValues_works() {
        List<Map<String, String>> opts = DashboardConfigController.getPicklistValues('Account', 'Industry');
        System.assertNotEquals(null, opts, 'Should return picklist options');
    }

    @isTest
    static void getObjectFields_unknown_returnsEmpty() {
        List<Map<String, String>> fields = DashboardConfigController.getObjectFields('NonExistentObject__c');
        System.assertEquals(0, fields.size(), 'Should be empty for unknown object');
    }

    @isTest
    static void hierarchyMethods_doNotThrow() {
        List<Map<String, String>> top = DashboardConfigController.getTopLevelUsers();
        Map<String, Object> sub = DashboardConfigController.getSubordinateUsers(UserInfo.getUserId());
        Set<Id> ids = DashboardConfigController.getAllSubordinateUserIds(UserInfo.getUserId());
        List<Map<String, String>> mgrs = DashboardConfigController.getTopLevelManagers();
        Map<String, Object> direct = DashboardConfigController.getDirectReports(UserInfo.getUserId());
        Set<Id> mIds = DashboardConfigController.getAllManagerSubordinateIds(UserInfo.getUserId());

        System.assertNotEquals(null, top, 'Top users not null');
        System.assertNotEquals(null, sub, 'Subordinates not null');
        System.assertNotEquals(null, ids, 'Ids not null');
        System.assertNotEquals(null, mgrs, 'Managers not null');
        System.assertNotEquals(null, direct, 'Direct not null');
        System.assertNotEquals(null, mIds, 'Manager Ids not null');
    }
}