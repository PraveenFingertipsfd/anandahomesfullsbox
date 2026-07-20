trigger FollowUpTrigger on Follow_up__c (before insert,after insert, after update) {
    if(label.Enable_FollowUp_Trigger=='TRUE'){
        if (Trigger.isBefore) {
            if (Trigger.isInsert) { 
                FollowUpHandler.MapPhoneNumbers(Trigger.new);
                FollowUpHandler.validateSingleScheduledFollowup(Trigger.new);
            }
        }
        //added by karthik 06-11
        if (Trigger.isAfter) {
            if (Trigger.isInsert) {
                FollowUpHandler.updateLeadFollowupDates(Trigger.new);
            }
        }
        
        //added by karthik 27-01-26 - To map the latest completed followup subject to lead
        if (Trigger.isAfter && Trigger.isUpdate) {
            FollowUpHandler.updateLatestFollowupSubject(Trigger.new,Trigger.oldMap);
        }
        
    }
}