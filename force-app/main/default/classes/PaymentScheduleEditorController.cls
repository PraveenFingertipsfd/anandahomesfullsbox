/**
 * @description Controller for the Payment Schedule Split Editor LWC.
 *
 *              Scope of editing (confirmed with business, FRD v3 §2.2):
 *                • ONLY the four split fields are editable: Bank Flat, Customer Flat,
 *                  Bank GST, Customer GST.
 *                • Base Amount, Percentage, GST, TDS, Amount are read-only context and are
 *                  never written from this editor.
 *
 *              Split rules (BRD §8.3.1, FRD §2.3):
 *                • Per milestone: Bank Flat + Customer Flat = Payment Schedule Amount (Base).
 *                • Per milestone: Bank GST  + Customer GST  = GST Amount.
 *                • Per booking:   Σ(Bank Flat + Bank GST)   = Loan Sanctioned Amount.
 *                • Per booking:   Σ(Cust Flat + Cust GST)   = Deficit − locked-unsplit total.
 *                • TDS is customer-payable in full and sits OUTSIDE the split, because
 *                  Deficit__c = Grand_Total__c − Loan_Sanctioned_Amount__c − TDS__c.
 *
 *              Locking (FRD §2.4): a milestone is locked if and only if Demand_Raised__c = true.
 *              Status and part-payment do NOT lock a milestone.
 *
 *              Edits are never written directly — PaymentScheduleRevisionService.stageAndSubmit
 *              trial-applies them inside a savepoint (so PaymentScheduleTrigger /
 *              ProrataInvariantService validate them), rolls back, then stages one
 *              Payment_Schedule_Revision__c for approval.
 * @author Arun Kumar N
 * @date 2026-08-05
 */
