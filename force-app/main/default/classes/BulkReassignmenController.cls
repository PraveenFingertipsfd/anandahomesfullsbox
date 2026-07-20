public class BulkReassignmenController {
    
    /*@AuraEnabled - sbox code
public static List<user> getPreSalesUserDetails(){
return [SELECT Id,Name,Profile.Name,isActive FROM user where Profile.Name='Pre-Sales Executive' or Profile.name='STM'];
}*/ 
    
    //prod code
    public class dointWrap{
        @AuraEnabled public Map<String, String> ProjVals{get;set;}
        @AuraEnabled public Map<String, String> LeadStatusVals{get;set;}
        @AuraEnabled public Map<String, String> LeadSourceVals{get;set;}
        @AuraEnabled public List<user> AllUserList{get;set;}
        @AuraEnabled public List<user> UserList{get;set;}
        @AuraEnabled public Map<String, String> FollowupSubjectVals {get;set;} //added by karthik 27-01-26

    }
    
    @AuraEnabled(cacheable=true)
    public static dointWrap getDoInitValues() {
        dointWrap dwp = new dointWrap();
        
        // Initialize Maps
        Map<String, String> prj = new Map<String, String>();
        Map<String, String> status = new Map<String, String>();
        Map<String, String> source = new Map<String, String>();
        
        //added by karthik 27-01-26
        Map<String, String> fupSubject = new Map<String, String>();
        
        //Followup subject values
        for (Schema.PicklistEntry p :Lead.Latest_Followup_Subject__c.getDescribe().getPicklistValues()) {
                 fupSubject.put(p.getValue(), p.getLabel());
             }
     
        // Allocated Project Picklist
        for (Schema.PicklistEntry p : Lead.Allocated_Project__c.getDescribe().getPicklistValues()) {
            prj.put(p.getValue(), p.getLabel());
        }
        System.debug('=== Allocated Project Picklist Values ===');
        System.debug(prj);
        
        // Lead Status Picklist
        for (Schema.PicklistEntry p : Lead.Lead_Status__c.getDescribe().getPicklistValues()) {
            status.put(p.getValue(), p.getLabel());
        }
        System.debug('=== Lead Status Picklist Values ===');
        System.debug(status);
        
        // Lead Source Picklist
        for (Schema.PicklistEntry p : Lead.Lead_Source__c.getDescribe().getPicklistValues()) {
            source.put(p.getValue(), p.getLabel());
        }
        System.debug('=== Lead Source Picklist Values ===');
        System.debug(source);
        
        // Fetch Active Users excluding unwanted profiles
        List<User> users = [
            SELECT Id, Name, Profile.Name, IsActive
            FROM User
            WHERE IsActive = TRUE
            AND Profile.Name NOT IN (
                'LeadInsert Profile',
                'Sales Insights Integration User',
                'SalesforceIQ Integration User',
                'Minimum Access - API Only Integrations',
                'Standard User',
                'Call Profile',
                'Pulse Profile',
                'Integration with WA Profile'
            )
        ];
        System.debug('=== Retrieved Users Count: ' + users.size());
        System.debug('=== Retrieved Users List ===');
        System.debug(users);
        
        List<User> allUsers = [
            SELECT Id, Name, Profile.Name, IsActive
            FROM User
            WHERE Profile.Name NOT IN (
                'LeadInsert Profile',
                'Sales Insights Integration User',
                'SalesforceIQ Integration User',
                'Minimum Access - API Only Integrations',
                'Standard User',
                'Call Profile',
                'Pulse Profile',
                'Integration with WA Profile'
            )
        ];
        
        // Assign values to wrapper
        dwp.ProjVals = prj;
        dwp.LeadStatusVals = status;
        dwp.LeadSourceVals = source;
        dwp.AllUserList = allUsers;
        dwp.UserList = users;
        dwp.FollowupSubjectVals = fupSubject; //added by karthik 27-01-26
        
        System.debug('=== Final Wrapper Values ===');
        System.debug(dwp);
        
        return dwp;
    }
    
    @AuraEnabled
    public static List<Lead> getcon(string currentUserId, String projectId, String leadStatus,String leadSource,Date fromCreatedDate, Date toCreatedDate, String filterCreatedDate,String batchcode,String subSource,Date fromAllocationDate,Date toAllocatonDate, Date fromSiteVisitDate,Date toSiteVisitDate, Date fromFollowUpDate, Date toFollowUpDate, String phoneNumber, String siteVisitDone,String followupSubject) {
        system.debug(currentUserId);
        system.debug(projectId);
        system.debug(leadStatus);
        system.debug(fromCreatedDate);
        system.debug(toCreatedDate);
        system.debug(fromAllocationDate);
        system.debug(toAllocatonDate);
        //system.debug('leadStatus-->'+ leadStatus +'  filterCreatedDate-->'+ filterCreatedDate +'  projectName-->'+ projectId +'  leadsource-->'+ leadSource );
        String fields ='ID,Name,Allocated_Project__c,Created_Dates__c,Lead_Record_Type__c,Site_Visit_Done__c,Phone__c,Lead_source__c,Lead_Status__c,CreatedDate,Lead_ID__c,OwnerId,Lead_Owner_Full_Name__c,Campaign__c,Pushed_On__c,Sub_Source__c';
        String ObjectName ='Lead';
        string wherefilter = '';
        
        DateTime startDateTime;
        DateTime endDateTime;
        
        if(fromSiteVisitDate != null)
            startDateTime = DateTime.newInstance(fromSiteVisitDate, Time.newInstance(0, 0, 0, 0));
        
        if(toSiteVisitDate != null)
            endDateTime = DateTime.newInstance(toSiteVisitDate, Time.newInstance(23, 59, 59, 999));
        
        //NEwley added by sandeep  on 15/9/2025 to fetch leads by sitevisit dates and foloup dates                             
        //  Step 1: Collect Lead Ids from Site Visits
        Set<Id> siteVisitLeadIds = new Set<Id>();
        if(fromSiteVisitDate != null || toSiteVisitDate != null) {
            String siteVisitQuery = 'SELECT SLead__c FROM Site_Visit__c WHERE SLead__c != NULL AND Status__c = \'Completed\'';
            if(fromSiteVisitDate != null) {
                siteVisitQuery += ' AND Check_In__c  >= :startDateTime';
            }
            if(toSiteVisitDate != null) {
                siteVisitQuery += ' AND Check_In__c  <= :endDateTime';
            }
            for(Site_Visit__c sv : Database.query(siteVisitQuery)) {
                siteVisitLeadIds.add(sv.SLead__c);
            }
        }
        System.debug('Site Visits Found: ' + siteVisitLeadIds.size());
        
        // Step 2: Collect Lead Ids from Follow Ups
        Set<Id> followUpLeadIds = new Set<Id>();
        if(fromFollowUpDate != null || toFollowUpDate != null) {
            String followUpQuery = 'SELECT SLead__c FROM Follow_Up__c WHERE SLead__c != NULL AND Status__c = \'Scheduled\'';
            if(fromFollowUpDate != null) {
                followUpQuery += ' AND Scheduled_Date__c >= :fromFollowUpDate';
            }
            if(toFollowUpDate != null) {
                followUpQuery += ' AND Scheduled_Date__c <= :toFollowUpDate';
            }
            for(Follow_Up__c fu : Database.query(followUpQuery)) {
                followUpLeadIds.add(fu.SLead__c);
            }
        }
        System.debug('Follow Ups Found: ' + followUpLeadIds.size());
        //  Step 3: Merge both sets
        Set<Id> finalLeadIds = new Set<Id>();
        finalLeadIds.addAll(siteVisitLeadIds);
        finalLeadIds.addAll(followUpLeadIds);
        System.debug('Final Lead Ids: ' + finalLeadIds.size());
        set<Id> dateFilterCustomerIds = new set<Id>();
        
        if(!String.isEmpty(currentUserId))
        {
            wherefilter = wherefilter+' where (OwnerId=:currentUserId )';
            
        }
        
        if(!String.isEmpty(projectId))
        {
            if(!String.isEmpty(currentUserId) )
            {  
                wherefilter = wherefilter+' and Allocated_Project__c=:projectId';
            }
            else{
                wherefilter = wherefilter+' where Allocated_Project__c=:projectId'; 
            }
        }
        if(fromCreatedDate != null )
        {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId))
            {  
                wherefilter = wherefilter+' and Created_Dates__c >=: fromCreatedDate';
            }
            else{
                wherefilter = wherefilter+' where Created_Dates__c >=: fromCreatedDate'; 
            }
        }
        if(toCreatedDate != null)
        {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId))
            {  
                wherefilter = wherefilter+' and Created_Dates__c <=: toCreatedDate';
            }
            else{
                wherefilter = wherefilter+' where Created_Dates__c <=: toCreatedDate'; 
            }
        }
        
        if(!String.isEmpty(filterCreatedDate))
        {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId))
            {  
                wherefilter = wherefilter+' and Created_Dates__c =: valuedate';
            }
            else{
                wherefilter = wherefilter+' where Created_Dates__c =: filterCreatedDate'; 
            }
        }
        if(!String.isEmpty(leadStatus))
        {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId) || !String.isEmpty(filterCreatedDate) )
            {  
                wherefilter = wherefilter+' and Lead_Status__c =: leadStatus';
            }
            else{
                wherefilter = wherefilter+' where Lead_Status__c =: leadStatus'; 
            }
        }
        if(!String.isEmpty(leadSource))
        {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId) || !String.isEmpty(filterCreatedDate) || !String.isEmpty(leadStatus))
            {  
                wherefilter = wherefilter+' and 	Lead_source__c =: leadSource';
            }
            else{
                wherefilter = wherefilter+' where 	Lead_source__c =: leadSource'; 
            }
        }
        if(!String.isEmpty(batchcode))
        {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId) || !String.isEmpty(filterCreatedDate) || !String.isEmpty(leadStatus) || !String.isEmpty(leadSource))
            {  
                wherefilter = wherefilter+' and 	Campaign__c =: batchcode';
            }
            else{
                wherefilter = wherefilter+' where 	Campaign__c =: batchcode'; 
            }
        }
        if(fromAllocationDate != null) {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId) || !String.isEmpty(filterCreatedDate) || !String.isEmpty(leadStatus) || !String.isEmpty(leadSource) || !String.isEmpty(batchcode)) {
                wherefilter = wherefilter+' and Pushed_On__c >=: fromAllocationDate';
            } else {
                wherefilter = wherefilter+' where Pushed_On__c >=: fromAllocationDate'; 
            }
        }
        if(toAllocatonDate != null) {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId) || !String.isEmpty(filterCreatedDate) || !String.isEmpty(leadStatus) || !String.isEmpty(leadSource) || !String.isEmpty(batchcode)) {
                wherefilter = wherefilter+' and Pushed_On__c <=: toAllocatonDate';
            } else {
                wherefilter = wherefilter+' where Pushed_On__c <=: toAllocatonDate'; 
            }
        }
        if(!finalLeadIds.isEmpty()) {
            whereFilter += (whereFilter == '' ? ' WHERE' : ' AND') + ' Id IN :finalLeadIds';
        }
        
        
        if(!String.isEmpty(subSource))
        {
            if(!String.isEmpty(currentUserId) || !String.isEmpty(projectId) || !String.isEmpty(filterCreatedDate) || !String.isEmpty(leadStatus) || !String.isEmpty(leadSource) ||!String.isEmpty(batchcode))
            {  
                wherefilter = wherefilter+' and Sub_Source__c =: subSource';
            }
            else{
                wherefilter = wherefilter+' where Sub_Source__c =: subSource'; 
            }
        }
        if (!String.isEmpty(phoneNumber)) {
            String likePhone = '%' + phoneNumber + '%';
            if (!String.isEmpty(wherefilter)) {
                wherefilter += ' AND (Phone__c LIKE :likePhone OR Secondary_Phone__c LIKE :likePhone OR Spouse_Phone__c LIKE :likePhone)';
            } else {
                wherefilter = ' WHERE (Phone__c LIKE :likePhone OR Secondary_Phone__c LIKE :likePhone OR Spouse_Phone__c LIKE :likePhone)';
            }
        }
        //added by karthik 02-12
        if(!String.isEmpty(siteVisitDone)) {
            if(siteVisitDone == 'Yes') {
                wherefilter += (wherefilter == '' ? ' WHERE ' : ' AND') + ' Site_Visit_Done__c = \'Yes\'';
            } 
            else if(siteVisitDone == 'No') {
                wherefilter += (wherefilter == '' ? ' WHERE ' : ' AND') + 
                    ' (Site_Visit_Done__c = \'No\' OR Site_Visit_Done__c = null OR Site_Visit_Done__c = \'\')';
            }
        }
   
        //added by karthik 27-01-26
        if (!String.isEmpty(followupSubject)) {
            wherefilter += (wherefilter == '' ? ' WHERE ' : ' AND ')
                + ' Latest_Followup_Subject__c = :followupSubject';
        }

        
        string query = 'Select '+ fields + ' FROM '+ ObjectName+wherefilter + ' LIMIT 5000'; 
        system.debug('query --'+query);
        list<Lead> leadlist = Database.Query(query);
        return leadlist;
    }
    
    @AuraEnabled 
    public static Map<String, String> getprojectFieldValue(){
        Map<String, String> options = new Map<String, String>();
        
        Schema.DescribeFieldResult fieldResult = Lead.Allocated_Project__c.getDescribe();
        
        List<Schema.PicklistEntry> pValues = fieldResult.getPicklistValues();
        for (Schema.PicklistEntry p: pValues) {
            options.put(p.getValue(), p.getLabel());
        }
        
        return options;
    }
    
    @AuraEnabled 
    public static Map<String, String> getleadstatusFieldValue(){
        Map<String, String> options = new Map<String, String>();
        
        Schema.DescribeFieldResult fieldResult = Lead.Lead_Status__c.getDescribe();
        
        List<Schema.PicklistEntry> pValues = fieldResult.getPicklistValues();
        for (Schema.PicklistEntry p: pValues) {
            options.put(p.getValue(), p.getLabel());
        }
        
        return options;
    }
    
    @AuraEnabled 
    public static Map<String, String> getLeadSource(){
        Map<String, String> options = new Map<String, String>();
        
        Schema.DescribeFieldResult fieldResult = Lead.Lead_source__c.getDescribe();
        
        List<Schema.PicklistEntry> pValues = fieldResult.getPicklistValues();
        for (Schema.PicklistEntry p: pValues) {
            options.put(p.getValue(), p.getLabel());
        }
        
        return options;
    }
    
    @AuraEnabled
    public static List<user> getPreSalesUserDetails(){
        return [SELECT Id,Name,Profile.Name,isActive FROM user];
    }
    
    //Helper method to detect user type (with your actual profiles)
    private static String getUserType(User u) {
        if (u == null) return '';
        String profile = (u.Profile != null && u.Profile.Name != null) ? u.Profile.Name.toLowerCase() : '';
        
        // 🔹 Match your real profile names
        if (profile.contains('pre-sales') || profile.contains('pre sales')) return 'Pre Sales';
        if (profile.contains('stm') ) return 'Sales';
        
        return 'Other';
    }
    
    @AuraEnabled
    public static List<Lead> updateLeadOwner(List<Lead> contacts, String currentUserId, String assignToId) {
        
        System.debug('contacts --> ' + contacts + 
                     ' currentUserId --> ' + currentUserId + 
                     ' assignToId --> ' + assignToId);
        
        if (contacts == null || contacts.isEmpty() || String.isBlank(currentUserId) || String.isBlank(assignToId)) {
            return new List<Lead>();
        }
        
        // Build a map of input leads for quick lookup (used in SV logic)
        Map<Id, Lead> leadInputMap = new Map<Id, Lead>();
        for (Lead l : contacts) {
            if (l != null && l.Id != null) leadInputMap.put(l.Id, l);
        }
        
        List<Lead> leadsToUpdate = new List<Lead>();
        
        // track lead -> set of scenario flags (allows multiple flags per lead)
        Map<Id, Set<String>> leadScenarioMap = new Map<Id, Set<String>>();
        Set<Id> leadIdsToProcess = new Set<Id>();
        
        // Record Type IDs
        Id preSalesRTId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Pre Sales').getRecordTypeId();
        Id salesRTId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
        
        // Query users (current assigner and target)
        Map<Id, User> userMap = new Map<Id, User>([SELECT Id, Profile.Name, UserRole.Name FROM User WHERE Id IN :new Set<Id>{ currentUserId, assignToId }]);
        
        User currentUser = userMap.get(currentUserId);
        User targetUser  = userMap.get(assignToId);
        
        String currentType = getUserType(currentUser);
        String targetType  = getUserType(targetUser);
        
        System.debug('Current Type: ' + currentType + ' | Target Type: ' + targetType);
        
        // ------------------------------------------------------------------------------------
        // BUILD LEAD UPDATE LIST (set fields and mark which leads need SV/FUP processing)
        // ------------------------------------------------------------------------------------
        for (Lead con : contacts) {
            if (con == null || con.OwnerId == null) continue;
            
            Lead up = new Lead(Id = con.Id);
            up.OwnerId = assignToId;
            up.Lead_Assigned__c = true;
            up.Re_assigned_date__c = System.now();
            up.Reassigned_By__c = UserInfo.getUserId();
            up.Is_Called__c = false; //added by karthik 01-12-25
            
            String curStatus = (con.Lead_Status__c == null) ? '' : con.Lead_Status__c;
            
            // -----------------------------------------------------------------------
            // CASE 1: Sales -> Pre-Sales
            // -----------------------------------------------------------------------
            if (currentType == 'Sales' && targetType == 'Pre Sales') {
                up.RecordTypeId = preSalesRTId;
                up.Pre_Sales_User__c = assignToId;
                up.Old_Owner_Name__c = assignToId;
                up.Sales_User__c = null;
                
                if (curStatus.equalsIgnoreCase('Closed Lost')) {
                    up.Lead_Status__c = 'New';
                }else {
                    up.Lead_Status__c = 'inValid';
                }
                leadScenarioMap.put(up.Id, new set<String>{'Normal'});
                
                // Status: Closed Lost -> New, else keep same
                /*if (curStatus.equalsIgnoreCase('Closed Lost')) {
                    up.Lead_Status__c = 'New';
                } else {
                    up.Lead_Status__c = curStatus;
                }
                
                // Cancel all SVs and mark FUPs missed for this lead
                // add flags
                Set<String> flags = leadScenarioMap.get(up.Id);
                if (flags == null) flags = new Set<String>();
                flags.add('CancelSV');
                flags.add('MissFUP');
                leadScenarioMap.put(up.Id, flags);
                leadIdsToProcess.add(up.Id);
				*/
            }
            
            // -----------------------------------------------------------------------
            // CASE 2: Pre-Sales -> Sales
            // -----------------------------------------------------------------------
            else if (currentType == 'Pre Sales' && targetType == 'Sales') {
                up.RecordTypeId = salesRTId;
                up.Pre_Sales_User__c = null; // clear pre-sales user
                up.Old_Owner_Name__c = null;
                up.Sales_User__c = assignToId;
                
                if (curStatus.equalsIgnoreCase('RNR')) {
                    up.Lead_Status__c = 'RNR';
                } else{
                    up.Lead_Status__c = 'New sales enquiry';
                }
                leadScenarioMap.put(up.Id, new set<String>{'Normal'});
                
                // Status mapping
                /*if (curStatus.equalsIgnoreCase('Unqualified')) {
                    up.Lead_Status__c = 'New sales enquiry';
                } else if (curStatus.equalsIgnoreCase('RNR')) {
                    up.Lead_Status__c = 'RNR';
                } else if (curStatus.equalsIgnoreCase('Site Visit Schedule')) {
                    up.Lead_Status__c = 'New sales enquiry';
                    Set<String> flags = leadScenarioMap.get(up.Id);
                    if (flags == null) flags = new Set<String>();
                    flags.add('CancelSV');
                    flags.add('MissFUP');
                    leadScenarioMap.put(up.Id, flags);
                    leadIdsToProcess.add(up.Id);
                } else {
                    // default -> New sales enquiry
                    up.Lead_Status__c = 'New sales enquiry';
                    // still process followups
                    Set<String> flags = leadScenarioMap.get(up.Id);
                    if (flags == null) flags = new Set<String>();
                    flags.add('MissFUP');
                    leadScenarioMap.put(up.Id, flags);
                    leadIdsToProcess.add(up.Id);
                }*/
            }
            
            // -----------------------------------------------------------------------
            // CASE 3: Sales -> Sales
            // -----------------------------------------------------------------------
            else if (currentType == 'Sales' && targetType == 'Sales') {
                up.RecordTypeId = salesRTId;
                up.Sales_User__c = assignToId;

                if (curStatus.equalsIgnoreCase('Closed Lost')) {
                    up.Lead_Status__c = 'New sales enquiry';
                } else if (curStatus.equalsIgnoreCase('Site Visit Schedule')) {
                    up.Lead_Status__c = 'New sales enquiry';
                }
                leadScenarioMap.put(up.Id, new set<String>{'PreSaleCheck'});
                    
                /*if (curStatus.equalsIgnoreCase('Closed Lost')) {
                    up.Lead_Status__c = 'New sales enquiry';
                } else if (curStatus.equalsIgnoreCase('Site Visit Schedule')) {
                    up.Lead_Status__c = 'New sales enquiry';
                    // For Sales->Sales SV logic we need conditional behavior:
                    // store a special flag; processing will check whether SV.CreatedById == lead.Pre_Sales_User__c
                    Set<String> flags = leadScenarioMap.get(up.Id);
                    if (flags == null) flags = new Set<String>();
                    flags.add('CheckSVCreator');
                    flags.add('MissFUP'); // always process follow-ups
                    leadScenarioMap.put(up.Id, flags);
                    leadIdsToProcess.add(up.Id);
                } else {
                    up.Lead_Status__c = curStatus;
                    // still process followups
                    Set<String> flags = leadScenarioMap.get(up.Id);
                    if (flags == null) flags = new Set<String>();
                    flags.add('MissFUP');
                    leadScenarioMap.put(up.Id, flags);
                    leadIdsToProcess.add(up.Id);
                }*/
            }
            
            // -----------------------------------------------------------------------
            // CASE 4: Pre-Sales -> Pre-Sales
            // -----------------------------------------------------------------------
            else if (currentType == 'Pre Sales' && targetType == 'Pre Sales') {
                up.RecordTypeId = preSalesRTId;
                up.Pre_Sales_User__c = assignToId;
                up.Old_Owner_Name__c = assignToId;
                
                if (curStatus.equalsIgnoreCase('Unqualified')) {
                    up.Lead_Status__c = 'New';
                } else if (curStatus.equalsIgnoreCase('Site Visit Schedule')) {
                    up.Lead_Status__c = 'Potential Site Visit';
                }
                leadScenarioMap.put(up.Id, new set<String>{'Normal'});
                
                /*if (curStatus.equalsIgnoreCase('Unqualified')) {
                    up.Lead_Status__c = 'New';
                } else if (curStatus.equalsIgnoreCase('Site Visit Schedule')) {
                    up.Lead_Status__c = 'Potential Site Visit';
                    Set<String> flags = leadScenarioMap.get(up.Id);
                    if (flags == null) flags = new Set<String>();
                    flags.add('CancelSV');
                    flags.add('MissFUP');
                    leadScenarioMap.put(up.Id, flags);
                    leadIdsToProcess.add(up.Id);
                } else {
                    up.Lead_Status__c = curStatus;
                    // still process followups
                    Set<String> flags = leadScenarioMap.get(up.Id);
                    if (flags == null) flags = new Set<String>();
                    flags.add('MissFUP');
                    leadScenarioMap.put(up.Id, flags);
                    leadIdsToProcess.add(up.Id);
                }*/
            }
            
            // Default fallback: keep type/status, but we already set owner and reassignment fields
            leadsToUpdate.add(up);
        } // end for contacts
        
        
        // ------------------------------------------------------------------------------------
        // UPDATE LEADS (bulk)
        // ------------------------------------------------------------------------------------
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
        
        // ------------------------------------------------------------------------------------
        // PROCESS SITE VISITS + FOLLOWUPS (bulk)
        // ------------------------------------------------------------------------------------
        /*if (!leadIdsToProcess.isEmpty()) {
            
            // Query scheduled site visits for these leads
            List<Site_Visit__c> svs = [SELECT Id, SLead__c, CreatedById, Status__c, Canceled_Reason__c FROM Site_Visit__c
                					   WHERE SLead__c IN :leadIdsToProcess AND Status__c = 'Scheduled'];
               
            List<Site_Visit__c> svToUpdate = new List<Site_Visit__c>();
            
            for (Site_Visit__c sv : svs) {
                Set<String> flags = leadScenarioMap.get(sv.SLead__c);
                if (flags == null) continue;
                
                // If any flag says CancelSV -> cancel unconditionally
                if (flags.contains('CancelSV')) {
                    sv.Status__c = 'Cancelled';
                    sv.Canceled_Reason__c = 'Cancelled by system due to lead Re-Assignment.';
                    svToUpdate.add(sv);
                    continue;
                }
                
                // If flag is CheckSVCreator -> preserve only if CreatedBy == Pre_Sales_User__c
                if (flags.contains('CheckSVCreator')) {
                    Lead original = leadInputMap.get(sv.SLead__c);
                    Id preSalesUser = (original != null) ? (Id) original.get('Pre_Sales_User__c') : null;
                    
                    // If there is a pre-sales user AND the createdBy matches that user -> do nothing (preserve)
                    if (preSalesUser != null && sv.CreatedById == preSalesUser) {
                        // preserve
                        continue;
                    } else {
                        // cancel in all other cases (including preSalesUser == null)
                        sv.Status__c = 'Cancelled';
                        sv.Canceled_Reason__c = 'Cancelled by system due to lead Re-Assignment.';
                        svToUpdate.add(sv);
                    }
                }
            } // end for svs
            
            // Query scheduled follow-ups for these leads
            List<Follow_Up__c> fus = [SELECT Id, SLead__c, Status__c, Description__c FROM Follow_Up__c
                					  WHERE SLead__c IN :leadIdsToProcess AND Status__c = 'Scheduled'];
                
            List<Follow_Up__c> fuToUpdate = new List<Follow_Up__c>();
            
            for (Follow_Up__c fu : fus) {
                Set<String> flags = leadScenarioMap.get(fu.SLead__c);
                if (flags == null) continue;
                
                // If any flag requests missed FUP -> set missed + description
                if (flags.contains('MissFUP')) {
                    fu.Status__c = 'Missed';
                    fu.Description__c = 'Cancelled by system due to lead Re-Assignment.';
                    fuToUpdate.add(fu);
                }
            }
            
            if (!svToUpdate.isEmpty()) update svToUpdate;
            if (!fuToUpdate.isEmpty()) update fuToUpdate;
        }*/
        
        if (!leadScenarioMap.isEmpty()) {
            List<Site_Visit__c> svToUpdate = new List<Site_Visit__c>();
            for (Site_Visit__c sv : [SELECT Id, SLead__c, CreatedById,CreatedBy.Profile.Name, Status__c, Canceled_Reason__c FROM Site_Visit__c
                					   WHERE SLead__c IN :leadScenarioMap.keyset() AND (Status__c = 'Scheduled' OR Status__c = 'Rescheduled') ]) {
                Set<String> flags = leadScenarioMap.get(sv.SLead__c);
                if(flags.contains('PreSaleCheck') && sv.CreatedBy.Profile.Name == 'Pre-Sales Executive'){
                    continue;
                }
                else{
                    sv.Status__c = 'Cancelled';
                    sv.Canceled_Reason__c = 'Cancelled by system due to lead Re-Assignment.';
                    svToUpdate.add(sv);
                }
            }
            
            /* 'Missed' follow-up status removed — do not auto-mark open follow-ups as Missed on lead re-assignment.
            // Query scheduled follow-ups for these leads
            List<Follow_Up__c> fuToUpdate = new List<Follow_Up__c>();
            for (Follow_Up__c fu : [SELECT Id, SLead__c, Status__c, Description__c FROM Follow_Up__c WHERE SLead__c IN :leadScenarioMap.keyset() AND Status__c = 'Scheduled']) {
                fu.Status__c = 'Missed';
                fu.Description__c = 'Missed by system due to lead Re-Assignment.';
                fuToUpdate.add(fu);
            }
            */

            if (!svToUpdate.isEmpty()) update svToUpdate;
            // if (!fuToUpdate.isEmpty()) update fuToUpdate;
        }
        
        
        // Refresh and return updated list for UI
        return getcon(currentUserId, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,null);
    }

}