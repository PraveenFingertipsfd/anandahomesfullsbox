trigger QuoteTrigger on Quote__c (before insert, after insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        QuoteApprovalTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        QuoteApprovalTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        QuoteApprovalTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}