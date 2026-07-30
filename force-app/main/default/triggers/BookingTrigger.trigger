/**
 * @description The BookingTrigger.
 * @author : Arun Kumar N
 * @createdDate : 21/12/2025
 * @status : Active trigger
 *
 * After-context handlers added to capture stage-wise remarks (BRD pointer 1).
 */
trigger BookingTrigger on Booking__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        //Stage-progression gates (BRD lifecycle prerequisites).
        if (Trigger.isUpdate) {
           BookingStageValidationService.validateStageTransitions(Trigger.new, Trigger.oldMap);
        }
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            BookingStageRemarkService.captureForNewBookings(Trigger.new);
        } else if (Trigger.isUpdate) {
            BookingStageRemarkService.captureForStageChanges(Trigger.new, Trigger.oldMap);
        }
    }
}