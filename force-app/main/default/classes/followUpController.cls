public class followUpController { // Updated: 2026-04-01 12:00  
    
    @AuraEnabled
    public static List<Follow_Up__c> getFollowUpDetails(String leadId) {
        // Fetch only the current user's Scheduled follow-ups for this Lead
        return [SELECT Id, Status__c FROM Follow_Up__c WHERE CLead__c = :leadId AND OwnerId = :UserInfo.getUserId() AND Status__c = 'Scheduled' LIMIT 1];
    }
    
    public static String dateFormat(String followupdate){ 	String dateTimeFormatted='';	
     String formattedDate='';
     String[] splitDateTime=followupdate.split(',');
     String[] splitDate=splitDateTime[0].split('/');
     for(integer i=splitDate.size()-1;i>=0;i--)
     {
         formattedDate+=splitDate[i];
         if(i!=0)
             formattedDate+='-';
     }
     
     dateTimeFormatted=	formattedDate+' '+splitDateTime[1];
     
     return dateTimeFormatted;
    }
    
     @AuraEnabled
    public static void createFollowUpApex(String followUpRecord, string SiteVisitId, string LeadId) {
        system.debug('SiteVisitId '+SiteVisitId+' LeadId '+LeadId);
        Site_Visit__c sv = new Site_Visit__c();
        string LeadIds = LeadId ;
        if(SiteVisitId != null && LeadId == ''){
            sv = [select Id, name, CLead__c from Site_Visit__c where Id=:SiteVisitId limit 1];
            LeadIds = sv.CLead__c;
            system.debug('LeadIds '+LeadIds);
        }
        
        
        // Deserialize the JSON string into a map
        Map<String, Object> followUpMap = (Map<String, Object>) JSON.deserializeUntyped(followUpRecord);
        String scheduledDateString = (String) followUpMap.get('Scheduled_Date__c');
        String followupComment = (String) followUpMap.get('Comments__c'); //added by karthik 10-11-25
        // Parse the date and time components
            Integer year = Integer.valueOf(scheduledDateString.substring(0, 4));
            Integer month = Integer.valueOf(scheduledDateString.substring(5, 7));
            Integer day = Integer.valueOf(scheduledDateString.substring(8, 10));
            Integer hour = Integer.valueOf(scheduledDateString.substring(11, 13));
            Integer minute = Integer.valueOf(scheduledDateString.substring(14, 16));
            Integer second = Integer.valueOf(scheduledDateString.substring(17, 19));
            
            // Manually create DateTime instance
            DateTime dateTimeScheduled = DateTime.newInstance(year, month, day, hour, minute, second);
            // Adjust the time by adding 5 hours and 30 minutes to convert to IST
            DateTime ISTScheduledDate = dateTimeScheduled.addHours(5).addMinutes(30);
        
        
        // Create a new Follow-up record
        Follow_up__c followUp = new Follow_up__c(
            Scheduled_Date__c = ISTScheduledDate,
            Subject__c = (String) followUpMap.get('Subject__c'),
            Comments__c = (String) followUpMap.get('Comments__c'),
            Description__c = (String) followUpMap.get('Description__c'),
            CLead__c = LeadIds,
            Status__c = 'Scheduled'
        );
		
        try{
            // Insert the Follow-up record
            insert followUp;
            // Added by karthik 10-11-25 to Update Lead's last note
            if (!String.isBlank(followupComment)) {
                AddNoteController.updateLastNote(LeadIds, followupComment);
            }
        }catch(exception e){
            system.debug('An error occurred: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void LeadUpdation(string leadRecord){
        system.debug('leadRecord '+leadRecord);
        Map<String, Object> leadMap = (Map<String, Object>) JSON.deserializeUntyped(leadRecord);
        try{
            Lead__c ld = new Lead__c();
			ld.Id = (string)leadMap.get('Id');
            ld.Lead_Status__c = (string)leadMap.get('Lead_Status__c');
            ld.Unqualified_Reason__c = (string)leadMap.get('Unqualified_Reason__c'); 
            ld.Closed_Lost_Reason__c = (String)leadMap.get('Closed_Lost_Reason__c');
            ld.Unqualified_Closed_Lost_Remarks__c = (String)leadMap.get('Unqualified_Closed_Lost_Remarks__c');
            update ld;  
            
            // Append to Lead.Last_Note__c if user entered remarks
            if (!String.isBlank(ld.Unqualified_Closed_Lost_Remarks__c)) {
                AddNoteController.updateLastNote(ld.Id,ld.Unqualified_Closed_Lost_Remarks__c);   
            }
        }
        catch(exception e){
            System.debug('An error occurred: ' + e.getMessage());
            throw new AuraHandledException('Failed to update Lead: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void createSiteVisitApex(String siteVisitRecord, String leadOwnerId) {

        // Deserialize the JSON string into a map
        Map<String, Object> siteVisitMap = (Map<String, Object>) JSON.deserializeUntyped(siteVisitRecord);
        String scheduledDateString = (String) siteVisitMap.get('Date__c');
        // Parse the date and time components
            Integer year = Integer.valueOf(scheduledDateString.substring(0, 4));
            Integer month = Integer.valueOf(scheduledDateString.substring(5, 7));
            Integer day = Integer.valueOf(scheduledDateString.substring(8, 10));
            Integer hour = Integer.valueOf(scheduledDateString.substring(11, 13));
            Integer minute = Integer.valueOf(scheduledDateString.substring(14, 16));
            Integer second = Integer.valueOf(scheduledDateString.substring(17, 19));

            // Manually create DateTime instance
            DateTime dateTimeScheduled = DateTime.newInstance(year, month, day, hour, minute, second);
            // Adjust the time by adding 5 hours and 30 minutes to convert to IST
            DateTime ISTScheduledDate = dateTimeScheduled.addHours(5).addMinutes(30);


        // Create a new Site Visit record
        Site_Visit__c siteVisit = new Site_Visit__c(
            Date__c = ISTScheduledDate,
            Project__c = (String) siteVisitMap.get('Project__c'),
            CLead__c = (String) siteVisitMap.get('CLead__c'),
            Feedback__c = (String) siteVisitMap.get('Feedback__c'),
            Status__c = (String) siteVisitMap.get('Status__c'),
            Visit_Type__c = (String) siteVisitMap.get('Visit_Type__c')
            // Visit_Source_Type__c = (String) siteVisitMap.get('Visit_Source_Type__c')
        );

        // Set Channel Partner if provided
        String channelPartnerId = (String) siteVisitMap.get('Channel_Partner__c');
        if (String.isNotBlank(channelPartnerId)) {
            siteVisit.Channel_Partner__c = channelPartnerId;
        }

        // Assign Site Visit to the same owner as the Lead
        if (String.isNotBlank(leadOwnerId)) {
            siteVisit.OwnerId = leadOwnerId;
        }

        try {
            insert siteVisit;
        } catch (Exception e) {
            System.debug('An error occurred: ' + e.getMessage());
            throw new AuraHandledException('Failed to create Site Visit: ' + e.getMessage());
        }

    }
    
    @AuraEnabled
    public static Lead__c fetchLeadDetails(String recordId) {
        Lead__c ld = new Lead__c();
        if(recordId != null){
           ld = [select Id,Name, RecordTypeId, RecordType.Name,Lead_Status__c from Lead__c where Id=:recordId limit 1]; 
        }
        return ld;
    }
    
    @AuraEnabled
    public static List<string> fetchSubject(){
        List<String> pickListValuesList= new List<String>();
        Schema.DescribeFieldResult fieldResult = Follow_up__c.Subject__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for( Schema.PicklistEntry pickListVal : ple){
            pickListValuesList.add(pickListVal.getLabel());
        }
        system.debug('pickListValuesList '+pickListValuesList);
        return pickListValuesList;
    }
    
    @AuraEnabled
    public static List<string> fetchProjectList(){
        List<String> pickListValuesList= new List<String>();
        Schema.DescribeFieldResult fieldResult = Site_Visit__c.Project__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for( Schema.PicklistEntry pickListVal : ple){
            pickListValuesList.add(pickListVal.getLabel());
        }
        system.debug('pickListValuesList '+pickListValuesList);
        return pickListValuesList;
    }
    
    @AuraEnabled
    public static List<string> fetchUnqualifiedReasonList(){
        List<String> pickListValuesList= new List<String>();
        Schema.DescribeFieldResult fieldResult = Lead__c.Unqualified_Reason__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for( Schema.PicklistEntry pickListVal : ple){
            pickListValuesList.add(pickListVal.getLabel());
        }
        system.debug('pickListValuesList '+pickListValuesList);
        return pickListValuesList;
    }
    
    @AuraEnabled
    public static List<string> fetchClosedLostReasonList(){
        List<String> pickListValuesList= new List<String>();
        Schema.DescribeFieldResult fieldResult = Lead__c.Closed_Lost_Reason__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for( Schema.PicklistEntry pickListVal : ple){
            pickListValuesList.add(pickListVal.getLabel());
        }
        system.debug('pickListValuesList '+pickListValuesList);
        return pickListValuesList;
    }
    
    //added by karthik 06-11
    public class InitDataWrapper {
        @AuraEnabled public Lead__c leadRecord { get; set; }
        @AuraEnabled public List<String> subjectList { get; set; }
        @AuraEnabled public List<String> unqualifiedReasonList { get; set; }
        @AuraEnabled public List<String> projectList { get; set; }
        @AuraEnabled public List<String> closedLostReasonList { get; set; }
        @AuraEnabled public List<String> visitTypeList { get; set; }
    }

    @AuraEnabled
    public static InitDataWrapper fetchInitData(String recordId) {
        InitDataWrapper wrapper = new InitDataWrapper();
        
        //Added by Pattu
        //Fetch Lead details
        if (recordId != null) {
            wrapper.leadRecord = [
                SELECT Id, Name, RecordTypeId, RecordType.Name, Lead_Status__c, Allocated_Project__c, OwnerId FROM Lead__c WHERE Id = :recordId LIMIT 1 ];
                       
            }
        
        // Fetch picklists
        wrapper.subjectList = getPicklistValues(Follow_up__c.Subject__c);
        wrapper.unqualifiedReasonList = getPicklistValues(Lead__c.Unqualified_Reason__c);
        wrapper.projectList = getPicklistValues(Site_Visit__c.Project__c);
        wrapper.closedLostReasonList = getPicklistValues(Lead__c.Closed_Lost_Reason__c);
        wrapper.visitTypeList = getActivePicklistValues(Site_Visit__c.Visit_Type__c);

        return wrapper;
    }

    // Utility method for any picklist
    private static List<String> getPicklistValues(Schema.SObjectField field) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry ple : field.getDescribe().getPicklistValues()) {
            values.add(ple.getLabel());
        }
        return values;
    }

    // Returns only active picklist values for a field
    private static List<String> getActivePicklistValues(Schema.SObjectField field) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry ple : field.getDescribe().getPicklistValues()) {
            if (ple.isActive()) {
                values.add(ple.getLabel());
            }
        }
        return values;
    }
    
    //added by karthik 14-11-25
    @AuraEnabled
    public static Boolean hasScheduledSV(String leadId, String projectName) {
        if (String.isBlank(leadId) || String.isBlank(projectName)) return false;
        
        return [SELECT Id FROM Site_Visit__c WHERE CLead__c = :leadId AND Project__c = :projectName AND Status__c IN ('Scheduled', 'Rescheduled') LIMIT 1].size() > 0;
    }
    
    
    
    // Return current Lead status (used to decide auto-update)
    @AuraEnabled
    public static String getLeadStatus(String leadId) {
        if (String.isBlank(leadId)) return null;
        Lead__c l = [SELECT Lead_Status__c FROM Lead__c WHERE Id = :leadId LIMIT 1];
        return l == null ? null : l.Lead_Status__c;
    }
    
    //for newsitevisit component
    @AuraEnabled
    public static void updateLeadStatusOnly(String leadId, String newStatus) {
        Lead__c l = new Lead__c(Id = leadId,Lead_Status__c = newStatus);
        update l;
    }

    @AuraEnabled
    public static Site_Visit__c fetchSiteVisitDetails(String recordId) {
        if (String.isBlank(recordId)) return null;
        return [SELECT Id, Date__c, CLead__c, OwnerId FROM Site_Visit__c WHERE Id = :recordId LIMIT 1];
    }
}