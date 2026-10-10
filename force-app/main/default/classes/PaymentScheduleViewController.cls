/**
 * @description Controller for Payment Schedule Viewer LWC
 * @author Arun Kumar N
 * @date 2026-01-29
 * @updated 2026-01-30 - Added last completed milestone tracking
 * @updated 2026-07-20 - Next Demand now uses only the Bank Flat + Bank GST portion of a
 *              completed milestone when a bank split exists (Customer Flat/GST and TDS are
 *              excluded — those are billed separately). When no bank split has been recorded
 *              for the milestone, the full schedule amount (Base + GST + TDS) is used instead.
 */
public with sharing class PaymentScheduleViewController {
    
    /**
     * Wrapper class for Payment Schedule display
     */
    public class PaymentScheduleWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String milestoneName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Decimal percentage { get; set; }
        @AuraEnabled public Decimal pendingAmount { get; set; }
        @AuraEnabled public Decimal interestPending { get; set; }
        @AuraEnabled public Decimal baseAmount { get; set; }
        @AuraEnabled public Decimal gstAmount { get; set; }
        @AuraEnabled public Decimal basePending { get; set; }
        @AuraEnabled public Decimal gstPending { get; set; }
        @AuraEnabled public Decimal basePaid { get; set; }
        @AuraEnabled public Decimal gstPaid { get; set; }
        // The amount this milestone actually contributes to the next demand: Bank Flat + Bank
        // GST when a bank split exists, otherwise the full Base + GST + TDS.
        @AuraEnabled public Decimal demandableAmount { get; set; }
        @AuraEnabled public String formattedDemandable { get; set; }
        // Where this milestone's demand comes from: 'Bank' when a bank split exists on the
        // record, 'Customer' otherwise. isBankDemand is the boolean equivalent for templates.
        @AuraEnabled public String demandSource { get; set; }
        @AuraEnabled public Boolean isBankDemand { get; set; }
        @AuraEnabled public String statusColor { get; set; }
        @AuraEnabled public String statusIcon { get; set; }
        @AuraEnabled public Boolean isPaid { get; set; }
        @AuraEnabled public Boolean isCompleted { get; set; }
        @AuraEnabled public String formattedAmount { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
    }
    
    /**
     * Wrapper class for Next Demand Summary
     */
    public class NextDemandWrapper {
        @AuraEnabled public Decimal totalPendingAmount { get; set; }
        @AuraEnabled public Decimal totalInterestPending { get; set; }
        @AuraEnabled public Decimal grandTotal { get; set; }
        @AuraEnabled public Boolean hasInterest { get; set; }
        @AuraEnabled public Integer completedScheduleCount { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
        @AuraEnabled public String formattedTotal { get; set; }
        @AuraEnabled public String lastCompletedMilestone { get; set; }
        // Split of the demand total by source, so the raising UI can show the user how much of
        // the next demand is Bank-funded vs Customer-payable.
        @AuraEnabled public Decimal totalBankAmount { get; set; }
        @AuraEnabled public Decimal totalCustomerAmount { get; set; }
        @AuraEnabled public String formattedBankAmount { get; set; }
        @AuraEnabled public String formattedCustomerAmount { get; set; }
    }
    
    /**
     * Result wrapper for the complete view
     */
    public class PaymentScheduleViewResult {
        @AuraEnabled public List<PaymentScheduleWrapper> schedules { get; set; }
        @AuraEnabled public NextDemandWrapper nextDemand { get; set; }
        @AuraEnabled public String bookingName { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public String unitName { get; set; }
        @AuraEnabled public Decimal totalPayableAmount { get; set; }
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
    }
    
    /**
     * @description Get all payment schedules for a booking with next demand calculation
     * @param bookingId The ID of the Booking record
     * @return PaymentScheduleViewResult
     */
    @AuraEnabled(cacheable=true)
    public static PaymentScheduleViewResult getPaymentSchedules(Id bookingId) {
        PaymentScheduleViewResult result = new PaymentScheduleViewResult();
        result.schedules = new List<PaymentScheduleWrapper>();
        result.success = false;
        
        try {
            // Validate bookingId
            if (bookingId == null) {
                result.errorMessage = 'Booking ID is required';
                return result;
            }
            
            // Query Booking details with null checks
            List<Booking__c> bookings = [
                SELECT Id, Name,
                       Project__c, Project__r.Name,
                       Plot__c, Plot__r.Name,
                       Total_Payable_Amount__c, Grand_Total__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            if (bookings.isEmpty()) {
                result.errorMessage = 'Booking record not found';
                return result;
            }

            Booking__c booking = bookings[0];
            result.bookingName = booking.Name;
            result.projectName = booking.Project__c != null ? booking.Project__r.Name : 'N/A';
            result.unitName = booking.Plot__c != null ? booking.Plot__r.Name : 'N/A';
            result.totalPayableAmount = booking.Total_Payable_Amount__c != null
                ? booking.Total_Payable_Amount__c
                : (booking.Grand_Total__c != null ? booking.Grand_Total__c : 0);
            
            // Query all Payment Schedules
            List<Payment_Schedule__c> schedules = [
                SELECT Id, Name, Milestone_Name__c, Status__c, Demand_Raised__c,
                       Amount__c, Percentage__c, Pending_Amount__c,
                       Interest_Pending__c,
                       Payment_Schedule_Amount__c, GST_Amount__c, TDS_Amount__c,
                       Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c,
                       Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                       Bank_Flat_Amount__c, Bank_GST_Amount__c
                FROM Payment_Schedule__c
                WHERE Booking__c = :bookingId
                ORDER BY CreatedDate ASC
            ];
            
            // Process schedules and calculate next demand
            List<PaymentScheduleWrapper> wrappers = new List<PaymentScheduleWrapper>();
            Decimal totalPendingForNextDemand = 0;
            Decimal totalInterestForNextDemand = 0;
            Decimal totalBankForNextDemand = 0;
            Decimal totalCustomerForNextDemand = 0;
            Integer completedCount = 0;
            String lastCompletedMilestone = 'No completed milestones';
            
            for (Payment_Schedule__c schedule : schedules) {
                PaymentScheduleWrapper wrapper = new PaymentScheduleWrapper();
                wrapper.id = schedule.Id;
                wrapper.name = schedule.Name != null ? schedule.Name : '';
                wrapper.milestoneName = String.isNotBlank(schedule.Milestone_Name__c)
                    ? schedule.Milestone_Name__c
                    : (schedule.Name != null ? schedule.Name : '');
                wrapper.status = schedule.Status__c != null ? schedule.Status__c : '';
                wrapper.amount = schedule.Amount__c != null ? schedule.Amount__c : 0;
                wrapper.percentage = schedule.Percentage__c != null ? schedule.Percentage__c : 0;
                wrapper.pendingAmount = schedule.Pending_Amount__c != null ? schedule.Pending_Amount__c : 0;
                wrapper.interestPending = schedule.Interest_Pending__c != null ? schedule.Interest_Pending__c : 0;
                wrapper.baseAmount = schedule.Payment_Schedule_Amount__c;
                wrapper.gstAmount = schedule.GST_Amount__c;
                wrapper.basePending = schedule.Payment_Schedule_Amount_Pending__c;
                wrapper.gstPending = schedule.GST_Amount_Pending__c;
                wrapper.basePaid = schedule.Payment_Schedule_Amount_Paid__c;
                wrapper.gstPaid = schedule.GST_Amount_Paid__c;

                Decimal demandable = demandableAmount(schedule);
                wrapper.demandableAmount = demandable;
                wrapper.formattedDemandable = formatCurrency(demandable);
                wrapper.isBankDemand = schedule.Bank_Flat_Amount__c != null;
                wrapper.demandSource = wrapper.isBankDemand ? 'Bank' : 'Customer';
                
                // Determine status color and icon
                wrapper.isPaid = (schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_PAID);
                wrapper.isCompleted = (schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED);
                wrapper.statusColor = PostSalesConstants.getStatusColor(schedule.Status__c);
                wrapper.statusIcon = PostSalesConstants.getStatusIcon(schedule.Status__c);

                if (schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED) {
                    completedCount++;

                    // Track last completed milestone
                    lastCompletedMilestone = String.isNotBlank(schedule.Milestone_Name__c) ?
                                            schedule.Milestone_Name__c : schedule.Name;

                    // Next demand = Bank Flat + Bank GST when a bank split exists on the
                    // milestone, otherwise the full schedule amount (Base + GST + TDS).
                    // Exclude milestones whose demand has already been raised so the "Next
                    // Payment Demand" total never re-demands an existing demand (e.g. the
                    // booking-amount demand on milestone #1). This keeps the single-demand
                    // total in agreement with the Bulk Raise Demand flow.
                    if (schedule.Demand_Raised__c != true) {
                        totalPendingForNextDemand += demandable;
                        if (wrapper.isBankDemand) {
                            totalBankForNextDemand += demandable;
                        } else {
                            totalCustomerForNextDemand += demandable;
                        }
                        totalInterestForNextDemand += (schedule.Interest_Pending__c != null ? schedule.Interest_Pending__c : 0);
                    }
                }
                
                // Format currency values
                wrapper.formattedAmount = formatCurrency(wrapper.amount);
                wrapper.formattedPending = formatCurrency(wrapper.pendingAmount);
                wrapper.formattedInterest = formatCurrency(wrapper.interestPending);
                
                wrappers.add(wrapper);
            }
            
            // Build Next Demand Wrapper
            NextDemandWrapper nextDemand = new NextDemandWrapper();
            nextDemand.totalPendingAmount = totalPendingForNextDemand;
            nextDemand.totalInterestPending = totalInterestForNextDemand;
            nextDemand.grandTotal = totalPendingForNextDemand + totalInterestForNextDemand;
            nextDemand.hasInterest = (totalInterestForNextDemand > 0);
            nextDemand.completedScheduleCount = completedCount;
            nextDemand.formattedPending = formatCurrency(nextDemand.totalPendingAmount);
            nextDemand.formattedInterest = formatCurrency(nextDemand.totalInterestPending);
            nextDemand.formattedTotal = formatCurrency(nextDemand.grandTotal);
            nextDemand.lastCompletedMilestone = lastCompletedMilestone;
            nextDemand.totalBankAmount = totalBankForNextDemand;
            nextDemand.totalCustomerAmount = totalCustomerForNextDemand;
            nextDemand.formattedBankAmount = formatCurrency(totalBankForNextDemand);
            nextDemand.formattedCustomerAmount = formatCurrency(totalCustomerForNextDemand);
            
            // Build result
            result.schedules = wrappers;
            result.nextDemand = nextDemand;
            result.success = true;
            
            return result;
            
        } catch (Exception e) {
            result.errorMessage = 'Error: ' + e.getMessage() + ' (Line: ' + e.getLineNumber() + ')';
            result.success = false;
            System.debug('Error in getPaymentSchedules: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            return result;
        }
    }
    
    /**
     * @description Format currency value
     * @param value Decimal value to format
     * @return Formatted currency string
     */
    private static String formatCurrency(Decimal value) {
        return PostSalesConstants.formatCurrency(value);
    }

    /**
     * @description The amount a milestone contributes to the next demand: when a bank split has
     *              been recorded (Bank_Flat_Amount__c is not null), only Bank Flat + Bank GST is
     *              demandable here — Customer Flat, Customer GST, and TDS are excluded, since
     *              those are billed to the customer separately. When no bank split exists, the
     *              full schedule amount (Base + GST + TDS) is used.
     */
    private static Decimal demandableAmount(Payment_Schedule__c ps) {
        if (ps.Bank_Flat_Amount__c != null) {
            return nz(ps.Bank_Flat_Amount__c) + nz(ps.Bank_GST_Amount__c);
        }
        return nz(ps.Pending_Amount__c);
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }

    /**
     * @description Raise a Demands__c record for the next payment demand on a booking.
     * Aggregates the demandable amount (Bank Flat + Bank GST when a bank split exists,
     * otherwise the full Base + GST + TDS) plus interest across schedules whose Status__c is
     * Completed (i.e. milestone reached but not yet fully paid) and inserts one demand row
     * linked to the earliest such schedule. Email-on-insert is left to the downstream
     * record-triggered flow on Demands__c — this method only creates the record.
     */
    @AuraEnabled
    public static Id raiseDemandForBooking(Id bookingId) {
        if (bookingId == null) {
            throw new AuraHandledException('Booking ID is required');
        }

        List<Payment_Schedule__c> schedules = [
            SELECT Id, Name, Milestone_Name__c, Status__c, Pending_Amount__c,
                   Interest_Pending__c, Due_Date__c, Sequence__c,
                   Payment_Schedule_Amount__c, GST_Amount__c, TDS_Amount__c,
                   Bank_Flat_Amount__c, Bank_GST_Amount__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId
            AND Status__c = :PostSalesConstants.SCHEDULE_STATUS_COMPLETED
            AND (Demand_Raised__c = false OR Demand_Raised__c = null)
            ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate ASC
        ];

        Decimal totalPending = 0;
        Decimal totalInterest = 0;
        Decimal totalFlat = 0;
        Decimal totalGst = 0;
        Decimal totalTds = 0;
        Id firstScheduleId;
        Date firstDueDate;
        Id latestScheduleId;       // milestone with the highest Sequence__c among those included
        Decimal latestSequence;
        List<Payment_Schedule__c> schedulesToMarkDemanded = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c ps : schedules) {
            Decimal p = demandableAmount(ps);
            Decimal i = ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;
            if (p <= 0 && i <= 0) continue;
            totalPending += p;
            totalInterest += i;

            Boolean isBank = ps.Bank_Flat_Amount__c != null;
            // Cumulative Flat/GST/TDS so they sum to totalPending. Bank-sourced milestones
            // contribute only Flat + GST (no TDS — see demandableAmount()); customer-sourced
            // milestones (no bank split) contribute the full Flat + GST + TDS.
            if (isBank) {
                totalFlat += nz(ps.Bank_Flat_Amount__c);
                totalGst += nz(ps.Bank_GST_Amount__c);
            } else {
                totalFlat += nz(ps.Payment_Schedule_Amount__c);
                totalGst += nz(ps.GST_Amount__c);
                totalTds += nz(ps.TDS_Amount__c);
            }

            if (firstScheduleId == null) {
                firstScheduleId = ps.Id;
                firstDueDate = ps.Due_Date__c;
            }
            // Track the latest milestone by sequence (the bigger Sequence__c number) among the
            // schedules actually included in this demand.
            if (ps.Sequence__c != null && (latestSequence == null || ps.Sequence__c > latestSequence)) {
                latestSequence = ps.Sequence__c;
                latestScheduleId = ps.Id;
            }

            // Mark this milestone's demand as raised — flips the general Demand_Raised__c flag
            // (which is what locks it for editing elsewhere) plus the Bank/Customer-specific
            // flag matching where this particular milestone's amount was demanded from.
            Payment_Schedule__c upd = new Payment_Schedule__c(Id = ps.Id);
            upd.Demand_Raised__c = true;
            upd.Demand_Date__c = Date.today();
            if (isBank) {
                upd.Bank_Demand_Raised__c = true;
            } else {
                upd.Customer_Demand_Raised__c = true;
            }
            schedulesToMarkDemanded.add(upd);
        }

        Decimal grandTotal = totalPending + totalInterest;
        if (grandTotal <= 0) {
            throw new AuraHandledException(
                'Nothing to raise: no completed payment schedule has a pending amount or interest.');
        }

        // Previous dues: milestones on this booking already demanded but still unpaid. These are
        // NOT re-raised here (they stay pending on their original demand); they are surfaced on
        // this demand so Net_Demand_Amount__c (= Demand Amount + Previous Dues + Interest) reflects
        // the customer's full outstanding — matching the Bulk Raise Demand behaviour. Runs before
        // the schedules raised now are marked demanded, so those aren't counted here.
        Decimal previousDues = 0;
        for (AggregateResult ar : [
            SELECT SUM(Pending_Amount__c) prev
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId
            AND Demand_Raised__c = true
            AND Pending_Amount__c > 0
        ]) {
            Object prev = ar.get('prev');
            if (prev != null) previousDues = (Decimal) prev;
        }

        Demands__c demand = new Demands__c();
        demand.Booking__c = bookingId;
        // Current demand principal only. Interest goes in Interest_Amount__c and previous dues in
        // Previous_Dues__c; the Net_Demand_Amount__c formula sums all three, so interest must NOT
        // also sit inside Demand_Amount__c or it would be double-counted in the net.
        demand.Demand_Amount__c = totalPending;
        demand.Pending_Amount__c = grandTotal;
        demand.Previous_Dues__c = previousDues;
        demand.Interest_Amount__c = totalInterest;
        // Cumulative components of this demand — Flat + GST + TDS equals totalPending (Interest
        // is tracked separately above), so Flat + GST + TDS + Interest = Demand_Amount__c.
        demand.Flat_Amount__c = totalFlat;
        demand.GST_Amount__c = totalGst;
        demand.TDS_Amount__c = totalTds;
        demand.Demand_Date__c = Date.today();
        demand.Due_Date__c = firstDueDate != null ? firstDueDate : Date.today().addDays(30);
        // 'Individual Demand' is the active picklist value matching a one-off,
        // booking-scoped demand. PostSalesConstants.DEMAND_TYPE_AUTO maps to
        // 'Auto Demand' which is intentionally inactive on the picklist.
        demand.Demand_Type__c = 'Individual Demand';
        demand.Status__c = PostSalesConstants.DEMAND_STATUS_RAISED;
        // Link to the latest milestone (highest Sequence__c) included in this demand, falling
        // back to the earliest-due schedule if none of the included rows had a sequence value.
        demand.Payment_Schedule__c = latestScheduleId != null ? latestScheduleId : firstScheduleId;

        // Insert the demand and mark every included milestone's schedule as demanded together —
        // if either DML fails, roll back both rather than leaving an orphaned demand with
        // schedules that still show as not-yet-demanded.
        Savepoint sp = Database.setSavepoint();
        try {
            insert demand;
            if (!schedulesToMarkDemanded.isEmpty()) {
                update schedulesToMarkDemanded;
            }
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not raise demand: ' + e.getDmlMessage(0));
        }
        return demand.Id;
    }

    /**
     * @description Save edited payment schedule amounts.
     *              Only updates Amount__c, Pending_Amount__c, Payment_Schedule_Amount__c
     *              for schedules where demand has not been raised.
     * @param amountsJson JSON map of scheduleId -> newAmount
     */
    /**
     * @description Save edited payment schedule amounts with validation.
     *              Validates that total of all schedule amounts equals booking's
     *              Total_Payable_Amount__c before saving.
     * @param bookingId The booking these schedules belong to
     * @param amountsJson JSON map of scheduleId -> newAmount
     */
    @AuraEnabled
    public static void saveScheduleAmounts(String bookingId, String amountsJson) {
        try {
            Map<String, Object> amounts = (Map<String, Object>) JSON.deserializeUntyped(amountsJson);
            if (amounts.isEmpty()) return;

            // Get booking total
            Booking__c booking = [
                SELECT Id, Total_Payable_Amount__c, Grand_Total__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            Decimal bookingTotal = booking.Total_Payable_Amount__c != null
                ? booking.Total_Payable_Amount__c
                : (booking.Grand_Total__c != null ? booking.Grand_Total__c : 0);

            // Get ALL schedules for this booking (not just edited ones)
            List<Payment_Schedule__c> allSchedules = [
                SELECT Id, Amount__c, Pending_Amount__c, Amount_Paid__c,
                       Payment_Schedule_Amount__c, GST_Amount__c,
                       Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                       Demand_Raised__c, Status__c
                FROM Payment_Schedule__c
                WHERE Booking__c = :bookingId
            ];

            // Calculate what the new total would be after applying changes
            Decimal newTotal = 0;
            List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();

            for (Payment_Schedule__c ps : allSchedules) {
                Object newAmountObj = amounts.get(ps.Id);

                if (newAmountObj != null) {
                    // This schedule is being edited
                    Boolean anyAmountPaid = ps.Amount_Paid__c != null && ps.Amount_Paid__c > 0;
                    if (ps.Demand_Raised__c == true ||
                        anyAmountPaid ||
                        ps.Status__c == PostSalesConstants.SCHEDULE_STATUS_PAID ||
                        ps.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED) {
                        throw new AuraHandledException(
                            'Cannot edit schedule ' + ps.Id + ' — demand already raised, amount already paid, '
                            + 'or schedule is paid/completed.'
                        );
                    }

                    Decimal newAmount = Decimal.valueOf(String.valueOf(newAmountObj));
                    if (newAmount < 0) {
                        throw new AuraHandledException('Amount cannot be negative.');
                    }

                    newTotal += newAmount;

                    Decimal paid = ps.Amount_Paid__c != null ? ps.Amount_Paid__c : 0;
                    ps.Amount__c = newAmount;
                    ps.Pending_Amount__c = Math.max(0, newAmount - paid);
                    ps.Payment_Schedule_Amount__c = newAmount;
                    ps.Payment_Schedule_Amount_Pending__c = Math.max(0, newAmount - paid);
                    toUpdate.add(ps);
                } else {
                    // Unchanged schedule — use existing amount
                    newTotal += (ps.Amount__c != null ? ps.Amount__c : 0);
                }
            }

            // Validate total matches booking total
            if (bookingTotal > 0 && newTotal.setScale(2) != bookingTotal.setScale(2)) {
                throw new AuraHandledException(
                    'Total of all schedule amounts (₹' + newTotal.setScale(2).format() +
                    ') must equal the booking total payable amount (₹' + bookingTotal.setScale(2).format() +
                    '). Difference: ₹' + (bookingTotal - newTotal).setScale(2).format()
                );
            }

            if (!toUpdate.isEmpty()) {
                // BRD 8.2: amount edits are staged for approval, not written directly. Build a
                // revision and submit it; values are applied once the revision is approved.
                List<PaymentScheduleRevisionService.RevisionLine> lines =
                    new List<PaymentScheduleRevisionService.RevisionLine>();
                for (Payment_Schedule__c ps : toUpdate) {
                    PaymentScheduleRevisionService.RevisionLine line =
                        new PaymentScheduleRevisionService.RevisionLine();
                    line.id = ps.Id;
                    line.amount = ps.Amount__c;
                    line.baseAmount = ps.Payment_Schedule_Amount__c;
                    lines.add(line);
                }
                PaymentScheduleRevisionService.stageAndSubmit((Id) bookingId, lines, null);
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving amounts: ' + e.getMessage());
        }
    }
}