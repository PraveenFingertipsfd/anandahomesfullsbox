@isTest
private class CostSheetControllerTest {

    @isTest
    static void testConstructor_WithLineItems() {
        Quote__c qt = new Quote__c();
        insert qt;

        Cost_Sheet_Line_Item__c item1 = new Cost_Sheet_Line_Item__c(
            Quote__c = qt.Id,
            S_No__c = 1,
            Payment_Schedule_Name__c = 'Booking Amount',
            Payment_percent__c = 10
        );
        Cost_Sheet_Line_Item__c item2 = new Cost_Sheet_Line_Item__c(
            Quote__c = qt.Id,
            S_No__c = 2,
            Payment_Schedule_Name__c = 'On Agreement',
            Payment_percent__c = 20
        );
        insert new List<Cost_Sheet_Line_Item__c>{ item1, item2 };

        Test.startTest();
        ApexPages.StandardController sc = new ApexPages.StandardController(qt);
        CostSheetController ctrl = new CostSheetController(sc);
        Test.stopTest();

        System.assertEquals(2, ctrl.lineItems.size(), 'Should return 2 line items');
        System.assertEquals(1, ctrl.lineItems[0].S_No__c, 'First item should be S_No 1');
    }

    @isTest
    static void testConstructor_NoLineItems() {
        Quote__c qt = new Quote__c();
        insert qt;

        Test.startTest();
        ApexPages.StandardController sc = new ApexPages.StandardController(qt);
        CostSheetController ctrl = new CostSheetController(sc);
        Test.stopTest();

        System.assertEquals(0, ctrl.lineItems.size(), 'Should return empty list when no line items exist');
    }
}