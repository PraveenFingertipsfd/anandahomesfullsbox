/**
 * @description Trigger on Additional_Charge__c. Seeds 1st/2nd reminder dates when a charge
 *              is demanded (BRD §13.1).
 * @author System
 */
trigger AdditionalChargeTrigger on Additional_Charge__c (before insert, before update) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        AdditionalChargeReminderService.populateReminderDates(Trigger.new, Trigger.oldMap);
    }
}