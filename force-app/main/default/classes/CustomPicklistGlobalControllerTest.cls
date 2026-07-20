@isTest
public class CustomPicklistGlobalControllerTest {
    
    @testSetup
    static void setupTestData() {
        // Insert test data for Project__c object
        Project__c pr1 = new Project__c(Name = 'Aarya', Project_Type__c = 'Residential');
        insert pr1;

        Project__c pr2 = new Project__c(Name = 'Arto Helix', Project_Type__c = 'Residential');
        insert pr2;
    }
    
    @isTest
    static void testFindPicklistOptions() {
        // Call the method to get picklist values
        List<CustomPicklistGlobalController.picklistWrapper> picklistValues = 
            CustomPicklistGlobalController.findPicklistOptions('Project__c', 'Project_Type__c');
        
        // Assert that picklist values are retrieved
        System.assertNotEquals(0, picklistValues.size(), 'Picklist values should not be empty');
        
        // Validate that the correct values are included
        Boolean foundApartments = false;
        for (CustomPicklistGlobalController.picklistWrapper value : picklistValues) {
            if (value.pickListValue == 'Residential') {
                foundApartments = true;
            }
        }
        System.assert(foundApartments, 'Expected picklist value "Apartments" was not found.');
    }

    @isTest
    static void invalidObjectReturnsEmptyOrNullSafely() {
        Boolean threw = false;
        List<CustomPicklistGlobalController.picklistWrapper> result;
        try {
            result = CustomPicklistGlobalController.findPicklistOptions('NotAnObject__c', 'NotAField__c');
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw || result == null || result.isEmpty(),
            'Invalid object/field should return empty/null or throw, not return data');
    }

    @isTest
    static void wrapperFieldsRoundtrip() {
        List<CustomPicklistGlobalController.picklistWrapper> result =
            CustomPicklistGlobalController.findPicklistOptions('Project__c', 'Project_Type__c');
        for (CustomPicklistGlobalController.picklistWrapper w : result) {
            System.assertNotEquals(null, w.pickListLabel, 'Label populated');
            System.assertNotEquals(null, w.pickListValue, 'Value populated');
        }
    }
}