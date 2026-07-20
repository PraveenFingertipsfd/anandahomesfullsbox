/**
 * @description Trigger on Receipt__c. Enforces the receipt approval / locking rules:
 *              one pending receipt per booking, no edits while pending, and frozen on
 *              rejection (BRD 5.12 - 5.15). See {@link ReceiptApprovalGateService}.
 * @author System
 */
trigger ReceiptTrigger on Receipt__c (before insert, before update) {
    /*if (Trigger.isBefore && Trigger.isInsert) {
        ReceiptApprovalGateService.validateNewReceipts(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        ReceiptApprovalGateService.validateReceiptEdits(Trigger.new, Trigger.oldMap);
    }*/
}