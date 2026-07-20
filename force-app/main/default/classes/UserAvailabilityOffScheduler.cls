public without sharing class UserAvailabilityOffScheduler implements Schedulable {

    @TestVisible
    private static final String AUTO_REASON = 'Auto turned off by nightly scheduler';

    public void execute(SchedulableContext sc) {
        turnOffAllAvailable();
    }

    public static void turnOffAllAvailable() {
        List<User> toTurnOff = [
            SELECT Id, Availability__c
            FROM User
            WHERE IsActive = true AND Availability__c = true
        ];
        if (toTurnOff.isEmpty()) {
            return;
        }

        for (User u : toTurnOff) {
            u.Availability__c = false;
        }

        UserAvailabilityHistoryHandler.turnOffReason = AUTO_REASON;
        update toTurnOff;
    }
}