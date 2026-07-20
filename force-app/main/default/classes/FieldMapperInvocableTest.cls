/**
 * @description Test class for FieldMapperInvocable
 */
@isTest
private class FieldMapperInvocableTest {

    @isTest
    static void mapFields_blankInputs_returnsErrorMessage() {
        FieldMapperInvocable.Request r = new FieldMapperInvocable.Request();
        r.sourceRecordId = '';
        r.objectApiName = '';
        r.isInsert = true;

        Test.startTest();
        List<FieldMapperInvocable.Result> results =
            FieldMapperInvocable.mapFields(new List<FieldMapperInvocable.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Blank inputs should fail');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be populated');
    }

    @isTest
    static void mapFields_noConfig_returnsSuccess() {
        Account a = new Account(Name = 'Mapper Test');
        insert a;

        FieldMapperInvocable.Request r = new FieldMapperInvocable.Request();
        r.sourceRecordId = String.valueOf(a.Id);
        r.objectApiName = 'Account';
        r.isInsert = true;
        r.targetRecordId = null;

        Test.startTest();
        List<FieldMapperInvocable.Result> results =
            FieldMapperInvocable.mapFields(new List<FieldMapperInvocable.Request>{ r });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'No config should still report success');
    }
}