public class transferLeadController {
    public static Boolean pushToSales = true;
    public static Boolean transferLead = false;
    @auraEnabled
    public static Boolean getRecordAccess(String recId){
        UserRecordAccess ura = [SELECT RecordId, HasEditAccess FROM UserRecordAccess WHERE UserId = :UserInfo.getUserId() AND RecordId = :recId];
        return ura.HasEditAccess;
    }
    
    @auraEnabled
    public static Boolean getUserType(){
        Boolean userT = false;
        String usType = [select id,name,Profile.Name from User where Id =: UserInfo.getUserId()].Profile.Name;
        if(usType == 'System Administrator'){
            userT = true;
        }
        return userT;
    }
    
    @auraEnabled
    public static List<String> getProjectNames(string recId)
    {
        system.debug(recId);
        Lead__c con = [SELECT Id,Allocated_project__c FROM Lead__c WHERE Id=:recId];
        Schema.DescribeFieldResult fieldResult = Lead__c.Allocated_Project__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        List<String> selectOpt = new List<String>();
        
        for( Schema.PicklistEntry f : ple)
        {
            if(con.Allocated_Project__c !=f.getValue()){
                selectOpt.add(f.getValue());
            }
            
        }     
        return selectOpt;
    }
    
    @auraEnabled
    public static List<String> getPickListValues(){
        List<String> pickListValuesList= new List<String>();
        Schema.DescribeFieldResult fieldResult = Lead__c.Allocated_Project__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for( Schema.PicklistEntry pickListVal : ple){
            pickListValuesList.add(pickListVal.getLabel());
        }     
        return pickListValuesList;
    }
    
    @AuraEnabled
    public static List<User> getAllUsers(string leadId){
        Lead__c ld = [SELECT Id,ownerId FROM Lead__c WHERE Id=:leadId ];
        string str= [select id,name from profile where id=:userinfo.getProfileId()].Name;
        
        return [SELECT Id,Name FROM user where isActive=TRUE AND Id!=:ld.OwnerId ];
        
        
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getCountryAndCode() {
        Map<String, String> countryMap = new Map<String, String>();
        List<Country_Code_Mapping__mdt> countryMetadata = [SELECT Label, CountryCode__c FROM Country_Code_Mapping__mdt ];
        for (Country_Code_Mapping__mdt country : countryMetadata) {
            countryMap.put(country.Label, country.CountryCode__c);
        }
        system.debug('====='+countryMap);
        return countryMap;
    }
     @AuraEnabled(cacheable=true)
    public static List<User> getSalesUsers() {
        // Query users with sales profile - adjust the profile name as needed
        return [SELECT Id, Name FROM User  WHERE IsActive = true  AND Profile.Name ='Sales'  ORDER BY Name];
    }
    
   /* @auraEnabled
    public static string moveToSales(string LeadId, string allocatedProject, string tReason, Boolean checkbox, string owner){
        transferLead = true;
        lead__c c = [SELECT Name,Phone__c,Email__c,Country__c,Leadsource__c,sub_source__c,Country_code__c,Secondary_phone__c,Secondary_email__c,Secondary_country__c,Secondary_Country_code__c,Proffession__c,Residential_Place__c FROM lead__c WHERE Id=:LeadId];
        lead__c con = new lead__c();
        con.Main_Lead__c = LeadId;
        con.Allocated_Project__c = allocatedProject;
        //con.FirstName = c.Name;
        con.Name = c.Name;
        con.Phone__c = c.Phone__c;
        con.Email__c = c.Email__c;
        con.Country__c = c.Country__c;
        con.Country_Code__c = c.Country_Code__c;
        con.Secondary_Email__c = c.Secondary_Email__c;
        con.Secondary_Phone__c = c.Secondary_Phone__c;
        con.Secondary_Country_Code__c = c.Secondary_Country_Code__c;
        con.Secondary_Country__c = c.Secondary_Country__c;
        con.Leadsource__c = 'Transferred lead';
        con.Sub_Source__c = userinfo.getUserName();
        con.Description__c = tReason;
        con.Type_of_lead__c ='Transfer Lead';
        if(checkbox){
            con.Lead_Assigned__c = true;
            con.OwnerId = owner;
        }
        insert con;
        lead__c cn = new lead__c();
        cn.Id = LeadId;
        cn.Lead_status__c = 'Lost';
        cn.Drop_Off_Reason__c = tReason;
        cn.Lost_Reason__c='Not looking for Property	';
        cn.Lead_Transfered__c = true;
        update cn;
        
        ListView lw= [SELECT Id, Name, DeveloperName, SobjectType FROM ListView WHERE SobjectType='lead__c' AND DeveloperName='Today'];
        return lw.Id;
    }*/
}