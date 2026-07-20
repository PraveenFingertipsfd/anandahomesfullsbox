public class SendLeadDetailsToPulseTeleSystem {
    @future(callout=true)
    public static void sendLeadDetailsInBulk(Set<Id> relatedSourceIds) {
        System.debug('Related Source IDs: ' + relatedSourceIds);
        
        List<Related_Source__c> relatedSources = [
            SELECT Id, Phone__c, Secondary_Phone__c,
                   CLead__r.Id, CLead__r.Name, CLead__r.Extension__c
            FROM Related_Source__c
            WHERE Id IN :relatedSourceIds 
        ];
        
        System.debug('Fetched Related Sources Records: ' + relatedSources);
        
        if (relatedSources.isEmpty()) {
            System.debug('No Related Source records found.');
            return;
        }
        
        String integrationType = System.Label.intergrationType;
        System.debug('Integration Type (from Label): ' + integrationType);
        
        if (String.isBlank(integrationType)) {
            System.debug('Integration type is blank. Please check the custom label.');
        }

        String baseEndpoint = 'https://y96z3n20jg.execute-api.ap-south-1.amazonaws.com/v1/originate';
        System.debug('Base Endpoint: ' + baseEndpoint);
        
        for (Related_Source__c rs : relatedSources) {
            Map<String, String> recordData = new Map<String, String>();
            recordData.put('agent_number', (rs.CLead__r != null) ? rs.CLead__r.Extension__c : 'Unknown');
            recordData.put('customer_number', String.isNotBlank(rs.Phone__c) ? rs.Phone__c : rs.Secondary_Phone__c);
            recordData.put('leadId', (rs.CLead__r != null) ? rs.CLead__r.Id : 'Unknown');
            recordData.put('intergrationType', integrationType);
            
            //String sampleJson ='{"agent_number":"1000","customer_number":"8890122109","leadId":"123456789","intergrationType":"salesforce"}';
            String bulkDataJson = JSON.serialize(recordData);
            System.debug('Final JSON Payload: ' + bulkDataJson);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(bulkDataJson); 
            //req.setBody(sampleJson);
            
            try {
                Http http = new Http();
                HttpResponse res = http.send(req);
                
                System.debug('API Response: ' + res.getBody());
                System.debug('Response Status Code: ' + res.getStatusCode());
                
                if (res.getStatusCode() != 200) {
                    System.debug('Error Response: ' + res.getBody());
                }
                
            } catch (Exception e) {
                System.debug('Error while sending bulk API request: ' + e.getMessage());
            }
        }
    }
}