trigger UserTrigger on User (before update, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        UserAvailabilityHistoryHandler.clearBackupCallerWhenWorking(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        UserAvailabilityHistoryHandler.handleAvailabilityChange(Trigger.new, Trigger.oldMap);
    }
}
