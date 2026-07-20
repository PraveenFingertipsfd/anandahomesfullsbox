/**
 * @description Test class for FieldMapperController
 */
@isTest
private class FieldMapperControllerTest {

    @testSetup
    static void setup() {
        Field_Mapping_Configuration__c c = new Field_Mapping_Configuration__c(
            Name = 'TestMap',
            From_Object__c = 'Account',
            To_Object__c = 'Contact',
            Is_Active__c = false,
            Mapping_Trigger__c = 'Insert Only'
        );
        insert c;
    }

    @isTest
    static void getObjectList_returnsList() {
        List<FieldMapperController.ObjectInfo> list1 = FieldMapperController.getObjectList();
        System.assert(list1.size() > 0, 'Should return objects');
    }

    @isTest
    static void getFieldList_returnsFields() {
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getFieldList('Account');
        System.assert(fields.size() > 0, 'Should return fields');
    }

    @isTest
    static void getFieldList_invalid_returnsEmpty() {
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getFieldList('NotARealObj');
        System.assertEquals(0, fields.size(), 'Empty for invalid');
    }

    @isTest
    static void getCompatibleFields_returnsFields() {
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getCompatibleFields('Account', 'STRING');
        System.assertNotEquals(null, fields, 'Should return list');
    }

    @isTest
    static void getCompatibleFields_invalidObject_returnsEmpty() {
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getCompatibleFields('NotAnObj', 'STRING');
        System.assertEquals(0, fields.size(), 'Empty');
    }

    @isTest
    static void getAllMappingConfigurations_returnsList() {
        List<FieldMapperController.MappingConfigWrapper> list1 =
            FieldMapperController.getAllMappingConfigurations();
        System.assert(list1.size() >= 1, 'Should return list');
    }

    @isTest
    static void deleteMappingConfiguration_removes() {
        Field_Mapping_Configuration__c c = [SELECT Id FROM Field_Mapping_Configuration__c LIMIT 1];
        FieldMapperController.deleteMappingConfiguration(c.Id);
        Integer count = [SELECT COUNT() FROM Field_Mapping_Configuration__c WHERE Id = :c.Id];
        System.assertEquals(0, count, 'Should be deleted');
    }

    @isTest
    static void deleteMappingConfiguration_blank_throws() {
        Boolean threw = false;
        try {
            FieldMapperController.deleteMappingConfiguration('');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void saveMappingConfiguration_creates() {
        Map<String, Object> details = new Map<String, Object>{
            'mappingName' => 'NewMap',
            'fromObject' => 'Lead',
            'toObject' => 'Contact',
            'lookupField' => null,
            'isActive' => false,
            'mappingTrigger' => 'Insert Only',
            'mappingDetails' => JSON.serialize(new List<Object>{
                new Map<String, Object>{
                    'fromField' => 'FirstName',
                    'toField' => 'FirstName',
                    'fromFieldType' => 'STRING',
                    'toFieldType' => 'STRING',
                    'sequence' => 1
                }
            })
        };
        Test.startTest();
        FieldMapperController.saveMappingConfiguration(JSON.serialize(details));
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Field_Mapping_Configuration__c WHERE Name = 'NewMap'];
        System.assertEquals(1, count, 'Should create 1 record');
    }

    @isTest
    static void saveMappingConfiguration_duplicateActive_throws() {
        // Create first active config
        Field_Mapping_Configuration__c existing = new Field_Mapping_Configuration__c(
            Name = 'Active',
            From_Object__c = 'Lead',
            To_Object__c = 'Opportunity',
            Is_Active__c = true
        );
        insert existing;

        Map<String, Object> details = new Map<String, Object>{
            'mappingName' => 'DupActive',
            'fromObject' => 'Lead',
            'toObject' => 'Opportunity',
            'lookupField' => null,
            'isActive' => true,
            'mappingTrigger' => 'Insert Only',
            'mappingDetails' => JSON.serialize(new List<Object>())
        };

        Boolean threw = false;
        try {
            FieldMapperController.saveMappingConfiguration(JSON.serialize(details));
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw on duplicate active');
    }
}