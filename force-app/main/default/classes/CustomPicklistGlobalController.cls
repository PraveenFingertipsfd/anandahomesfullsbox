public class CustomPicklistGlobalController {
    @AuraEnabled  
    public static List<picklistWrapper> findPicklistOptions(string objAPIName, string fieldAPIname) {
        list<picklistWrapper> returnValue = new list<picklistWrapper>();
        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        
        // Get the object type of the SObject.
        Schema.sObjectType objType = schemaMap.get(objAPIName);
        
        // Describe the SObject using its object type.
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        
        // Get a map of fields for the SObject
        map < String, Schema.SObjectField > fieldMap = objDescribe.fields.getMap();
        
        // Get the list of picklist values for this field.
        list < Schema.PicklistEntry > values = fieldMap.get(fieldAPIname).getDescribe().getPickListValues();
        //pickListFieldWrapper picklistDetails = new pickListFieldWrapper();
        
        // Add these values to the selectoption list.
        for (Schema.PicklistEntry a: values) {
            picklistWrapper aa = new picklistWrapper();
            aa.pickListLabel = a.getLabel();
            aa.pickListValue = a.getValue();
            returnValue.add(aa);
        }
        system.debug('*****returnValue'+returnValue);
        return returnValue;
        
        
    }
    public class picklistWrapper{
        @AuraEnabled 
        public string pickListLabel;
        @AuraEnabled 
        public string pickListValue;
        
    }
}