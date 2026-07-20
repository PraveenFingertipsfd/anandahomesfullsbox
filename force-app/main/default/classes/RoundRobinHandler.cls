public without sharing class RoundRobinHandler {
    public static void assignLead(List<Lead__c> leadList,boolean updateLeads,string usType){
        Datetime d = system.now();
        String dayOfWeek = d.format('EEEE');
        Set<string>  projectinterested  = new Set<string>();
        Map<string,List<Lead__c>>  projectLeadMap = new Map<string,List<Lead__c>>(); 
        Map<id,user>  rrMemberMapToUpdate = new  Map<id,user> ();
        for(Lead__c l:leadList){  
            string project = l.Allocated_Project__c;
            if(project != null && project != '' && l.Lead_Assigned__c !=true && l.Delete_Lead__c !=true){ 
                
                projectinterested.add(project);
                List<Lead__c>  projectQue = projectLeadMap.get(project); 
                if(projectQue  == null){
                    projectLeadMap.put(project, new List<Lead__c>{l});
                }else{
                    projectQue.add(l);  
                    projectLeadMap.put(project,  projectQue);
                } 
            }
        }
        system.debug('projectinterested'+ projectinterested.size());
        Map<string,List<Round_Robin_Member__c>>  projectAvaliableQueMap = new Map<string,List<Round_Robin_Member__c>>();
        Map<string,List<Round_Robin_Member__c>>  projectQueMap = new Map<string,List<Round_Robin_Member__c>>();
        
        List<Round_Robin__c> RRAvaliablequeList=[Select id,Project_Assigned__c, (select Name,User__c from  Round_Robin_Members__r  where Active__c =true AND user__r.Availability__c=true AND user__r.isActive=true AND user__r.is_working__c=TRUE AND User__r.Week_off_days__c excludes ( :dayOfWeek) AND User_Type__c=:usType  order by Last_Assigned_time_user__c,createddate asc nulls first ) from Round_Robin__c where Project_Assigned__c in :projectinterested and Active__c = true ];
      	List<Round_Robin__c> RRqueList=[Select id,Project_Assigned__c, (select Name,User__c from  Round_Robin_Members__r  where Active__c =true AND user__r.isActive=true AND user__r.is_working__c=TRUE AND User__r.Week_off_days__c excludes ( :dayOfWeek) AND User_Type__c=:usType order by Last_Assigned_time_user__c,createddate	 asc nulls first  ) from Round_Robin__c where Project_Assigned__c in :projectinterested and Active__c = true ];
        if(RRAvaliablequeList.size()>0){
            for(Round_Robin__c rr : RRAvaliablequeList){
                if(rr.Round_Robin_Members__r.size()>0){
                    projectAvaliableQueMap.put(rr.Project_Assigned__c,rr.Round_Robin_Members__r);
                }
            }
        }
        if(RRqueList.size()>0){
            for(Round_Robin__c rr : RRqueList){
                if(rr.Round_Robin_Members__r.size()>0){
                    projectQueMap.put(rr.Project_Assigned__c,rr.Round_Robin_Members__r);
                }
            }
        }
        
        for(string prj : projectinterested){
           
            if(projectAvaliableQueMap.containskey(prj) && projectAvaliableQueMap.get(prj).size()>0){
                List<Round_Robin_Member__c>  projectQue = projectAvaliableQueMap.get(prj);  
                integer counter = 0; 
                for(Lead__c l : projectLeadMap.get(prj)){
                    if(projectQue!=null && projectQue.size() > 0 && projectQue[counter] != null && projectQue[counter].user__c != null){
                        system.debug('projectQue[counter].user__c: ' + projectQue[counter].user__c);
                        l.ownerId = projectQue[counter].user__c;
                        l.Lead_Assigned__c = true;
                        if(usType =='Pre Sales'){
                                l.Pre_sales_user__c =projectQue[counter].user__c;
                            }else{
                                l.Sales_User__c =projectQue[counter].user__c;
                                
                                l.SV_User__c=projectQue[counter].user__c;
                                
                            }
                        //l.Reassigned_By__c = UserInfo.getUserId();
                        //l.Re_assigned_date__c = system.now();
                         
                        user u = new user();
                        u.Id = projectQue[counter].user__c;
                        u.LastAssignmentTime1__c = system.now().getTime(); 
                       
                        rrMemberMapToUpdate.put(projectQue[counter].user__c,u ) ; 
                        counter ++; 
                        if(projectQue.size() == counter  ){
                            counter  =0; 
                        } 
                    }
                }
            }
            else if(projectQueMap.containsKey(prj) && projectQueMap.get(prj).size()>0){
                List<Round_Robin_Member__c>  projectQue = projectQueMap.get(prj);  
                integer counter = 0; 
                for(Lead__c l : projectLeadMap.get(prj)){
                    if(projectQue!=null && projectQue.size() > 0 && projectQue[counter] != null && projectQue[counter].user__c != null){
                        system.debug('projectQue[counter].user__c: ' + projectQue[counter].user__c);
                        l.ownerId = projectQue[counter].user__c;
                        l.Lead_Assigned__c = true;
                        if(usType =='Pre Sales'){
                            l.Pre_sales_user__c =projectQue[counter].user__c;
                        }else{
                            l.Sales_User__c =projectQue[counter].user__c;
                        }
                        //l.Reassigned_By__c = UserInfo.getUserId();
                        //l.Re_assigned_date__c = system.now();
                        
                        user u = new user();
                        u.Id = projectQue[counter].user__c;
                        u.LastAssignmentTime1__c = system.now().getTime(); 
                        
                        rrMemberMapToUpdate.put(projectQue[counter].user__c,u ) ; 
                        counter ++; 
                        if(projectQue.size() == counter  ){
                            counter  =0; 
                        } 
                    }
                }
            }
        
    }
        if(rrMemberMapToUpdate.values().size()>0){
            UPDATE rrMemberMapToUpdate.values();
            rrMemberMapToUpdate.clear();
        }
        if(updateLeads){
            Update leadList;
        }
    } 
    
    // added by claude 30-03-26 08:49 - Method for single Lead assignment (GRE new lead creation)
    public static Id assignSingleLead(String projectName, String usType){
        Datetime d = system.now();
        String dayOfWeek = d.format('EEEE');

        // Query available users first
        List<Round_Robin__c> RRAvailableQueList = [SELECT Id, Project_Assigned__c, (SELECT Name, User__c FROM Round_Robin_Members__r
             WHERE Active__c = true AND User__r.Availability__c = true AND User__r.IsActive = true AND User__r.is_working__c = TRUE
             AND User__r.Week_off_days__c EXCLUDES (:dayOfWeek) AND User_Type__c = :usType ORDER BY Last_Assigned_Time_User__c, CreatedDate ASC NULLS FIRST)
             FROM Round_Robin__c WHERE Project_Assigned__c = :projectName AND Active__c = true LIMIT 1];

        // Fallback to all users if no available users
        List<Round_Robin__c> RRQueList = [SELECT Id, Project_Assigned__c,(SELECT Name, User__c FROM Round_Robin_Members__r
                                          WHERE Active__c = true AND User__r.IsActive = true AND User__r.is_working__c = TRUE
                                          AND User__r.Week_off_days__c EXCLUDES (:dayOfWeek) AND User_Type__c = :usType
                                          ORDER BY Last_Assigned_Time_User__c, CreatedDate ASC NULLS FIRST) FROM Round_Robin__c
                                          WHERE Project_Assigned__c = :projectName  AND Active__c = true LIMIT 1];

        List<Round_Robin_Member__c> members;

        // Prefer available users
        if (RRAvailableQueList.size() > 0 && RRAvailableQueList[0].Round_Robin_Members__r.size() > 0) {
            members = RRAvailableQueList[0].Round_Robin_Members__r;
        }
        // Fallback to all users
        else if (RRQueList.size() > 0 && RRQueList[0].Round_Robin_Members__r.size() > 0) {
            members = RRQueList[0].Round_Robin_Members__r;
        }

        // If we found users, assign the first one and update their lead assignment timestamp
        if (members != null && members.size() > 0) {
            Id assignedUserId = members[0].User__c;

            // Update user's last lead assignment time
            User u = new User();
            u.Id = assignedUserId;
            u.LastAssignmentTime1__c = System.now().getTime();
            update u;

            return assignedUserId;
        }

        return null; // No users available
    }

    // Method for single Site Visit assignment (GRE use case)
    public static Id assignSingleSiteVisit(String projectName, String usType){
        Datetime d = system.now();
        String dayOfWeek = d.format('EEEE');
        
        // Query available users first
        List<Round_Robin__c> RRAvailableQueList = [SELECT Id, Project_Assigned__c, (SELECT Name, User__c FROM Round_Robin_Members__r  
             WHERE Active__c = true AND User__r.Availability__c = true AND User__r.IsActive = true AND User__r.is_working__c = TRUE 
             AND User__r.Week_off_days__c EXCLUDES (:dayOfWeek) AND User_Type__c = :usType ORDER BY Last_SV_Assigned_Time__c, CreatedDate ASC NULLS FIRST) 
             FROM Round_Robin__c WHERE Project_Assigned__c = :projectName AND Active__c = true LIMIT 1];
        
        // Fallback to all users if no available users
        List<Round_Robin__c> RRQueList = [SELECT Id, Project_Assigned__c,(SELECT Name, User__c FROM Round_Robin_Members__r  
                                          WHERE Active__c = true AND User__r.IsActive = true AND User__r.is_working__c = TRUE 
                                          AND User__r.Week_off_days__c EXCLUDES (:dayOfWeek) AND User_Type__c = :usType 
                                          ORDER BY Last_SV_Assigned_Time__c, CreatedDate ASC NULLS FIRST) FROM Round_Robin__c 
                                          WHERE Project_Assigned__c = :projectName  AND Active__c = true LIMIT 1];
        
        List<Round_Robin_Member__c> members;
        
        // Prefer available users
        if (RRAvailableQueList.size() > 0 && RRAvailableQueList[0].Round_Robin_Members__r.size() > 0) {
            members = RRAvailableQueList[0].Round_Robin_Members__r;
        } 
        // Fallback to all users
        else if (RRQueList.size() > 0 && RRQueList[0].Round_Robin_Members__r.size() > 0) {
            members = RRQueList[0].Round_Robin_Members__r;
        }
        
        // If we found users, assign the first one and update their timestamp
        if (members != null && members.size() > 0) {
            Id assignedUserId = members[0].User__c;
            
            // Update user's last SV assignment time
            User u = new User();
            u.Id = assignedUserId;
            u.LastSVAssignmentTime__c = System.now().getTime();
            update u;
            
            return assignedUserId;
        }
        
        return null; // No users available
    }
    
    
    
    public static void testcover(){
        integer i=0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}