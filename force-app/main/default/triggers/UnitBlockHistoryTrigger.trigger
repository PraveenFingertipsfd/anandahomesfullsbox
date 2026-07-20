trigger UnitBlockHistoryTrigger on Unit_Block_History__c (before update, after update) {

    if (Trigger.isBefore && Trigger.isUpdate) {
        Datetime now = System.now();
        Id currentUserId = UserInfo.getUserId();

        for (Unit_Block_History__c rec : Trigger.new) {
            Unit_Block_History__c old = Trigger.oldMap.get(rec.Id);
            if (rec.Status__c == 'Revoked' && old.Status__c != 'Revoked') {
                if (rec.Revoked_Time__c == null) {
                    rec.Revoked_Time__c = now;
                }
                if (rec.Unblocked_By__c == null) {
                    rec.Unblocked_By__c = currentUserId;
                }
            }
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        Set<Id> unitIdsToFree = new Set<Id>();
        for (Unit_Block_History__c rec : Trigger.new) {
            Unit_Block_History__c old = Trigger.oldMap.get(rec.Id);
            if (rec.Status__c == 'Revoked'
                && old.Status__c != 'Revoked'
                && rec.Unit__c != null) {
                unitIdsToFree.add(rec.Unit__c);
            }
        }

        if (!unitIdsToFree.isEmpty()) {
            List<Plot__c> plotsToUpdate = new List<Plot__c>();
            for (Id unitId : unitIdsToFree) {
                plotsToUpdate.add(new Plot__c(Id = unitId, Status__c = 'Available'));
            }
            update plotsToUpdate;
        }
    }
}