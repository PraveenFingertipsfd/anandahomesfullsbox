/**
 * @description Test class for ConfigMatchingService
 */
@isTest
private class ConfigMatchingServiceTest {

    @testSetup
    static void setup() {
        Project__c project = new Project__c(
            Name = 'CMS Test Project',
            Project_Type__c = 'Apartment',
            Interest_Rate__c = 12
        );
        insert project;
    }

    @isTest
    static void evaluateCriteria_blank_returnsTrue() {
        Test.startTest();
        Boolean result = ConfigMatchingService.evaluateCriteria(null, null, 'Account');
        Test.stopTest();
        System.assertEquals(true, result, 'Blank criteria should evaluate to true');
    }

    @isTest
    static void evaluateCriteria_emptyConditions_returnsTrue() {
        String json = '{"matchLogic":"AND","conditions":[]}';
        Test.startTest();
        Boolean result = ConfigMatchingService.evaluateCriteria(json, null, 'Account');
        Test.stopTest();
        System.assertEquals(true, result, 'Empty conditions should evaluate to true');
    }

    @isTest
    static void evaluateCriteria_profileMatchAnd_returnsBoolean() {
        User u = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String json = '{"matchLogic":"AND","conditions":[' +
            '{"type":"profile","operator":"in","values":["' + u.Profile.Name + '"]}' +
            ']}';

        Test.startTest();
        Boolean result = ConfigMatchingService.evaluateCriteria(json, null, 'Account');
        Test.stopTest();
        System.assertEquals(true, result, 'Profile match should return true for current user profile');
    }

    @isTest
    static void evaluateCriteria_profileNotIn_returnsFalse() {
        User u = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String json = '{"matchLogic":"AND","conditions":[' +
            '{"type":"profile","operator":"notIn","values":["' + u.Profile.Name + '"]}' +
            ']}';

        Test.startTest();
        Boolean result = ConfigMatchingService.evaluateCriteria(json, null, 'Account');
        Test.stopTest();
        System.assertEquals(false, result, 'notIn for matching profile should return false');
    }

    @isTest
    static void evaluateCriteria_orLogic_anyMatchReturnsTrue() {
        User u = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String json = '{"matchLogic":"OR","conditions":[' +
            '{"type":"profile","operator":"in","values":["NoSuchProfile"]},' +
            '{"type":"profile","operator":"in","values":["' + u.Profile.Name + '"]}' +
            ']}';

        Test.startTest();
        Boolean result = ConfigMatchingService.evaluateCriteria(json, null, 'Account');
        Test.stopTest();
        System.assertEquals(true, result, 'OR logic with one match should return true');
    }

    @isTest
    static void evaluateCriteria_fieldEquals_evaluatesAgainstRecord() {
        Project__c project = [SELECT Id, Name FROM Project__c LIMIT 1];
        String json = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","fieldPath":"Name","operator":"equals","value":"' + project.Name + '"}' +
            ']}';

        Test.startTest();
        Boolean result = ConfigMatchingService.evaluateCriteria(json, project.Id, 'Project__c');
        Test.stopTest();
        System.assertEquals(true, result, 'Field equality should match');
    }

    @isTest
    static void evaluateCriteria_fieldOperators_coverage() {
        Project__c project = [SELECT Id, Name, Interest_Rate__c FROM Project__c LIMIT 1];

        String containsJson = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","fieldPath":"Name","operator":"contains","value":"Test"}]}';
        String startsJson = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","fieldPath":"Name","operator":"startsWith","value":"CMS"}]}';
        String gtJson = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","fieldPath":"Interest_Rate__c","operator":"greaterThan","value":"5"}]}';
        String ltJson = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","fieldPath":"Interest_Rate__c","operator":"lessThan","value":"100"}]}';
        String notNullJson = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","fieldPath":"Name","operator":"isNotNull","value":""}]}';

        Test.startTest();
        System.assertEquals(true, ConfigMatchingService.evaluateCriteria(containsJson, project.Id, 'Project__c'),
            'Contains should match');
        System.assertEquals(true, ConfigMatchingService.evaluateCriteria(startsJson, project.Id, 'Project__c'),
            'StartsWith should match');
        System.assertEquals(true, ConfigMatchingService.evaluateCriteria(gtJson, project.Id, 'Project__c'),
            'GreaterThan should match');
        System.assertEquals(true, ConfigMatchingService.evaluateCriteria(ltJson, project.Id, 'Project__c'),
            'LessThan should match');
        System.assertEquals(true, ConfigMatchingService.evaluateCriteria(notNullJson, project.Id, 'Project__c'),
            'isNotNull should match');
        Test.stopTest();
    }

