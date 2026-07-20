trigger RelatedSourceTrigger on Related_Source__c (after insert, before insert) {
    /*
    Set<Id> relatedSourceIds = new Set<Id>();
    
    // Collect the Ids of the newly inserted Related Source records
    for (Related_Source__c rs : Trigger.new) {
        relatedSourceIds.add(rs.Id);
    }
    
    // Call the future method to send the data to Pulse TeleSystem
    if (!relatedSourceIds.isEmpty()) {
        SendLeadDetailsToPulseTeleSystem.sendLeadDetailsInBulk(relatedSourceIds);
    }
    */
    
    if (Trigger.isAfter && Trigger.isInsert) {
        
        Set<Id> relatedSourceIds = new Set<Id>();
        Set<Id> leadIdsToUpdate = new Set<Id>();
        
        //added by karthik 16-01-26 [To collect cp owners and leads]
        Map<Id, Set<Id>> cpOwnerToLeadMap = new Map<Id, Set<Id>>(); 
        
        Set<Id> CPRecIds = new Set<Id>();
        for (Related_Source__c rs : Trigger.new) {
            if (rs.Channel_Partner__c != null){
                CPRecIds.add(rs.Channel_Partner__c);
            }
        }
        Map<Id,Channel_Partner__c> CPMap = new Map<Id,Channel_Partner__c>([select id,ownerId from Channel_Partner__c where Id in: CPRecIds]);
        
        for (Related_Source__c rs : Trigger.new) {
            
            relatedSourceIds.add(rs.Id);
            
            //add type condition exclude both fresh and re-opened
            if (rs.SLead__c != null && rs.Medium__c == 'CHANNEL PARTNERS' && rs.Channel_Partner__c != null && rs.Lead_Type__c == 'Re-Engaged') {
                leadIdsToUpdate.add(rs.SLead__c);
            }
            
            // Only Channel Partner related sources - added by karthik 16-01-26
            if (rs.SLead__c == null || rs.Channel_Partner__c == null || rs.Medium__c != 'CHANNEL PARTNERS') {
                    continue;
                }
            
            // CP Owner
            //Id cpOwnerId = rs.Channel_Partner__r.OwnerId;
            
            Id cpOwnerId = CPMap.get(rs.Channel_Partner__c) != null ? CPMap.get(rs.Channel_Partner__c).OwnerId : null;
            system.debug('CPOwnerId > '+cpOwnerId);
            if (cpOwnerId == null) {
                continue;
            }
            system.debug('CPOwnerId > '+cpOwnerId);
            if (!cpOwnerToLeadMap.containsKey(cpOwnerId)) {
                cpOwnerToLeadMap.put(cpOwnerId, new Set<Id>());
            }
            
            cpOwnerToLeadMap.get(cpOwnerId).add(rs.SLead__c);
            
        }
        
        // Call the future method to send the data to Pulse TeleSystem
        if (!relatedSourceIds.isEmpty()) {
            SendLeadDetailsToPulseTeleSystem.sendLeadDetailsInBulk(relatedSourceIds);
        }
        
        if (!leadIdsToUpdate.isEmpty()) {
            
            //List<Lead> leadsToUpdate = [SELECT Id, Reengaged_From_CP__c FROM Lead WHERE Id IN :leadIdsToUpdate AND Reengaged_From_CP__c = false];	
            
            List<Lead> leadsToUpdate = [SELECT Id, Re_Engaged_CP_Date__c FROM Lead WHERE Id IN :leadIdsToUpdate];
            
            for (Lead ld : leadsToUpdate) {
                ld.Re_Engaged_CP_Date__c = System.today();
            }
            
            if (!leadsToUpdate.isEmpty()) {
                update leadsToUpdate;
            }
        }
        
        /* =================================================
           CP OWNER–WISE SHARING (NEW LOGIC)
        ================================================= */

        if (cpOwnerToLeadMap.isEmpty()) {
            return;
        }

        /* -----------------------------
           Fetch existing LeadShares
        ----------------------------- */
        Set<String> existingShares = new Set<String>();
        
        //Flatten all LeadIds from Map<CP_Owner, Set<LeadId>>
        Set<Id> allLeadIds = new Set<Id>();
        for (Set<Id> leadSet : cpOwnerToLeadMap.values()) {
            allLeadIds.addAll(leadSet);
        }

        List<LeadShare> existingLeadShares = [SELECT LeadId, UserOrGroupId FROM LeadShare WHERE UserOrGroupId IN :cpOwnerToLeadMap.keySet() AND LeadId IN :allLeadIds];

        for (LeadShare ls : existingLeadShares) {
            existingShares.add(ls.LeadId + '-' + ls.UserOrGroupId);
        }

        /* -----------------------------
           Create missing LeadShares
        ----------------------------- */
        List<LeadShare> sharesToInsert = new List<LeadShare>();

        for (Id cpOwnerId : cpOwnerToLeadMap.keySet()) {
            for (Id leadId : cpOwnerToLeadMap.get(cpOwnerId)) {

                String key = leadId + '-' + cpOwnerId;
                if (existingShares.contains(key)) {
                    continue;
                }

                LeadShare ls = new LeadShare();
                ls.LeadId = leadId;
                ls.UserOrGroupId = cpOwnerId;
                ls.LeadAccessLevel = 'Read';
                ls.RowCause = Schema.LeadShare.RowCause.Manual;

                sharesToInsert.add(ls);
            }
        }

        if (!sharesToInsert.isEmpty()) {
            insert sharesToInsert;
        }
    }
}