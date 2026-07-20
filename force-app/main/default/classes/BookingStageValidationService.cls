/**
 * @description Enforces the BRD stage-progression gates on Booking. Runs on before update
 *              and blocks forward stage transitions whose prerequisites are not met:
 *
 *                • → Booked                : signed Booking Form must be uploaded (BRD §5.17–18).
 *                • → Demands & Collections : Sale Agreement Status = Completed (BRD §38–39).
 *                • → Registration          : Sale Agreement Status = Completed AND, per funding
 *                                            type, payments collected with no receipt pending
 *                                            approval (BRD §8.50).
 *                • → Handover              : Sale Deed Status = Completed (+ Date + Registration
 *                                            Number) AND final payment cleared AND all
 *                                            additional charges cleared (BRD §56–59, §84).
 *
 *              Only forward moves through the linear lifecycle are validated; moves into
 *              Cancellation / Swapping (approval-driven) and backward corrections are left
 *              alone. Set {@code bypass = true} for trusted data loads.
 * @author System
 */
public with sharing class BookingStageValidationService {

    /** Escape hatch for trusted bulk / migration processes. */
    public static Boolean bypass = false;

    private static final String COMPLETED = 'Completed';

    /** Receipt approval-status values that mean "still awaiting a decision". */
    private static final Set<String> RECEIPT_PENDING_STATUSES = new Set<String>{
        'Pending Approval', 'Pending For Approval', 'Pending'
    };

    /** Additional-charge statuses that mean the charge is fully settled / irrelevant. */
    private static final Set<String> CHARGE_CLEARED_STATUSES = new Set<String>{
        'Paid', 'Cancelled'
    };

    /** Funding types that pay entirely from own funds (BRD §8.1). */
    private static final Set<String> SELF_FUNDING = new Set<String>{ 'Self', 'Self-Funded' };

    /** Funding types where the bank disburses against milestones (BRD §8.1). */
    private static final Set<String> LOAN_FUNDING = new Set<String>{ 'Loan', 'Bank Loan', 'NBFC Loan' };

    /** Linear lifecycle order. Stages not listed (Cancellation/Swapping) are not gated. */
    private static final Map<String, Integer> STAGE_ORDER = new Map<String, Integer>{
        'New' => 0,
        'Booked' => 1,
        'Agreement' => 2,
        'Demands & Collections' => 3,
        'Registration' => 4,
        'Handover' => 5
    };

    public static void validateStageTransitions(List<Booking__c> newList, Map<Id, Booking__c> oldMap) {
        if (bypass || newList == null || oldMap == null) return;

        // Bookings transitioning into Registration / Handover need a financial (payment)
        // check that requires querying related records — collect them for one bulk pass.
        Map<Id, Booking__c> needFinancialCheck = new Map<Id, Booking__c>();

        for (Booking__c b : newList) {
            Booking__c old = oldMap.get(b.Id);
            if (old == null) continue;
            if (b.Status__c == old.Status__c) continue;

            // A booking that has already been Cancelled or Swapped is terminal — its status
            // cannot be changed again (prevents "un-cancelling" / reactivating a swapped booking).
            if (old.Status__c == 'Cancelled' || old.Status__c == 'Swapped') {
                b.addError('This booking is ' + old.Status__c + ' and its status can no longer be changed.');
                continue;
            }

            // BUG-0514: Cancellation must be approval-driven. A booking may only enter the
            // Cancellation stage after a cancellation approval has been submitted, and may only
            // reach Cancelled once that approval is Approved (blocks e.g. Booked -> Cancelled/
            // Cancellation directly).
            if (b.Status__c == 'Cancellation' || b.Status__c == 'Cancelled') {
                if (!isSubmittedOrApproved(b.Cancellation_Approval_Before_Agreement__c)) {
                    b.addError('Cannot move this booking to ' + b.Status__c
                        + ': a Cancellation approval must be submitted first.');
                    continue;
                }
                if (b.Status__c == 'Cancelled'
                    && !isApproved(b.Cancellation_Approval_Before_Agreement__c)) {
                    b.addError('Cannot cancel this booking: a Cancellation approval must be Approved first.');
                    continue;
                }
            }

            // BUG-0515: Swapping must be approval-driven too. A booking may only enter the
            // Swapping stage after a swapping approval has been submitted, and may only reach
            // Swapped once that approval is Approved and a target unit is chosen (blocks e.g.
            // Booked -> Swapping/Swapped directly).
            if (b.Status__c == 'Swapping' || b.Status__c == 'Swapped') {
                if (!isSubmittedOrApproved(b.Swapping_Approval_Before_Agreement__c)) {
                    b.addError('Cannot move this booking to ' + b.Status__c
                        + ': a Swapping approval must be submitted first.');
                    continue;
                }
                if (b.Status__c == 'Swapped') {
                    if (!isApproved(b.Swapping_Approval_Before_Agreement__c)) {
                        b.addError('Cannot swap this booking: a Swapping approval must be Approved first.');
                        continue;
                    }
                    if (b.Swap_To_Plot__c == null) {
                        b.addError('Cannot swap this booking: the Swap To Unit must be selected first.');
                        continue;
                    }
                }
            }

            Integer newIdx = STAGE_ORDER.containsKey(b.Status__c) ? STAGE_ORDER.get(b.Status__c) : null;
            Integer oldIdx = STAGE_ORDER.containsKey(old.Status__c) ? STAGE_ORDER.get(old.Status__c) : null;

            // Only gate forward moves within the linear lifecycle.
            if (newIdx == null) continue;
            if (oldIdx != null && newIdx <= oldIdx) continue;

            String error = prerequisiteError(b);
            if (String.isNotBlank(error)) {
                b.addError(error);
                continue; // field-level prerequisite already failed; no need for financial query
            }

            if (b.Status__c == 'Registration' || b.Status__c == 'Handover') {
                needFinancialCheck.put(b.Id, b);
            }
        }

        if (!needFinancialCheck.isEmpty()) {
            applyFinancialGates(needFinancialCheck);
        }
    }

    /** True when an approval-status picklist value means the approval has been granted. */
    private static Boolean isApproved(String value) {
        return value != null && 'Approved'.equalsIgnoreCase(value);
    }

    /** True when an approval has at least been submitted (still pending) or granted. */
    private static Boolean isSubmittedOrApproved(String value) {
        return value != null
            && ('Approved'.equalsIgnoreCase(value) || 'Pending Approval'.equalsIgnoreCase(value));
    }

    private static String prerequisiteError(Booking__c b) {
        if (b.Status__c == 'Booked') {
            // New -> Booked: signed Booking Form uploaded, Booking Verification approval Approved,
            // and the Primary Applicant's KYC captured.
            if (b.Signed_Booking_Form_Uploaded__c != true) {
                return 'Cannot move to Booked: the signed Booking Form must be uploaded and '
                    + '"Signed Booking Form Uploaded" must be checked.';
            }
            if (!isApproved(b.Booking_Verification_Approval_Status__c)) {
                return 'Cannot move to Booked: the Booking Verification approval must be Approved.';
            }
            List<String> kyc = new List<String>();
            if (String.isBlank(b.Aadhaar__c)) kyc.add('Aadhaar Number');
            if (String.isBlank(b.PAN_Number__c)) kyc.add('PAN Number');
            if (String.isBlank(b.Mobile__c)) kyc.add('Mobile Number');
            if (!kyc.isEmpty()) {
                return 'Cannot move to Booked: the Primary Applicant\'s ' + String.join(kyc, ', ')
                    + ' ' + (kyc.size() == 1 ? 'is' : 'are') + ' required.';
            }
        } else if (b.Status__c == 'Agreement') {
            // Booked -> Agreement: the Booking Welcome mail must have been sent.
            if (b.Welcome_Email_Sent__c != true
                && b.Welcome_Mail_Sent_DateTime__c == null) {
                return 'Cannot move to Agreement: the Booking Welcome mail must be sent first '
                    + '(send it from Send Email).';
            }
        } else if (b.Status__c == 'Demands & Collections' || b.Status__c == 'Registration') {
            // Agreement -> Demands & Collections / Registration: Agreement Date + Sale Agreement
            // Status must be captured/Completed.
            List<String> missing = new List<String>();
            if (!COMPLETED.equalsIgnoreCase(b.Sale_Agreement_Status__c)) missing.add('Sale Agreement Status = Completed');
            if (b.Agreement_Date__c == null) missing.add('Agreement Date');
            if (!missing.isEmpty()) {
                return 'Cannot move to ' + b.Status__c + ': ' + String.join(missing, ', ') + ' required.';
            }
        } else if (b.Status__c == 'Handover') {
            // Registration -> Handover: registration details must be filled.
            List<String> missing = new List<String>();
            if (!COMPLETED.equalsIgnoreCase(b.Sale_Deed_Status__c)) missing.add('Sale Deed Status = Completed');
            if (b.Sale_Deed_Date__c == null) missing.add('Sale Deed Date');
            if (b.Registration_Date__c == null) missing.add('Registration Date');
            if (String.isBlank(b.Registration_Number__c)) missing.add('Registration Number');
            if (!missing.isEmpty()) {
                return 'Cannot move to Handover until registration is complete: ' + String.join(missing, ', ') + '.';
            }
        }
        return null;
    }

    // ==================== FINANCIAL (PAYMENT) GATES ====================

    /**
     * @description Adds payment-completion errors for bookings moving into Registration
     *              (BRD §8.50) or Handover (BRD §58–59, §84), based on outstanding payment
     *              schedule balances, receipts still awaiting approval, and unpaid additional
     *              charges. Runs three bulk queries regardless of batch size.
     */
    private static void applyFinancialGates(Map<Id, Booking__c> bookingsById) {
        Set<Id> bookingIds = bookingsById.keySet();

        // 1. Outstanding payment-schedule balance per booking.
        Map<Id, Decimal> pendingByBooking = new Map<Id, Decimal>();
        for (Payment_Schedule__c ps : [
            SELECT Booking__c, Pending_Amount__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
        ]) {
            Decimal pend = ps.Pending_Amount__c == null ? 0 : ps.Pending_Amount__c;
            Decimal running = pendingByBooking.containsKey(ps.Booking__c) ? pendingByBooking.get(ps.Booking__c) : 0;
            pendingByBooking.put(ps.Booking__c, running + pend);
        }

        // 2. Receipts still awaiting approval per booking.
        Set<Id> bookingsWithPendingReceipt = new Set<Id>();
        for (Receipt__c r : [
            SELECT Booking__c
            FROM Receipt__c
            WHERE Booking__c IN :bookingIds
            AND Approval_Status__c IN :RECEIPT_PENDING_STATUSES
        ]) {
            bookingsWithPendingReceipt.add(r.Booking__c);
        }

        // 3. Additional charges not yet cleared per booking (only relevant for Handover).
        Set<Id> bookingsWithOpenCharges = new Set<Id>();
        for (Additional_Charge__c ac : [
            SELECT Booking__c, Status__c
            FROM Additional_Charge__c
            WHERE Booking__c IN :bookingIds
            AND Status__c NOT IN :CHARGE_CLEARED_STATUSES
        ]) {
            bookingsWithOpenCharges.add(ac.Booking__c);
        }

        for (Id bookingId : bookingIds) {
            Booking__c b = bookingsById.get(bookingId);
            Decimal pending = pendingByBooking.containsKey(bookingId) ? pendingByBooking.get(bookingId) : 0;
            Boolean fullyCollected = pending <= 0;
            Boolean hasPendingReceipt = bookingsWithPendingReceipt.contains(bookingId);
            Boolean hasOpenCharges = bookingsWithOpenCharges.contains(bookingId);
            String funding = b.Funding_Type__c;

            if (b.Status__c == 'Registration') {
                String err = registrationError(funding, fullyCollected, hasPendingReceipt);
                if (String.isNotBlank(err)) b.addError(err);
            } else if (b.Status__c == 'Handover') {
                List<String> problems = new List<String>();
                if (!fullyCollected) problems.add('all payments must be received');
                if (hasPendingReceipt) problems.add('no receipt may be awaiting approval');
                if (hasOpenCharges) problems.add('all additional charges must be fully paid');
                if (!problems.isEmpty()) {
                    b.addError('Cannot move to Handover: ' + String.join(problems, '; ') + '.');
                }
            }
        }
    }

    private static String registrationError(String funding, Boolean fullyCollected, Boolean hasPendingReceipt) {
        // A receipt awaiting approval blocks Registration for every funding type.
        if (hasPendingReceipt) {
            return 'Cannot move to Registration: a receipt is still awaiting approval. '
                + 'All receipts must be approved first.';
        }
        // Loan cases disburse the bank portion at registration, so full collection is not
        // forced here (BRD §8.50 only requires the loan note on the Sale Deed). Self,
        // Prorata and Partial must be fully collected before moving to Registration.
        Boolean isLoan = funding != null && LOAN_FUNDING.contains(funding);
        if (!isLoan && !fullyCollected) {
            return 'Cannot move to Registration: all payments must be received and the '
                + 'corresponding receipts approved before registration.';
        }
        return null;
    }
}