    @isTest
    static void filterMatchingConfigs_returnsOnlyMatching() {
        User u = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String matchCriteria = '{"matchLogic":"AND","conditions":[' +
            '{"type":"profile","operator":"in","values":["' + u.Profile.Name + '"]}]}';
        String nonMatchCriteria = '{"matchLogic":"AND","conditions":[' +
            '{"type":"profile","operator":"in","values":["NotARealProfile"]}]}';

        String configsJson = '[' +
            '{"id":"a","matchingCriteria":' + JSON.serialize(matchCriteria) + '},' +
            '{"id":"b","matchingCriteria":' + JSON.serialize(nonMatchCriteria) + '}' +
            ']';

        Test.startTest();
        List<String> matched = ConfigMatchingService.filterMatchingConfigs(configsJson, null, 'Account');
        Test.stopTest();

        System.assertEquals(1, matched.size(), 'Only one config should match');
        System.assertEquals('a', matched[0], 'Matching config id should be "a"');
    }

    @isTest
    static void getAllProfiles_returnsList() {
        Test.startTest();
        List<Map<String, String>> profiles = ConfigMatchingService.getAllProfiles();
        Test.stopTest();
        System.assert(profiles != null && !profiles.isEmpty(), 'Profiles should be returned');
    }

    @isTest
    static void getAllRoles_returnsList() {
        Test.startTest();
        List<Map<String, String>> roles = ConfigMatchingService.getAllRoles();
        Test.stopTest();
        System.assertNotEquals(null, roles, 'Roles list should not be null');
    }

    @isTest
    static void searchUsers_returnsList() {
        Test.startTest();
        List<Map<String, String>> users = ConfigMatchingService.searchUsers('a');
        Test.stopTest();
        System.assertNotEquals(null, users, 'Users list should not be null');
    }

    @isTest
    static void getFieldsForObject_validObject_returnsFields() {
        Test.startTest();
        List<Map<String, String>> fields = ConfigMatchingService.getFieldsForObject('Account');
        Test.stopTest();
        System.assert(fields != null && !fields.isEmpty(), 'Account fields should be returned');
    }

    @isTest
    static void getFieldsForObject_blankObject_returnsEmpty() {
        Test.startTest();
        List<Map<String, String>> fields = ConfigMatchingService.getFieldsForObject('');
        Test.stopTest();
        System.assertEquals(0, fields.size(), 'Blank object name should return empty list');
    }

    @isTest
    static void getFieldsForObject_invalidObject_returnsEmpty() {
        Test.startTest();
        List<Map<String, String>> fields = ConfigMatchingService.getFieldsForObject('NotARealObject__c');
        Test.stopTest();
        System.assertEquals(0, fields.size(), 'Unknown object should return empty list');
    }

    @isTest
    static void getPicklistValues_blankInputs_returnsEmpty() {
        Test.startTest();
        List<Map<String, String>> values = ConfigMatchingService.getPicklistValues(null, null);
        Test.stopTest();
        System.assertEquals(0, values.size(), 'Blank inputs should return empty list');
    }

    @isTest
    static void getPicklistValues_validField_returns() {
        Test.startTest();
        // Industry on Account is a standard picklist
        List<Map<String, String>> values = ConfigMatchingService.getPicklistValues('Account', 'Industry');
        Test.stopTest();
        System.assertNotEquals(null, values, 'Should return a list');
    }

    @isTest
    static void resolveEmailTemplateForAction_noConfig_returnsNull() {
        Test.startTest();
        String result = ConfigMatchingService.resolveEmailTemplateForAction('SomeAction', null, 'Account');
        Test.stopTest();
        System.assertEquals(null, result, 'No template configured should return null');
    }
}