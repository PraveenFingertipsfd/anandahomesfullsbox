/**
 * @description Trigger on NOC__c. Syncs the NOC's approval status onto its Booking
 *              (Booking__c.NOC_Approval_Status__c) on insert and when it changes.
 *              See NOCApprovalSyncService.
 * @author System
 */
trigger NOCTrigger on NOC__c (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        NOCApprovalSyncService.syncToBooking(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
    }
}