/**
 * @description Trigger on Receipt__c.
 *              - (before) Receipt approval / locking rules (BRD 5.12 - 5.15). See
 *                {@link ReceiptApprovalGateService}.
 *              - (after update) When a receipt becomes Approved, create its Receipt Line Items and
 *                adjust the payment schedules / demands / advances. A Rejected receipt never reaches
 *                Approved, so no line items are created for it. See {@link ReceiptAllocationService}.
 * @author System
 */
trigger ReceiptTrigger on Receipt__c (before insert, before update, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        //ReceiptApprovalGateService.validateNewReceipts(Trigger.new);
        //ReceiptApprovalGateService.SubmitForApproval(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        //ReceiptApprovalGateService.validateReceiptEdits(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        // Allocate (create line items + adjust milestones) only when the receipt is Approved;
        // nothing happens on Rejected.
        ReceiptAllocationService.allocateOnApproval(Trigger.new, Trigger.oldMap);
    }
}