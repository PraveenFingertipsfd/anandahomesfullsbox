/**
 * @description Enforces milestone-by-milestone payment sequencing on Bookings.
 *
 *              BRD pointer 4: "For each payment milestone, only after the entire payment
 *              (approved receipts) is completed should it move to the next milestone. If a
 *              receipt is pending for a milestone and a new receipt is going to the next
 *              milestone, it will be restricted. If it is for the same milestone, it will
 *              be accepted."
 *
 *              The allocation of a Receipt to a milestone happens through
 *              Receipt_Line_Item__c.Payment_Schedule__c. When a new line item is allocated
 *              to a payment-schedule (milestone) of sequence N, every EARLIER milestone
 *              (sequence < N) on the same Booking must already be fully settled by APPROVED
 *              receipts. If any earlier milestone still has a pending balance, or has a
 *              receipt that is still Pending Approval, the allocation to the later milestone
 *              is blocked. Allocations to the same (or an earlier) milestone are always
 *              allowed.
 * @author System
 */
public with sharing class MilestonePaymentGateService {

    /**
     * @description Escape hatch for trusted server-side processes (e.g. data migration,
     *              swap/transfer of receipts) that need to bypass the sequencing gate.
     */
    public static Boolean bypass = false;

    private static final Set<String> PAID_STATUSES = new Set<String>{
        'Paid', 'Completed', 'Waived'
    };

    /**
     * @description Validates a set of new Receipt Line Item allocations against the
     *              milestone sequencing rule. Adds an addError() to any offending line.
     * @param newLines Trigger.new from Receipt_Line_Item__c before insert
     */
    public static void validateAllocations(List<Receipt_Line_Item__c> newLines) {
        if (bypass || newLines == null || newLines.isEmpty()) return;

        // Target schedules being allocated to.
        Set<Id> targetScheduleIds = new Set<Id>();
        for (Receipt_Line_Item__c li : newLines) {
            if (li.Payment_Schedule__c != null) targetScheduleIds.add(li.Payment_Schedule__c);
        }
        if (targetScheduleIds.isEmpty()) return;

        // Resolve booking + sequence for each target schedule.
        Map<Id, Payment_Schedule__c> targetSchedules = new Map<Id, Payment_Schedule__c>([
            SELECT Id, Booking__c, Sequence__c
            FROM Payment_Schedule__c
            WHERE Id IN :targetScheduleIds
        ]);

        Set<Id> bookingIds = new Set<Id>();
        for (Payment_Schedule__c ps : targetSchedules.values()) {
            if (ps.Booking__c != null) bookingIds.add(ps.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        // All schedules for the involved bookings, keyed by booking.
        Map<Id, List<Payment_Schedule__c>> schedulesByBooking = new Map<Id, List<Payment_Schedule__c>>();
        for (Payment_Schedule__c ps : [
            SELECT Id, Booking__c, Sequence__c, Status__c, Pending_Amount__c, Milestone_Name__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
            ORDER BY Sequence__c ASC NULLS LAST
        ]) {
            if (!schedulesByBooking.containsKey(ps.Booking__c)) {
                schedulesByBooking.put(ps.Booking__c, new List<Payment_Schedule__c>());
            }
            schedulesByBooking.get(ps.Booking__c).add(ps);
        }

        // Which schedules currently have a receipt that is still Pending Approval.
        Set<Id> schedulesWithPendingReceipt = findSchedulesWithPendingReceipts(bookingIds);

        // Evaluate each new allocation.
        for (Receipt_Line_Item__c li : newLines) {
            if (li.Payment_Schedule__c == null) continue;

            Payment_Schedule__c target = targetSchedules.get(li.Payment_Schedule__c);
            if (target == null || target.Booking__c == null || target.Sequence__c == null) continue;

            List<Payment_Schedule__c> bookingSchedules = schedulesByBooking.get(target.Booking__c);
            if (bookingSchedules == null) continue;

            Payment_Schedule__c blocker = findBlockingEarlierMilestone(
                bookingSchedules, target.Sequence__c, schedulesWithPendingReceipt
            );

            if (blocker != null) {
                li.addError(buildErrorMessage(blocker, target));
            }
        }
    }

    /**
     * @description Returns the first earlier (lower-sequence) milestone that is not yet
     *              fully settled by approved receipts, or null if all earlier milestones
     *              are clear.
     */
    private static Payment_Schedule__c findBlockingEarlierMilestone(
        List<Payment_Schedule__c> bookingSchedules,
        Decimal targetSequence,
        Set<Id> schedulesWithPendingReceipt
    ) {
        for (Payment_Schedule__c ps : bookingSchedules) {
            if (ps.Sequence__c == null) continue;
            // Only earlier milestones gate the next one. Same / later never block.
            if (ps.Sequence__c >= targetSequence) continue;

            Boolean fullyPaid = isFullyPaid(ps);
            Boolean hasPendingReceipt = schedulesWithPendingReceipt.contains(ps.Id);

            if (!fullyPaid || hasPendingReceipt) {
                return ps;
            }
        }
        return null;
    }

    private static Boolean isFullyPaid(Payment_Schedule__c ps) {
        if (ps.Status__c != null && PAID_STATUSES.contains(ps.Status__c)) {
            // Still require zero pending to be safe against stale statuses.
            return ps.Pending_Amount__c == null || ps.Pending_Amount__c <= 0;
        }
        return ps.Pending_Amount__c != null && ps.Pending_Amount__c <= 0;
    }

    /**
     * @description Finds payment schedules on the given bookings that are referenced by at
     *              least one Receipt whose approval is still pending.
     */
    private static Set<Id> findSchedulesWithPendingReceipts(Set<Id> bookingIds) {
        Set<Id> result = new Set<Id>();
        for (Receipt_Line_Item__c li : [
            SELECT Payment_Schedule__c, Receipt__r.Approval_Status__c
            FROM Receipt_Line_Item__c
            WHERE Booking__c IN :bookingIds
            AND Payment_Schedule__c != null
            AND Receipt__c != null
        ]) {
            String approval = li.Receipt__r.Approval_Status__c;
            if (isPendingApproval(approval)) {
                result.add(li.Payment_Schedule__c);
            }
        }
        return result;
    }

    private static Boolean isPendingApproval(String approvalStatus) {
        if (String.isBlank(approvalStatus)) return false;
        String s = approvalStatus.toLowerCase();
        // Treat anything explicitly pending as a blocker; approved / rejected do not block.
        return s.contains('pending');
    }

    private static String buildErrorMessage(Payment_Schedule__c blocker, Payment_Schedule__c target) {
        String blockerName = String.isNotBlank(blocker.Milestone_Name__c)
            ? blocker.Milestone_Name__c
            : ('Milestone #' + String.valueOf(blocker.Sequence__c));
        String targetName = String.isNotBlank(target.Milestone_Name__c)
            ? target.Milestone_Name__c
            : ('Milestone #' + String.valueOf(target.Sequence__c));

        return 'This receipt cannot be allocated to a later milestone (' + targetName + ') because '
            + blockerName + ' is not yet fully paid through approved receipts (it still has a pending '
            + 'balance or a receipt awaiting approval). Complete the payment for ' + blockerName
            + ' first. Receipts for the same milestone are allowed.';
    }
}