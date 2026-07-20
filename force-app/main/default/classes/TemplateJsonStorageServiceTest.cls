/**
 * @description Test class for TemplateJsonStorageService
 */
@isTest
private class TemplateJsonStorageServiceTest {

    @testSetup
    static void setup() {
        Document_Template__c template = new Document_Template__c(
            Name = 'TJSTest Template',
            Template_JSON__c = '{"legacy":true}'
        );
        insert template;
    }

    @isTest
    static void loadTemplateJson_legacyField_returnsValue() {
        Document_Template__c t = [
            SELECT Id, Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c LIMIT 1
        ];

        Test.startTest();
        String json = TemplateJsonStorageService.loadTemplateJson(t);
        Test.stopTest();

        System.assertEquals('{"legacy":true}', json, 'Should fall back to legacy field');
    }

    @isTest
    static void loadTemplateJson_emptyTemplate_returnsNull() {
        Document_Template__c t = new Document_Template__c(
            Name = 'TJSTest Empty'
        );
        insert t;
        Document_Template__c queried = [
            SELECT Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c WHERE Id = :t.Id
        ];

        Test.startTest();
        String json = TemplateJsonStorageService.loadTemplateJson(queried);
        Test.stopTest();

        System.assertEquals(null, json, 'Empty template should return null');
    }

    @isTest
    static void saveTemplateJson_blankInputs_returnsNull() {
        Test.startTest();
        String r1 = TemplateJsonStorageService.saveTemplateJson(null, '{"a":1}');
        String r2 = TemplateJsonStorageService.saveTemplateJson('001000000000000', null);
        Test.stopTest();
        System.assertEquals(null, r1, 'Blank id should return null');
        System.assertEquals(null, r2, 'Blank json should return null');
    }

    @isTest
    static void saveTemplateJson_createsContentVersion_andLoadsBack() {
        Document_Template__c t = [SELECT Id FROM Document_Template__c LIMIT 1];

        Test.startTest();
        String contentDocId = TemplateJsonStorageService.saveTemplateJson(t.Id, '{"new":"data"}');
        Test.stopTest();

        System.assertNotEquals(null, contentDocId, 'ContentDocumentId should be returned');

        Document_Template__c reloaded = [
            SELECT Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c WHERE Id = :t.Id
        ];
        System.assertEquals(contentDocId, reloaded.Template_Content_Document_Id__c,
            'Template should now reference the ContentDocument');
        System.assertEquals(null, reloaded.Template_JSON__c,
            'Legacy JSON field should be cleared');

        // Now load it back
        String loaded = TemplateJsonStorageService.loadTemplateJson(reloaded);
        System.assertEquals('{"new":"data"}', loaded,
            'Loaded JSON should match what we saved');
    }

    @isTest
    static void saveTemplateJson_updatesExistingContentVersion() {
        Document_Template__c t = [SELECT Id FROM Document_Template__c LIMIT 1];

        Test.startTest();
        TemplateJsonStorageService.saveTemplateJson(t.Id, '{"v":1}');
        TemplateJsonStorageService.saveTemplateJson(t.Id, '{"v":2}');
        Test.stopTest();

        Document_Template__c reloaded = [
            SELECT Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c WHERE Id = :t.Id
        ];
        String latest = TemplateJsonStorageService.loadTemplateJson(reloaded);
        System.assertEquals('{"v":2}', latest, 'Should load the latest version');
    }
}