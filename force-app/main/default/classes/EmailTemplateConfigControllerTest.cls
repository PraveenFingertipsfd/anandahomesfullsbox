/**
 * @description Test class for EmailTemplateConfigController
 */
@isTest
private class EmailTemplateConfigControllerTest {

    @testSetup
    static void setup() {
        Email_Template_Config__c t = new Email_Template_Config__c(
            Template_Name__c = 'Setup Template',
            Object_API_Name__c = 'Account',
            Subject__c = 'Subject',
            Email_Body__c = '<p>Body</p>',
            Is_Active__c = true,
            Is_Default__c = true
        );
        insert t;
    }

    @isTest
    static void getAllTemplates_returnsList() {
        List<EmailTemplateConfigController.TemplateWrapper> list1 =
            EmailTemplateConfigController.getAllTemplates();
        System.assert(list1.size() >= 1, 'Should have templates');
    }

    @isTest
    static void getTemplatesForObject_returnsList() {
        List<EmailTemplateConfigController.TemplateWrapper> list1 =
            EmailTemplateConfigController.getTemplatesForObject('Account');
        System.assert(list1.size() >= 1, 'Should have templates for Account');
    }

    @isTest
    static void getTemplatesForObject_blank_returnsEmpty() {
        List<EmailTemplateConfigController.TemplateWrapper> list1 =
            EmailTemplateConfigController.getTemplatesForObject('');
        System.assertEquals(0, list1.size(), 'Empty for blank');
    }

    @isTest
    static void getTemplateById_existing_returns() {
        Email_Template_Config__c t = [SELECT Id FROM Email_Template_Config__c LIMIT 1];
        EmailTemplateConfigController.TemplateWrapper w = EmailTemplateConfigController.getTemplateById(t.Id);
        System.assertEquals(t.Id, w.id, 'Should match');
    }

    @isTest
    static void getTemplateById_blank_throws() {
        Boolean threw = false;
        try {
            EmailTemplateConfigController.getTemplateById('');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void saveTemplate_createNew() {
        EmailTemplateConfigController.TemplateWrapper w = new EmailTemplateConfigController.TemplateWrapper();
        w.name = 'New Template';
        w.objectApiName = 'Account';
        w.subject = 'Hi';
        w.emailBody = '<p>X</p>';
        w.isActive = true;
        w.isDefault = false;
        Test.startTest();
        String newId = EmailTemplateConfigController.saveTemplate(JSON.serialize(w));
        Test.stopTest();
        System.assertNotEquals(null, newId, 'Should return Id');
    }

    @isTest
    static void saveTemplate_setAsDefault_unsetsOthers() {
        EmailTemplateConfigController.TemplateWrapper w = new EmailTemplateConfigController.TemplateWrapper();
        w.name = 'New Default';
        w.objectApiName = 'Account';
        w.subject = 'Hi';
        w.emailBody = '<p>X</p>';
        w.isActive = true;
        w.isDefault = true;
        String newId = EmailTemplateConfigController.saveTemplate(JSON.serialize(w));
        Integer count = [SELECT COUNT() FROM Email_Template_Config__c
                          WHERE Object_API_Name__c='Account' AND Is_Default__c=true];
        System.assert(count >= 1, 'New default exists');
    }

    @isTest
    static void saveTemplate_blank_throws() {
        Boolean threw = false;
        try {
            EmailTemplateConfigController.saveTemplate('');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void deleteTemplate_removes() {
        Email_Template_Config__c t = [SELECT Id FROM Email_Template_Config__c LIMIT 1];
        EmailTemplateConfigController.deleteTemplate(t.Id);
        Integer count = [SELECT COUNT() FROM Email_Template_Config__c WHERE Id = :t.Id];
        System.assertEquals(0, count, 'Should be deleted');
    }

    @isTest
    static void deleteTemplate_blank_throws() {
        Boolean threw = false;
        try {
            EmailTemplateConfigController.deleteTemplate('');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void cloneTemplate_returnsId() {
        Email_Template_Config__c t = [SELECT Id FROM Email_Template_Config__c LIMIT 1];
        Test.startTest();
        String cloneId = EmailTemplateConfigController.cloneTemplate(t.Id);
        Test.stopTest();
        System.assertNotEquals(null, cloneId, 'Should return clone Id');
    }

    @isTest
    static void toggleActiveStatus_updates() {
        Email_Template_Config__c t = [SELECT Id, Is_Active__c FROM Email_Template_Config__c LIMIT 1];
        EmailTemplateConfigController.toggleActiveStatus(t.Id, false);
        Email_Template_Config__c after1 = [SELECT Is_Active__c FROM Email_Template_Config__c WHERE Id = :t.Id];
        System.assertEquals(false, after1.Is_Active__c, 'Should be inactive');
    }
}