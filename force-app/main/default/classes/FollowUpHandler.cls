public class FollowUpHandler {

    public static void MapPhoneNumbers(List<Follow_up__c> followUpList) {
        if (followUpList == null || followUpList.isEmpty()) return;

        // Step 1: Collect all related SLead Ids
        Set<Id> sLeadIds = new Set<Id>();
        for (Follow_up__c fu : followUpList) {
            if (fu.CLead__c != null) {
                sLeadIds.add(fu.CLead__c);
            }
        }

        if (sLeadIds.isEmpty()) return;
		system.debug('sLeadIds '+sLeadIds);
        
        // Step 2: Query all related Leads
        Map<Id, Lead__c> leadMap = new Map<Id, Lead__c>(
            [SELECT Id, Phone__c, Secondary_Phone__c FROM Lead__c WHERE Id IN :sLeadIds]
        );
		system.debug('leadMap '+leadMap);
        // Step 3: Update Follow_up__c records directly in memory (before insert)
        for (Follow_up__c fu : followUpList) {
            if (fu.CLead__c != null && leadMap.containsKey(fu.CLead__c)) {
                Lead__c relatedLead = leadMap.get(fu.CLead__c);
                fu.Primary_Phone__c = relatedLead.Phone__c;
                fu.Secondary_Phone__c = relatedLead.Secondary_Phone__c;
            }
        }    
    }
    
    //added by karthik 06-11
    public static void validateSingleScheduledFollowup(List<Follow_up__c> newFollowups) {
        
        Set<Id> leadIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        
        // Collect all leads and owners for new Scheduled followups
        for (Follow_up__c f : newFollowups) {
            if (f.CLead__c != null && f.OwnerId != null && f.Status__c == 'Scheduled') {
                leadIds.add(f.CLead__c);
                ownerIds.add(f.OwnerId);
            }
        }
        
        if (leadIds.isEmpty() || ownerIds.isEmpty()) return;
        
        // Fetch existing Scheduled followups for same Lead + Owner
        Map<String, Follow_up__c> existingMap = new Map<String, Follow_up__c>();
        for (Follow_up__c existing : [SELECT Id, CLead__c, OwnerId, Status__c FROM Follow_up__c WHERE CLead__c IN :leadIds AND OwnerId IN :ownerIds AND Status__c = 'Scheduled']){
            String key = existing.CLead__c + '-' + existing.OwnerId;
            existingMap.put(key, existing);
        }

        // Add validation error if duplicate scheduled followup found
        for (Follow_up__c f : newFollowups) {
            if (f.CLead__c != null && f.OwnerId != null && f.Status__c == 'Scheduled') {
                String key = f.CLead__c + '-' + f.OwnerId;
                if (existingMap.containsKey(key)) {
                    f.addError('You already have a Scheduled Followup for this Lead.');
                }
            }
        }
    }
    
    //added by karthik 06-11
    public static void updateLeadFollowupDates(List<Follow_up__c> newFollowups) {
        
        List<Lead__c> leadstoUpdate = new List<Lead__c>();
        
        for(Follow_up__c fup : newFollowups)
        {
            if(fup.CLead__c != null)
            {
                leadstoUpdate.add(new Lead__c(Id = fup.CLead__c, Next_Followup_Date__c = fup.Scheduled_Date__c , Recent_Followup_Date__c = fup.CreatedDate ));
            }
        }
        
        if(!leadstoUpdate.isEmpty())
        {
            update leadstoUpdate;
        }
    }
    
    //added by karthik 27-01
    public static void updateLatestFollowupSubject(List<Follow_up__c> newFollowups,Map<Id, Follow_up__c> oldMap) {
        Map<Id, String> leadSubjectMap = new Map<Id, String>();
        
        for (Follow_up__c f : newFollowups) {
            Follow_up__c oldF = oldMap.get(f.Id);
            
            // Only when status changes to Completed
            if (f.CLead__c != null && f.Status__c == 'Completed' && oldF.Status__c != 'Completed' && f.Subject__c != null) {
                leadSubjectMap.put(f.CLead__c, f.Subject__c);
            }
        }
        
        if (leadSubjectMap.isEmpty()) return;
        
        List<Lead__c> leadsToUpdate = new List<Lead__c>();
        for (Id leadId : leadSubjectMap.keySet()) {
            leadsToUpdate.add(new Lead__c(Id = leadId,Latest_Followup_Subject__c = leadSubjectMap.get(leadId)));
        }
        
        update leadsToUpdate;
    }
}