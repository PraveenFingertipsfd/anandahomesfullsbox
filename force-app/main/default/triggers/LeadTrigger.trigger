trigger LeadTrigger on Lead__c (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    if(label.Enable_Trigger=='TRUE'){
        system.debug(utility.runLeadTrigger);
        if(Utility.runLeadTrigger  != false){
            
            if (Trigger.isBefore) {
                if (Trigger.isInsert) {
                    
                    
                    user u = [SELECT Id,Name,Profile.Name FROM user WHERE Id=:userinfo.getUserId()];
                    RelatedSourceHandler.checkMobileNumber(trigger.new);
                    RelatedSourceHandler.mapCampaignLookup(trigger.new);
                    RelatedSourceHandler.duplicateCheck2(trigger.new);

                    list<Lead__c> PreSalesLeads = new list<Lead__c>();
                    list<Lead__c> WalkinLeads = new list<Lead__c>();
                    
                    // if leads are creating by admin then it will go to roundrobin, if lead is creating by other user it will assign same user.
                    if(u.Profile.Name =='System Administrator' || u.Profile.Name =='Lead Capture Profile' || u.Profile.Name == 'Routecall API Profile'
                       ||u.Profile.Name == 'Minimum Access - API Only Integrations'||u.Profile.Name == 'LeadInsert Profile' ||u.Profile.Name == 'Front Office' 
                       ||u.Profile.Name == 'pulse Profile' || u.Profile.Name == 'Call Profile' || u.Profile.Name == 'LeadPush Profile')
                    {
                        for(Lead__c ld : trigger.new){
                            if(ld.Lead_source__c =='Walk-in'){
                                system.debug('Inside the Walking- In Leads');
                                ld.RecordTypeId=Schema.SObjectType.Lead__c.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                                ld.Lead_Status__c='New sales enquiry';
                                if(!ld.Round_Robin_Off__c && !ld.Lead_Assigned__c){
                                    WalkinLeads.add(ld); 
                                }
                            }
                            else{
                                ld.RecordTypeId=Schema.SObjectType.Lead__c.getRecordTypeInfosByName().get('Pre Sales').getRecordTypeId();
                                PreSalesLeads.add(ld);
                            }
                        }
                        
                        if(PreSalesLeads.size()>0){
                            RoundRobinHandler.assignLead(PreSalesLeads,false,'Pre Sales'); 
                        }
                        if(WalkinLeads.size()>0){
                            RoundRobinHandler.assignLead(WalkinLeads,false,'Sales'); 
                        }
                        
                    }else{
                        for(Lead__c ld : trigger.new){
                            ld.Lead_Assigned__c = true;
                            if(ld.Lead_source__c =='Walk-in'){
                                ld.RecordTypeId=Schema.SObjectType.Lead__c.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                                ld.Lead_Status__c='New sales enquiry';
                            }
                        }
                    }
                    
                    
                    
                }
                /*if (Trigger.isUpdate) {
                    system.debug('on update');
                    
                    List<Lead__c> preSalesLdList = new List<Lead__c>();
                    List<Lead__c> salesLdList = new List<Lead__c>();
                    Set<String> phonePrjSet = new Set<String>();
                    
                    //-----------For Checking Duplicate while edit the Primary Phone or Secondary Phone
                    For(Lead__c ld : Trigger.New){
                        if (ld.Phone__c!= Trigger.oldmap.get(ld.Id).Phone__c && ld.Phone__c != null) {
                            phonePrjSet.add(ld.Phone__c);
                        }
                        else if (ld.Secondary_Phone__c!= Trigger.oldmap.get(ld.Id).Secondary_Phone__c && ld.Secondary_Phone__c != null) {
                            phonePrjSet.add(ld.Secondary_Phone__c);
                        }
                        else if (ld.Spouse_Phone__c!= Trigger.oldmap.get(ld.Id).Spouse_Phone__c && ld.Spouse_Phone__c != null) {
                            phonePrjSet.add(ld.Spouse_Phone__c);
                        }
                        
                        if (ld.Lead_status__c != Trigger.oldmap.get(ld.Id).Lead_status__c && ld.Lead_status__c=='New' && !ld.Lead_Assigned__c && !ld.Lead_Transfered__c){
                            preSalesLdList.add(ld);
                        }else if(ld.Lead_status__c=='New sales enquiry' && pushToSalesController.pushToSales && !ld.Lead_Assigned__c){
                            salesLdList.add(ld);
                        }
                    }
                    if(phonePrjSet.size()>0 ){
                        
                        List<Lead__c> oldLeadList = [SELECT Id, Lead_ID__c, Phone__c, Secondary_Phone__c, Spouse_Phone__c, Allocated_Project__c, PhoneProject__c, Secondary_Phone_Project__c, SpousePhoneProject__c
                                                  FROM Lead__c  WHERE (PhoneProject__c IN :phonePrjSet OR Secondary_Phone_Project__c IN :phonePrjSet OR SpousePhoneProject__c IN :phonePrjSet) ORDER BY CreatedDate ASC ];
                        
                        List<Related_Source__c> oldList = [SELECT Id, Name, PhoneProject__c, SecondaryPhoneProject__c, New_Lead__c 
                                                           FROM Related_Source__c WHERE (PhoneProject__c IN :phonePrjSet OR SecondaryPhoneProject__c IN :phonePrjSet) AND New_Lead__c != null ORDER BY CreatedDate ASC];
                        
                        Map<String, Id> phonePrjMap = new Map<String, Id>();
                        
                        for (Lead__c oldLd : oldLeadList) {
                            if (oldLd.PhoneProject__c != null)
                                phonePrjMap.put(oldLd.PhoneProject__c, oldLd.Id);
                            if (oldLd.Secondary_Phone_Project__c != null)
                                phonePrjMap.put(oldLd.Secondary_Phone_Project__c, oldLd.Id);
                            if (oldLd.SpousePhoneProject__c != null)
                                phonePrjMap.put(oldLd.SpousePhoneProject__c, oldLd.Id);
                        }
                        
                        for (Related_Source__c oldRs : oldList) {
                            if (oldRs.PhoneProject__c != null) 
                                phonePrjMap.put(oldRs.PhoneProject__c, oldRs.New_Lead__c);
                            if (oldRs.SecondaryPhoneProject__c != null) 
                                phonePrjMap.put(oldRs.SecondaryPhoneProject__c, oldRs.New_Lead__c);
                        }
                        
                        // Validation on new leads
                        for (Lead__c nld : Trigger.new) {
                            String phoneKey = nld.PhoneProject__c;
                            String secPhoneKey = nld.Secondary_Phone_Project__c;
                            String spoPhoneKey = nld.SpousePhoneProject__c;
                            
                            if (phoneKey != null && phonePrjMap.containsKey(phoneKey) && phonePrjMap.get(phoneKey) != nld.Id) {
                                nld.addError('Lead with the same phone number already exists for this project.');
                            }
                            if (secPhoneKey != null && phonePrjMap.containsKey(secPhoneKey) && phonePrjMap.get(secPhoneKey) != nld.Id) {
                                nld.addError('Lead with the same secondary phone number already exists for this project.');
                            }
                            if (spoPhoneKey != null && phonePrjMap.containsKey(spoPhoneKey) && phonePrjMap.get(spoPhoneKey) != nld.Id) {
                                nld.addError('Lead with the same spouse phone number already exists for this project.');
                            }
                        }
                    }
                    
                    if(preSalesLdList.size()>0){
                        RoundRobinHandler.assignLead(preSalesLdList,false,'Pre Sales');
                    }
                    if(salesLdList.size()>0){
                        RoundRobinHandler.assignLead(salesLdList,false,'Sales');
                    }
                } */
                if (Trigger.isUpdate) {
                    system.debug('on update');
                    
                    List<Lead__c> preSalesLdList = new List<Lead__c>();
                    List<Lead__c> salesLdList = new List<Lead__c>();
                    Set<String> keySet = new Set<String>();
                    
                    // Collect changed phone composite keys
                    for(Lead__c ld : Trigger.New){
                        if (ld.Phone__c != Trigger.oldmap.get(ld.Id).Phone__c && ld.PhoneProject__c != null) {
                            keySet.add(ld.PhoneProject__c);
                        }
                        if (ld.Secondary_Phone__c != Trigger.oldmap.get(ld.Id).Secondary_Phone__c && ld.Secondary_Phone_Project__c != null) {
                            keySet.add(ld.Secondary_Phone_Project__c);
                        }

                        if (ld.Lead_status__c != Trigger.oldmap.get(ld.Id).Lead_status__c && ld.Lead_status__c=='New' && !ld.Lead_Assigned__c && !ld.Lead_Transfered__c){
                            preSalesLdList.add(ld);
                        } else if(ld.Lead_status__c=='New sales enquiry' && pushToSalesController.pushToSales && !ld.Lead_Assigned__c && !ld.Round_Robin_Off__c){
                            salesLdList.add(ld);
                        }
                    }
                    
                    if(keySet.size() > 0){
                        
                        List<Lead__c> oldLeadList = [SELECT Id, Lead_ID__c, Phone__c, Secondary_Phone__c, Allocated_Project__c, PhoneProject__c,
                                                     Secondary_Phone_Project__c
                                                     FROM Lead__c WHERE (PhoneProject__c IN :keySet OR Secondary_Phone_Project__c IN :keySet) ORDER BY CreatedDate ASC];

                        List<Related_Source__c> oldList = [SELECT Id, Name, PhoneProject__c, SecondaryPhoneProject__c, CLead__c
                                                           FROM Related_Source__c WHERE (PhoneProject__c IN :keySet OR SecondaryPhoneProject__c IN :keySet) AND CLead__c != null  ORDER BY CreatedDate ASC];
                        
                        Map<String, Id> keyMap = new Map<String, Id>();
                        
                        for (Lead__c oldLd : oldLeadList) {
                            if (oldLd.PhoneProject__c != null)
                                keyMap.put(oldLd.PhoneProject__c, oldLd.Id);
                            if (oldLd.Secondary_Phone_Project__c != null)
                                keyMap.put(oldLd.Secondary_Phone_Project__c, oldLd.Id);
                        }

                        for (Related_Source__c oldRs : oldList) {
                            if (oldRs.PhoneProject__c != null)
                                keyMap.put(oldRs.PhoneProject__c, oldRs.CLead__c);
                            if (oldRs.SecondaryPhoneProject__c != null)
                                keyMap.put(oldRs.SecondaryPhoneProject__c, oldRs.CLead__c);
                        }

                        // Validation on updating leads
                        for (Lead__c nld : Trigger.new) {
                            if (nld.PhoneProject__c != null && keyMap.containsKey(nld.PhoneProject__c) && keyMap.get(nld.PhoneProject__c) != nld.Id) {
                                nld.addError('Lead with the same phone number already exists.');
                            }
                            if (nld.Secondary_Phone_Project__c != null && keyMap.containsKey(nld.Secondary_Phone_Project__c) && keyMap.get(nld.Secondary_Phone_Project__c) != nld.Id) {
                                nld.addError('Lead with the same secondary phone number already exists.');
                            }
                        }
                    }
                    
                    if(preSalesLdList.size() > 0){
                        RoundRobinHandler.assignLead(preSalesLdList, false, 'Pre Sales');
                    }
                    if(salesLdList.size() > 0){
                        RoundRobinHandler.assignLead(salesLdList, false, 'Sales');
                    }
                }
                if (Trigger.isDelete) {
                    Set<Id> leadIdsToCheck = new Set<Id>();
                    
                    // Collect the IDs of the leads being deleted
                    for (Lead__c ld : Trigger.old) {
                        leadIdsToCheck.add(ld.Id);
                    }
                    
                    // Query related records from Site_Visit__c, Quote__c, Follow_up__c, and Booking__c
                    List<Site_Visit__c> siteVisits = [SELECT Id FROM Site_Visit__c WHERE CLead__c IN :leadIdsToCheck LIMIT 1];
                    List<Quote__c> quotes = [SELECT Id FROM Quote__c WHERE CLead__c IN :leadIdsToCheck LIMIT 1];
                    List<Follow_up__c> followUps = [SELECT Id FROM Follow_up__c WHERE CLead__c IN :leadIdsToCheck LIMIT 1];
                    List<Booking__c> bookings = [SELECT Id FROM Booking__c WHERE CLead__c IN :leadIdsToCheck LIMIT 1];
                    //List<Related_Source__c> RelatedSources = [SELECT Id FROM Related_Source__c WHERE New_Lead__c IN :leadIdsToCheck LIMIT 1];
                    
                    // Check if any related records exist
                    if (!siteVisits.isEmpty() || !quotes.isEmpty() || !followUps.isEmpty() || !bookings.isEmpty() ) {
                        // Prevent the deletion by adding an error to each Lead record
                        for (Lead__c ld : Trigger.old) {
                            ld.addError('Please delete related child records (Site Visits, Quotes, Follow-ups, Related Sources, or Bookings) before deleting this Lead.');
                        }
                    } 
                }
            }



            /* ── BEFORE INSERT ────────────────────────────────────── Added By pattu 05/03/26
            if (Trigger.isBefore) {
                if (Trigger.isInsert) {

                    // ✅ ADD THIS LINE (campaign validation — before existing logic)
                    RelatedSourceHandler.handleCampaignValidation(Trigger.new, null);

                    user u = [SELECT Id,Name,Profile.Name FROM user WHERE Id=:userinfo.getUserId()];
                    RelatedSourceHandler.checkMobileNumber(trigger.new);
                    RelatedSourceHandler.duplicateCheck2(trigger.new);
                    
                }

            // ── BEFORE UPDATE ──────────────────────────────────────────────────
                if (Trigger.isUpdate) {

                    // ✅ ADD THIS LINE (campaign validation — before existing logic)
                    RelatedSourceHandler.handleCampaignValidation(Trigger.new, Trigger.oldMap);

                    system.debug('on update');
                    
                }
            }
            */
            if (Trigger.isAfter) {
                if (Trigger.isInsert) {
                    RelatedSourceHandler.afterinsertLogic2(trigger.new);
                } 
                if (Trigger.isUpdate) {
                    /* 
List<Lead__c> nonRespondedLeads = new List<Lead__c>();
for (Lead__c newLead : Trigger.new) {
Lead__c oldLead = Trigger.oldMap.get(newLead.Id);
if (newLead.Not_Responded__c == true && oldLead.Not_Responded__c != true) {
nonRespondedLeads.add(newLead);
}
}

// Only process if we have qualifying leads
if (!nonRespondedLeads.isEmpty()) {
GupshupWhatsAppHelper.processUpdatedLeadsForNonResponded(
nonRespondedLeads,
Trigger.oldMap
);
}*/
                    Set<Id> cpOwnerChangeLeads = new Set<Id>(); //added by karthik 16-01-26
                    Integer expiryDays = Integer.valueOf(Label.CP_Lead_Expiry_Days);
                    Date expiryCutoffDate = Date.today().addDays(-expiryDays);
                    
                    Set<Id> lostWinLeads = new Set<Id>();
                    Set<Id> cancelFollowupLeads = new Set<Id>();
                    Set<Id> ownerChange = new Set<Id>();
                    List<Lead__c> ldList = new List<Lead__c>();
                    List<Lead__c> toshare = new List<Lead__c>();
                    for(Lead__c con : Trigger.new){
                        system.debug(Trigger.oldmap.get(con.Id).lead_status__c );
                        system.debug(con.Lead_status__c );
                        if(con.Lead_status__c!=Trigger.oldmap.get(con.Id).lead_status__c && (con.Lead_status__c=='Unqualified' || con.Lead_status__c=='Closed Lost' || con.Lead_Status__c=='Booked')){
                            lostWinLeads.add(con.Id);
                        }
                        // Follow-ups are only cancelled for Unqualified / Closed Lost — NOT Booked
                        // (post-booking follow-ups must stay open), unlike Site Visits below.
                        if(con.Lead_status__c!=Trigger.oldmap.get(con.Id).lead_status__c && (con.Lead_status__c=='Unqualified' || con.Lead_status__c=='Closed Lost')){
                            cancelFollowupLeads.add(con.Id);
                        }
                        if(con.OwnerId!=Trigger.oldmap.get(con.Id).OwnerId && con.Lead_status__c!='Unqualified' && con.Lead_status__c!='Closed Lost'){
                            ownerChange.add(con.Id);
                        }
                        //added by karthik 16-01-26 
                        if (con.OwnerId != Trigger.oldMap.get(con.Id).OwnerId && con.Criteria_Date__c != null && con.Criteria_Date__c > expiryCutoffDate) {
                            cpOwnerChangeLeads.add(con.Id);
                        }

                    }
                    
                    //Sharing the Lead to Pre sales with view Access
                    /*system.debug('inside the view access for the pre sales');
                    List<Lead__c> ldListShare = new List<Lead__c>();
                    List<Lead__c> ldListShareToRecovery = new List<Lead__c>();
                    Map<Id,Id> LdSPMap = new Map<Id,Id>();
                    
                    for(Lead__c con : Trigger.New){
                        system.debug('Pre sales user' +con.Pre_sales_user__c);
                        if(con.Pre_sales_user__c != null){
                            system.debug('Pre sales user if is breached ------- ');
                            ldListShare.add(con);
                        }
                    }
                    if(ldListShare.size()>0){
                        system.debug('called the share record ------- ');
                        manualSharingClass.shareAnyRecord(ldListShare,'Read');
                    }*/
                    
                    if(lostWinLeads.size()>0){
                        List<site_visit__c> svList = [SELECT Id,Name,status__c,Canceled_Reason__c FROM site_visit__c WHERE CLead__c IN: lostWinLeads and status__c = 'Scheduled'];
                        if(svList.size()>0){
                            for(site_visit__c sv : svList){
                                sv.status__c='Cancelled';
                                sv.Canceled_Reason__c = 'The system has cancelled the action as the Lead stage was updated	';
                            }
                            try{
                                Update svList;  
                            }catch(Exception e){
                                System.debug('Error occurred while updating: ' + e.getMessage());
                                
                            }
                            
                        }
                    }
                    if(cancelFollowupLeads.size()>0){
                        List<Follow_up__c> fuList = [SELECT Id,Status__c,Comments__c FROM Follow_up__c WHERE CLead__c IN :cancelFollowupLeads AND Status__c IN ('Scheduled','Pending')];
                        if(fuList.size()>0){
                            for(Follow_up__c fu : fuList){
                                fu.Status__c = 'Cancelled';
                                if(String.isBlank(fu.Comments__c)){
                                    fu.Comments__c = 'The system has cancelled the follow-up as the Lead stage was updated';
                                }
                            }
                            try{
                                Update fuList;
                            }catch(Exception e){
                                System.debug('Error occurred while updating follow-ups: ' + e.getMessage());
                            }
                        }
                    }
                    if(ownerChange.size()>0){
                        /*List<Follow_up__c> fwList = [SELECT Id,Name,OwnerId,New_Lead__r.ownerId FROM Follow_Up__c WHERE New_Lead__c IN: ownerChange and status__c='Scheduled'];
                        if(fwList.size()>0){
                            for(Follow_Up__c fw : fwList){
                                fw.ownerId = fw.New_Lead__r.OwnerId;
                            }
                            Update fwList;
                        }
                        List<site_visit__c> fwList1 = [SELECT Id,Name,OwnerId,New_Lead__r.ownerId,New_Lead__c,New_Lead__r.Id,New_Lead__r.Pre_sales_user__c FROM site_visit__c WHERE New_Lead__c IN: ownerChange];
                        if(fwList1.size()>0){
                            for(site_visit__c fw1 : fwList1){
                                fw1.ownerId = fw1.New_Lead__r.OwnerId;
                            }
                            Update fwList1;
                        }
						*/      
                    }
                    
                    // ================= CP RE-SHARING LOGIC (Owner Change) =================
                    // Added by Karthik – 16-01-26
                    
                    if (!cpOwnerChangeLeads.isEmpty()) {
                            
                            // CP Owner → Leads map
                            Map<Id, Set<Id>> cpOwnerToLeadMap = new Map<Id, Set<Id>>();
                            
                            for (Related_Source__c rs : [SELECT CLead__c, Channel_Partner__r.OwnerId FROM Related_Source__c
                                                         WHERE CLead__c IN :cpOwnerChangeLeads AND Channel_Partner__c != null]) {
                                
                                if (rs.Channel_Partner__r.OwnerId == null) continue;
                                
                                if (!cpOwnerToLeadMap.containsKey(rs.Channel_Partner__r.OwnerId)) {
                                    cpOwnerToLeadMap.put(rs.Channel_Partner__r.OwnerId, new Set<Id>());
                                }
                                
                                cpOwnerToLeadMap.get(rs.Channel_Partner__r.OwnerId).add(rs.CLead__c);
                            }
                            
                            if (!cpOwnerToLeadMap.isEmpty()) {
                                
                                // Flatten Lead Ids
                                Set<Id> allLeadIds = new Set<Id>();
                                for (Set<Id> leadSet : cpOwnerToLeadMap.values()) {
                                    allLeadIds.addAll(leadSet);
                                }
                                
                                // NOTE: Custom Lead__c object requires custom sharing implementation
                                // Standard LeadShare object only works with standard Lead object
                                // You'll need to create a custom sharing object Lead__Share or implement manual sharing
                                
                                /* CUSTOM SHARING IMPLEMENTATION NEEDED HERE
                                // Example pattern if you have Lead__Share custom object:
                                Set<String> existingShares = new Set<String>();
                                for (Lead__Share ls : [SELECT ParentId, UserOrGroupId FROM Lead__Share WHERE ParentId IN :allLeadIds
                                                      AND UserOrGroupId IN :cpOwnerToLeadMap.keySet()]) {
                                    existingShares.add(ls.ParentId + '-' + ls.UserOrGroupId);
                                }
                                
                                List<Lead__Share> sharesToInsert = new List<Lead__Share>();
                                
                                for (Id cpOwnerId : cpOwnerToLeadMap.keySet()) {
                                    for (Id leadId : cpOwnerToLeadMap.get(cpOwnerId)) {
                                        
                                        String key = leadId + '-' + cpOwnerId;
                                        if (existingShares.contains(key)) {
                                            continue;
                                        }
                                        
                                        Lead__Share ls = new Lead__Share();
                                        ls.ParentId = leadId;
                                        ls.UserOrGroupId = cpOwnerId;
                                        ls.AccessLevel = 'Read';
                                        ls.RowCause = 'Manual';
                                        
                                        sharesToInsert.add(ls);
                                    }
                                }
                                
                                if (!sharesToInsert.isEmpty()) {
                                    insert sharesToInsert;
                                }
                                */
                            }
                        
                    }
                    // ================= END CP RE-SHARING LOGIC =================

                }
            } 
        }
    }
}