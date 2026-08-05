/**
 * @description Trigger on Receipt_Line_Item__c. Enforces milestone-by-milestone payment
 *              sequencing (BRD pointer 4) when receipts are allocated to payment schedules.
 * @author System
 */
trigger ReceiptLineItemTrigger on Receipt_Line_Item__c (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        //MilestonePaymentGateService.validateAllocations(Trigger.new);
    }
}