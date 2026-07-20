public without sharing class pushToSalesController {
    
    public static Boolean pushToSales=true;
    @auraEnabled
    public static string moveToSales(string LeadId,string addNote, string salesUser){
        pushToSales = true;
        Lead__c ld = [SELECT Id,Lead_Status__c,Pre_sales_user__c,OwnerId,Lead_Transfer_Note__c,RecordTypeId,Lead_Assigned__c,Allocated_Project__c,Pushed_On__c,Pushed_By__c,phone__c	 FROM Lead__c WHERE Id=:LeadId];
        //ld.status ='Qualified';
        ld.Pre_sales_user__c = ld.OwnerId;
        ld.Old_Owner_Name__c = ld.OwnerId;
        ld.RecordTypeId = Schema.SObjectType.Lead__c.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
        if (String.isNotBlank(salesUser)) {
           ld.OwnerId =  salesUser;
           ld.Lead_Assigned__c = true; 
        }
        else{
            ld.Lead_Assigned__c = false;
        }
        
        //ld.Projects__c = projectType;
        //ld.Allocated_Project__c = project;
        ld.Lead_Status__c = 'New sales enquiry';
        ld.Pushed_On__c = system.now();
        ld.Pushed_By__c = UserInfo.getUserId();
        ld.IsPushed__c=true;
        ld.Lead_Transfer_Note__c=addNote;
        
        update ld;

        // Re-query lead to get actual OwnerId after round-robin assignment in BEFORE trigger
        Lead__c updatedLd = [SELECT Id, OwnerId, Pre_Sales_User__c, Old_Owner_Name__c FROM Lead__c WHERE Id = :LeadId];

        // Check for scheduled SVs and update lead status to 'Site Visit Scheduled' if any exist
        List<Site_Visit__c> svList = [SELECT Id, OwnerId, Owner_Changed__c, Status__c FROM Site_Visit__c WHERE CLead__c = :LeadId AND (Status__c = 'Scheduled' OR Status__c = 'Rescheduled')];
        if (!svList.isEmpty()) {
            Boolean hasScheduledSV = false;
            for (Site_Visit__c sv : svList) {
                if (sv.Status__c == 'Scheduled') {
                    hasScheduledSV = true;
                    break;
                }
            }
            if (hasScheduledSV) {
                updatedLd.Lead_Status__c = 'Site Visit Scheduled';
                update updatedLd;
            }
        }

        // Share Lead with pre-sales user (Read access); fall back to old owner if pre-sales user is blank
        Id shareUserId = updatedLd.Pre_Sales_User__c != null
            ? updatedLd.Pre_Sales_User__c
            : updatedLd.Old_Owner_Name__c;

        if (shareUserId != null) {
            Lead__Share ls = new Lead__Share();
            ls.ParentId = updatedLd.Id;
            ls.UserOrGroupId = shareUserId;
            ls.AccessLevel = 'Read';
            ls.RowCause = Schema.Lead__Share.RowCause.Manual;
            Database.insert(ls, false);
        }

        // Reassign ALL Follow-ups on this lead to the round-robin-assigned sales owner
        // so the pre-sales user loses edit access (Follow_up__c OWD is Private),
        // then grant the pre-sales user read-only visibility via Follow_up__Share.
        List<Follow_up__c> fupList = [SELECT Id, OwnerId FROM Follow_up__c WHERE CLead__c = :LeadId];
        if (!fupList.isEmpty()) {
            for (Follow_up__c fup : fupList) {
                fup.OwnerId = updatedLd.OwnerId;
            }
            update fupList;

            if (shareUserId != null) {
                List<Follow_up__Share> fuShares = new List<Follow_up__Share>();
                for (Follow_up__c fup : fupList) {
                    fuShares.add(new Follow_up__Share(
                        ParentId = fup.Id,
                        UserOrGroupId = shareUserId,
                        AccessLevel = 'Read',
                        RowCause = Schema.Follow_up__Share.RowCause.Manual
                    ));
                }
                Database.insert(fuShares, false);
            }
        }

        // Reassign scheduled/rescheduled Site Visits to the round-robin-assigned sales owner
        if (!svList.isEmpty()) {
            for (Site_Visit__c sv : svList) {
                sv.OwnerId = updatedLd.OwnerId;
                sv.Owner_Changed__c = true;
            }
            update svList;
        }

        return updatedLd.Id;
    }
 @auraEnabled
    public static Integer CheckFollowups(string LeadId){
        List<Follow_up__c>fplist = [SELECT Id, Name, Status__c, OwnerId, SLead__c FROM Follow_up__c WHERE Status__c='Scheduled' AND SLead__c=:LeadId];
        return fplist.size();
    }
    @AuraEnabled
    public static Boolean isSiteVisitScheduled(string LdId) {
        system.debug('Inside the the validation' + LdId);
        List<Site_Visit__c> sitelst = [select id,Status__c from Site_Visit__c where SLead__c =: LdId and Status__c='Scheduled'];
        System.debug(sitelst.size());
        if(sitelst.isEmpty()){
            return false;
        }
        else{
            return true;
        }
       
    }
  
}