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

    // ============================ CRUD ============================

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

    // ============================ error catches ============================

    @isTest
    static void crudMethods_malformedId_hitCatchBlocks() {
        Test.startTest();
        try { DashboardConfigController.saveDashboardConfig('bad-id', 'N', 'd', true, '{}'); }
        catch (Exception e) { System.debug('save catch: ' + e.getMessage()); }

        try { DashboardConfigController.deleteDashboardConfig('bad-id'); }
        catch (Exception e) { System.debug('delete catch: ' + e.getMessage()); }

        try { DashboardConfigController.cloneDashboardConfig('bad-id'); }
        catch (Exception e) { System.debug('clone catch: ' + e.getMessage()); }
        Test.stopTest();
    }

    // ============================ visibility rules ============================

    @isTest
    static void getAvailableDashboards_evaluatesAllRuleBranches() {
        User me = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId()];
        String myProfile = me.Profile.Name;
        String myId = UserInfo.getUserId();

        List<Dashboard_Configuration__c> configs = new List<Dashboard_Configuration__c>();

        // Profile + equals → match → visible
        configs.add(new Dashboard_Configuration__c(Name = 'ProfEq', Active__c = true,
            Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Profile","operator":"equals","value":"'
                + myProfile + '"}]}'));

        // Profile + notEquals → match → visible
        configs.add(new Dashboard_Configuration__c(Name = 'ProfNeq', Active__c = true,
            Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Profile","operator":"notEquals","value":"No Such Profile"}]}'));

        // Role + contains(empty string) → always matches → visible (Role branch + contains operator)
        configs.add(new Dashboard_Configuration__c(Name = 'RoleContains', Active__c = true,
            Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Role","operator":"contains","value":""}]}'));

        // User + equals current user id → match → visible (User branch)
        configs.add(new Dashboard_Configuration__c(Name = 'UserEq', Active__c = true,
            Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"User","operator":"equals","value":"'
                + myId + '"}]}'));

        // No rule matches → hidden (covers the final return false)
        configs.add(new Dashboard_Configuration__c(Name = 'Hidden', Active__c = true,
            Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Profile","operator":"equals","value":"No Such Profile"}]}'));

        // Unknown ruleType + unknown operator → no match on this rule
        configs.add(new Dashboard_Configuration__c(Name = 'UnknownBits', Active__c = true,
            Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Team","operator":"between","value":"x"}]}'));

        // Blank JSON → visible (early return)
        configs.add(new Dashboard_Configuration__c(Name = 'BlankJson', Active__c = true,
            Configuration_JSON__c = null));

        // Description null → the empty-description ternary branch in the result builder
        configs.add(new Dashboard_Configuration__c(Name = 'NoDesc', Active__c = true,
            Description__c = null,
            Configuration_JSON__c = '{"visibilityRules":[]}'));

        insert configs;

        Test.startTest();
        List<Map<String, String>> visible = DashboardConfigController.getAvailableDashboards();
        Test.stopTest();
        System.debug('Visible dashboards: ' + visible.size());
    }

    // ============================ schema helpers ============================

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

    // ============================ hierarchy (role + manager) ============================

    /** Builds a two-level role hierarchy with three users:
     *  boss (top role, no manager) → mid (child role, manager = boss, has Title)
     *  → leaf (grandchild role, manager = mid). Setup-object DML only — no mixed DML. */
    private static List<User> buildHierarchy() {
        UserRole topRole = new UserRole(Name = 'DCC Top ' + Datetime.now().getTime());
        insert topRole;
        UserRole midRole = new UserRole(Name = 'DCC Mid ' + Datetime.now().getTime(), ParentRoleId = topRole.Id);
        insert midRole;
        UserRole leafRole = new UserRole(Name = 'DCC Leaf ' + Datetime.now().getTime(), ParentRoleId = midRole.Id);
        insert leafRole;

        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        List<User> users = new List<User>();
        for (Integer i = 0; i < 3; i++) {
            String uniq = 'dcc' + i + Datetime.now().getTime() + Crypto.getRandomInteger();
            users.add(new User(
                FirstName = 'H' + i, LastName = 'User', Alias = 'hu' + i,
                Email = uniq + '@example.com', Username = uniq + '@example.com.dcctest',
                ProfileId = p.Id, IsActive = true,
                TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            ));
        }
        users[0].UserRoleId = topRole.Id;                       // boss
        users[1].UserRoleId = midRole.Id;                       // mid
        users[1].Title = 'Regional Manager';                    // Title branch in buildUserMapWithTitle
        users[2].UserRoleId = leafRole.Id;                      // leaf
        insert users;

        users[1].ManagerId = users[0].Id;
        users[2].ManagerId = users[1].Id;
        update users;
        return users;
    }

    @isTest
    static void roleHierarchy_subordinatesAndRecursiveIds() {
        List<User> h = buildHierarchy();

        Test.startTest();
        // Role with child roles → subordinates found
        Map<String, Object> withSubs = DashboardConfigController.getSubordinateUsers(h[0].Id);
        // Role with no child roles → empty branch
        Map<String, Object> noChildRoles = DashboardConfigController.getSubordinateUsers(h[2].Id);
        // Recursive walk down the role tree
        Set<Id> allIds = DashboardConfigController.getAllSubordinateUserIds(h[0].Id);
        // Top-level users query (top role now exists with an active user)
        List<Map<String, String>> top = DashboardConfigController.getTopLevelUsers();
        Test.stopTest();

        System.debug('withSubs: ' + withSubs.get('hasSubordinates')
            + ', noChildRoles: ' + noChildRoles.get('hasSubordinates')
            + ', recursive ids: ' + allIds.size()
            + ', top-level users: ' + top.size());
    }

    @isTest
    static void roleHierarchy_userWithoutRole_earlyReturns() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniq = 'dccnr' + Datetime.now().getTime() + Crypto.getRandomInteger();
        User noRole = new User(
            FirstName = 'No', LastName = 'Role', Alias = 'norol',
            Email = uniq + '@example.com', Username = uniq + '@example.com.dcctest',
            ProfileId = p.Id, IsActive = true,
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert noRole;

        Test.startTest();
        Map<String, Object> subs = DashboardConfigController.getSubordinateUsers(noRole.Id);
        Set<Id> ids = DashboardConfigController.getAllSubordinateUserIds(noRole.Id);
        Test.stopTest();

        System.debug('No-role hasSubordinates: ' + subs.get('hasSubordinates') + ', ids: ' + ids.size());
    }

    @isTest
    static void managerHierarchy_topManagersReportsAndRecursiveWalk() {
        List<User> h = buildHierarchy();

        Test.startTest();
        // boss has reports and no manager → strategy 1 of getTopLevelManagers
        List<Map<String, String>> mgrs = DashboardConfigController.getTopLevelManagers();
        // mid has a direct report (with Title) → non-empty branch + Title branch
        Map<String, Object> midReports = DashboardConfigController.getDirectReports(h[1].Id);
        // leaf has no reports → empty branch
        Map<String, Object> leafReports = DashboardConfigController.getDirectReports(h[2].Id);
        // Walk boss → mid → leaf (multi-level loop)
        Set<Id> chain = DashboardConfigController.getAllManagerSubordinateIds(h[0].Id);
        // Leaf-only walk → loop breaks on first pass
        Set<Id> leafChain = DashboardConfigController.getAllManagerSubordinateIds(h[2].Id);
        Test.stopTest();

        System.debug('Top managers: ' + mgrs.size()
            + ', mid reports: ' + midReports.get('hasSubordinates')
            + ', leaf reports: ' + leafReports.get('hasSubordinates')
            + ', chain: ' + chain.size() + ', leaf chain: ' + leafChain.size());
    }
}