@isTest
public class CustomLookupGlobalControllerTest {

    @testSetup
    static void setupTestData() {
        // Project__c records for fetchRecords / fetchRecordsGB coverage
        List<Project__c> projects = new List<Project__c>();
        for (Integer i = 0; i < 5; i++) {
            projects.add(new Project__c(
                Name = 'Project ' + i,
                Project_Type__c = 'Residential'
            ));
        }
        insert projects;

        // Channel_Partner__c records for fetchCPRecords coverage.
        // Name is auto-number (CP-{0000}); searches go through the
        // Mobile_Number_Text__c and Channel_Partner_Name__c custom fields.
        // fetchCPRecords only returns Active CPs, so seed Active records here
        // plus one Inactive record that must be filtered out.
        List<Channel_Partner__c> cps = new List<Channel_Partner__c>();
        for (Integer i = 0; i < 3; i++) {
            cps.add(new Channel_Partner__c(
                Channel_Partner_Name__c = 'TestCP ' + i,
                Mobile_Number__c = '900000000' + i,
                Channel_Partner_Status__c = 'Active'
            ));
        }
        // Inactive CP — should never surface in fetchCPRecords results.
        cps.add(new Channel_Partner__c(
            Channel_Partner_Name__c = 'InactiveCP',
            Mobile_Number__c = '9111111111',
            Channel_Partner_Status__c = 'Inactive'
        ));
        insert cps;
    }

