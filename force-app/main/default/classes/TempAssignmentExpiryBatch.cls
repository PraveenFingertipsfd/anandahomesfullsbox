// 2026-05-27
// 2026-05-26
global class TempAssignmentExpiryBatch implements Database.Batchable<SObject> {
//test
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Lead__c, New_Owner__c, Status__c
            FROM Reassignment_History__c
            WHERE Reassignment_Type__c = 'Temporary'
            AND Status__c = 'Active'
            AND Temp_Expiry__c <= :Date.today()
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Reassignment_History__c> scope) {
        Set<Id> leadIds = new Set<Id>();
        Map<Id, Id> leadToTempOwner = new Map<Id, Id>();

        for (Reassignment_History__c rh : scope) {
            leadIds.add(rh.Lead__c);
            leadToTempOwner.put(rh.Lead__c, rh.New_Owner__c);
            rh.Status__c             = 'Expired';
            rh.Ownership_End_Date__c = Date.today();
            rh.Exit_Status__c        = 'Expired by Scheduled Job';
            rh.Access_Removed_By__c  = null;
        }

        // Clear temp owner on leads
        List<Lead__c> leadsToUpdate = new List<Lead__c>();
        for (Id leadId : leadIds) {
            leadsToUpdate.add(new Lead__c(
                Id = leadId,
                Temp_Owner__c  = null,
                Temp_Start__c  = null,
                Temp_Expiry__c = null
            ));
        }

        // Remove sharing inline (no external dependency) — Lead + Follow_up + Site_Visit
        List<Lead__Share> allShares = [
            SELECT Id, ParentId, UserOrGroupId
            FROM Lead__Share
            WHERE ParentId IN :leadToTempOwner.keySet()
            AND RowCause = 'Manual'
        ];
        List<Lead__Share> toDelete = new List<Lead__Share>();
        for (Lead__Share share : allShares) {
            Id expectedUser = leadToTempOwner.get(share.ParentId);
            if (expectedUser != null && share.UserOrGroupId == expectedUser) {
                toDelete.add(share);
            }
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }

        Map<Id, Id> followUpIdToLeadId = new Map<Id, Id>();
        for (Follow_up__c fu : [
            SELECT Id, CLead__c FROM Follow_up__c WHERE CLead__c IN :leadToTempOwner.keySet()
        ]) {
            followUpIdToLeadId.put(fu.Id, fu.CLead__c);
        }
        if (!followUpIdToLeadId.isEmpty()) {
            List<Follow_up__Share> fuToDelete = new List<Follow_up__Share>();
            for (Follow_up__Share share : [
                SELECT Id, ParentId, UserOrGroupId
                FROM Follow_up__Share
                WHERE ParentId IN :followUpIdToLeadId.keySet()
                AND RowCause = 'Manual'
            ]) {
                Id leadId = followUpIdToLeadId.get(share.ParentId);
                Id expectedUser = leadId == null ? null : leadToTempOwner.get(leadId);
                if (expectedUser != null && share.UserOrGroupId == expectedUser) {
                    fuToDelete.add(share);
                }
            }
            if (!fuToDelete.isEmpty()) {
                Database.delete(fuToDelete, false);
            }
        }

        Map<Id, Id> siteVisitIdToLeadId = new Map<Id, Id>();
        for (Site_Visit__c sv : [
            SELECT Id, CLead__c FROM Site_Visit__c WHERE CLead__c IN :leadToTempOwner.keySet()
        ]) {
            siteVisitIdToLeadId.put(sv.Id, sv.CLead__c);
        }
        if (!siteVisitIdToLeadId.isEmpty()) {
            List<Site_Visit__Share> svToDelete = new List<Site_Visit__Share>();
            for (Site_Visit__Share share : [
                SELECT Id, ParentId, UserOrGroupId
                FROM Site_Visit__Share
                WHERE ParentId IN :siteVisitIdToLeadId.keySet()
                AND RowCause = 'Manual'
            ]) {
                Id leadId = siteVisitIdToLeadId.get(share.ParentId);
                Id expectedUser = leadId == null ? null : leadToTempOwner.get(leadId);
                if (expectedUser != null && share.UserOrGroupId == expectedUser) {
                    svToDelete.add(share);
                }
            }
            if (!svToDelete.isEmpty()) {
                Database.delete(svToDelete, false);
            }
        }

        if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
        if (!scope.isEmpty()) update scope;
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('TempAssignmentExpiryBatch completed.');
    }
}