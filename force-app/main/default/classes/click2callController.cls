global without sharing class click2callController {

    // Wrapper returned to the component
    public class PhoneOptions {
        @AuraEnabled public String primaryPhone;
        @AuraEnabled public String secondaryPhone;
    }

    // METHOD 1 — fetch the numbers on init
    @AuraEnabled
    public static PhoneOptions getPhoneNumbers(Id recordId) {
        PhoneOptions opt = new PhoneOptions();
        // TODO: change object + field API names to match your record
        Lead__c c = [SELECT Id, Phone__c, Secondary_Phone__c
                     FROM Lead__c
                     WHERE Id = :recordId
                     LIMIT 1];
        opt.primaryPhone   = String.isBlank(c.Phone__c)   ? null : c.Phone__c;
        opt.secondaryPhone = String.isBlank(c.Secondary_Phone__c) ? null : c.Secondary_Phone__c;
        return opt;
    }

    // METHOD 2 — make the Knowlarity callout for the chosen number
    @AuraEnabled
    public static String clickToCall(Id recordId, String customerNumber) {
        User u = [SELECT Phone, MobilePhone FROM User
                  WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String agentNumber = String.isNotBlank(u.MobilePhone) ? u.MobilePhone : u.Phone;

        Map<String, Object> payload = new Map<String, Object>{
            'k_number'        => 'YOUR_K_NUMBER',
            'agent_number'    => agentNumber,
            'customer_number' => customerNumber,
            'caller_id'       => 'YOUR_CALLER_ID'
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://kpi.knowlarity.com/Basic/v1/account/call/makecall');
        req.setMethod('POST');
        req.setHeader('content-type', 'application/json');
        req.setHeader('x-api-key', 'QdQa83awS05tyB0KAVATX7tvm3WuBXz16QEluhix');
        req.setHeader('Authorization', '2a4ed706-af93-11e5-b374-067cf20e9301');
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            return res.getBody();
        }
        throw new AuraHandledException('Call failed (' + res.getStatusCode() + '): ' + res.getBody());
    }
}