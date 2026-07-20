trigger UserTrigger on User (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        UserAvailabilityHistoryHandler.handleAvailabilityChange(Trigger.new, Trigger.oldMap);
    }
}