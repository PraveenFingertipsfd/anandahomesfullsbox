/**
 * @description Enforces the BRD §8.3.1 Prorata / Partial split invariants on Payment Schedules.
 *
 *              Invariants enforced, per booking:
 *                • Per milestone: Bank Flat + Customer Flat = milestone Flat (base) amount.
 *                • Per milestone: Bank GST  + Customer GST  = milestone GST amount.
 *                • Σ (Bank Flat + Bank GST)     = Loan Sanctioned Amount (when populated).
 *                • Σ (Customer Flat + Cust GST) = Deficit (when populated, Prorata/Partial only).
 *                • No split may be added or changed on a milestone whose demand is raised.
 *
 *              TDS sits outside the split entirely: Deficit__c is defined as
 *              Grand_Total__c − Loan_Sanctioned_Amount__c − TDS__c, so the customer's split
 *              obligation excludes TDS and this service must not add it in.
 *
 *              Locked milestones that were never split have their Flat + GST treated as
 *              already settled by the customer and subtracted from the Deficit target, so only
 *              the editable/already-split milestones reconcile against the reduced figure.
 *
 * CHANGE LOG (FRD v3 §3A):
 *   • isLocked() now tests Demand_Raised__c ONLY. It previously also treated the closed
 *     statuses (Paid/Completed/Waived) as locked, which contradicted
 *     PaymentScheduleEditorController and blocked edits the editor had declared open.
 *   • Booking-level errors are surfaced again (the addError call was commented out, making
 *     every balance check inert).
 *   • Per-milestone errors are raised on the offending row rather than pooled at booking level.
 *   • The bank total is enforced whenever Loan Sanctioned is populated, even if every split
 *     has been cleared.
 * @author System
 */
