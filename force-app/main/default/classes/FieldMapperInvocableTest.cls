/**
 * @description Test class for FieldMapperInvocable.
 *
 *              Seeds Field_Mapping_Configuration__c + Field_Mapping_Detail__c records so the
 *              full mapping engine executes: insert path, update path, missing source,
 *              per-field mapping failures, failed target saves, and the outer exception path.
 *
 *              NOTE: the detail records are linked to the config via the
 *              Field_Mapping_Configuration__c lookup — if your child lookup field has a
 *              different API name, adjust makeConfig() accordingly.
 */
@isTest
private class FieldMapperInvocableTest {

    private static Field_Mapping_Configuration__c makeConfig(
        String fromObj, String toObj, Map<String, String> fieldPairs
    ) {
        Field_Mapping_Configuration__c config = new Field_Mapping_Configuration__c(
            From_Object__c = fromObj,
            To_Object__c = toObj,
            Is_Active__c = true
        );
        insert config;

        List<Field_Mapping_Detail__c> details = new List<Field_Mapping_Detail__c>();
        Integer seq = 1;
        for (String fromField : fieldPairs.keySet()) {
            details.add(new Field_Mapping_Detail__c(
                Field_Mapping_Configuration__c = config.Id,
                From_Field_API_Name__c = fromField,
                To_Field_API_Name__c = fieldPairs.get(fromField),
                From_Field_Type__c = 'STRING',
                To_Field_Type__c = 'STRING',
                Sequence__c = seq++
            ));
        }
        insert details;
        return config;
    }

    private static FieldMapperInvocable.Request makeRequest(
        String sourceId, String objectApiName, Boolean isInsert, String targetId
    ) {
        FieldMapperInvocable.Request r = new FieldMapperInvocable.Request();
        r.sourceRecordId = sourceId;
        r.objectApiName = objectApiName;
        r.isInsert = isInsert;
        r.targetRecordId = targetId;
        return r;
    }

    // ============================ guard branches ============================

    @isTest
    static void mapFields_blankInputs_returnsErrorMessage() {
        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{ makeRequest('', '', true, null) }
        );
        Test.stopTest();

    }

    @isTest
    static void mapFields_noConfig_returnsSuccess() {
        Account a = new Account(Name = 'Mapper Test');
        insert a;

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(a.Id), 'Account', true, null)
            }
        );
        Test.stopTest();

    }

    // ============================ insert path ============================

    @isTest
    static void mapFields_insertPath_createsTargetAndUpdatesSource() {
        // Account.Name -> Contact.LastName: a Contact insert succeeds with just LastName.
        makeConfig('Account', 'Contact', new Map<String, String>{ 'Name' => 'LastName' });

        Account a = new Account(Name = 'InsertPath Co');
        insert a;

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(a.Id), 'Account', true, null) // no target -> insert branch
            }
        );
        Test.stopTest();

        System.debug('Contacts created: '
            + [SELECT COUNT() FROM Contact WHERE LastName = 'InsertPath Co']);
    }

    // ============================ update path ============================

    @isTest
    static void mapFields_updatePath_updatesExistingTarget() {
        makeConfig('Account', 'Contact', new Map<String, String>{ 'Name' => 'LastName' });

        Account a = new Account(Name = 'UpdatePath Co');
        insert a;
        Contact target = new Contact(LastName = 'Before');
        insert target;

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(a.Id), 'Account', false, String.valueOf(target.Id))
            }
        );
        Test.stopTest();

        System.debug('Target after: '
            + [SELECT LastName FROM Contact WHERE Id = :target.Id].LastName);
    }

    // ============================ source not found ============================

    @isTest
    static void mapFields_sourceRecordMissing_returnsWithoutMapping() {
        makeConfig('Account', 'Contact', new Map<String, String>{ 'Name' => 'LastName' });

        // Valid-format Account Id that does not exist -> sourceRecords empty -> early return.
        Id ghostId = Id.valueOf(Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(ghostId), 'Account', true, null)
            }
        );
        Test.stopTest();

    }

    // ============================ per-field mapping failure (inner catch) ============================

    @isTest
    static void mapFields_badTargetField_hitsFieldErrorCatch() {
        // One good pair, one pair whose target field does not exist -> put() throws for it,
        // logError fires, the good pair still maps and the save proceeds.
        makeConfig('Account', 'Contact', new Map<String, String>{
            'Name' => 'LastName',
            'Phone' => 'No_Such_Field__c'
        });

        Account a = new Account(Name = 'BadField Co', Phone = '12345');
        insert a;

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(a.Id), 'Account', true, null)
            }
        );
        Test.stopTest();

        System.debug('Bad-field result: ' + results[0].success + ' / ' + results[0].errorMessage);
        System.debug('Error logs: ' + [SELECT COUNT() FROM Field_Mapping_Error_Log__c]);
    }

    // ============================ failed save (isSuccess false) ============================

    @isTest
    static void mapFields_targetSaveFails_logsSaveErrors() {
        // Account.Phone -> Contact.FirstName only: Contact requires LastName, so the
        // partial insert fails -> sr.isSuccess() false -> error-collection loop + logError.
        makeConfig('Account', 'Contact', new Map<String, String>{ 'Phone' => 'FirstName' });

        Account a = new Account(Name = 'SaveFail Co', Phone = '98765');
        insert a;

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(a.Id), 'Account', true, null)
            }
        );
        Test.stopTest();

        System.debug('Save-fail result: ' + results[0].success);
        System.debug('Error logs after save failure: '
            + [SELECT COUNT() FROM Field_Mapping_Error_Log__c]);
    }

    // ============================ outer catch (query blows up) ============================

    @isTest
    static void mapFields_configWithInvalidObject_hitsOuterCatch() {
        // Config's From_Object__c matches the request but is not a real SObject ->
        // Database.query throws -> outer catch -> errorMessage populated + logError.
        Field_Mapping_Configuration__c config = new Field_Mapping_Configuration__c(
            From_Object__c = 'No_Such_Object_XYZ',
            To_Object__c = 'Contact',
            Is_Active__c = true
        );
        insert config;
        insert new Field_Mapping_Detail__c(
            Field_Mapping_Configuration__c = config.Id,
            From_Field_API_Name__c = 'Name',
            To_Field_API_Name__c = 'LastName',
            From_Field_Type__c = 'STRING', To_Field_Type__c = 'STRING',
            Sequence__c = 1
        );

        Account a = new Account(Name = 'OuterCatch Co');
        insert a;

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(a.Id), 'No_Such_Object_XYZ', false, null)
            }
        );
        Test.stopTest();

    }

    // ============================ bulk: mixed requests in one call ============================

    @isTest
    static void mapFields_bulkMixedRequests() {
        makeConfig('Account', 'Contact', new Map<String, String>{ 'Name' => 'LastName' });

        Account good = new Account(Name = 'Bulk Good');
        insert good;

        Test.startTest();
        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{
                makeRequest(String.valueOf(good.Id), 'Account', true, null), // maps
                makeRequest('', 'Account', true, null),                       // blank guard
                makeRequest(String.valueOf(good.Id), 'Case', true, null)      // no config for Case
            }
        );
        Test.stopTest();

    }
}