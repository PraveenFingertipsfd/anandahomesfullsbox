public class CostSheetController {

    public List<Cost_Sheet_Line_Item__c> lineItems { get; set; }

    public CostSheetController(ApexPages.StandardController controller) {
        Id quoteId = controller.getId();
        lineItems = [SELECT S_No__c, Payment_Schedule_Name__c, Payment_percent__c
                     FROM Cost_Sheet_Line_Item__c
                     WHERE Quote__c = :quoteId
                     ORDER BY S_No__c ASC];
    }
}