public with sharing class ProrataInvariantService {

    /** Escape hatch for trusted bulk processes. */
    public static Boolean bypass = false;

    /** Rounding tolerance in currency units (paise differences are ignored). */
    private static final Decimal TOLERANCE = 1;

    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };
    private static final Set<String> FUNDING_SPLIT = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };

    public static void validate(List<Payment_Schedule__c> newList, Map<Id, Payment_Schedule__c> oldMap) {
        if (bypass || newList == null || newList.isEmpty()) return;

        Set<Id> bookingIds = new Set<Id>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Booking__c != null) bookingIds.add(ps.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        Map<Id, Booking__c> bookings = new Map<Id, Booking__c>([
            SELECT Id, Funding_Type__c, Loan_Sanctioned_Amount__c, Deficit__c
            FROM Booking__c
            WHERE Id IN :bookingIds AND Funding_Type__c IN :FUNDING_SPLIT
        ]);
        if (bookings.isEmpty()) return;

        // 1) Block split changes on demand-raised milestones.
        if (oldMap != null) {
            for (Payment_Schedule__c ps : newList) {
                if (!bookings.containsKey(ps.Booking__c)) continue;
                Payment_Schedule__c old = oldMap.get(ps.Id);
                if (old == null) continue;
                if (isLocked(old) && splitChanged(ps, old)) {
                    ps.addError('The split on "' + nameOf(ps)
                        + '" cannot be changed because its demand has been raised.');
                }
            }
        }

        // 2) Build the full per-booking picture (DB rows overridden by Trigger.new rows).
        Set<Id> newIds = new Set<Id>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Id != null) newIds.add(ps.Id);
        }

        Map<Id, Payment_Schedule__c> inFlightById = new Map<Id, Payment_Schedule__c>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Id != null) inFlightById.put(ps.Id, ps);
        }

        Map<Id, List<Payment_Schedule__c>> rowsByBooking = new Map<Id, List<Payment_Schedule__c>>();
        for (Payment_Schedule__c db : [
            SELECT Id, Booking__c, Milestone_Name__c, Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c, GST_Amount__c,
                   Payment_Schedule_Amount__c, Demand_Raised__c, Status__c, Amount_Paid__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookings.keySet()
        ]) {
            if (newIds.contains(db.Id)) continue; // superseded by the in-flight version
            addRow(rowsByBooking, db);
        }
        for (Payment_Schedule__c ps : newList) {
            if (bookings.containsKey(ps.Booking__c)) addRow(rowsByBooking, ps);
        }

        // 3) Evaluate invariants per booking.
        Map<Id, List<String>> errorsByBooking = new Map<Id, List<String>>();

        for (Id bookingId : rowsByBooking.keySet()) {
            Booking__c book = bookings.get(bookingId);
            if (book == null) continue;

            List<String> errors = new List<String>();
            Decimal sumBankPayable = 0, sumCustPayable = 0, lockedUnsplitTotal = 0;

            for (Payment_Schedule__c ps : rowsByBooking.get(bookingId)) {
                Boolean hasSplit = ps.Bank_Flat_Amount__c != null || ps.Customer_Flat_Prorata__c != null
                    || ps.Bank_GST_Amount__c != null || ps.Customer_GST_Prorata__c != null;

                // Locked and never split: treated as already settled by the customer and
                // subtracted from the Deficit target. The row itself is never written.
                if (!hasSplit && isLocked(ps)) {
                    lockedUnsplitTotal += nz(ps.Payment_Schedule_Amount__c) + nz(ps.GST_Amount__c);
                    continue;
                }
                if (!hasSplit) continue;

                Decimal bf = nz(ps.Bank_Flat_Amount__c);
                Decimal cf = nz(ps.Customer_Flat_Prorata__c);
                Decimal bg = nz(ps.Bank_GST_Amount__c);
                Decimal cg = nz(ps.Customer_GST_Prorata__c);

                // Per-milestone failures are raised on the offending row when it is in flight,
                // so the client can map the error back to a specific line.
                Decimal base = nz(ps.Payment_Schedule_Amount__c);
                if (base > 0 && (bf + cf - base).abs() > TOLERANCE) {
                    rowError(inFlightById, ps, 'Bank Flat + Customer Flat is '
                        + money(bf + cf) + ', but the milestone base is ' + money(base) + '.', errors);
                }

                Decimal gst = nz(ps.GST_Amount__c);
                if (gst > 0 && (bg + cg - gst).abs() > TOLERANCE) {
                    rowError(inFlightById, ps, 'Bank GST + Customer GST is '
                        + money(bg + cg) + ', but the milestone GST is ' + money(gst) + '.', errors);
                }

                if (bf < 0 || cf < 0 || bg < 0 || cg < 0) {
                    rowError(inFlightById, ps, 'A split amount is negative.', errors);
                }

                sumBankPayable += bf + bg;
                sumCustPayable += cf + cg;
            }

            // Bank total is enforced whenever Loan Sanctioned is populated — including when
            // every split has been cleared, which would otherwise leave the bank unallocated.
            if (book.Loan_Sanctioned_Amount__c != null && book.Loan_Sanctioned_Amount__c != 0
                && (sumBankPayable - book.Loan_Sanctioned_Amount__c).abs() > TOLERANCE) {
                errors.add('Total Bank Payable (Flat + GST) across milestones is '
                    + money(sumBankPayable) + ', but the Loan Sanctioned Amount is '
                    + money(book.Loan_Sanctioned_Amount__c) + '. Difference: '
                    + money(sumBankPayable - book.Loan_Sanctioned_Amount__c) + '.');
            }

            // Customer split total = Deficit, less whatever is already settled by locked,
            // never-split milestones. TDS is excluded by the definition of Deficit__c.
            if (FUNDING_PRORATA.contains(book.Funding_Type__c) && book.Deficit__c != null) {
                Decimal targetDeficit = book.Deficit__c - lockedUnsplitTotal;
                if ((sumCustPayable - targetDeficit).abs() > TOLERANCE) {
                    errors.add('Total Customer Payable (Flat + GST) across editable milestones is '
                        + money(sumCustPayable) + ', but the target is ' + money(targetDeficit)
                        + ' (Deficit ' + money(book.Deficit__c)
                        + ' less ' + money(lockedUnsplitTotal)
                        + ' already settled on demand-raised milestones).');
                }
            }

            if (!errors.isEmpty()) errorsByBooking.put(bookingId, errors);
        }

        // 4) Surface booking-level errors on the in-flight rows.
        if (!errorsByBooking.isEmpty()) {
            for (Payment_Schedule__c ps : newList) {
                if (errorsByBooking.containsKey(ps.Booking__c)) {
                    ps.addError('The split does not balance:\n• '
                        + String.join(errorsByBooking.get(ps.Booking__c), '\n• '));
                }
            }
        }
    }

    // ─── helpers ──────────────────────────────────────────────────────────────────

    /**
     * @description Raises a per-milestone error on the in-flight row where possible, so the
     *              client can attribute it to a line. Falls back to the booking-level list
     *              when the offending row is not part of this DML.
     */
    private static void rowError(
        Map<Id, Payment_Schedule__c> inFlightById, Payment_Schedule__c ps,
        String message, List<String> bookingErrors
    ) {
        Payment_Schedule__c target = ps.Id != null ? inFlightById.get(ps.Id) : null;
        if (target != null) {
            target.addError('"' + nameOf(ps) + '": ' + message);
        } else {
            bookingErrors.add('Milestone "' + nameOf(ps) + '": ' + message);
        }
    }

    private static void addRow(Map<Id, List<Payment_Schedule__c>> bucket, Payment_Schedule__c ps) {
        if (ps.Booking__c == null) return;
        if (!bucket.containsKey(ps.Booking__c)) {
            bucket.put(ps.Booking__c, new List<Payment_Schedule__c>());
        }
        bucket.get(ps.Booking__c).add(ps);
    }

    private static Boolean splitChanged(Payment_Schedule__c n, Payment_Schedule__c o) {
        return nz(n.Bank_Flat_Amount__c)      != nz(o.Bank_Flat_Amount__c)
            || nz(n.Customer_Flat_Prorata__c) != nz(o.Customer_Flat_Prorata__c)
            || nz(n.Bank_GST_Amount__c)       != nz(o.Bank_GST_Amount__c)
            || nz(n.Customer_GST_Prorata__c)  != nz(o.Customer_GST_Prorata__c);
    }

    /**
     * @description A milestone is locked if and only if its demand has been raised.
     *              Must stay identical to PaymentScheduleEditorController.computeLockReason:
     *              if the two diverge, the editor offers rows the trigger then rejects.
     *              Closed status and part-payment are NOT lock conditions.
     */
    private static Boolean isLocked(Payment_Schedule__c ps) {
        return ps.Demand_Raised__c == true;
    }

    private static String nameOf(Payment_Schedule__c ps) {
        return String.isNotBlank(ps.Milestone_Name__c) ? ps.Milestone_Name__c : 'Unnamed';
    }

    private static String money(Decimal v) {
        return PostSalesConstants.formatCurrency(v);
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}