public without sharing class GRE_Lead_Controller {
    
    public class InitDataWrapper {
        @AuraEnabled public List<Lead__c> leadRecords { get; set; }
        @AuraEnabled public List<String> ProjLst { get; set; }
        @AuraEnabled public Map<string, List<User>> prjUserList { get; set; }
        @AuraEnabled public String salesRecordTypeId { get; set; }
    }
    
    @AuraEnabled
    public static InitDataWrapper fetchLeads(String searchValue) {
        InitDataWrapper intWrp = new InitDataWrapper();

        List<Lead__c> leads = new List<Lead__c>();

        if (isPhoneNumber(searchValue)) {
            leads = [SELECT Id, Name__c, Lead_Type__c, Last_Re_Opened_Date__c, RecordTypeId, Lead_Assigned__c,
                     Phone__c, Secondary_Phone__c, Allocated_Project__c, RecordType.Name, Unit_Preference__c,
                     Medium__c, Source_Type__c, Email__c, Lead_Status__c, Primary_Source__c, CreatedDate,
                     Lead_Owner_Full_Name__c, Lead_ID__c, OwnerId
                     FROM Lead__c
                     WHERE Phone__c = :searchValue
                        OR Secondary_Phone__c = :searchValue
                     LIMIT 10];
        } else {
            leads = [SELECT Id, Name__c, Lead_Type__c, Last_Re_Opened_Date__c, RecordTypeId, Lead_Assigned__c,
                     Phone__c, Secondary_Phone__c, Allocated_Project__c, RecordType.Name, Unit_Preference__c,
                     Medium__c, Source_Type__c, Email__c, Lead_Status__c, Primary_Source__c, CreatedDate,
                     Lead_Owner_Full_Name__c, Lead_ID__c, OwnerId
                     FROM Lead__c
                     WHERE Lead_ID__c LIKE :('%' + searchValue + '%')
                     LIMIT 10];
        }
        
        /*
        if (isPhoneNumber(searchValue)) {
            leads = [SELECT Id, Name__c, Lead_Type__c, Last_Re_Opened_Date__c, RecordTypeId, Lead_Assigned__c,  Phone__c,Secondary_Phone__c, Allocated_Project__c, RecordType.Name, Unit_Preference__c, Medium__c, Source_Type__c, Email__c, Lead_Status__c, Primary_Source__c, CreatedDate, Lead_Owner_Full_Name__c, Lead_ID__c, OwnerId FROM Lead__c WHERE Phone__c = :searchValue OR Secondary_Phone__c = :searchValue OR Spouse_Phone__c = :searchValue LIMIT 10];
        } else {
            leads = [SELECT Id, Name__c, Lead_Type__c, Last_Re_Opened_Date__c, RecordTypeId, Lead_Assigned__c, Phone__c,Secondary_Phone__c, Allocated_Project__c, RecordType.Name, Unit_Preference__c, Medium__c, Source_Type__c, Email__c, Lead_Status__c, Primary_Source__c, CreatedDate, Lead_Owner_Full_Name__c, Lead_ID__c, OwnerId FROM Lead__c WHERE Name__c LIKE :('%' + searchValue + '%') LIMIT 10];
        }
*/
        intWrp.leadRecords = leads;
        
        String salesRTId = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead__c' AND Name = 'Sales' LIMIT 1].Id;
        intWrp.salesRecordTypeId = salesRTId;
        
        List<String> pickListValuesList= new List<String>();
        Schema.DescribeFieldResult fieldResult = Lead.Allocated_Project__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for( Schema.PicklistEntry pickListVal : ple){
            pickListValuesList.add(pickListVal.getLabel());
        }
        system.debug('pickListValuesList '+pickListValuesList);
        intWrp.ProjLst = pickListValuesList;
        
        
        
        
        Map<string, List<User>> projectHandledByMap = new Map<string, List<User>>();
        Datetime d = system.now();
        String dayOfWeek = d.format('EEEE');
        // Available users
        List<Round_Robin__c> RRAvaliablequeList = [
            SELECT Id, Project_Assigned__c,
            (SELECT Id, Name, User__c,User__r.Id, User__r.Name 
             FROM Round_Robin_Members__r  
             WHERE Active__c = true
             AND User__r.Availability__c = true
             AND User__r.IsActive = true
             AND User__r.Is_Working__c = true
             AND User__r.Week_Off_Days__c EXCLUDES (:dayOfWeek)
             AND User_Type__c = 'Sales'
             ORDER BY Last_Assigned_Time_User__c, CreatedDate ASC NULLS FIRST)
            FROM Round_Robin__c
            WHERE Active__c = true
        ];
        
        // All users (not filtered by availability)
        List<Round_Robin__c> RRqueList = [
            SELECT Id, Project_Assigned__c,
            (SELECT Id, Name, User__c, User__r.Id, User__r.Name 
             FROM Round_Robin_Members__r  
             WHERE Active__c = true
             AND User__r.IsActive = true
             AND User__r.Is_Working__c = true
             AND User__r.Week_Off_Days__c EXCLUDES (:dayOfWeek)
             AND User_Type__c = 'Sales'
             ORDER BY Last_Assigned_Time_User__c, CreatedDate ASC NULLS FIRST)
            FROM Round_Robin__c
            WHERE Active__c = true
        ];
        
        // Build a combined map (prefer available users if present)
        for (Round_Robin__c rr : RRqueList) {
            List<User> options = new List<User>();
            // If project exists in available queue, use that
            List<Round_Robin_Member__c> members = new List<Round_Robin_Member__c>();
            if (RRAvaliablequeList != null) {
                for (Round_Robin__c availableRR : RRAvaliablequeList) {
                    if (availableRR.Project_Assigned__c == rr.Project_Assigned__c) {
                        members = availableRR.Round_Robin_Members__r;
                        break;
                    }
                }
            }
            // If no available ones, fallback to all members
            if (members.isEmpty() && rr.Round_Robin_Members__r != null) {
                members = rr.Round_Robin_Members__r;
            }
            
            for (Round_Robin_Member__c member : members) {
                options.add(member.User__r);
            }
            
            projectHandledByMap.put(rr.Project_Assigned__c, options);
        }
        
        
        intWrp.prjUserList = projectHandledByMap;
        
        
        return intWrp;
    }
    private static Boolean isPhoneNumber(String searchValue) {
        String phonePattern = '^\\+?[0-9]{1,4}?[-.\\s]?[0-9]{1,4}[-.\\s]?[0-9]{1,4}[-.\\s]?[0-9]{1,9}$';
        return Pattern.matches(phonePattern, searchValue);
    }
    @AuraEnabled
    public static Map<String, String> getCountryAndCode() {
        return transferLeadController.getCountryAndCode();
    }
    @AuraEnabled
    public static Boolean getUserType() {
        return transferLeadController.getUserType();
    }
    @AuraEnabled(cacheable=true)
    public static Id getSalesRecordTypeId() {
        // Query to get the RecordTypeId for 'Sales' record type on Lead object
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead__c' AND DeveloperName = 'Sales' LIMIT 1];
        return rt.Id;
    }
    @AuraEnabled
    public static Map<String, Object> getLeadandSiteVisitDetails(Id leadId) {
        Map<String, Object> result = new Map<String, Object>();
        
        // Query for the lead and its record type, as well as associated site visits
        //Lead lead = [SELECT Id, CreatedDate, RecordType.Name FROM Lead WHERE Id = :leadId LIMIT 1];
        
        // commented out for later use - Medium__c, Source_Type__c removed; Primary_Sub_Source__c added (Lead_Type__c retained)
        // Lead__c lead = [SELECT Id, Name__c, Lead_Type__c, Last_Re_Opened_Date__c, RecordTypeId, Lead_Assigned__c, Phone__c,Secondary_Phone__c, Allocated_Project__c,
        //          RecordType.Name, Unit_Preference__c, Medium__c, Source_Type__c, Email__c, Lead_Status__c, Primary_Source__c, CreatedDate, Lead_Owner_Full_Name__c,Owner.Name,
        //          Lead_ID__c, OwnerId FROM Lead__c WHERE Id = :leadId LIMIT 1];
        Lead__c lead = [SELECT Id, Name__c, Lead_Type__c, Last_Re_Opened_Date__c, RecordTypeId, Lead_Assigned__c, Phone__c,Secondary_Phone__c, Allocated_Project__c,
                 RecordType.Name, Unit_Preference__c, Primary_Sub_Source__c, Email__c, Lead_Status__c, Primary_Source__c, CreatedDate, Lead_Owner_Full_Name__c,Owner.Name,
                 Lead_ID__c, OwnerId FROM Lead__c WHERE Id = :leadId LIMIT 1];
        
        List<Site_Visit__c> siteVisits = [SELECT Name,Check_Out__c, Project__c, Status__c,CreatedBy.Name,CreatedDate,SV_Completed_Date_Time__c,Id, Date__c, Owner.Name, Visit_Type__c FROM Site_Visit__c
                                          WHERE CLead__c = :leadId ORDER BY Project__c,createdDate asc];
        //AND (Status__c = 'Scheduled' OR Status__c = 'Rescheduled')
        
        // Add the record type name to the result map
        result.put('recordTypeName', lead.RecordType.Name);
        result.put('siteVisits', siteVisits);
        result.put('selectedld', lead);
        
        return result;
    }
    
    @AuraEnabled
    public static Site_Visit__c createSiteVisit(Id leadId, String projectName, Id handledById) {
        Site_Visit__c newSiteVisit = new Site_Visit__c(
            slead__c = leadId,
            Status__c = 'GRE Verified',
            Date__c = System.now().addMinutes(5),
            Project__c = projectName,
            Check_In__c = System.now()
        );
        
        if (handledById != null) {
            newSiteVisit.Handled_By__c = handledById; 
        }
        
        insert newSiteVisit;
        
        return [SELECT Name, Project__c, Status__c, Date__c, Owner.Name, Id
                FROM Site_Visit__c
                WHERE Id = :newSiteVisit.Id
                LIMIT 1];
    }


    @AuraEnabled
    public static Site_Visit__c updateSiteVisitStatus(Id siteVisitId, string status, string Remark,Datetime checkouttime) {
        //try {
            //system.debug('Check In: '+CheckIn+' Check Out: '+CheckOut);
            // Assuming the string is still in local time zone, you should append 'Z' (UTC) 
            /*CheckIn = CheckIn.replace('Z', '');  // Remove existing 'Z' if already present.*/
        	String CheckOut = String.valueOf(checkouttime); // Convert Datetime to String
            CheckOut = CheckOut.replace('Z', ''); // Remove existing 'Z' if already present.
            
            //CheckIn = CheckIn.substring(0, 19) + 'Z';  // Append 'Z' for UTC (or use user's local time zone)
            CheckOut = CheckOut.substring(0, 19) + 'Z'; // Append 'Z' for UTC (or use user's local time zone)
            
            // Debugging after cleaning the input
            //System.debug('Cleaned Check In: ' + CheckIn + ' Cleaned Check Out: ' + CheckOut);
            System.debug(' Cleaned Check Out: ' + CheckOut);

            // Query the site visit record
            Site_Visit__c siteVisit = [SELECT Name, Project__c, Status__c,Check_In__c,Check_Out__c, Date__c, Owner.Name, Id FROM Site_Visit__c WHERE Id = :siteVisitId LIMIT 1];
            system.debug('siteVisit '+siteVisit);
            // Update the status
            siteVisit.Status__c = 'GRE Verified';
            //siteVisit.SV_Completed_Date_Time__c = System.now();
            //siteVisit.Check_Out__c = system.now();
            siteVisit.Remark__c = Remark;
            if(siteVisit.Check_In__c == null){
                siteVisit.Check_In__c = siteVisit.Date__c;
            }

            // Repeat for CheckOut
            Integer year = Integer.valueOf(CheckOut.substring(0, 4));
            Integer month = Integer.valueOf(CheckOut.substring(5, 7));
            Integer day = Integer.valueOf(CheckOut.substring(8, 10));
            Integer hour = Integer.valueOf(CheckOut.substring(11, 13));
            Integer minute = Integer.valueOf(CheckOut.substring(14, 16));
            Integer second = Integer.valueOf(CheckOut.substring(17, 19));
            // Create DateTime for CheckOut
            DateTime dateTimeCheckOut = DateTime.newInstance(year, month, day, hour, minute, second);
            
            // Adjust the time by adding 5 hours and 30 minutes to convert to IST
            DateTime ISTCheckOut = dateTimeCheckOut.addHours(5).addMinutes(30);
            
            //siteVisit.Check_In__c = ISTCheckIn;
            siteVisit.Check_Out__c = ISTCheckOut;
            // Save the changes
            update siteVisit;
            
            // Return the updated site visit record
            return siteVisit;
        /*} catch (Exception e) {
            // Handle exceptions and return an error message to the front-end
            throw new AuraHandledException('Error updating site visit status: ' + e.getMessage());
        }*/
    }
    @AuraEnabled
    public static string moveToSales(string LeadId,string addNote, string salesUser) {
        system.debug('moveToSales');
        String record = pushToSalesController.moveToSales(LeadId, addNote, salesUser);
        Lead__c leads = [SELECT Id, Name__c, Phone__c, RecordType.Name, Medium__c, Source_Type__c, Allocated_Project__c, Primary_Source__c, CreatedDate FROM Lead__c WHERE Id = :record LIMIT 1];
        return leads.RecordType.Name;
    }
    /* commented out by claude 30-03-26 15:32 - queries standard Lead instead of Lead__c, replaced by getLeadandSiteVisitDetails
    @AuraEnabled(cacheable=true)
    public static Lead getLeadDetailsById(String leadId) {
        system.debug('leadId' + leadId);
        Lead leadRecord = [SELECT Id,Name, Company, Phone, Email,Unit_Preference__c,RecordType.Name,Phone__c,
                           Medium__c,Source_Type__c,Allocated_Project__c, Lead_Status__c, Status, Lead_source__c, CreatedDate
                           FROM Lead WHERE Id = :leadId LIMIT 1];
        return leadRecord;
    }
    */
    @AuraEnabled(cacheable=true)
    public static List<User> fetchSalesUsers() {
        List<User> u = [select Id,Name from User where profile.Name='STM' and IsActive	=true and Availability__c=true and Working__c=true];
        system.debug(u);
        return u;
    }
    
    @AuraEnabled
    public static void saveChanges(Lead__c ldRec, Site_Visit__c svRec, Related_Source__c rsRec, String LeadOwner, String SVOwner, String actionType, Boolean useRoundRobin){
        system.debug('ldRec > '+ldRec);
        system.debug('svRec > '+svRec);
        system.debug('rsRec > '+rsRec);
        system.debug('LeadOwner > '+LeadOwner);
        system.debug('SVOwner > '+SVOwner);
        system.debug('actionType > '+actionType);
        if(String.isNotBlank(ldRec.Lead_source__c)){
            ldRec.Primary_Source__c = ldRec.Lead_source__c;
        }
        if(String.isNotBlank(ldRec.Sub_Source__c)){
            ldRec.Primary_Sub_Source__c = ldRec.Sub_Source__c;
        }
        // ⭐ NEW: If Round Robin is enabled, get user from Round Robin - 18-02-26
        if(useRoundRobin && svRec.Project__c != null){
            Id assignedUserId = RoundRobinHandler.assignSingleSiteVisit(svRec.Project__c, 'Sales');
            
            if(assignedUserId != null){
                svRec.Handled_By__c = assignedUserId;
                SVOwner = assignedUserId;
                ldRec.OwnerId = assignedUserId;
                LeadOwner = assignedUserId;
                
                // Update actionType if needed
                if(actionType == 'NoAction' && ldRec.OwnerId != assignedUserId){
                    actionType = 'ShareRecords';
                }
            } else {
                throw new AuraHandledException('No users available in Round Robin for this project.');
            }
        }
        
        update ldRec;
        
        Site_Visit__c sv = new Site_Visit__c();
        sv.Handled_By__c = svRec.Handled_By__c;
        sv.OwnerId = svRec.Handled_By__c;
        sv.Check_In__c = svRec.Check_In__c;
        sv.CLead__c = ldRec.Id; 
        sv.SV_Completed_Date_Time__c = svRec.SV_Completed_Date_Time__c;
        sv.Remark__c = svRec.Remark__c;
        sv.Status__c = svRec.Status__c;
        // sv.Feedback__c = 'NULL';
        sv.Site_Visit_rating__c = 'Warm';
        sv.Visit_Type__c = svRec.Visit_Type__c;
        sv.Visit_Source_Type__c = svRec.Visit_Source_Type__c;
        sv.Channel_Partner__c = svRec.Channel_Partner__c;
        if(svRec.Id == null){
            sv.Project__c = svRec.Project__c;   
            sv.Date__c = svRec.Date__c;
        }else{
            sv.Id = svRec.Id;
        }
        upsert sv;
 
        if(actionType == 'insertRelatedSource'){
            if(rsRec != null ){
                Related_Source__c rs = rsRec;
                rs.CLead__c = ldRec.Id;
                insert rs;
            }
        }
        else if(actionType == 'CancelFollowups'){
            /* 'Missed' follow-up status removed — do not auto-mark open follow-ups as Missed when GRE pushes the lead to Sales.
            List<Follow_up__c> FupList = [SELECT Id, Name, status__c, Description__c FROM Follow_up__c WHERE CLead__c =: ldRec.Id and status__c = 'Scheduled'];
            if(!FupList.isEmpty()){
                for(Follow_up__c fup : FupList){
                    fup.status__c = 'Missed';
                    fup.Description__c = 'Cancelled by System as GRE Pushed the Lead to Sales Team';
                }
                Update FupList;
            }
            */
        }
        else if(actionType == 'ShareRecords'){
            // Sharing Lead to SV Handler/SV Owner
            List<Lead__Share> existingLdShares = [SELECT Id, ParentId, UserOrGroupId FROM Lead__Share WHERE ParentId = :ldRec.Id AND UserOrGroupId = :SVOwner];
            if (existingLdShares.isEmpty()) {
                Lead__Share ldShr = new Lead__Share();
                ldShr.ParentId = ldRec.Id;  // For custom objects, use ParentId instead of LeadId
                ldShr.UserOrGroupId = SVOwner;
                ldShr.AccessLevel = 'Read';  // For custom objects, use AccessLevel instead of LeadAccessLevel
                ldShr.RowCause = Schema.Lead__Share.RowCause.Manual;
                insert ldShr;
                System.debug('✅ Lead__c shared with user: ' + SVOwner);
            }else {
                System.debug('⚠️ User already has Lead access. Skipping share.');
            }
            
            // Sharing Site Visit to Lead Owner
            List<Site_Visit__Share> existingSvShares = [ SELECT Id, ParentId, UserOrGroupId FROM Site_Visit__Share WHERE ParentId = :sv.Id AND UserOrGroupId = :LeadOwner];
            if (existingSvShares.isEmpty()) {
                Site_Visit__Share svShr = new Site_Visit__Share();
                svShr.ParentId = sv.Id;
                svShr.UserOrGroupId = LeadOwner;
                svShr.AccessLevel = 'Read';
                svShr.RowCause = Schema.Site_Visit__Share.RowCause.Manual;
                insert svShr;
                System.debug('✅ Site Visit shared with Lead Owner: ' + LeadOwner);
            } else {
                System.debug('⚠️ Lead Owner already has Site Visit access. Skipping share.');
            }
        }

        // added by claude 30-03-26 15:32 - Share Lead to original Pre-Sales user when routing Pre-Sales → Sales
        if (actionType == 'CancelFollowups' && ldRec.Pre_Sales_User__c != null) {
            List<Lead__Share> existingPreSalesShares = [SELECT Id FROM Lead__Share WHERE ParentId = :ldRec.Id AND UserOrGroupId = :ldRec.Pre_Sales_User__c];
            if (existingPreSalesShares.isEmpty()) {
                Lead__Share preSalesShare = new Lead__Share();
                preSalesShare.ParentId = ldRec.Id;
                preSalesShare.UserOrGroupId = ldRec.Pre_Sales_User__c;
                preSalesShare.AccessLevel = 'Read';
                preSalesShare.RowCause = Schema.Lead__Share.RowCause.Manual;
                insert preSalesShare;
                System.debug('Lead shared with Pre-Sales user: ' + ldRec.Pre_Sales_User__c);
            }
        }
    }

    //added by karthik 18-11-25
    public class UserInfoWrapper {
        @AuraEnabled public String profileName;
        @AuraEnabled public String projectPicklistValue;
        @AuraEnabled public Id userId;
    }
    
    @AuraEnabled
    public static UserInfoWrapper getCurrentUserDetails() {
        User u = [SELECT Id, Profile.Name, Project__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        UserInfoWrapper w = new UserInfoWrapper();
        w.profileName = u.Profile.Name;
        w.projectPicklistValue = u.Project__c;
        w.userId = u.Id;
        return w;
    }
    
    // added by claude 30-03-26 08:49 - Round-robin lead assignment for GRE new lead creation
    @AuraEnabled
    public static void assignLeadRoundRobin(Id leadId) {
        Lead__c ld = [SELECT Id, Allocated_Project__c FROM Lead__c WHERE Id = :leadId LIMIT 1];

        if (ld.Allocated_Project__c == null) {
            throw new AuraHandledException('Lead does not have an allocated project.');
        }

        Id assignedUserId = RoundRobinHandler.assignSingleLead(ld.Allocated_Project__c, 'Sales');

        if (assignedUserId != null) {
            ld.OwnerId = assignedUserId;
            ld.Sales_User__c = assignedUserId;
            ld.SV_User__c = assignedUserId;
            ld.Lead_Assigned__c = true;
            // updated by claude 31-03-26 - Set status to Site Visit Completed to match saveChanges pattern
            // and prevent LeadTrigger before update from calling bulk assignLead (double round-robin)
            ld.Lead_Status__c = 'Site Visit Completed';
            update ld;

            // added by claude 30-03-26 15:32 - Auto-create completed Site Visit for GRE new lead
            Site_Visit__c sv = new Site_Visit__c();
            sv.CLead__c = leadId;
            sv.Status__c = 'Completed';
            sv.Handled_By__c = assignedUserId;
            sv.OwnerId = assignedUserId;
            sv.Check_In__c = System.now();
            sv.SV_Completed_Date_Time__c = System.now();
            sv.Project__c = ld.Allocated_Project__c;
            sv.Date__c = System.now();
            // sv.Feedback__c = 'NULL';
            sv.Site_Visit_rating__c = 'Warm';
            sv.Remark__c = 'Auto-created by GRE during new lead creation';
            insert sv;
        } else {
            throw new AuraHandledException('No sales users available in Round Robin for this project.');
        }
    }

    @AuraEnabled
    public static void updateSVCheckoutTime(Id svId, Datetime checkoutTime) {
        Site_Visit__c sv = [SELECT Id FROM Site_Visit__c WHERE Id = :svId LIMIT 1];
        sv.Check_Out__c = checkoutTime;
        update sv;
    }

}