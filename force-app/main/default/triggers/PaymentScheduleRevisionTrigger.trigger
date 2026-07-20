/**
 * @description Trigger on Payment_Schedule_Revision__c. When a revision is approved
 *              (Approval_Status__c -> Approved), applies the staged values onto the
 *              Payment Schedule (BRD 8.2). See PaymentScheduleRevisionService.
 * @author System
 */
trigger PaymentScheduleRevisionTrigger on Payment_Schedule_Revision__c (before update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        PaymentScheduleRevisionService.applyApprovedFromTrigger(Trigger.new, Trigger.oldMap);
    }
}