public with sharing class PaymentScheduleEditorController {

    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };

    // Bank-funded types carrying a per-milestone Bank/Customer split (BRD §8.1).
    private static final Set<String> FUNDING_SPLIT = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };

    private static final Set<String> SCHEDULE_READONLY_MODES = new Set<String>{
        'standard', 'locked', 'read only', 'readonly', 'view only', 'viewonly'
    };

    /** Currency rounding tolerance. Mirrors ProrataInvariantService.TOLERANCE. */
    private static final Decimal TOLERANCE = 1;

    // ─── Wrappers ────────────────────────────────────────────────────────────────

    public class ScheduleWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String milestoneName;
        @AuraEnabled public String status;

        // Read-only context
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal baseAmount;
        @AuraEnabled public Decimal gstAmount;
        @AuraEnabled public Decimal tdsAmount;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Decimal pendingAmount;

        // Editable split
        @AuraEnabled public Decimal bankFlat;
        @AuraEnabled public Decimal customerFlat;
        @AuraEnabled public Decimal bankGst;
        @AuraEnabled public Decimal customerGst;

        @AuraEnabled public Boolean isEditable;
        @AuraEnabled public String lockReason;
        @AuraEnabled public Boolean demandRaised;
        @AuraEnabled public Boolean hasSplit;
    }

    public class BookingTotals {
        @AuraEnabled public Decimal grandTotal;          // Σ Amount across all milestones
        @AuraEnabled public Decimal totalBase;
        @AuraEnabled public Decimal totalGst;
        @AuraEnabled public Decimal totalTds;
        @AuraEnabled public Decimal loanSanctioned;
        @AuraEnabled public Decimal deficit;             // raw Deficit__c
        @AuraEnabled public Decimal lockedUnsplitTotal;  // Base+GST of locked, never-split rows
        @AuraEnabled public Decimal deficitTarget;       // deficit − lockedUnsplitTotal
        @AuraEnabled public Decimal bookingTds;          // Booking__c.TDS__c, for reconciliation
    }

    public class EditResult {
        @AuraEnabled public List<ScheduleWrapper> schedules;
        @AuraEnabled public BookingTotals totals;
        @AuraEnabled public Boolean editingEnabled;
        @AuraEnabled public Boolean isProrata;        // show the split columns at all
        @AuraEnabled public Boolean isStrictProrata;  // enforce Customer total = Deficit target
        @AuraEnabled public String fundingType;
    }

    // ─── Read ────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static EditResult getSchedulesForEditing(Id bookingId) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Select a booking to load its payment schedule.');
            }

            List<Booking__c> bookings = [
                SELECT Id, Funding_Type__c, Loan_Sanctioned_Amount__c, Deficit__c, TDS__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];
            if (bookings.isEmpty()) {
                throw new AuraHandledException('This booking no longer exists.');
            }
            Booking__c booking = bookings[0];

            EditResult result = new EditResult();
            result.fundingType = booking.Funding_Type__c;
            result.isProrata = booking.Funding_Type__c != null
                && FUNDING_SPLIT.contains(booking.Funding_Type__c);
            result.isStrictProrata = booking.Funding_Type__c != null
                && FUNDING_PRORATA.contains(booking.Funding_Type__c);
            result.editingEnabled = checkEditingEnabled(booking);

            List<Payment_Schedule__c> schedules = [
                SELECT Id, Name, Sequence__c, Milestone_Name__c, Percentage__c,
                       Amount__c, Payment_Schedule_Amount__c, GST_Amount__c,
                       TDS_Amount__c, Amount_Paid__c, Pending_Amount__c, Status__c,
                       Demand_Raised__c, Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                       Bank_GST_Amount__c, Customer_GST_Prorata__c
                FROM Payment_Schedule__c
                WHERE Booking__c = :bookingId
                ORDER BY Sequence__c ASC NULLS LAST
            ];

            BookingTotals totals = new BookingTotals();
            totals.grandTotal = 0;
            totals.totalBase = 0;
            totals.totalGst = 0;
            totals.totalTds = 0;
            totals.lockedUnsplitTotal = 0;
            totals.loanSanctioned = booking.Loan_Sanctioned_Amount__c;
            totals.deficit = booking.Deficit__c;
            totals.bookingTds = booking.TDS__c;

            List<ScheduleWrapper> wrappers = new List<ScheduleWrapper>();
            for (Payment_Schedule__c ps : schedules) {
                ScheduleWrapper w = new ScheduleWrapper();
                w.id = ps.Id;
                w.name = ps.Name != null ? ps.Name : '';
                w.sequence = nz(ps.Sequence__c);
                w.milestoneName = ps.Milestone_Name__c != null ? ps.Milestone_Name__c : '';
                w.status = ps.Status__c != null ? ps.Status__c : '';
                w.percentage = nz(ps.Percentage__c);
                w.amount = nz(ps.Amount__c);
                w.baseAmount = nz(ps.Payment_Schedule_Amount__c);
                w.gstAmount = nz(ps.GST_Amount__c);
                w.tdsAmount = nz(ps.TDS_Amount__c);
                w.amountPaid = nz(ps.Amount_Paid__c);
                w.pendingAmount = nz(ps.Pending_Amount__c);
                w.bankFlat = ps.Bank_Flat_Amount__c;
                w.customerFlat = ps.Customer_Flat_Prorata__c;
                w.bankGst = ps.Bank_GST_Amount__c;
                w.customerGst = ps.Customer_GST_Prorata__c;
                w.demandRaised = ps.Demand_Raised__c == true;
                w.hasSplit = hasSplit(ps);

                w.lockReason = computeLockReason(ps);
                w.isEditable = String.isBlank(w.lockReason);

                totals.totalBase += w.baseAmount;
                totals.totalGst += w.gstAmount;
                totals.totalTds += w.tdsAmount;
                totals.grandTotal += w.amount;

                // A locked milestone that was never split is treated as already settled by the
                // customer and reduces the Deficit target, mirroring ProrataInvariantService.
                if (!w.isEditable && !w.hasSplit) {
                    totals.lockedUnsplitTotal += w.baseAmount + w.gstAmount;
                }

                wrappers.add(w);
            }

            totals.deficitTarget = totals.deficit == null
                ? null
                : totals.deficit - totals.lockedUnsplitTotal;

            result.totals = totals;
            result.schedules = wrappers;
            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('getSchedulesForEditing: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('The payment schedule could not be loaded: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isEditingEnabled(Id bookingId) {
        if (bookingId == null) {
            throw new AuraHandledException('Select a booking first.');
        }
        List<Booking__c> bks = [
            SELECT Id, Funding_Type__c FROM Booking__c WHERE Id = :bookingId LIMIT 1
        ];
        return bks.isEmpty() ? false : checkEditingEnabled(bks[0]);
    }

    // ─── Write ───────────────────────────────────────────────────────────────────

    /**
     * @description Stages the edited split for approval. Only the four split fields are sent
     *              on each RevisionLine, so Amount/Base/GST/TDS/Percentage are structurally
     *              incapable of being changed from this editor, whatever the client posts.
     *              stageAndSubmit trial-applies the values (running the prorata invariants)
     *              before staging, so an unbalanced split is rejected here, not at approval.
     */
    @AuraEnabled
    public static Id saveEditedSchedules(Id bookingId, String schedulesJson, String reason) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Select a booking first.');
            }
            if (String.isBlank(schedulesJson)) {
                throw new AuraHandledException('There is nothing to submit.');
            }

            List<ScheduleWrapper> edited = (List<ScheduleWrapper>) JSON.deserialize(
                schedulesJson, List<ScheduleWrapper>.class
            );
            if (edited == null || edited.isEmpty()) {
                throw new AuraHandledException('There is nothing to submit.');
            }

            Set<Id> ids = new Set<Id>();
            for (ScheduleWrapper w : edited) {
                if (w.id != null) ids.add(w.id);
            }
            if (ids.isEmpty()) {
                throw new AuraHandledException('There is nothing to submit.');
            }

            Map<Id, Payment_Schedule__c> existing = new Map<Id, Payment_Schedule__c>([
                SELECT Id, Booking__c, Milestone_Name__c, Demand_Raised__c,
                       Payment_Schedule_Amount__c, GST_Amount__c,
                       Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                       Bank_GST_Amount__c, Customer_GST_Prorata__c
                FROM Payment_Schedule__c
                WHERE Id IN :ids AND Booking__c = :bookingId
            ]);

            List<PaymentScheduleRevisionService.RevisionLine> lines =
                new List<PaymentScheduleRevisionService.RevisionLine>();

            for (ScheduleWrapper w : edited) {
                if (w.id == null || !existing.containsKey(w.id)) continue;

                Payment_Schedule__c current = existing.get(w.id);

                // A locked milestone is never staged, whatever the client sent.
                if (String.isNotBlank(computeLockReason(current))) continue;

                // Skip rows whose split is unchanged, so the approver sees only real edits.
                if (!splitChanged(w, current)) continue;

                PaymentScheduleRevisionService.RevisionLine line =
                    new PaymentScheduleRevisionService.RevisionLine();
                line.id = w.id;
                line.bankFlat = nz(w.bankFlat);
                line.customerFlat = nz(w.customerFlat);
                line.bankGst = nz(w.bankGst);
                line.customerGst = nz(w.customerGst);
                // Deliberately NOT set: amount, baseAmount, gstAmount, tdsAmount,
                // percentage, withGst. buildScheduleUpdates only writes non-null fields,
                // so these stay untouched on the Payment Schedule.
                lines.add(line);
            }

            if (lines.isEmpty()) {
                throw new AuraHandledException(
                    'No editable milestone has changed. Demand-raised milestones cannot be edited.'
                );
            }

            // Fail fast on the two rules whose messages are clearer here than from the trigger.
            preValidate(bookingId, edited, existing);

            return PaymentScheduleRevisionService.stageAndSubmit(bookingId, lines, reason);

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (DmlException de) {
            throw new AuraHandledException(
                de.getDmlMessage(0) != null ? de.getDmlMessage(0) : de.getMessage()
            );
        } catch (Exception e) {
            System.debug('saveEditedSchedules: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('The changes could not be submitted: ' + e.getMessage());
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────────

    /**
     * @description A milestone is locked if and only if its demand has been raised.
     *              Status and part-payment are deliberately NOT lock conditions.
     *              ProrataInvariantService.isLocked must stay identical to this.
     */
    @TestVisible
    private static String computeLockReason(Payment_Schedule__c ps) {
        if (ps == null) return null;
        if (ps.Demand_Raised__c == true) {
            return 'Demand raised';
        }
        return null;
    }

    private static Boolean hasSplit(Payment_Schedule__c ps) {
        return ps.Bank_Flat_Amount__c != null || ps.Customer_Flat_Prorata__c != null
            || ps.Bank_GST_Amount__c != null || ps.Customer_GST_Prorata__c != null;
    }

    private static Boolean splitChanged(ScheduleWrapper w, Payment_Schedule__c ps) {
        return nz(w.bankFlat) != nz(ps.Bank_Flat_Amount__c)
            || nz(w.customerFlat) != nz(ps.Customer_Flat_Prorata__c)
            || nz(w.bankGst) != nz(ps.Bank_GST_Amount__c)
            || nz(w.customerGst) != nz(ps.Customer_GST_Prorata__c);
    }

    /**
     * @description Row-balance and bank-total checks, raised before staging so the message
     *              names the milestone rather than arriving as a generic DML error.
     *              The trial update in stageAndSubmit remains the authority.
     */
    private static void preValidate(
        Id bookingId, List<ScheduleWrapper> edited, Map<Id, Payment_Schedule__c> existing
    ) {
        List<String> problems = new List<String>();

        for (ScheduleWrapper w : edited) {
            if (w.id == null || !existing.containsKey(w.id)) continue;
            if (String.isNotBlank(computeLockReason(existing.get(w.id)))) continue;

            String label = String.isNotBlank(w.milestoneName) ? w.milestoneName : String.valueOf(w.sequence);

            if (nz(w.bankFlat) < 0 || nz(w.customerFlat) < 0
                || nz(w.bankGst) < 0 || nz(w.customerGst) < 0) {
                problems.add(label + ': a split amount is negative.');
                continue;
            }

            Decimal base = nz(w.baseAmount);
            if (base > 0 && (nz(w.bankFlat) + nz(w.customerFlat) - base).abs() > TOLERANCE) {
                problems.add(label + ': Bank Flat + Customer Flat is '
                    + fmt(nz(w.bankFlat) + nz(w.customerFlat)) + ', but the milestone base is '
                    + fmt(base) + '.');
            }

            Decimal gst = nz(w.gstAmount);
            if (gst > 0 && (nz(w.bankGst) + nz(w.customerGst) - gst).abs() > TOLERANCE) {
                problems.add(label + ': Bank GST + Customer GST is '
                    + fmt(nz(w.bankGst) + nz(w.customerGst)) + ', but the milestone GST is '
                    + fmt(gst) + '.');
            }
        }

        if (!problems.isEmpty()) {
            throw new AuraHandledException(String.join(problems, '\n'));
        }
    }

    private static String fmt(Decimal value) {
        return PostSalesConstants.formatCurrency(value);
    }

    private static Boolean checkEditingEnabled(Booking__c booking) {
        // Bank-funded bookings can always revise their split; the control is approval, not a
        // config toggle (BRD §8.1/§8.2).
        if (booking.Funding_Type__c != null && FUNDING_SPLIT.contains(booking.Funding_Type__c)) {
            return true;
        }
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Schedule_Edit_Mode__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = 'Payment Schedule' AND Is_Active__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) return true;
        String mode = configs[0].Schedule_Edit_Mode__c;
        return String.isBlank(mode) || !SCHEDULE_READONLY_MODES.contains(mode.trim().toLowerCase());
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}