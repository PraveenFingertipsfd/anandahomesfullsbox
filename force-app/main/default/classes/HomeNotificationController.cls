// Last Modified: 2026-07-02
public class HomeNotificationController {
    
@auraEnabled
    public static list<Follow_Up__c> getFollowUpInformation()
    {
        System.debug(userinfo.getFirstName()+'===>'+userinfo.getUserId());
        List<Follow_Up__c> followUpDetails=[Select Id,Name,Scheduled_Date__c,Comments__c,Status__c,Owner.Name,CLead__c,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Last_Comment__c,CLead__r.Id from Follow_Up__c  where Status__c='Scheduled' AND Scheduled_Date__c=today AND OwnerId =:userInfo.getUserId() order by Scheduled_Date__c  ];
        System.debug(followUpDetails);
        return followUpDetails;
    }

@auraEnabled
    public static list<Follow_Up__c> getPendingFollowUpInformation()
    {
        List<Follow_Up__c> followUpDetails=[Select Id,Name,Scheduled_Date__c,Status__c,Comments__c,Owner.Name,CLead__c,CLead__r.Last_Comment__c,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Id from Follow_Up__c  where (Status__c='Scheduled' ) AND Scheduled_Date__c=yesterday AND OwnerId =:userInfo.getUserId() order by Scheduled_Date__c  ];
       System.debug(followUpDetails);
        return followUpDetails;
    }
    
    
    @auraEnabled
    public static list<Site_Visit__c> getPendingSiteVistInformation()
    {
        System.debug('Sv Details');
        List<Site_Visit__c> svDetails=[Select Id,Name,CLead__c,Date__c,Status__c,Feedback__c,Owner.Name,CLead__r.Last_Comment__c,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Id,Canceled_Reason__c,CLead__r.Requirement_Description__c from Site_Visit__c  where (Status__c='Scheduled' OR Status__c='Reschedule' OR Status__c='Missed' ) AND Date__c=yesterday AND OwnerId =:userInfo.getUserId() order by Date__c ];
        return svDetails;
    }
    
    @auraEnabled
    public static list<Site_Visit__c> getSiteVistInformation()
    {
        System.debug('Sv Details');
        List<Site_Visit__c> svDetails=[Select Id,Name,CLead__c,Date__c,Status__c,Feedback__c,Owner.Name,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Last_Comment__c,CLead__r.Id,Canceled_Reason__c,CLead__r.Requirement_Description__c from Site_Visit__c  where (Status__c='Scheduled' OR Status__c='Reschedule' ) AND Date__c=today AND OwnerId =:userInfo.getUserId() order by Date__c ];
        return svDetails;
    }
    

    @auraEnabled
    public static String updateFollowupDetails(String recID, String FLStatus,String FLRemarks) {
        List<Follow_Up__c> svData = [
            SELECT Id, Status__c, Comments__c, Completed_Date__c, Call_Duration_In_Mins__c
            FROM Follow_Up__c
            WHERE Id = :recID
            LIMIT 1
        ];

        if (svData.isEmpty()) {
            return 'Record not found';
        }

        svData[0].Status__c   = FLStatus;
        svData[0].Comments__c = FLRemarks;
        // Follow_up__c has three Completed-gated validation rules:
        //   Follow_ups_Completed_Date    -> requires Completed_Date__c
        //   Follow_Ups_Remarks_Mandatory -> requires Comments__c (set above from modal)
        //   Call_Duration_Mandatory      -> requires Call_Duration_In_Mins__c
        // The Today's Agenda modal only captures Status + Remarks, so default the other
        // two fields here. Existing values are preserved.
        if (FLStatus == 'Completed') {
            if (svData[0].Completed_Date__c == null) {
                svData[0].Completed_Date__c = System.now();
            }
            if (svData[0].Call_Duration_In_Mins__c == null) {
                svData[0].Call_Duration_In_Mins__c = 0;
            }
        }

        try {
            update svData[0];
            return 'Updated';
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }
    
    @AuraEnabled
    public static datawrapper todaysLeads(Integer pageSize, Integer pageNumber) {
        datawrapper dw = new datawrapper();
        Integer offset = (pageNumber - 1) * pageSize;
        
        String userProfile = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId()].Profile.Name;
        
        List<Lead__c> lstld;
        Integer leadCount;

        if (userProfile == 'Pre-Sales Executive') {
            lstld = [SELECT Id, Name, Name__c, Projects__c, Lead_Status__c, Lead_Type__c,
                     Allocated_Project__c, Secondary_Email__c, Phone__c, Secondary_Phone__c,
                     CreatedDate
                     FROM Lead__c
                     WHERE CreatedDate = TODAY AND OwnerId = :UserInfo.getUserId()
                     ORDER BY CreatedDate DESC
                     LIMIT :pageSize OFFSET :offset];

            leadCount = [SELECT COUNT() FROM Lead__c WHERE CreatedDate = TODAY AND OwnerId = :UserInfo.getUserId() ];

        } else if (userProfile == 'Sales') {
            lstld = [SELECT Id, Name, Name__c, Projects__c, Lead_Status__c, Lead_Type__c, Lead_source__c,
                     Allocated_Project__c, Secondary_Email__c, Phone__c, Secondary_Phone__c,
                      CreatedDate
                     FROM Lead__c
                     WHERE Pushed_On__c = TODAY AND OwnerId = :UserInfo.getUserId()
                     ORDER BY Pushed_On__c DESC
                     LIMIT :pageSize OFFSET :offset];

            leadCount = [SELECT COUNT() FROM Lead__c WHERE Pushed_On__c = TODAY AND OwnerId = :UserInfo.getUserId() ];
        }else {
        // Default: show leads created today for any other profile
        lstld = [
            SELECT Id, Name, Name__c, Projects__c, Lead_Status__c, Lead_Type__c,
                   Allocated_Project__c, Secondary_Email__c, Phone__c, Secondary_Phone__c,
                   CreatedDate
            FROM Lead__c
            WHERE CreatedDate = TODAY AND OwnerId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT :pageSize OFFSET :offset
        ];

        leadCount = [
            SELECT COUNT()
            FROM Lead__c
            WHERE CreatedDate = TODAY
        ];
    }
    
    dw.ldListtodays = lstld;
    dw.todaysldCount = leadCount;
    return dw;
}
    
    public class datawrapper{
        @AuraEnabled
        public Decimal todaysldCount {get; set;}
        @AuraEnabled
        public List<Lead__c> ldListtodays {get; set;}
    }
    
    @AuraEnabled
    public static String getUserName() {
        String userId = UserInfo.getUserId();
        User currentUser = [SELECT Name FROM User WHERE Id = :userId];
        return currentUser.Name;
    }

}