public without sharing class RelatedSourceHandler {
    
    public static List<Lead__c> deleteList = new List<Lead__c>();
    public static List<Lead__c> updateList = new List<Lead__c>();
    public static List<Related_source__c> rsList = new List<Related_source__c>();
    public static Map<Id,Lead__c> matchedMap = new  Map<Id,Lead__c>();
    public static datetime startTime;
    public static datetime endTime;
    
    // this method will segrate phone number and country code 
    public static void checkMobileNumber(List<Lead__c> newRecordsList) {
        
        Map<String, String> countryCodeMap = Utility.getAllCountryCodeMappings(true); 
        List<Lead__c> contactItems = newRecordsList;
        for( Lead__c contact : contactItems ) { 
            boolean phone=true; 
            boolean secondaryPhone=true;
            if(contact.Phone__c != null){
                contact.Phone__c = contactFormatter.getformated(contact.Phone__c);
            }
            
            if(contact.Phone__c != null && contact.Phone__c.startsWith('+')){
                contact.Phone__c = contact.Phone__c.removeStart('+');
                if(contact.Phone__c != null && contact.Phone__c.startsWith('91')){
                    contact.Country_Code__c = '91';
                    contact.Country__c = countryCodeMap.get('91');
                    contact.Phone__c = contact.Phone__c.removeStart('91');
                }
                else{
                    
                    for(String countryCode : countryCodeMap.keySet()){
                        if(contact.Phone__c != null && contact.Phone__c.startsWith(countryCode) && phone){
                            contact.Country_Code__c = countryCode;
                            contact.Country__c = countryCodeMap.get(countryCode);
                            contact.Phone__c = contact.Phone__c.removeStart(countryCode);
                            phone = false;
                        }
                    }
                }
            }
            if(contact.Secondary_Phone__c != null && contact.Secondary_Phone__c.startsWith('+')){
                contact.Secondary_Phone__c = contact.Secondary_Phone__c.removeStart('+');
                if(contact.Secondary_Phone__c  != null && contact.Secondary_Phone__c .startsWith('91')){
                    contact.Secondary_Country_Code__c = '91';
                    contact.Secondary_Country__c = countryCodeMap.get('91');
                    contact.Secondary_Phone__c = contact.Secondary_Phone__c.removeStart('91');
                }else{
                    for(String countryCode : countryCodeMap.keySet()){
                        if(contact.Secondary_Phone__c != null && contact.Secondary_Phone__c.startsWith(countryCode) && secondaryPhone){
                            contact.Secondary_Country_Code__c = countryCode;
                            contact.Secondary_Country__c = countryCodeMap.get(countryCode);
                            contact.Secondary_Phone__c = contact.Secondary_Phone__c.removeStart(countryCode);
                            secondaryPhone = false;
                        }
                    }  
                }
            }
            if(contact.Phone__c != null && contact.Country__c == null &&   contact.Country_Code__c  == null){
                contact.Country_Code__c = '91';
                contact.Country__c = countryCodeMap.get('91');
            }
            if(contact.Secondary_Phone__c != null && contact.Secondary_Country__c == null){
                contact.Secondary_Country_Code__c = '91';
                contact.Secondary_Country__c = countryCodeMap.get('91');
            }
        }
    }
    
    /* Duplication check with only contact info (phone,secondary phone,spouse phone)
    public static void duplicateCheck2(List<Lead__c> ldList){
        Set <String> PhoneSet = new Set<String>();
        Set <String> mailSet = new Set<String>();
        for(Lead__c ld : ldList){
            if(ld.Phone__c !=null){
                PhoneSet.add(ld.Phone__c);
            }
            if(ld.Secondary_Phone__c !=null){
                PhoneSet.add(ld.Secondary_Phone__c);
            }
            if(ld.Spouse_Phone__c !=null){
                PhoneSet.add(ld.Spouse_Phone__c);
            }
        }
        system.debug('---'+PhoneSet);
        List<Lead__c> oldLeadList = [SELECT Id,PhoneProject__c,Secondary_Phone_Project__c,Phone__c,Spouse_Phone__c,SpousePhoneProject__c,Email__c,Secondary_phone__c,Secondary_Email__c FROM Lead__c WHERE (PhoneProject__c IN : PhoneSet OR Secondary_Phone_Project__c IN :PhoneSet OR SpousePhoneProject__c IN :PhoneSet) ORDER BY CreatedDate ASC];
        system.debug(oldLeadList.size());
        if(oldLeadList.size()>0){
            Map<string,Lead__c> PhoneMap = new Map<string,Lead__c>();
            
            for(Lead__c old : oldLeadList){
                if(old.PhoneProject__c !=null){
                    PhoneMap.put(old.PhoneProject__c,old);
                }
                if(old.Secondary_Phone_Project__c !=null){
                    PhoneMap.put(old.Secondary_Phone_Project__c,old);
                }
                if(old.SpousePhoneProject__c !=null){
                    PhoneMap.put(old.SpousePhoneProject__c,old);
                }
            }
            for(Lead__c nld : ldList){
                if(nld.Phone__c !=null && PhoneMap.containsKey(nld.Phone__c)){
                    nld.Delete_Lead__c = true;
                    nld.Main_Lead__c = PhoneMap.get(nld.Phone__c).Id;
                }else if(nld.Secondary_phone__c !=null && PhoneMap.containsKey(nld.Secondary_phone__c)){
                    nld.Delete_Lead__c = true;
                    nld.Main_Lead__c = PhoneMap.get(nld.Secondary_phone__c).Id;
                }else if(nld.Spouse_Phone__c !=null && PhoneMap.containsKey(nld.Spouse_Phone__c)){
                    nld.Delete_Lead__c = true;
                    nld.Main_Lead__c = PhoneMap.get(nld.Spouse_Phone__c).Id;
                }
            }
        }
        else{
            List<Related_Source__c> oldList = [SELECT Id,Name,PhoneProject__c,SecondaryPhoneProject__c,New_Lead__c 
                                               FROM Related_Source__c 
                                               WHERE (PhoneProject__c IN : PhoneSet OR SecondaryPhoneProject__c IN :PhoneSet) 
                                               AND New_Lead__c!=null ORDER BY CreatedDate ASC];
            system.debug(oldList);            
            Map<string,Related_Source__c> PhoneMap = new Map<string,Related_Source__c>();
            
            if(oldList.size() >0){
                for(Related_Source__c old : oldList){
                    
                    if(old.PhoneProject__c !=null){
                        PhoneMap.put(old.PhoneProject__c,old);
                    }
                    if(old.SecondaryPhoneProject__c !=null){
                        PhoneMap.put(old.SecondaryPhoneProject__c,old);
                    }
                }
                
                for(Lead__c nld : ldList){
                    if(nld.Phone__c !=null && PhoneMap.containsKey(nld.Phone__c)){
                        nld.Delete_Lead__c = true;
                        nld.Main_Lead__c = PhoneMap.get(nld.Phone__c).New_Lead__c;
                    }else if(nld.Secondary_phone__c !=null && PhoneMap.containsKey(nld.Secondary_phone__c)){
                        nld.Delete_Lead__c = true;
                        nld.Main_Lead__c = PhoneMap.get(nld.Secondary_phone__c).New_Lead__c;
                    }
                    else if(nld.Spouse_Phone__c !=null && PhoneMap.containsKey(nld.Spouse_Phone__c)){
                        nld.Delete_Lead__c = true;
                        nld.Main_Lead__c = PhoneMap.get(nld.Spouse_Phone__c).New_Lead__c;
                    }
                } 
            }
        }
    }
*/
    
    // Duplication check based on phone, secondary phone, email, secondary email and project
    public static void duplicateCheck2(List<Lead__c> ldList){
        Set<String> keySet = new Set<String>();
        
        for(Lead__c ld : ldList){
            if(ld.PhoneProject__c != null){
                keySet.add(ld.PhoneProject__c);
            }
            if(ld.Secondary_Phone_Project__c != null){
                keySet.add(ld.Secondary_Phone_Project__c);
            }
        }
        
        system.debug('---keySet: ' + keySet);
        
        if(keySet.isEmpty()) return;
        
        List<Lead__c> oldLeadList = [SELECT Id, PhoneProject__c, Secondary_Phone_Project__c, Phone__c, Secondary_Phone__c
                                     FROM Lead__c WHERE (PhoneProject__c IN :keySet OR Secondary_Phone_Project__c IN :keySet) ORDER BY CreatedDate ASC];
        
        system.debug(oldLeadList.size());
        
        if(oldLeadList.size() > 0){
            Map<String, Lead__c> keyMap = new Map<String, Lead__c>();
            
            for(Lead__c old : oldLeadList){
                if(old.PhoneProject__c != null){
                    keyMap.put(old.PhoneProject__c, old);
                }
                if(old.Secondary_Phone_Project__c != null){
                    keyMap.put(old.Secondary_Phone_Project__c, old);
                }
            }

            for(Lead__c nld : ldList){
                if(nld.PhoneProject__c != null && keyMap.containsKey(nld.PhoneProject__c)){
                    nld.Delete_Lead__c = true;
                    nld.Main_Lead__c = keyMap.get(nld.PhoneProject__c).Id;
                } else if(nld.Secondary_Phone_Project__c != null && keyMap.containsKey(nld.Secondary_Phone_Project__c)){
                    nld.Delete_Lead__c = true;
                    nld.Main_Lead__c = keyMap.get(nld.Secondary_Phone_Project__c).Id;
                }
            }
        } else {
            List<Related_Source__c> oldList = [SELECT Id, Name, PhoneProject__c, SecondaryPhoneProject__c, CLead__c
                                               FROM Related_Source__c  WHERE (PhoneProject__c IN :keySet OR SecondaryPhoneProject__c IN :keySet) AND CLead__c != null ORDER BY CreatedDate ASC];
            
            system.debug(oldList);
            
            Map<String, Related_Source__c> keyMap = new Map<String, Related_Source__c>();
            
            if(oldList.size() > 0){
                for(Related_Source__c old : oldList){
                    if(old.PhoneProject__c != null){
                        keyMap.put(old.PhoneProject__c, old);
                    }
                    if(old.SecondaryPhoneProject__c != null){
                        keyMap.put(old.SecondaryPhoneProject__c, old);
                    }
                }

                for(Lead__c nld : ldList){
                    if(nld.PhoneProject__c != null && keyMap.containsKey(nld.PhoneProject__c)){
                        nld.Delete_Lead__c = true;
                        nld.Main_Lead__c = keyMap.get(nld.PhoneProject__c).CLead__c;
                    } else if(nld.Secondary_Phone_Project__c != null && keyMap.containsKey(nld.Secondary_Phone_Project__c)){
                        nld.Delete_Lead__c = true;
                        nld.Main_Lead__c = keyMap.get(nld.Secondary_Phone_Project__c).CLead__c;
                    }
                }
            }
        }
    }
    
    
    public static void afterinsertLogic2(List<Lead__c> ldList){
        /*Map<string,Lead__c> newPhoneMap = new Map<string,Lead__c>();
if(ldList.size()>1){
for(Lead__c fnld : ldList){
if(fnld.Phone__c !=null && !newPhoneMap.containsKey(fnld.Phone__c)){
newPhoneMap.put(fnld.Phone__c,fnld);
}
if(fnld.Secondary_phone__c !=null && !newPhoneMap.containsKey(fnld.Secondary_phone__c)){
newPhoneMap.put(fnld.Secondary_phone__c,fnld);
}
if(fnld.Spouse_Phone__c !=null && !newPhoneMap.containsKey(fnld.Spouse_Phone__c)){
newPhoneMap.put(fnld.Phone__c,fnld);
}
}
system.debug(newPhoneMap.size());
}
*/   
        Map<String, Lead__c> newKeyMap = new Map<String, Lead__c>();
        if(ldList.size() > 1){
            for(Lead__c fnld : ldList){
                if(fnld.PhoneProject__c != null && !newKeyMap.containsKey(fnld.PhoneProject__c)){
                    newKeyMap.put(fnld.PhoneProject__c, fnld);
                }
                if(fnld.Secondary_Phone_Project__c != null && !newKeyMap.containsKey(fnld.Secondary_Phone_Project__c)){
                    newKeyMap.put(fnld.Secondary_Phone_Project__c, fnld);
                }
            }
            system.debug(newKeyMap.size());
        }
        
        /*for(Lead__c nld : ldList){
system.debug('-------'+ nld.Delete_Lead__c);
system.debug('-----'+ nld.Main_Lead__c);

if(nld.Delete_Lead__c && nld.Main_Lead__c !=null){
system.debug('====='+nld);
system.debug('-----'+ nld.Main_Lead__c+'--=='+ nld.id);
addRelatedSource(nld);
}else if(nld.Phone__c !=null && NewPhoneMap.containsKey(nld.Phone__c) && nld.Id !=NewPhoneMap.get(nld.Phone__c).Id){
addRelatedSource2(nld,NewPhoneMap.get(nld.Phone__c));
}else if(nld.Secondary_phone__c !=null && NewPhoneMap.containsKey(nld.Secondary_phone__c) && nld.Id !=NewPhoneMap.get(nld.Secondary_phone__c).Id){
addRelatedSource2(nld,NewPhoneMap.get(nld.Secondary_phone__c));
}else if(nld.Spouse_Phone__c !=null && NewPhoneMap.containsKey(nld.Spouse_Phone__c) && nld.Id !=NewPhoneMap.get(nld.Spouse_Phone__c).Id){
addRelatedSource2(nld,NewPhoneMap.get(nld.Spouse_Phone__c));
}*/
        
        for(Lead__c nld : ldList){
            system.debug('-------'+ nld.Delete_Lead__c);
            system.debug('-----'+ nld.Main_Lead__c);
            
            if(nld.Delete_Lead__c && nld.Main_Lead__c != null){
                system.debug('====='+nld);
                system.debug('-----'+ nld.Main_Lead__c+'--=='+ nld.id);
                addRelatedSource(nld);
            } else if(nld.PhoneProject__c != null && newKeyMap.containsKey(nld.PhoneProject__c) && nld.Id != newKeyMap.get(nld.PhoneProject__c).Id){
                addRelatedSource2(nld, newKeyMap.get(nld.PhoneProject__c));
            } else if(nld.Secondary_Phone_Project__c != null && newKeyMap.containsKey(nld.Secondary_Phone_Project__c) && nld.Id != newKeyMap.get(nld.Secondary_Phone_Project__c).Id){
                addRelatedSource2(nld, newKeyMap.get(nld.Secondary_Phone_Project__c));
            }
            else{
                Related_source__c rs = new Related_source__c();
                rs.ERP_Id__c = nld.ERP_Id__c;
                rs.Lead_Name__c = nld.Name__c;
                rs.CLead__c = nld.Id;
                rs.Source__c = nld.Primary_Source__c;
                rs.Sub_Source__c = nld.Primary_Sub_Source__c;
                rs.Source_Type__c = nld.Source_Type__c; //added
                rs.Medium__c = nld.Medium__c; //added
                rs.Referring_Customer_s_Unit__c = nld.Referring_Customer_Unit__c; //added
                rs.Referring_Customer_s_Project__c = nld.Referring_Customer_Project__c; //added
                rs.Referring_Vendor_s_Company_Name__c = nld.Referring_Vendor_Company_Name__c; //added
                rs.Referring_Vendor_s_Id__c = nld.Referring_Vendor_Id__c; //added 
                rs.Referring_Employee_ID__c = nld.Referring_Employee_ID__c; //added
                
                rs.Referral_Source__c = nld.Referral_Source__c; //added
                rs.Referring_For__c = nld.Referring_For__c; //added
                
                rs.Existing_Customer_Info__c = nld.Existing_Customer_Info__c; //added by karthik 16-01-26
                
                //rs.Referral_Type__c = nld.Referral_Type__c; 
                rs.Employee_Id__c = nld.Employee_Id__c;
                rs.Referrer_Name__c = nld.Referrer_Name__c;
                rs.Referrer_Mobile_No__c = nld.Referrer_Mobile_No__c;
                rs.Referrer_Alternate_Mobile_No__c = nld.Referrer_Alternate_Mobile_No__c;
                rs.Referrer_Email__c = nld.Referrer_Email__c;
                rs.Referrer_Alternate_Email__c = nld.Referrer_Alternate_Email__c;
                /*=============== newley added fields by sandeep  completed==============*/
                rs.Country__c = nld.Country__c; //added
                rs.executiveName__c = nld.executiveName__c; //added
                //rs.Referring_Vendor_s_Id__c = nld.channelPartnerName__c; //added
                rs.executivePhone__c = nld.executivePhone__c; //added
                rs.comments__c = nld.Comments__c; //added
                rs.state__c = nld.State__c; //added
                rs.city__c = nld.City__c; //added
                rs.Channel_Partner__c = nld.Channel_Partner__c; //added
                /*=============== newley added fields by sandeep  completed==============*/
                rs.Phone__c = nld.Phone__c; 
                rs.Country_Code__c = nld.Country_Code__c;
                rs.Secondary_Phone__c = nld.Secondary_Phone__c;
                rs.Secondary_Contry_Code__c = nld.Secondary_Country_Code__c;
                rs.Email__c = nld.Email__c;
                rs.Secondary_Email__c = nld.Secondary_Email__c;
                rs.Description__c = nld.Last_Comment__c;
                system.debug('======'+  rs.Description__c);
                rs.Allocated_Project__c = nld.Allocated_Project__c;
                rs.Campaign__c = nld.Campaign_Name__c;
                rs.Campaign_Text__c = nld.Campaign__c;
                rs.type_of_lead__c = nld.Type_of_lead__c;
                rs.Query_For__c = nld.Query_For__c;
                rs.Query_Type__c = nld.Query_Type__c;
                rs.Message__c = nld.Message__c;
                rsList.add(rs);
                if(!matchedMap.containsKey(nld.Id)){
                    system.debug(nld.Id);
                    Lead__c ld = new Lead__c();
                    ld.Id = nld.Id;
                    ld.Last_Source_Of_Enquiry__c =nld.Lead_source__c;
                    ld.Last_Sub_Source__c =  nld.Sub_Source__c;
                    ld.First_Source_Of_Enquiry__c = nld.Lead_source__c;
                    ld.First_Sub_Source__c =  nld.Sub_Source__c;
                    ld.First_Contatced_On__c = system.now();
                    ld.First_Campaign__c = nld.Campaign__c;
                    ld.Last_Campagin__c = nld.Campaign__c;
                    // Set Primary Campaign and Channel Partner for new leads
                    ld.Primary_Campaign__c = nld.Campaign_Name__c;
                    if (nld.Primary_Source__c == 'CP') {
                        ld.Primary_Channel_Partner__c = nld.Channel_Partner__c;
                    }
                    //ld.Last_Re_engaged_On__c = system.now();
                    system.debug(nld.Re_engaged_Count__c);
                    // ld.Re_engaged_Count__c = nld.Re_engaged_Count__c + 1;
                    matchedMap.put(nld.Id,ld);
                }
            }
        }
        
        if(rsList.size() >0){
            insert rsList;
            rsList.clear();
        }
        
        if(matchedMap.size() >0){
            updateList = matchedMap.values();
            update updateList;
            matchedMap.clear();
            updateList.clear();
        }
        if(deleteList.size() >0){
            delete deleteList;
            deleteList.clear();
        }
    }
    
    public static void addRelatedSource(Lead__c nld){
        Related_source__c rs = new Related_source__c();
        rs.Lead_Name__c = nld.Name__c;
        rs.CLead__c = nld.Main_Lead__c;
        rs.ERP_Id__c = nld.ERP_Id__c;
        rs.Source__c = nld.Primary_Source__c;
        rs.Sub_Source__c = nld.Primary_Sub_Source__c;
        rs.Source_Type__c = nld.Source_Type__c; //added
        rs.Medium__c = nld.Medium__c; //added
        rs.Referring_Customer_s_Unit__c = nld.Referring_Customer_Unit__c; //added
        rs.Referring_Customer_s_Project__c = nld.Referring_Customer_Project__c; //added
        rs.Referring_Vendor_s_Company_Name__c = nld.Referring_Vendor_Company_Name__c; //added
        rs.Referring_Vendor_s_Id__c = nld.Referring_Vendor_Id__c; //added
        rs.Referring_Employee_ID__c = nld.Referring_Employee_ID__c; //added
        rs.Employee_Id__c = nld.Employee_Id__c; //added
        rs.Referral_Source__c = nld.Referral_Source__c; //added
        rs.Referring_For__c = nld.Referring_For__c; //added
        
        rs.Existing_Customer_Info__c = nld.Existing_Customer_Info__c; //added by karthik 16-01-26
        
        //rs.Referral_Type__c = nld.Referral_Type__c;
        rs.Referrer_Name__c = nld.Referrer_Name__c;
        rs.Referrer_Mobile_No__c = nld.Referrer_Mobile_No__c;
        rs.Referrer_Alternate_Mobile_No__c = nld.Referrer_Alternate_Mobile_No__c;
        rs.Referrer_Email__c = nld.Referrer_Email__c;
        rs.Referrer_Alternate_Email__c = nld.Referrer_Alternate_Email__c;
          /*=============== newley added fields by sandeep ==============*/
        rs.Country__c = nld.Country__c; //added
        rs.executiveName__c = nld.executiveName__c; //added
        //rs.Referring_Vendor_s_Id__c = nld.channelPartnerName__c; //added
        rs.executivePhone__c = nld.executivePhone__c; //added
        rs.comments__c = nld.Comments__c; //added
        rs.state__c = nld.State__c; //added
        rs.city__c = nld.City__c; //added
         rs.Channel_Partner__c = nld.Channel_Partner__c; //added
             /*=============== newley added fields by sandeep  completed==============*/
        rs.Phone__c = nld.Phone__c;
        rs.Country_Code__c = nld.Country_Code__c;
        rs.Secondary_Phone__c = nld.Secondary_Phone__c;
        rs.Secondary_Contry_Code__c = nld.Secondary_Country_Code__c;
        rs.Email__c = nld.Email__c;
        rs.Secondary_Email__c = nld.Secondary_Email__c;
        rs.Description__c = nld.Last_Comment__c;
        rs.Allocated_Project__c = nld.Allocated_Project__c;
        rs.Campaign__c = nld.Campaign_Name__c;
        rs.Campaign_Text__c = nld.Campaign__c;
        rs.Query_For__c = nld.Query_For__c;
        rs.Query_Type__c = nld.Query_Type__c;
        rs.Message__c = nld.Message__c;
        rs.type_of_lead__c = nld.Type_of_lead__c;
        system.debug('Lead status '+nld.Main_lead_status__c);
        //if(nld.Main_lead_status__c == 'Closed Lost' || nld.Main_lead_status__c == 'Booked'|| nld.Main_lead_status__c =='Unqualified'){
        if(nld.Main_lead_status__c == 'Closed Lost' || nld.Main_lead_status__c =='Unqualified'){
            rs.Lead_Type__c = 'Re-Opened';
        }else{
            rs.Lead_Type__c = 'Re-Engaged';
        }
        rsList.add(rs);
        deleteList.add(new Lead__c(Id=nld.Id));
        Lead__c ld = new Lead__c();
        ld.Id=nld.Main_Lead__c;
        ld.Last_Source_Of_Enquiry__c =nld.Lead_source__c;
        ld.Last_Sub_Source__c =  nld.Sub_Source__c;
        ld.Last_Campagin__c = nld.Campaign__c;
        ld.Need_Pick_Up_Assistance__c = nld.Need_Pick_Up_Assistance__c;
        ld.Comments__c = nld.Comments__c;
        //ld.Re_Engaged_Date__c = system.now();
        //ld.Last_Re_engaged_On__c = system.now();
        //ld.Re_engaged_Count__c = nld.Re_engaged_Count__c + 1;
        system.debug('====='+nld.Main_lead_status__c +'==='+ nld.Main_Pre_Sales_User__c );
        //if( nld.Main_lead_status__c == 'Booked'|| nld.Main_lead_status__c =='Unqualified' || nld.Main_lead_status__c == 'Closed Lost'){
        if(nld.Main_lead_status__c =='Unqualified' || nld.Main_lead_status__c == 'Closed Lost'){
            string RecTypeId;
            if(nld.Main_lead_status__c == 'Unqualified'){
                RecTypeId = Schema.SObjectType.Lead__c.getRecordTypeInfosByName().get('Pre Sales').getRecordTypeId();
                ld.Lead_status__c = 'New Enquiry';
            } else if(nld.Main_lead_status__c == 'Closed Lost'){
                RecTypeId = Schema.SObjectType.Lead__c.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                ld.Lead_status__c = 'New Sales Enquiry';
            }
            system.debug('==='+RecTypeId);

            ld.Latest_Followup_Subject__c = '';
            ld.Re_opened_CP_Date__c = null;
            ld.Re_Engaged_CP_Date__c = null;
            if(nld.Medium__c == 'CHANNEL PARTNERS')
            {
                ld.Re_opened_CP_Date__c = System.today();
            }
            ld.Lead_Assigned__c=true;
            ld.Lead_Transfered__c = false;
            ld.Type_of_lead__c = 'Direct Lead';
            ld.Lead_Type__c ='Re-Opened';
            ld.Is_Called__c = false; //added by karthik 01-12-25
            ld.Comments__c = nld.Comments__c;
            ld.Last_Re_Opened_Date__c = system.now();
            // Update Primary Source and Last Re-engaged details on Re-Open
            ld.Primary_Source__c = nld.Primary_Source__c;
            ld.Primary_Sub_Source__c = nld.Primary_Sub_Source__c;
            ld.Primary_Campaign__c = nld.Campaign_Name__c;
            ld.Last_Source_Of_Enquiry__c = nld.Primary_Source__c;
            ld.Last_Sub_Source__c = nld.Primary_Sub_Source__c;
            ld.Last_Re_engaged_Campaign__c = nld.Campaign_Name__c;
            if (nld.Primary_Source__c == 'CP') {
                ld.Primary_Channel_Partner__c = nld.Channel_Partner__c;
                ld.Last_Re_engaged_Channel_Partner__c = nld.Channel_Partner__c;
            }
            ld.Re_assigned_date__c=null;
            ld.RNR_date__c=null;
            ld.status_change_date__c=null;
            ld.Last_comment__c = '';
            ld.Site_Visit_Schedule_Date__c=null;
            ld.Site_visit_Project__c = null;
            ld.Reassigned_By__c=null;
            ld.Site_Visit_Feedback__c=null;
            ld.Followup_Subject__c=null;
            //ld.Next_follow_up_Date__c=null;
            ld.Next_Followup_Date__c=null;
            ld.Next_Site_visit_Date__c=null;
            ld.Closed_Lost_Reason__c=null;
            ld.Remark_for_Closed_Lost__c=null;
            system.debug('=='+nld.Main_Pre_Sales_User__c);
            system.debug('=='+nld.Sales_User__c);
            //ld.OwnerId=nld.Main_Pre_Sales_User__c;

            ld.RecordTypeId=RecTypeId;
        }
        else{
            ld.Lead_Type__c ='Re-Engaged';
            ld.Re_Engaged_Date__c = system.now();
            ld.Last_Re_Engaged_Date__c = system.now();
            ld.Last_Source_Of_Enquiry__c = nld.Primary_Source__c;
            ld.Last_Sub_Source__c = nld.Primary_Sub_Source__c;
            ld.Last_Re_engaged_Campaign__c = nld.Campaign_Name__c;
            if (nld.Primary_Source__c == 'CP') {
                ld.Last_Re_engaged_Channel_Partner__c = nld.Channel_Partner__c;
            }
            system.debug('else of closed lost');
        }
        matchedMap.put(nld.Main_Lead__c,ld);
    }
    
    public static void addRelatedSource2(Lead__c nld, Lead__c mainContact){
        Related_source__c rs = new Related_source__c();
        rs.Lead_Name__c = nld.Name__c;
        rs.CLead__c = mainContact.Id;
        rs.Source__c = nld.Primary_Source__c;
        rs.Sub_Source__c = nld.Primary_Sub_Source__c;
        rs.Source_Type__c = nld.Source_Type__c; //added
        rs.Medium__c = nld.Medium__c; //added
        rs.Referring_Customer_s_Unit__c = nld.Referring_Customer_Unit__c; //added
        rs.Referring_Customer_s_Project__c = nld.Referring_Customer_Project__c; //added
        rs.Referring_Vendor_s_Company_Name__c = nld.Referring_Vendor_Company_Name__c; //added
        rs.Referring_Vendor_s_Id__c = nld.Referring_Vendor_Id__c; //added
        rs.Referring_Employee_ID__c = nld.Referring_Employee_ID__c; //added
        rs.Employee_Id__c = nld.Employee_Id__c; //added
        //rs.Referral_Type__c = nld.Referral_Type__c;
        rs.Referrer_Name__c = nld.Referrer_Name__c;
        rs.Referrer_Mobile_No__c = nld.Referrer_Mobile_No__c;
        rs.Referrer_Alternate_Mobile_No__c = nld.Referrer_Alternate_Mobile_No__c;
        rs.Referrer_Email__c = nld.Referrer_Email__c;
        rs.Referrer_Alternate_Email__c = nld.Referrer_Alternate_Email__c;
        
        rs.Referral_Source__c = nld.Referral_Source__c; //added
        rs.Referring_For__c = nld.Referring_For__c; //added
        
        rs.Existing_Customer_Info__c = nld.Existing_Customer_Info__c; //added by karthik 16-01-26
        
        /*=============== newley added fields by sandeep ==============*/
        rs.Country__c = nld.Country__c; //added
        rs.executiveName__c = nld.executiveName__c; //added
        //rs.Referring_Vendor_s_Id__c = nld.channelPartnerName__c; //added
        rs.executivePhone__c = nld.executivePhone__c; //added
        rs.comments__c = nld.Comments__c; //added
        rs.state__c = nld.State__c; //added
        rs.city__c = nld.City__c; //added
         rs.Channel_Partner__c = nld.Channel_Partner__c; //added
          /*=============== newley added fields by sandeep  completed==============*/
        rs.Phone__c = nld.Phone__c;
        rs.Country_Code__c = nld.Country_Code__c;
        rs.Secondary_Phone__c = nld.Secondary_Phone__c;
        rs.Secondary_Contry_Code__c = nld.Secondary_Country_Code__c;
        rs.Email__c = nld.Email__c;
        rs.Secondary_Email__c = nld.Secondary_Email__c;
        rs.Description__c = nld.Last_Comment__c;
        rs.Allocated_Project__c = nld.Allocated_Project__c;
        rs.Campaign__c = nld.Campaign_Name__c;
        rs.Campaign_Text__c = nld.Campaign__c;
        rs.type_of_lead__c = nld.Type_of_lead__c;
        rs.Query_For__c = nld.Query_For__c;
        rs.Query_Type__c = nld.Query_Type__c;
        rs.Message__c = nld.Message__c;
        rsList.add(rs);
        /*deleteList.add(new Lead__c(Id=nld.Id));*/
        Lead__c ld = new Lead__c();
        ld.Id=mainContact.Id;
        ld.First_Source_Of_Enquiry__c = mainContact.Lead_source__c;
        ld.First_Sub_Source__c = mainContact.Sub_Source__c;
        ld.Last_Source_Of_Enquiry__c =nld.Lead_source__c;
        ld.Last_Sub_Source__c =  nld.Sub_Source__c;
        ld.Last_Campagin__c = nld.Campaign__c;
        ld.Last_Re_Engaged_Date__c	 = system.now();
        ld.Need_Pick_Up_Assistance__c = nld.Need_Pick_Up_Assistance__c;
        ld.Comments__c = nld.Comments__c;
        //ld.Last_Re_engaged_On__c = system.now();
        system.debug(nld.Re_engaged_Count__c);
        //ld.Re_engaged_Count__c = nld.Re_engaged_Count__c + 1;
        /*matchedMap.put(mainContact.Id,ld);*/
    }
    
    // Resolves Campaign__c (text) to Campaign_Name__c (lookup) before insert.
    // Checks if the text is a valid Campaign__c Id first, then tries matching by Campaign_Name__c text.
    public static void mapCampaignLookup(List<Lead__c> newList) {
        Set<Id> campaignIds = new Set<Id>();
        Set<String> campaignNames = new Set<String>();

        for (Lead__c ld : newList) {
            if (String.isBlank(ld.Campaign__c) || ld.Campaign_Name__c != null) continue;
            try {
                Id campId = Id.valueOf(ld.Campaign__c);
                if (campId.getSObjectType() == Campaign__c.SObjectType) {
                    campaignIds.add(campId);
                }
            } catch (Exception e) {
                campaignNames.add(ld.Campaign__c);
            }
        }

        if (campaignIds.isEmpty() && campaignNames.isEmpty()) return;

        Map<Id, Campaign__c> idMap = new Map<Id, Campaign__c>();
        Map<String, Id> nameMap = new Map<String, Id>();

        List<Campaign__c> campaigns = [SELECT Id, Campaign_Name__c FROM Campaign__c
                                        WHERE Id IN :campaignIds OR Campaign_Name__c IN :campaignNames];
        for (Campaign__c c : campaigns) {
            idMap.put(c.Id, c);
            if (c.Campaign_Name__c != null) {
                nameMap.put(c.Campaign_Name__c, c.Id);
            }
        }

        for (Lead__c ld : newList) {
            if (String.isBlank(ld.Campaign__c) || ld.Campaign_Name__c != null) continue;
            try {
                Id campId = Id.valueOf(ld.Campaign__c);
                if (idMap.containsKey(campId)) {
                    ld.Campaign_Name__c = campId;
                }
            } catch (Exception e) {
                if (nameMap.containsKey(ld.Campaign__c)) {
                    ld.Campaign_Name__c = nameMap.get(ld.Campaign__c);
                }
            }
        }
    }

}