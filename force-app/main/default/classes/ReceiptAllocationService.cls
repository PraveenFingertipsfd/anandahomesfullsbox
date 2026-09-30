/**
 * @description Runs the receipt allocation (Receipt Line Item creation + payment schedule / demand /
 *              advance adjustment) when a Receipt is APPROVED, not when it is created. A receipt that
 *              is Rejected never reaches 'Approved', so no line items are ever created for it and there
 *              is nothing to reverse.
 *
 *              Called from {@link ReceiptTrigger} (after update); the heavy lifting is
 *              {@link FinancialTransactionController#allocateReceipt}, which is idempotent.
 * @author System
 */
public without sharing class ReceiptAllocationService {

    /**
     * @description Recursion guard. allocateReceipt updates the Receipt (to store the created advance),
     *              which re-fires this after-update trigger; the status is unchanged on that pass, so no
     *              re-allocation happens, but the guard makes that explicit and cheap.
     */
    public static Boolean bypass = false;

    /**
     * @description For each receipt whose Approval_Status__c has just become 'Approved', allocate it.
     *              Does nothing for any other transition (including 'Rejected').
     * @param newList Trigger.new
     * @param oldMap  Trigger.oldMap
     */
    public static void allocateOnApproval(List<Receipt__c> newList, Map<Id, Receipt__c> oldMap) {
        if (bypass || newList == null || oldMap == null) return;

        List<Id> toAllocate = new List<Id>();
        for (Receipt__c r : newList) {
            Receipt__c old = oldMap.get(r.Id);
            if (old == null) continue;

            Boolean nowApproved = PostSalesConstants.APPROVAL_STATUS_APPROVED.equalsIgnoreCase(r.Approval_Status__c);
            Boolean wasApproved = PostSalesConstants.APPROVAL_STATUS_APPROVED.equalsIgnoreCase(old.Approval_Status__c);

            if (nowApproved && !wasApproved) {
                toAllocate.add(r.Id);
            }
            // Rejected (or any other status): nothing to do - no line items were ever created.
        }

        if (toAllocate.isEmpty()) return;

        bypass = true;
        try {
            for (Id receiptId : toAllocate) {
                FinancialTransactionController.allocateReceipt(receiptId);
            }
        } finally {
            bypass = false;
        }
    }
}
