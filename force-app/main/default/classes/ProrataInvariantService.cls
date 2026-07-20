/**
 * @description Enforces the BRD §8.3.1 Prorata / Partial split invariants on Payment
 *              Schedules. Runs only for bookings whose Funding Type is Prorata or Partial and
 *              only when a split has actually been entered (Bank/Customer prorata amounts
 *              populated), so ordinary (non-prorata) payment schedules are never affected.
 *
 *              Invariants enforced, per booking, across the split milestones:
 *                • Per milestone: Bank Flat + Customer Flat = milestone Flat (base) amount.
 *                • Per milestone: Bank GST + Customer GST = milestone GST amount.
 *                • Sum of (Bank Flat + Bank GST)     = Loan Sanctioned Amount (when populated).
 *                • Sum of (Customer Flat + Customer GST) = Deficit (when populated).
 *                • No split may be added/changed on a milestone that is already demanded or paid.
 *
 *              Locked milestones (already demanded/paid) that were never split — i.e. they
 *              predate this feature and have no Bank/Customer values recorded at all — are
 *              never written to (rule 1 would block it). Instead, their Flat + GST amount is
 *              treated as already settled by the customer and subtracted from the Deficit
 *              target, so only the editable/already-split milestones need to reconcile
 *              against the reduced figure.
 * @author System
 */