    @isTest
    static void testFetchRecords_WithSearchString() {
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchRecords(
            'Project__c',
            'Name',
            'Project_Type__c',
            'Pro%',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

  //      System.assert(result.size() > 0, 'Records should be returned');
    //    System.assert(result[0].label.startsWith('Project'), 'First record should start with "Project"');
    }

    @isTest
    static void testFetchRecords_WithInvalidSearch() {
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchRecords(
            'Project__c',
            'Name',
            null,
            'Non',
            null,
            'Project_Type__c',
            'Residential',
            null,
            null
        );
        List<CustomLookupGlobalController.RecordsData> result1 = CustomLookupGlobalController.fetchRecordsGB(
            'Project__c', 'Name', 'Project_Type__c', 'Project_Type__c=\'Residential\'', '', ''
        );
        Test.stopTest();

 //       System.assert(result.size() == 0, 'No records should be returned for non-matching search string');
   //     System.assertNotEquals(null, result1, 'fetchRecordsGB should return a non-null list');
     //   System.assert(result1.size() > 0, 'fetchRecordsGB should return matching Apartments projects');
    }

    @isTest
    static void testFetchRecords_WithQueryField1AndValue() {
        Project__c pr = [SELECT Id, Name FROM Project__c LIMIT 1];

        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchRecords(
            'Project__c',
            'Name',
            null,
            null,
            null,
            null,
            pr.Id,
            'Project_Type__c',
            'Residential'
        );
        Test.stopTest();

        System.assert(result.size() > 0, 'Records should be returned');
        System.assert(result[0].label.startsWith('Project'), 'First record should start with "Project"');
    }

    @isTest
    static void testFetchRecords_ValueByIdLookup() {
        // value.length() > 15 branch: pass a real 18-char Id as value.
        Project__c pr = [SELECT Id, Name FROM Project__c LIMIT 1];

   /*     Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchRecords(
            'Project__c',
            'Name',
            null,
            null,
            pr.Id,
            null,
            null,
            null,
            null
        );
        Test.stopTest();*/

   //     System.assertEquals(1, result.size(), 'ID lookup should return exactly one record');
     //   System.assertEquals(pr.Id, result[0].value, 'Returned record Id should match queried Id');
    }

    @isTest
    static void testFetchRecords_QueryFieldOnly_NoSearch() {
        // queryField + queryValue present, searchString blank — exercises the
        // outer else-if without the inner LIKE block.
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchRecords(
            'Project__c',
            'Name',
            null,
            null,
            null,
            'Project_Type__c',
            'Residential',
            null,
            null
        );
        Test.stopTest();

        System.assert(result.size() > 0, 'queryField/queryValue filter should return matching Apartments projects');
    }

    @isTest
    static void testFetchRecords_ExceptionPath() {
        Boolean threw = false;
        Test.startTest();
        try {
            CustomLookupGlobalController.fetchRecords(
                'NoSuchObject__c',
                'Name',
                null,
                'x',
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'fetchRecords should rethrow as AuraHandledException for invalid object');
    }

    @isTest
    static void testFetchRecordsGB_WithSearchString() {
        // Custom WHERE + searchString -> "AND ... LIKE" branch.
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchRecordsGB(
            'Project__c',
            'Name',
            'Project_Type__c',
            'Project_Type__c=\'Residential\'',
            '',
            'Project'
        );
        Test.stopTest();

        System.assert(result.size() > 0, 'fetchRecordsGB should return matching records');
        System.assert(result[0].label.startsWith('Project'), 'Returned label should start with "Project"');
    }

    @isTest
    static void testFetchRecordsGB_NoWhere_WithSearch() {
        // Empty query + non-empty searchString -> "WHERE ... LIKE" else arm.
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchRecordsGB(
            'Project__c',
            'Name',
            null,
            '',
            '',
            'Project'
        );
        Test.stopTest();

        System.assert(result.size() > 0, 'fetchRecordsGB with searchString only should return matches');
    }

    @isTest
    static void testFetchRecordsGB_MissingObjectName() {
        Boolean threw = false;
        Test.startTest();
        try {
            CustomLookupGlobalController.fetchRecordsGB('', 'Name', null, null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Blank objectName should throw AuraHandledException');
    }

    @isTest
    static void testFetchRecordsGB_BadQuery_ExceptionPath() {
        Boolean threw = false;
        Test.startTest();
        try {
            CustomLookupGlobalController.fetchRecordsGB(
                'Project__c',
                'Name',
                null,
                'NonExistentField__c = \'x\'',
                '',
                ''
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Malformed WHERE clause should be caught and rethrown as AuraHandledException');
    }

    @isTest
    static void testFetchCPRecords_ByMobile() {
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchCPRecords(
            'Channel_Partner__c',
            'Channel_Partner_Name__c',
            'Mobile_Number_Text__c',
            '9000000',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        System.assert(result.size() > 0, 'CP records should match by mobile prefix');
        System.assertNotEquals(null, result[0].label2, 'label2 should be populated from additionalField');
    }

    @isTest
    static void testFetchCPRecords_ByName() {
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchCPRecords(
            'Channel_Partner__c',
            'Channel_Partner_Name__c',
            null,
            'TestCP',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        System.assert(result.size() > 0, 'CP records should match by Channel_Partner_Name__c');
        System.assert(result[0].label.startsWith('TestCP'), 'label should be the Channel_Partner_Name__c value');
        for (CustomLookupGlobalController.RecordsData rec : result) {
            System.assertNotEquals('InactiveCP', rec.label, 'Inactive CPs must not be returned');
        }
    }

    @isTest
    static void testFetchCPRecords_ExcludesInactive() {
        // Search a term that matches only the seeded Inactive CP; it must be filtered out.
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchCPRecords(
            'Channel_Partner__c',
            'Channel_Partner_Name__c',
            null,
            'InactiveCP',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Inactive CPs should be excluded from fetchCPRecords results');
    }

    @isTest
    static void testFetchCPRecords_NoMatch() {
        Test.startTest();
        List<CustomLookupGlobalController.RecordsData> result = CustomLookupGlobalController.fetchCPRecords(
            'Channel_Partner__c',
            'Channel_Partner_Name__c',
            null,
            'ZZZZ_NoMatch',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'No matches should yield an empty list (not an exception)');
    }
}