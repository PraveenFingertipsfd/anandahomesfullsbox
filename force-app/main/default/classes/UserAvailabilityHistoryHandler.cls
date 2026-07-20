public without sharing class UserAvailabilityHistoryHandler {

    // Optional reason supplied by the caller (e.g. UserStatusController) before
    // the User DML; stamped on the history row closed by this transaction.
    public static String turnOffReason;

    public static void handleAvailabilityChange(List<User> newUsers, Map<Id, User> oldMap) {
        Set<Id> flippedOn  = new Set<Id>();
        Set<Id> flippedOff = new Set<Id>();

        for (User u : newUsers) {
            User oldU = oldMap.get(u.Id);
            if (u.Availability__c == true && oldU.Availability__c == false) {
                flippedOn.add(u.Id);
            } else if (u.Availability__c == false && oldU.Availability__c == true) {
                flippedOff.add(u.Id);
            }
        }

        if (flippedOn.isEmpty() && flippedOff.isEmpty()) {
            return;
        }

        DateTime now = System.now();
        Date today = Date.today();

        List<User_Availability_History__c> toInsert = new List<User_Availability_History__c>();
        for (Id uId : flippedOn) {
            toInsert.add(new User_Availability_History__c(
                Executive__c  = uId,
                Is_Active__c  = true,
                Log_Date__c   = today,
                Start_Time__c = now
            ));
        }

        List<User_Availability_History__c> toUpdate = new List<User_Availability_History__c>();
        if (!flippedOff.isEmpty()) {
            Map<Id, User_Availability_History__c> openByUser = new Map<Id, User_Availability_History__c>();
            for (User_Availability_History__c h : [
                SELECT Id, Executive__c, Start_Time__c
                FROM User_Availability_History__c
                WHERE Executive__c IN :flippedOff
                  AND Is_Active__c = true
                  AND End_Time__c = null
                ORDER BY Start_Time__c DESC
            ]) {
                if (!openByUser.containsKey(h.Executive__c)) {
                    openByUser.put(h.Executive__c, h);
                }
            }
            String reason = (turnOffReason == null) ? null : turnOffReason.trim();
            for (User_Availability_History__c h : openByUser.values()) {
                h.Is_Active__c = false;
                h.End_Time__c  = now;
                if (String.isNotBlank(reason)) {
                    h.Turn_Off_Reason__c = reason;
                }
                toUpdate.add(h);
            }
        }

        try {
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'UserAvailabilityHistoryHandler DML failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AvailabilityHistoryException('Could not write User Availability History: ' + e.getDmlMessage(0), e);
        }
    }

    public class AvailabilityHistoryException extends Exception {}
}