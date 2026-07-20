public class Utility {

    public static boolean runLeadTrigger = true;
    public static boolean runTaskTrigger = true; 
    public static boolean runOpportunityTrigger = true; 
     
    
    
     public static Map<String, String> getAllProjectNameMappings() {
        Map<String, String> projectNameMappingsMap = new Map<String, String>();
        List<Project_Name_Mappings__mdt> prjList = [ SELECT     Label, SF_Project_Name__c  FROM Project_Name_Mappings__mdt ];
        for( Project_Name_Mappings__mdt pn :  prjList ) {
            projectNameMappingsMap.put( pn.Label, pn.SF_Project_Name__c );
        }
        
        return projectNameMappingsMap;
    }
    
    public static Set<String> getGlobalPicklistValues() {
        Set<String> globalPicklistValues = new set<String>();
        
        // Get a map of fields for the SObject
        Map<String, Schema.SObjectField> fieldMap   = SObjectType.Lead.fields.getMap(); 
        // Get the list of picklist values for this field.
        List<Schema.PicklistEntry> values  = fieldMap.get( 'Allocated_Project__c' ).getDescribe().getPickListValues();
        
        for( PicklistEntry entry : values ) {
            globalPicklistValues.add( entry.getLabel());
        }
        
        return globalPicklistValues;
    }
    
    public static Map<String, String> getAllCountryCodeMappings(Boolean codeAsKey) {
        Map<String, String> countryCodeMappingsMap = new Map<String, String>();
        List<Country_Code_Mapping__mdt> countryList = [SELECT Label, CountryCode__c FROM Country_Code_Mapping__mdt ];
        for(Country_Code_Mapping__mdt co : countryList) {
            if(codeAsKey){
                countryCodeMappingsMap.put(co.CountryCode__c,co.Label);
            }else{
                countryCodeMappingsMap.put(co.Label,co.CountryCode__c);
            }
        }
        return countryCodeMappingsMap;
    }  
   
    public static List<string> geAllPhoneNumbers(string phones){   
        if(phones == null ){
            return new list<string>();
        }
        List<string> allphones = phones.split(',');   
        return allphones;
    }
    
}