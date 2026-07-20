trigger SiteVisitTrigger on Site_Visit__c (after insert, before update, after update) {
    
    
    // Before Update → Set Completed Date/Time....
    
    if (Trigger.isBefore && Trigger.isUpdate) {
        for (Site_Visit__c sv : Trigger.New) {
            Site_Visit__c oldSV = Trigger.oldMap.get(sv.Id);

            if (sv.Status__c == 'Completed' && oldSV.Status__c != 'Completed') {
                sv.SV_Completed_Date_Time__c = System.now();
                System.debug('Setting Completed Date for: ' + sv.Id);
            }
        }
    }


    
    // After Insert + After Update → Update Lead Field ....
    
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        //List<Lead> leadsToUpdate = new List<Lead>();
        Map<Id, Lead__c> leadsToUpdate = new Map<Id, Lead__c>();

        for (Site_Visit__c sv : Trigger.new) {

            Site_Visit__c oldSV = Trigger.isUpdate ? Trigger.oldMap.get(sv.Id) : null;

            Boolean changedToCompleted = sv.Status__c == 'Completed' && (oldSV == null || oldSV.Status__c != 'Completed');
                
            System.debug('SV: ' + sv.Id + 
                         ' Status: ' + sv.Status__c + 
                         ' Lead: ' + sv.CLead__c + 
                         ' ChangedToCompleted: ' + changedToCompleted);

            if (changedToCompleted && sv.CLead__c != null && !leadsToUpdate.containsKey(sv.CLead__c)) {
                leadsToUpdate.put(sv.CLead__c,
                    new Lead__c(
                        Id = sv.CLead__c,
                        Site_Visit_Done__c = 'Yes'
                    )
                );
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate.values();
            System.debug('Updated Leads: ' + leadsToUpdate.size());
        }
    }
    
}