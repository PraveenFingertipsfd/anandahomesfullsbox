/**
 * @description Test class for EmailMergeFieldResolver
 */
@isTest
private class EmailMergeFieldResolverTest {

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'Merge Test Account', Phone = '555-1234');
        insert a;
    }

    @isTest
    static void resolveMergeFields_blankInputs_returnsAsIs() {
        System.assertEquals(null, EmailMergeFieldResolver.resolveMergeFields(null, null, 'Account'), 'Null template returns null');
        System.assertEquals('text', EmailMergeFieldResolver.resolveMergeFields('text', null, 'Account'), 'Null id returns template');
    }

    @isTest
    static void resolveMergeFields_validTemplate_replacesField() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        String result = EmailMergeFieldResolver.resolveMergeFields('Hello {!Name}', a.Id, 'Account');
        Test.stopTest();

        System.assert(result.contains('Merge Test Account'), 'Should resolve {!Name}');
    }

    @isTest
    static void extractMergeFields_returnsFieldNames() {
        Set<String> fields = EmailMergeFieldResolver.extractMergeFields('Hi {!Name}, phone {!Phone}');
        System.assertEquals(2, fields.size(), 'Should extract two fields');
        System.assert(fields.contains('Name'), 'Should contain Name');
        System.assert(fields.contains('Phone'), 'Should contain Phone');
    }

    @isTest
    static void extractMergeFields_blank_returnsEmpty() {
        Set<String> fields = EmailMergeFieldResolver.extractMergeFields(null);
        System.assertEquals(0, fields.size(), 'Null template returns empty set');
    }

    @isTest
    static void getFieldValue_simpleField_returnsValue() {
        Account a = [SELECT Id, Name FROM Account LIMIT 1];

        Test.startTest();
        String value = EmailMergeFieldResolver.getFieldValue(a, 'Name');
        Test.stopTest();

        System.assertEquals('Merge Test Account', value, 'Should return Name value');
    }

    @isTest
    static void getFieldValue_blankPath_returnsNull() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        System.assertEquals(null, EmailMergeFieldResolver.getFieldValue(a, ''), 'Blank path returns null');
        System.assertEquals(null, EmailMergeFieldResolver.getFieldValue(null, 'Name'), 'Null record returns null');
    }

    @isTest
    static void resolveEmailField_returnsValue() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        String result = EmailMergeFieldResolver.resolveEmailField('Name', a.Id, 'Account');
        Test.stopTest();

        System.assertEquals('Merge Test Account', result, 'Should resolve to Name');
    }

    @isTest
    static void resolveEmailField_blankInputs_returnsNull() {
        System.assertEquals(null, EmailMergeFieldResolver.resolveEmailField(null, null, 'Account'));
    }

    @isTest
    static void resolveRecipientEmail_static() {
        String result = EmailMergeFieldResolver.resolveRecipientEmail('Static', null, 'foo@bar.com', null, null);
        System.assertEquals('foo@bar.com', result);
    }

    @isTest
    static void resolveRecipientEmail_currentUser() {
        String result = EmailMergeFieldResolver.resolveRecipientEmail('CurrentUser', null, null, null, null);
        System.assertEquals(UserInfo.getUserEmail(), result, 'Should return running user email');
    }

    @isTest
    static void resolveRecipientEmail_recordOwner() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        String result = EmailMergeFieldResolver.resolveRecipientEmail('RecordOwner', null, null, a.Id, 'Account');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Owner email should not be null');
    }

    @isTest
    static void resolveRecipientEmail_field() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        String result = EmailMergeFieldResolver.resolveRecipientEmail('Field', 'Name', null, a.Id, 'Account');
        Test.stopTest();
        System.assertEquals('Merge Test Account', result);
    }

    @isTest
    static void resolveFileName_returnsResolved() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        String name = EmailMergeFieldResolver.resolveFileName('File_{!Name}.pdf', a.Id, 'Account');
        Test.stopTest();
        System.assert(name.contains('Merge Test Account'), 'File name should resolve merge field');
    }

    @isTest
    static void resolveFileName_blank_returnsDefault() {
        String name = EmailMergeFieldResolver.resolveFileName(null, null, null);
        System.assertEquals('Attachment.pdf', name, 'Default file name should be returned');
    }
}