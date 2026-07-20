// Last Modified: 2026-03-27
trigger SLeadTrigger on Lead (after insert) {
    SLeadTriggerHandler.pushToCustomLead(Trigger.new);
}