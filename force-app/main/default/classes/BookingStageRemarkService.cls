/**
 * @description Captures stage-wise remarks for Bookings into the Booking_Stage_Remark__c
 *              history object. A snapshot is taken:
 *                - on Booking creation (initial stage), and
 *                - every time the Booking Stage (Status__c) changes.
 *
 *              The remark text is read from Booking.Stage_Remarks__c, which the user
 *              maintains for the stage currently in progress. This gives an auditable,
 *              per-stage trail of what happened at each stage of the post-sales lifecycle.
 *
 *              BRD pointer 1: "Each booking stage-wise remarks to be captured."
 * @author System
 */
public with sharing class BookingStageRemarkService {

    /**
     * @description Captures an initial stage remark for newly created bookings.
     *              Invoked from BookingTrigger after insert.
     * @param newBookings Trigger.new list (already committed)
     */
    public static void captureForNewBookings(List<Booking__c> newBookings) {
        if (newBookings == null || newBookings.isEmpty()) return;

        List<Booking_Stage_Remark__c> toInsert = new List<Booking_Stage_Remark__c>();
        for (Booking__c b : newBookings) {
            toInsert.add(buildRemark(b.Id, null, b.Status__c, b.Stage_Remarks__c));
        }
        insertRemarks(toInsert);
    }

    /**
     * @description Captures a stage remark for every booking whose Stage (Status__c) changed.
     *              Invoked from BookingTrigger after update.
     * @param newBookings Trigger.new list
     * @param oldMap Trigger.oldMap
     */
    public static void captureForStageChanges(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        if (newBookings == null || newBookings.isEmpty() || oldMap == null) return;

        List<Booking_Stage_Remark__c> toInsert = new List<Booking_Stage_Remark__c>();
        for (Booking__c b : newBookings) {
            Booking__c oldB = oldMap.get(b.Id);
            if (oldB == null) continue;

            // Only capture when the stage actually changed.
            if (b.Status__c == oldB.Status__c) continue;

            // The remark belongs to the stage that was just completed (the previous stage),
            // using whatever Stage_Remarks the user recorded while in that stage.
            toInsert.add(buildRemark(b.Id, oldB.Status__c, b.Status__c, b.Stage_Remarks__c));
        }
        insertRemarks(toInsert);
    }

    // ==================== HELPERS ====================

    private static Booking_Stage_Remark__c buildRemark(Id bookingId, String previousStage, String stage, String remarks) {
        return new Booking_Stage_Remark__c(
            Booking__c = bookingId,
            Previous_Stage__c = previousStage,
            Stage__c = stage,
            Remarks__c = remarks,
            Captured_By__c = UserInfo.getUserId(),
            Captured_Date__c = System.now()
        );
    }

    private static void insertRemarks(List<Booking_Stage_Remark__c> remarks) {
        if (remarks == null || remarks.isEmpty()) return;
        // Allow partial success so one bad row never blocks a booking save.
        Database.insert(remarks, false);
    }
}