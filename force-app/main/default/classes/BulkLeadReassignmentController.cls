// 2026-05-27
// 2026-05-26
public without sharing class BulkLeadReassignmentController {

    // ─── Wrapper for init data ───
    public class InitData {
        @AuraEnabled public List<PicklistOption> projectOptions { get; set; }
        @AuraEnabled public List<PicklistOption> statusOptions { get; set; }
        @AuraEnabled public List<UserOption> activeUsers { get; set; }
    }

    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class UserOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String profileName { get; set; }
        public UserOption(User u) {
            this.label = u.Name;
            this.value = u.Id;
            this.profileName = u.Profile.Name;
        }
    }

    // ─── 1. Get Init Data (picklists + users) ───
    @AuraEnabled(cacheable=true)
    public static InitData getInitData() {
        InitData data = new InitData();

        // Project picklist
        data.projectOptions = new List<PicklistOption>();
        for (Schema.PicklistEntry pe : Lead__c.Allocated_Project__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                data.projectOptions.add(new PicklistOption(pe.getLabel(), pe.getValue()));
            }
        }

        // Lead Status picklist
        data.statusOptions = new List<PicklistOption>();
        for (Schema.PicklistEntry pe : Lead__c.Lead_Status__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                data.statusOptions.add(new PicklistOption(pe.getLabel(), pe.getValue()));
            }
        }

        // Active users (only Pre-Sales Executive and Associate Manager profiles)
        data.activeUsers = new List<UserOption>();
        for (User u : [
            SELECT Id, Name, Profile.Name
            FROM User
            WHERE IsActive = TRUE
            AND Profile.Name IN ('Pre-Sales Executive', 'Associate Manager')
            ORDER BY Name
        ]) {
            data.activeUsers.add(new UserOption(u));
        }

        return data;
    }

    // ─── 2. Get Leads by Owner with filters ───
    @AuraEnabled
    public static List<Lead__c> getLeadsByOwner(
        String ownerId,
        String projectFilter,
        String statusFilter,
        Date fromDate,
        Date toDate,
        String mobileFilter
    ) {
        if (String.isBlank(ownerId)) {
            return new List<Lead__c>();
        }

        String query = 'SELECT Id, Name, Phone__c, Lead_Status__c, Allocated_Project__c, '
            + 'Lead_Owner_Full_Name__c, Created_Dates__c, Temp_Owner__c, Temp_Expiry__c, OwnerId '
            + 'FROM Lead__c WHERE OwnerId = :ownerId';

        if (String.isNotBlank(projectFilter)) {
            query += ' AND Allocated_Project__c = :projectFilter';
        }
        if (String.isNotBlank(statusFilter)) {
            query += ' AND Lead_Status__c = :statusFilter';
        }
        if (fromDate != null) {
            DateTime fromDT = DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
            query += ' AND Created_Dates__c >= :fromDT';
        }
        if (toDate != null) {
            DateTime toDT = DateTime.newInstance(toDate, Time.newInstance(23, 59, 59, 999));
            query += ' AND Created_Dates__c <= :toDT';
        }
        String mobileLike;
        if (String.isNotBlank(mobileFilter)) {
            mobileLike = '%' + mobileFilter.trim() + '%';
            query += ' AND (Phone__c LIKE :mobileLike OR Secondary_Phone__c LIKE :mobileLike)';
        }

        query += ' ORDER BY Created_Dates__c DESC LIMIT 2000';
        return Database.query(query);
    }

    // ─── 3. Reassign Leads (Permanent or Temporary) ───
    @AuraEnabled
    public static String reassignLeads(
        List<Id> leadIds,
        String currentOwnerId,
        String newOwnerId,
        String reassignmentType,
        String reason,
        Date tempExpiryDate
    ) {
        if (leadIds == null || leadIds.isEmpty()) {
            throw new AuraHandledException('No leads selected for reassignment.');
        }
        if (String.isBlank(newOwnerId)) {
            throw new AuraHandledException('New owner is required.');
        }
        if (reassignmentType == 'Temporary' && tempExpiryDate == null) {
            throw new AuraHandledException('Expiry date is required for temporary assignments.');
        }

        List<Lead__c> leads = [
            SELECT Id, OwnerId, Lead_Status__c, Temp_Owner__c
            FROM Lead__c
            WHERE Id IN :leadIds
        ];

        List<Lead__c> leadsToUpdate = new List<Lead__c>();
        List<Reassignment_History__c> histories = new List<Reassignment_History__c>();

        for (Lead__c ld : leads) {
            Reassignment_History__c rh = new Reassignment_History__c();
            rh.Lead__c = ld.Id;
            rh.Old_Owner__c = ld.OwnerId;
            rh.New_Owner__c = newOwnerId;
            rh.Assigned_By__c = UserInfo.getUserId();
            rh.Reassignment_Type__c = reassignmentType;
            rh.Reason__c = reason;
            rh.Reassigned_Date__c = DateTime.now();
            rh.Lead_Status_At_Change__c = ld.Lead_Status__c;
            rh.Entry_Status__c = 'Reassigned by ' + UserInfo.getName();

            Lead__c upd = new Lead__c(Id = ld.Id);

            if (reassignmentType == 'Permanent') {
                // Change actual owner; ownership dates are not applicable for Permanent
                upd.OwnerId = newOwnerId;
                rh.Status__c = 'Completed';
                rh.Exit_Status__c = 'Permanent Transfer';
            } else {
                // Temporary: keep owner, set temp fields
                upd.Temp_Owner__c = newOwnerId;
                upd.Temp_Start__c = Date.today();
                upd.Temp_Expiry__c = tempExpiryDate;
                rh.Status__c = 'Active';
                rh.Temp_Expiry__c = tempExpiryDate;
                rh.Ownership_Start_Date__c = Date.today();
            }

            leadsToUpdate.add(upd);
            histories.add(rh);
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
        if (!histories.isEmpty()) {
            insert histories;
        }

        // For temporary assignments, create manual sharing
        if (reassignmentType == 'Temporary') {
            createTempSharing(leadIds, newOwnerId);
            notifyTempOwner(leadIds, newOwnerId, tempExpiryDate);
        }

        return 'Successfully reassigned ' + leadIds.size() + ' lead(s).';
    }

    // ─── 4. Create manual sharing for temp owner ───
    // Grants Edit access to the Lead and to its Follow_up__c / Site_Visit__c children.
    private static void createTempSharing(List<Id> leadIds, String tempOwnerId) {
        List<Lead__Share> leadShares = new List<Lead__Share>();
        for (Id leadId : leadIds) {
            leadShares.add(new Lead__Share(
                ParentId = leadId,
                UserOrGroupId = tempOwnerId,
                AccessLevel = 'Edit',
                RowCause = 'Manual'
            ));
        }
        if (!leadShares.isEmpty()) {
            Database.insert(leadShares, false);
        }

        List<Follow_up__Share> fuShares = new List<Follow_up__Share>();
        for (Follow_up__c fu : [SELECT Id FROM Follow_up__c WHERE CLead__c IN :leadIds]) {
            fuShares.add(new Follow_up__Share(
                ParentId = fu.Id,
                UserOrGroupId = tempOwnerId,
                AccessLevel = 'Edit',
                RowCause = 'Manual'
            ));
        }
        if (!fuShares.isEmpty()) {
            Database.insert(fuShares, false);
        }

        List<Site_Visit__Share> svShares = new List<Site_Visit__Share>();
        for (Site_Visit__c sv : [SELECT Id FROM Site_Visit__c WHERE CLead__c IN :leadIds]) {
            svShares.add(new Site_Visit__Share(
                ParentId = sv.Id,
                UserOrGroupId = tempOwnerId,
                AccessLevel = 'Edit',
                RowCause = 'Manual'
            ));
        }
        if (!svShares.isEmpty()) {
            Database.insert(svShares, false);
        }
    }

    // ─── 4b. Notify temp owner via in-app Custom Notification ───
    private static void notifyTempOwner(List<Id> leadIds, String tempOwnerId, Date tempExpiryDate) {
        try {
            List<CustomNotificationType> types = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'Temporary_Assignment_Notification'
                LIMIT 1
            ];
            if (types.isEmpty()) {
                return;
            }

            Integer leadCount = leadIds.size();
            String expiry = tempExpiryDate == null ? '' : tempExpiryDate.format();
            String leadWord = leadCount == 1 ? 'lead' : 'leads';
            String body = UserInfo.getName() + ' has temporarily assigned ' + leadCount +
                          ' ' + leadWord + ' to you. Expires on ' + expiry + '.';

            Id targetId = leadCount == 1 ? leadIds[0] : (Id) UserInfo.getUserId();

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(types[0].Id);
            notification.setTitle('Temporary Lead Assignment');
            notification.setBody(body);
            notification.setTargetId(targetId);
            notification.send(new Set<String>{ tempOwnerId });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send Temporary Assignment notification: ' + e.getMessage());
        }
    }

    // ─── 5. Get Active Temporary Assignments ───
    @AuraEnabled
    public static List<Reassignment_History__c> getActiveTemporaryAssignments() {
        return [
            SELECT Id, Name, Lead__c, Lead__r.Name, Lead__r.Phone__c,
                   Lead__r.Lead_Status__c, Lead__r.Allocated_Project__c,
                   Old_Owner__c, Old_Owner__r.Name,
                   New_Owner__c, New_Owner__r.Name,
                   Assigned_By__c, Assigned_By__r.Name,
                   Reassigned_Date__c, Temp_Expiry__c,
                   Status__c, Reason__c
            FROM Reassignment_History__c
            WHERE Reassignment_Type__c = 'Temporary'
            AND Status__c = 'Active'
            AND Lead__c != null
            ORDER BY Temp_Expiry__c ASC
            LIMIT 500
        ];
    }

    // ─── 6. Revoke Temporary Access ───
    @AuraEnabled
    public static String revokeTemporaryAccess(List<Id> historyIds) {
        if (historyIds == null || historyIds.isEmpty()) {
            throw new AuraHandledException('No records selected.');
        }

        List<Reassignment_History__c> records = [
            SELECT Id, Lead__c, New_Owner__c, Status__c
            FROM Reassignment_History__c
            WHERE Id IN :historyIds
            AND Status__c = 'Active'
        ];

        Set<Id> leadIds = new Set<Id>();
        Map<Id, Id> leadToTempOwner = new Map<Id, Id>();
        for (Reassignment_History__c rh : records) {
            leadIds.add(rh.Lead__c);
            leadToTempOwner.put(rh.Lead__c, rh.New_Owner__c);
            rh.Status__c = 'Revoked';
            rh.Ownership_End_Date__c = Date.today();
            rh.Exit_Status__c = 'Manually Revoked';
        }

        // Clear temp fields on leads
        List<Lead__c> leadsToUpdate = new List<Lead__c>();
        for (Id leadId : leadIds) {
            leadsToUpdate.add(new Lead__c(
                Id = leadId,
                Temp_Owner__c = null,
                Temp_Start__c = null,
                Temp_Expiry__c = null
            ));
        }

        // Remove manual shares — Lead + Follow_up + Site_Visit
        List<Lead__Share> sharesToDelete = new List<Lead__Share>();
        for (Lead__Share s : [
            SELECT Id, ParentId, UserOrGroupId
            FROM Lead__Share
            WHERE ParentId IN :leadToTempOwner.keySet()
            AND RowCause = 'Manual'
        ]) {
            Id expectedUser = leadToTempOwner.get(s.ParentId);
            if (expectedUser != null && s.UserOrGroupId == expectedUser) {
                sharesToDelete.add(s);
            }
        }
        if (!sharesToDelete.isEmpty()) {
            Database.delete(sharesToDelete, false);
        }

        Map<Id, Id> followUpIdToLeadId = new Map<Id, Id>();
        for (Follow_up__c fu : [
            SELECT Id, CLead__c FROM Follow_up__c WHERE CLead__c IN :leadToTempOwner.keySet()
        ]) {
            followUpIdToLeadId.put(fu.Id, fu.CLead__c);
        }
        if (!followUpIdToLeadId.isEmpty()) {
            List<Follow_up__Share> fuToDelete = new List<Follow_up__Share>();
            for (Follow_up__Share s : [
                SELECT Id, ParentId, UserOrGroupId
                FROM Follow_up__Share
                WHERE ParentId IN :followUpIdToLeadId.keySet()
                AND RowCause = 'Manual'
            ]) {
                Id leadId = followUpIdToLeadId.get(s.ParentId);
                Id expectedUser = leadId == null ? null : leadToTempOwner.get(leadId);
                if (expectedUser != null && s.UserOrGroupId == expectedUser) {
                    fuToDelete.add(s);
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
            for (Site_Visit__Share s : [
                SELECT Id, ParentId, UserOrGroupId
                FROM Site_Visit__Share
                WHERE ParentId IN :siteVisitIdToLeadId.keySet()
                AND RowCause = 'Manual'
            ]) {
                Id leadId = siteVisitIdToLeadId.get(s.ParentId);
                Id expectedUser = leadId == null ? null : leadToTempOwner.get(leadId);
                if (expectedUser != null && s.UserOrGroupId == expectedUser) {
                    svToDelete.add(s);
                }
            }
            if (!svToDelete.isEmpty()) {
                Database.delete(svToDelete, false);
            }
        }
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
        if (!records.isEmpty()) {
            update records;
        }

        return 'Access revoked for ' + records.size() + ' assignment(s).';
    }
}