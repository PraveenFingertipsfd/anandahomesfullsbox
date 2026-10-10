/**
 * @description Enforces the receipt approval / locking rules from the BRD.
 *
 *              BRD 5.12 - 5.13: While a receipt is Pending Approval it cannot be edited, and
 *              only NEW receipts can be created; if any receipt is Pending Approval for a
 *              booking, creation of a new receipt is blocked until the pending receipt is
 *              Approved or Rejected.
 *
 *              BRD 5.15: A Rejected receipt cannot be modified and cannot be resubmitted; the
 *              user must create a fresh receipt instead.
 *
 *              Three rules are enforced from {@link ReceiptTrigger}:
 *                1. (before insert) Block a new receipt for a booking that already has a
 *                   receipt awaiting approval.
 *                2. (before update) Block edits to a receipt that is still Pending Approval
 *                   (the approval engine may still transition its status to Approved/Rejected).
 *                3. (before update) Block any change to a Rejected receipt.
 * @author System
 */
public without sharing class ReceiptApprovalGateService {

    /** Escape hatch for trusted server-side processes (swap/transfer clones, migrations). */
    public static Boolean bypass = false;

    /** Approval-status values that mean "still awaiting a decision". */
    @TestVisible
    private static final Set<String> PENDING_STATUSES = new Set<String>{
        'Pending Approval', 'Pending For Approval', 'Pending'
    };

    private static final String STATUS_REJECTED = 'Rejected';

    // ==================== INSERT GATE ====================

    /**
     * @description Blocks creating a new receipt for a booking that still has a receipt
     *              awaiting approval (BRD 5.13).
     * @param newReceipts Trigger.new (before insert)
     */
    public static void validateNewReceipts(List<Receipt__c> newReceipts) {
        if (bypass || newReceipts == null || newReceipts.isEmpty()) return;

        Set<Id> bookingIds = new Set<Id>();
        for (Receipt__c r : newReceipts) {
            if (r.Booking__c != null) bookingIds.add(r.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        // Bookings that already have a receipt awaiting approval.
        Set<Id> bookingsWithPending = new Set<Id>();
        for (Receipt__c existing : [
            SELECT Booking__c
            FROM Receipt__c
            WHERE Booking__c IN :bookingIds
            AND Approval_Status__c IN :PENDING_STATUSES
        ]) {
            bookingsWithPending.add(existing.Booking__c);
        }
        if (bookingsWithPending.isEmpty()) return;

        for (Receipt__c r : newReceipts) {
            if (r.Booking__c != null && bookingsWithPending.contains(r.Booking__c)) {
                r.addError(
                    'A receipt for this booking is still awaiting approval. A new receipt cannot be '
                    + 'created until the pending receipt is Approved or Rejected.'
                );
            }
        }
    }

    // ==================== UPDATE GATE ====================

    /**
     * @description Blocks editing a receipt that is still Pending Approval, and blocks any
     *              change to a Rejected receipt (BRD 5.12 / 5.15). The approval engine is
     *              still allowed to move a Pending receipt to Approved/Rejected because that
     *              transition changes the Approval_Status itself.
     * @param newList Trigger.new (before update)
     * @param oldMap  Trigger.oldMap
     */
    public static void validateReceiptEdits(List<Receipt__c> newList, Map<Id, Receipt__c> oldMap) {
        if (bypass || newList == null || oldMap == null) return;

        for (Receipt__c r : newList) {
            Receipt__c old = oldMap.get(r.Id);
            if (old == null) continue;

            String oldStatus = old.Approval_Status__c;
            String newStatus = r.Approval_Status__c;

            // Rejected receipts are frozen — no edits, no resubmission.
            if (STATUS_REJECTED.equalsIgnoreCase(oldStatus)) {
                r.addError(
                    'This receipt was Rejected and can no longer be modified or resubmitted. '
                    + 'Please create a fresh receipt instead.'
                );
                continue;
            }

            // Pending receipts are locked while the status remains pending. Allowing the
            // status to move to Approved/Rejected lets the approval process complete.
            if (PENDING_STATUSES.contains(oldStatus) && oldStatus == newStatus) {
                r.addError(
                    'This receipt is awaiting approval and cannot be edited until it is '
                    + 'Approved or Rejected.'
                );
            }
        }
    }
    
    public static void SubmitForApproval(List<Receipt__c> newList) {

    List<Approval.ProcessSubmitRequest> requests = new List<Approval.ProcessSubmitRequest>();

    for (Receipt__c rep : newList) {
        // Skip records already approved or already mid-approval, so a re-fired
        // trigger doesn't try to submit the same record twice.
        if (rep.Approval_Status__c != 'Approved' && rep.Approval_Status__c != 'Pending Approval') {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setComments('Receipt Approval');
            req.setObjectId(rep.Id);
            req.setSubmitterId(UserInfo.getUserId());
            req.setProcessDefinitionNameOrId('Receipt_Approval');
            req.setSkipEntryCriteria(true);
            requests.add(req);
        }
    }

    if (requests.isEmpty()) {
        return;
    }

    // allOrNone = false: one record failing (e.g. "already has a pending approval
    // request") won't block approval submission for the rest of the batch.
    List<Approval.ProcessResult> results = Approval.process(requests, false);

    List<String> errors = new List<String>();
    for (Approval.ProcessResult result : results) {
        if (!result.isSuccess()) {
            for (Database.Error err : result.getErrors()) {
                errors.add('Receipt ' + result.getEntityId() + ': ' + err.getMessage());
            }
        }
    }

    if (!errors.isEmpty()) {
        // Surface failures without throwing — adjust to your logging/error convention
        // (custom exception, a Log__c record, etc.) as needed.
        System.debug(LoggingLevel.ERROR, 'Receipt approval submission failures: ' + String.join(errors, ' | '));
    }
}
}