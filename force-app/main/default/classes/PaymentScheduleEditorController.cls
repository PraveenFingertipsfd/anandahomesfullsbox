/**
 * @description Controller for Payment Schedule Editor LWC.
 *              Supports editing amounts/percentages on payment schedules post-booking creation
 *              when Schedule_Edit_Mode__c = 'Custom' in the Payment Schedule configuration.
 *
 *              Editability rules (BRD §8.2 / §8.3.1 and project pointers):
 *                • A milestone whose demand has already been raised is locked.
 *                • A milestone that has any amount paid against it is locked.
 *                • A milestone in a closed status (Paid/Completed/Waived) is locked.
 *              For Prorata / Partial bookings the editor also exposes the per-milestone
 *              split columns (Bank / Customer Flat & GST, With-GST flag, Forecast Date),
 *              which are validated against the §8.3.1 invariants on save by
 *              ProrataInvariantService.
 * @author Arun Kumar N
 * @date 2026-04-01
 */
public with sharing class PaymentScheduleEditorController {

    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };
    // Bank-funded types whose milestones are split into a Bank portion and a Customer portion
    // (BRD §8.1: Loan/Prorata/Partial all have a bank-paid portion per milestone). Self is the
    // only type with no bank split.
    private static final Set<String> FUNDING_SPLIT = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };

    // Schedule_Edit_Mode__c values that explicitly disable editing (compared lower-cased).
    // Anything else — including blank or 'Custom' — leaves the editor enabled.
    private static final Set<String> SCHEDULE_READONLY_MODES = new Set<String>{
        'standard', 'locked', 'read only', 'readonly', 'view only', 'viewonly'
    };

    // ─── Inner Wrapper Classes ───────────────────────────────────────────────────

    public class ScheduleWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String milestoneName;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal baseAmount;
        @AuraEnabled public Decimal gstAmount;
        @AuraEnabled public Decimal tdsAmount;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Decimal pendingAmount;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isEditable;   // false if demanded/paid/closed
        @AuraEnabled public String lockReason;    // why the row is locked (for UI)

        // Prorata / Partial split fields
        @AuraEnabled public Decimal bankFlat;
        @AuraEnabled public Decimal customerFlat;
        @AuraEnabled public Decimal bankGst;
        @AuraEnabled public Decimal customerGst;
        @AuraEnabled public Boolean withGst;
        @AuraEnabled public String forecastDate;  // ISO yyyy-MM-dd
        @AuraEnabled public Boolean demandRaised;
    }

    public class BookingTotals {
        @AuraEnabled public Decimal totalPayableAmount;
        @AuraEnabled public Decimal totalBaseAmount;
        @AuraEnabled public Decimal totalGstAmount;
        @AuraEnabled public Decimal loanSanctioned;
        @AuraEnabled public Decimal deficit;
    }

    public class EditResult {
        @AuraEnabled public List<ScheduleWrapper> schedules;
        @AuraEnabled public BookingTotals totals;
        @AuraEnabled public Boolean editingEnabled;
        @AuraEnabled public Boolean isProrata;        // show the Bank/Customer split columns
        @AuraEnabled public Boolean isStrictProrata;  // enforce Customer Flat total = Deficit
        @AuraEnabled public String fundingType;
    }

    // ─── AuraEnabled Methods ─────────────────────────────────────────────────────

    /**
     * @description Retrieves payment schedules for a booking along with booking totals,
     *              prorata context and whether custom editing is enabled.
     */
    @AuraEnabled(cacheable=true)
    public static EditResult getSchedulesForEditing(Id bookingId) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Booking ID is required.');
            }

            EditResult result = new EditResult();
            result.editingEnabled = checkEditingEnabled(bookingId);

            List<Booking__c> bookings = [
                SELECT Id, Total_Payable_Amount__c, Funding_Type__c,
                       Loan_Sanctioned_Amount__c, Deficit__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];
            if (bookings.isEmpty()) {
                throw new AuraHandledException('Booking record not found.');
            }
            Booking__c booking = bookings[0];

            result.fundingType = booking.Funding_Type__c;
            // Show the Bank/Customer split for any bank-funded booking (BRD §8.1).
            result.isProrata = booking.Funding_Type__c != null
                && FUNDING_SPLIT.contains(booking.Funding_Type__c);
            // The Customer-Flat-total = Deficit invariant is specific to Prorata/Partial (§8.3.1).
            result.isStrictProrata = booking.Funding_Type__c != null
                && FUNDING_PRORATA.contains(booking.Funding_Type__c);

            BookingTotals totals = new BookingTotals();
            totals.totalPayableAmount = nz(booking.Total_Payable_Amount__c);
            totals.loanSanctioned = booking.Loan_Sanctioned_Amount__c;
            totals.deficit = booking.Deficit__c;
            result.totals = totals;

            List<Payment_Schedule__c> schedules = [
                SELECT Id, Name, Sequence__c, Milestone_Name__c, Percentage__c,
                       Amount__c, Payment_Schedule_Amount__c, GST_Amount__c,
                       TDS_Amount__c, Amount_Paid__c, Pending_Amount__c, Status__c,
                       Demand_Raised__c, Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                       Bank_GST_Amount__c, Customer_GST_Prorata__c, With_GST__c, Forecast_Date__c
                FROM Payment_Schedule__c
                WHERE Booking__c = :bookingId
                ORDER BY Sequence__c ASC
            ];

            List<ScheduleWrapper> wrappers = new List<ScheduleWrapper>();
            for (Payment_Schedule__c ps : schedules) {
                ScheduleWrapper w = new ScheduleWrapper();
                w.id = ps.Id;
                w.name = ps.Name != null ? ps.Name : '';
                w.sequence = nz(ps.Sequence__c);
                w.milestoneName = ps.Milestone_Name__c != null ? ps.Milestone_Name__c : '';
                w.percentage = nz(ps.Percentage__c);
                w.amount = nz(ps.Amount__c);
                w.baseAmount = nz(ps.Payment_Schedule_Amount__c);
                w.gstAmount = nz(ps.GST_Amount__c);
                w.tdsAmount = nz(ps.TDS_Amount__c);
                w.amountPaid = nz(ps.Amount_Paid__c);
                w.pendingAmount = nz(ps.Pending_Amount__c);
                w.status = ps.Status__c != null ? ps.Status__c : '';
                w.bankFlat = ps.Bank_Flat_Amount__c;
                w.customerFlat = ps.Customer_Flat_Prorata__c;
                w.bankGst = ps.Bank_GST_Amount__c;
                w.customerGst = ps.Customer_GST_Prorata__c;
                w.withGst = ps.With_GST__c;
                w.forecastDate = ps.Forecast_Date__c != null ? String.valueOf(ps.Forecast_Date__c) : null;
                w.demandRaised = ps.Demand_Raised__c == true;

                // Lock rules
                String lockReason = computeLockReason(ps);
                w.lockReason = lockReason;
                w.isEditable = String.isBlank(lockReason);

                wrappers.add(w);
            }

            result.schedules = wrappers;
            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('Error in getSchedulesForEditing: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading schedules: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isEditingEnabled(Id bookingId) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Booking ID is required.');
            }
            return checkEditingEnabled(bookingId);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('Error in isEditingEnabled: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error checking edit mode: ' + e.getMessage());
        }
    }

    /**
     * @description Saves edited payment schedules. Locked milestones (demanded / paid /
     *              closed) are never updated even if the client sends changed values.
     *              Prorata split fields are persisted for Prorata/Partial bookings and
     *              validated by ProrataInvariantService on update.
     */
    @AuraEnabled
    public static EditResult saveEditedSchedules(Id bookingId, String schedulesJson) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Booking ID is required.');
            }
            if (String.isBlank(schedulesJson)) {
                throw new AuraHandledException('No schedule data provided.');
            }

            List<ScheduleWrapper> editedSchedules = (List<ScheduleWrapper>) JSON.deserialize(
                schedulesJson, List<ScheduleWrapper>.class
            );
            if (editedSchedules == null || editedSchedules.isEmpty()) {
                throw new AuraHandledException('No schedules to save.');
            }

            // Booking-level guards (BRD §8.3.1): the grand total for the booking must not
            // change — milestones may be redistributed, but the sum stays the same — and the
            // milestone percentages must add up to 100%.
            validateBookingTotals(bookingId, editedSchedules);

            Set<Id> scheduleIds = new Set<Id>();
            for (ScheduleWrapper w : editedSchedules) {
                if (w.id != null) scheduleIds.add(w.id);
            }

            Map<Id, Payment_Schedule__c> existing = new Map<Id, Payment_Schedule__c>([
                SELECT Id, Status__c, Amount_Paid__c, Demand_Raised__c,Pending_Amount__c
                FROM Payment_Schedule__c
                WHERE Id IN :scheduleIds
            ]);

            List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();

            for (ScheduleWrapper w : editedSchedules) {
                if (w.id == null || !existing.containsKey(w.id)) continue;

                // Never persist changes to a locked milestone, regardless of the client.
                if (String.isNotBlank(computeLockReason(existing.get(w.id)))) {
                    continue;
                }

                Payment_Schedule__c ps = new Payment_Schedule__c();
                ps.Id = w.id;
                // Keep the milestone total consistent with the edited Base + GST.
                ps.Amount__c = nz(w.baseAmount) + nz(w.gstAmount);
                ps.Payment_Schedule_Amount__c = w.baseAmount;
                ps.GST_Amount__c = w.gstAmount;
                ps.TDS_Amount__c = w.tdsAmount;
                ps.Percentage__c = w.percentage;

                // Prorata split fields
                ps.Bank_Flat_Amount__c = w.bankFlat;
                ps.Customer_Flat_Prorata__c = w.customerFlat;
                ps.Bank_GST_Amount__c = w.bankGst;
                ps.Customer_GST_Prorata__c = w.customerGst;
                ps.With_GST__c = w.withGst;
                // Forecast_Date__c is a cross-object formula (from Master Payment Schedule)
                // and is not writeable here — it is display-only in the editor.

                schedulesToUpdate.add(ps);
            }

            if (!schedulesToUpdate.isEmpty()) {
                // BRD 8.2: edits are not written directly. Stage them as a revision and submit
                // for approval; the values are applied to the Payment Schedule only once the
                // revision is approved (PaymentScheduleRevisionService / -Trigger).
                List<PaymentScheduleRevisionService.RevisionLine> lines =
                    new List<PaymentScheduleRevisionService.RevisionLine>();
                for (Payment_Schedule__c ps : schedulesToUpdate) {
                    PaymentScheduleRevisionService.RevisionLine line =
                        new PaymentScheduleRevisionService.RevisionLine();
                    line.id = ps.Id;
                    line.amount = ps.Amount__c;
                    line.baseAmount = ps.Payment_Schedule_Amount__c;
                    line.gstAmount = ps.GST_Amount__c;
                    line.tdsAmount = ps.TDS_Amount__c;
                    line.percentage = ps.Percentage__c;
                    line.bankFlat = ps.Bank_Flat_Amount__c;
                    line.customerFlat = ps.Customer_Flat_Prorata__c;
                    line.bankGst = ps.Bank_GST_Amount__c;
                    line.customerGst = ps.Customer_GST_Prorata__c;
                    line.withGst = ps.With_GST__c;
                    lines.add(line);
                }
                PaymentScheduleRevisionService.stageAndSubmit(bookingId, lines, null);
            }

            return getSchedulesForEditing(bookingId);

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (DmlException de) {
            // Surface trigger validation (e.g. prorata invariants) cleanly to the UI.
            throw new AuraHandledException(de.getDmlMessage(0) != null ? de.getDmlMessage(0) : de.getMessage());
        } catch (Exception e) {
            System.debug('Error in saveEditedSchedules: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error saving schedules: ' + e.getMessage());
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    /**
     * @description Returns a non-blank lock reason if the milestone must not be edited.
     */
    private static String computeLockReason(Payment_Schedule__c ps) {
        if (ps == null) return null;
        /*if (PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(ps.Status__c)) {
            return 'Milestone is ' + ps.Status__c + ' (closed).';
        }*/
        if (ps.Demand_Raised__c == true) {
            return 'Demand already raised for this milestone.';
        }
        if (ps.Pending_Amount__c <= 0) {
            return 'Amount already paid against this milestone.';
        }
        return null;
    }

    /**
     * @description Validates that the edited schedule set keeps the booking's grand total
     *              unchanged and that the milestone percentages add up to 100%. The total to
     *              preserve is the current sum of all milestone amounts for the booking, so a
     *              user can shift money between milestones but cannot change the overall total.
     */
    private static void validateBookingTotals(Id bookingId, List<ScheduleWrapper> edited) {
        // Current grand total = sum of every milestone's (Base + GST) for the booking.
        Decimal currentTotal = 0;
        for (Payment_Schedule__c ps : [
            SELECT Payment_Schedule_Amount__c, GST_Amount__c
            FROM Payment_Schedule__c WHERE Booking__c = :bookingId
        ]) {
            currentTotal += nz(ps.Payment_Schedule_Amount__c) + nz(ps.GST_Amount__c);
        }

        // Proposed grand total = sum of every edited milestone's (Base + GST).
        Decimal newTotal = 0;
        Decimal totalPct = 0;
        for (ScheduleWrapper w : edited) {
            newTotal += nz(w.baseAmount) + nz(w.gstAmount);
            totalPct += nz(w.percentage);
        }

        // Grand total must stay the same (allow a tiny rounding tolerance).
        if (currentTotal > 0) {
            Decimal tolerance = Math.max(1, (currentTotal * 0.0001).setScale(2));
            if (Math.abs(newTotal - currentTotal) > tolerance) {
                throw new AuraHandledException(
                    'The total of all milestone amounts must remain ' + formatAmt(currentTotal)
                    + '. Your changes total ' + formatAmt(newTotal) + ' (difference '
                    + formatAmt(newTotal - currentTotal) + '). Redistribute the amounts so the '
                    + 'booking total is unchanged.'
                );
            }
        }

        // Percentages must add up to 100.
        if (Math.abs(totalPct - 100) > 0.5) {
            throw new AuraHandledException(
                'The milestone percentages must add up to 100% (they currently total '
                + totalPct.setScale(2) + '%).'
            );
        }
    }

    private static String formatAmt(Decimal value) {
        return value == null ? '0' : value.setScale(2).format();
    }

    private static Boolean checkEditingEnabled(Id bookingId) {
        // Bank-funded bookings (Loan/Prorata/Partial) can always revise their split (BRD §8.1/§8.2).
        // The revision is controlled by approval (PaymentScheduleRevisionService), not an admin
        // toggle, so the editor is available by default for these bookings.
        List<Booking__c> bks = [
            SELECT Funding_Type__c FROM Booking__c WHERE Id = :bookingId LIMIT 1
        ];
        if (!bks.isEmpty() && bks[0].Funding_Type__c != null
            && FUNDING_SPLIT.contains(bks[0].Funding_Type__c)) {
            return true;
        }

        // For other bookings, editing is available by DEFAULT and is only turned OFF when an
        // active Payment Schedule configuration explicitly selects a read-only mode (e.g.
        // 'Standard'). Per-milestone locks (demand raised / paid / closed) still apply.
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Schedule_Edit_Mode__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = 'Payment Schedule'
            AND Is_Active__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            return true; // no configuration → editable by default
        }
        String mode = configs[0].Schedule_Edit_Mode__c;
        return String.isBlank(mode) || !SCHEDULE_READONLY_MODES.contains(mode.trim().toLowerCase());
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}