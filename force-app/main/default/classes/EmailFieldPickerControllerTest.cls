/**
 * @description Test class for EmailFieldPickerController
 */
@isTest
private class EmailFieldPickerControllerTest {

    @testSetup
    static void setup() {
        postSalesTestDataFactory.createAccount('Field Picker Acc');
    }

    @isTest
    static void getAllObjects_returnsList() {
        List<EmailFieldPickerController.ObjectWrapper> objs =
            EmailFieldPickerController.getAllObjects();
        System.assert(objs.size() > 0, 'Should return objects');
    }

    @isTest
    static void getFieldsForObject_returnsList() {
        List<EmailFieldPickerController.FieldWrapper> fields =
            EmailFieldPickerController.getFieldsForObject('Account');
        System.assert(fields.size() > 0, 'Should return fields');
    }

    @isTest
    static void getFieldsForObject_blank_returnsEmpty() {
        List<EmailFieldPickerController.FieldWrapper> fields =
            EmailFieldPickerController.getFieldsForObject('');
        System.assertEquals(0, fields.size(), 'Empty');
    }

    @isTest
    static void getFieldsForObject_invalid_throws() {
        Boolean threw = false;
        try {
            EmailFieldPickerController.getFieldsForObject('NotAnObject!!!');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void getEmailFieldsForObject_returnsList() {
        List<EmailFieldPickerController.FieldWrapper> fields =
            EmailFieldPickerController.getEmailFieldsForObject('Contact');
        System.assertNotEquals(null, fields, 'Should return list');
    }

    @isTest
    static void getMergeFieldsForObject_returnsList() {
        List<EmailFieldPickerController.FieldWrapper> fields =
            EmailFieldPickerController.getMergeFieldsForObject('Account');
        System.assertNotEquals(null, fields, 'Should return list');
    }

    @isTest
    static void getOrgWideEmailAddresses_returnsList() {
        List<EmailFieldPickerController.ObjectWrapper> addrs =
            EmailFieldPickerController.getOrgWideEmailAddresses();
        System.assertNotEquals(null, addrs, 'Should return list');
    }

    @isTest
    static void getVisualforcePages_returnsList() {
        List<EmailFieldPickerController.ObjectWrapper> pages =
            EmailFieldPickerController.getVisualforcePages();
        System.assertNotEquals(null, pages, 'Should return list');
    }

    @isTest
    static void getRelatedObjects_returnsList() {
        List<EmailFieldPickerController.RelationshipWrapper> rels =
            EmailFieldPickerController.getRelatedObjects('Account');
        System.assertNotEquals(null, rels, 'Should return list');
    }

    @isTest
    static void getRelatedObjects_blank_returnsEmpty() {
        List<EmailFieldPickerController.RelationshipWrapper> rels =
            EmailFieldPickerController.getRelatedObjects('');
        System.assertEquals(0, rels.size(), 'Empty for blank input');
    }

    @isTest
    static void getRelatedObjects_invalid_throws() {
        Boolean threw = false;
        try {
            EmailFieldPickerController.getRelatedObjects('NotAnObject!!!');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void searchRecords_returnsList() {
        List<EmailFieldPickerController.ObjectWrapper> r =
            EmailFieldPickerController.searchRecords('Account', 'Field');
        System.assertNotEquals(null, r, 'Should return list');
    }

    @isTest
    static void searchRecords_noTerm_returnsList() {
        List<EmailFieldPickerController.ObjectWrapper> r =
            EmailFieldPickerController.searchRecords('Account', null);
        System.assertNotEquals(null, r, 'Should return list');
    }

    @isTest
    static void searchRecords_blank_returnsEmpty() {
        List<EmailFieldPickerController.ObjectWrapper> r =
            EmailFieldPickerController.searchRecords('', 'X');
        System.assertEquals(0, r.size(), 'Empty for blank object');
    }
}