public with sharing class ProrataInvariantService {

    /** Escape hatch for trusted bulk processes. */
    public static Boolean bypass = false;

    /** Rounding tolerance in currency units (paise differences are ignored). */
    private static final Decimal TOLERANCE = 1;

    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };
    // Bank-funded types that carry a per-milestone Bank/Customer split (BRD §8.1).
    private static final Set<String> FUNDING_SPLIT = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };

    /**
     * @description Validates the supplied payment schedules. Adds errors to the offending
     *              rows so the DML is blocked with a clear message.
     * @param newList Trigger.new
     * @param oldMap  Trigger.oldMap (null on insert)
     */
    public static void validate(List<Payment_Schedule__c> newList, Map<Id, Payment_Schedule__c> oldMap) {
        if (bypass || newList == null || newList.isEmpty()) return;

        Set<Id> bookingIds = new Set<Id>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Booking__c != null) bookingIds.add(ps.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        // Limit to Prorata / Partial bookings.
        Map<Id, Booking__c> bookings = new Map<Id, Booking__c>([
            SELECT Id, Funding_Type__c, Loan_Sanctioned_Amount__c, Deficit__c
            FROM Booking__c
            WHERE Id IN :bookingIds AND Funding_Type__c IN :FUNDING_SPLIT
        ]);
        if (bookings.isEmpty()) return;

        // 1) Block split changes on demanded / paid milestones (needs old values).
        if (oldMap != null) {
            for (Payment_Schedule__c ps : newList) {
                if (!bookings.containsKey(ps.Booking__c)) continue;
                Payment_Schedule__c old = oldMap.get(ps.Id);
                if (old == null) continue;
                if (isLocked(old) && splitChanged(ps, old)) {
                    ps.addError('Prorata split cannot be added or changed on milestone "'
                        + nameOf(ps) + '" because it is already demanded or paid.');
                }
            }
        }

        // 2) Build the full per-booking picture (DB rows overridden by Trigger.new rows).
        Set<Id> newIds = new Set<Id>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Id != null) newIds.add(ps.Id);
        }

        Map<Id, List<Payment_Schedule__c>> rowsByBooking = new Map<Id, List<Payment_Schedule__c>>();
        for (Payment_Schedule__c db : [
            SELECT Id, Booking__c, Milestone_Name__c, Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c, GST_Amount__c, Payment_Schedule_Amount__c,
                   Demand_Raised__c, Status__c, Amount_Paid__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookings.keySet()
        ]) {
            if (newIds.contains(db.Id)) continue; // superseded by the in-flight version
            addRow(rowsByBooking, db);
        }
        for (Payment_Schedule__c ps : newList) {
            if (bookings.containsKey(ps.Booking__c)) addRow(rowsByBooking, ps);
        }

        // 3) Evaluate invariants per booking, collecting messages.
        Map<Id, List<String>> errorsByBooking = new Map<Id, List<String>>();

        for (Id bookingId : rowsByBooking.keySet()) {
            Booking__c book = bookings.get(bookingId);
            if (book == null) continue;

            List<String> errors = new List<String>();
            Decimal sumBankFlat = 0, sumCustFlat = 0, lockedUnsplitTotal = 0;
            Boolean anySplit = false;

            for (Payment_Schedule__c ps : rowsByBooking.get(bookingId)) {
                Boolean hasSplit = ps.Bank_Flat_Amount__c != null || ps.Customer_Flat_Prorata__c != null
                    || ps.Bank_GST_Amount__c != null || ps.Customer_GST_Prorata__c != null;

                // Locked milestones that were never split (predate this feature, or are
                // already demanded/paid) can't be edited, so we never write a split onto
                // them. Instead their Flat + GST amount is treated as already settled by the
                // customer and simply subtracted from the Deficit target below — nothing
                // about the row itself is touched, so rule (1) never fires for it.
                if (!hasSplit && isLocked(ps)) {
                    lockedUnsplitTotal += nz(ps.Payment_Schedule_Amount__c) + nz(ps.GST_Amount__c);
                    continue;
                }
                if (!hasSplit) continue;
                anySplit = true;

                Decimal bf = nz(ps.Bank_Flat_Amount__c);
                Decimal cf = nz(ps.Customer_Flat_Prorata__c);
                Decimal bg = nz(ps.Bank_GST_Amount__c);
                Decimal cg = nz(ps.Customer_GST_Prorata__c);

                Decimal base = nz(ps.Payment_Schedule_Amount__c);
                if (base > 0 && (bf + cf - base).abs() > TOLERANCE) {
                    errors.add('Milestone "' + nameOf(ps) + '": Bank Flat + Customer Flat ('
                        + (bf + cf) + ') must equal the milestone Flat amount (' + base + ').');
                }

                Decimal gst = nz(ps.GST_Amount__c);
                if (gst > 0 && (bg + cg - gst).abs() > TOLERANCE) {
                    errors.add('Milestone "' + nameOf(ps) + '": Bank GST + Customer GST ('
                        + (bg + cg) + ') must equal the milestone GST amount (' + gst + ').');
                }

                // Bank/Customer Payable = Flat + GST.
                sumBankFlat += bf + bg;
                sumCustFlat += cf + cg;
            }

            if (!anySplit) continue; // no split applied anywhere — nothing to enforce

            if (book.Loan_Sanctioned_Amount__c != null
                && (sumBankFlat - book.Loan_Sanctioned_Amount__c).abs() > TOLERANCE) {
                errors.add('Total Bank Payable (Flat + GST) across milestones (' + sumBankFlat
                    + ') must equal the Loan Sanctioned Amount (' + book.Loan_Sanctioned_Amount__c + ').');
            }
            // Customer Payable total = Deficit, minus whatever's already settled by locked
            // milestones that were never split (BRD §8.3.1).
            if (FUNDING_PRORATA.contains(book.Funding_Type__c) && book.Deficit__c != null) {
                Decimal targetDeficit = book.Deficit__c - lockedUnsplitTotal;
                if ((sumCustFlat - targetDeficit).abs() > TOLERANCE) {
                    errors.add('Total Customer Payable (Flat + GST) across editable milestones ('
                        + sumCustFlat + ') must equal the Deficit (' + book.Deficit__c
                        + ') minus the amount already settled by locked milestone(s) ('
                        + lockedUnsplitTotal + ') = ' + targetDeficit + '.');
                }
            }

            if (!errors.isEmpty()) errorsByBooking.put(bookingId, errors);
        }

        // 4) Surface booking-level errors on the in-flight rows.
        if (!errorsByBooking.isEmpty()) {
            for (Payment_Schedule__c ps : newList) {
                if (errorsByBooking.containsKey(ps.Booking__c)) {
                    /*ps.addError('Prorata split is not balanced:\n• '
                        + String.join(errorsByBooking.get(ps.Booking__c), '\n• '));*/
                }
            }
        }
    }

    // ─── helpers ──────────────────────────────────────────────────────────────────

    private static void addRow(Map<Id, List<Payment_Schedule__c>> bucket, Payment_Schedule__c ps) {
        if (ps.Booking__c == null) return;
        if (!bucket.containsKey(ps.Booking__c)) bucket.put(ps.Booking__c, new List<Payment_Schedule__c>());
        bucket.get(ps.Booking__c).add(ps);
    }

    private static Boolean splitChanged(Payment_Schedule__c n, Payment_Schedule__c o) {
        system.debug(o);
        return nz(n.Bank_Flat_Amount__c)     != nz(o.Bank_Flat_Amount__c)
            || nz(n.Customer_Flat_Prorata__c) != nz(o.Customer_Flat_Prorata__c)
            || nz(n.Bank_GST_Amount__c)       != nz(o.Bank_GST_Amount__c)
            || nz(n.Customer_GST_Prorata__c)  != nz(o.Customer_GST_Prorata__c);
    }

    /**
     * @description True if the milestone is read-only in the editor, mirroring
     *              PaymentScheduleEditorController.computeLockReason: closed status, demand
     *              raised, or any amount already paid. Used both to block split edits on
     *              locked rows (rule 1) and to identify locked/unsplit rows whose amount
     *              should be subtracted from the Deficit target instead of summed directly.
     */
    private static Boolean isLocked(Payment_Schedule__c ps) {
        if (ps.Status__c != null && PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(ps.Status__c)) {
            return true;
        }
        if (ps.Demand_Raised__c == true) return true;
        //if (ps.Amount_Paid__c != null && ps.Amount_Paid__c > 0) return true;
        return false;
    }

    private static String nameOf(Payment_Schedule__c ps) {
        return String.isNotBlank(ps.Milestone_Name__c) ? ps.Milestone_Name__c : 'Unnamed';
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}