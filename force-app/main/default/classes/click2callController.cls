global without sharing class click2callController {

    // ==== KNOWLARITY CREDENTIALS — replace with client's real keys ====
    private static final String K_API_KEY    = 'QdQa83awS05tyB0KAVATX7tvm3WuBXz16QEluhix';
    private static final String K_AUTH_KEY   = '2a4ed706-af93-11e5-b374-067cf20e9301';
    private static final String K_NUMBER     = '917679777888';
    private static final String K_CALLER_ID  = '911140023556';
    private static final String K_ENDPOINT   = 'https://kpi.knowlarity.com/Basic/v1/account/call/makecall';
    // ==================================================================

    public class PhoneOptions {
        @AuraEnabled public String primaryPhone;
        @AuraEnabled public String secondaryPhone;
    }

    @AuraEnabled
    public static PhoneOptions getPhoneNumbers(Id recordId) {
        PhoneOptions opt = new PhoneOptions();
        Lead__c c = [SELECT Id, Phone__c, Secondary_Phone__c
                     FROM Lead__c
                     WHERE Id = :recordId
                     LIMIT 1];
        opt.primaryPhone   = String.isBlank(c.Phone__c) ? null : c.Phone__c;
        opt.secondaryPhone = String.isBlank(c.Secondary_Phone__c) ? null : c.Secondary_Phone__c;
        return opt;
    }

    @AuraEnabled
    public static String clickToCall(Id recordId, String customerNumber) {
        if (String.isBlank(customerNumber)) {
            throw new AuraHandledException('No customer number provided.');
        }

        User u = [SELECT Phone, MobilePhone FROM User
                  WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String agentNumber = String.isNotBlank(u.MobilePhone) ? u.MobilePhone : u.Phone;

        if (String.isBlank(agentNumber)) {
            throw new AuraHandledException(
                'Your user record has no Phone/Mobile number. Update your Salesforce user phone before calling.');
        }

        Map<String, Object> payload = new Map<String, Object>{
            'k_number'        => K_NUMBER,
            'agent_number'    => agentNumber,
            'customer_number' => customerNumber,
            'caller_id'       => K_CALLER_ID
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(K_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('content-type', 'application/json');
        req.setHeader('x-api-key', K_API_KEY);
        req.setHeader('Authorization', K_AUTH_KEY);
        req.setTimeout(20000);
        req.setBody(JSON.serialize(payload));

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new AuraHandledException('Callout error: ' + e.getMessage());
        }

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            return res.getBody();
        }
        if (res.getStatusCode() == 401) {
            throw new AuraHandledException(
                'Knowlarity rejected the credentials (401). Verify x-api-key and Authorization key. Response: ' + res.getBody());
        }
        throw new AuraHandledException('Call failed (' + res.getStatusCode() + '): ' + res.getBody());
    }
}