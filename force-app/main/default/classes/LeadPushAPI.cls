@RestResource(urlMapping='/LeadPush')
global without sharing class LeadPushAPI {

    global class LeadPushRequest {
        public String firstName;
        public String lastName;
        public String primaryMobileNumber;
        public String secondaryMobileNumber;
        public String primaryEmail;
        public String secondaryEmail;
        public String source;
        public String subSource;
        public String campaignId;
        public String campaignName;
        public String interestedProject;
        public String propertyType;
        public String bhkType;
        public String budget;
        public String remarks;
    }

    global class LeadPushResponse {
        public String status;
        public String message;
        public String leadId;

        public LeadPushResponse(String status, String message, String leadId) {
            this.status = status;
            this.message = message;
            this.leadId = leadId;
        }
    }

    @HttpPost
    global static LeadPushResponse pushLead() {
        RestRequest req = RestContext.request;
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c = 'LeadPushAPI.pushLead';
        log.Request__c = req.requestBody != null ? req.requestBody.toString().left(131072) : '';

        try {
            LeadPushRequest payload = (LeadPushRequest) JSON.deserialize(req.requestBody.toString(), LeadPushRequest.class);

            // Validate required field
            if (String.isBlank(payload.primaryMobileNumber)) {
                log.Status__c = 'FAIL';
                log.Error_Message__c = 'Primary Mobile Number is required.';
                insert log;
                RestContext.response.statusCode = 400;
                return new LeadPushResponse('FAIL', 'Primary Mobile Number is required.', null);
            }

            // Build Lead__c record
            Lead__c ld = new Lead__c();
            ld.Lead_First_Name__c = payload.firstName;
            ld.Lead_Last_Name__c = payload.lastName;

            // Name__c is required — combine first and last name
            String fullName = '';
            if (String.isNotBlank(payload.firstName)) {
                fullName = payload.firstName;
            }
            if (String.isNotBlank(payload.lastName)) {
                fullName = String.isNotBlank(fullName) ? fullName + ' ' + payload.lastName : payload.lastName;
            }
            if (String.isBlank(fullName)) {
                fullName = payload.primaryMobileNumber;
            }
            ld.Name__c = fullName;

            ld.Phone__c = payload.primaryMobileNumber;
            ld.Secondary_Phone__c = payload.secondaryMobileNumber;
            ld.Email__c = payload.primaryEmail;
            ld.Secondary_Email__c = payload.secondaryEmail;
            //ld.Lead_source__c = payload.source;
            //ld.Sub_Source__c = payload.subSource;
            // Mirror GRE_Lead_Controller.cls:306-307 — populate Primary_* so the
            // after-insert trigger (RelatedSourceHandler.afterinsertLogic2) carries
            // the values onto the Related_Source__c row it creates.
            ld.Primary_Source__c = payload.source;
            ld.Primary_Sub_Source__c = payload.subSource;
            ld.Allocated_Project__c = payload.interestedProject;
            ld.Property_Type__c = payload.propertyType;
            ld.Unit_Type_Intrested__c = payload.bhkType;
            ld.Budget__c = payload.budget;
            ld.Remark__c = payload.remarks;

            // Default status — matches the Pre Sales record type default and the
            // pattern in CPLeadRegistrationAPI.cls:305. LeadTrigger will override
            // this to 'New sales enquiry' for Walk-in / Sales record type leads.
            ld.Lead_Status__c = 'New Enquiry';

            // Campaign handling — store raw value in text field; lookup resolved by trigger
            if (String.isNotBlank(payload.campaignId)) {
                ld.Campaign__c = payload.campaignId;
            }
            if (String.isNotBlank(payload.campaignName) && String.isBlank(ld.Campaign__c)) {
                ld.Campaign__c = payload.campaignName;
            }

            // Insert — LeadTrigger handles phone normalization, duplicate check, and round-robin
            insert ld;

            log.Response__c = String.valueOf(ld.Id);
            log.Status__c = 'SUCCESS';
            insert log;

            RestContext.response.statusCode = 200;
            return new LeadPushResponse('SUCCESS', 'Lead created successfully.', ld.Id);

        } catch (JSONException je) {
            log.Status__c = 'FAIL';
            log.Error_Message__c = 'Invalid JSON: ' + je.getMessage();
            insert log;
            RestContext.response.statusCode = 400;
            return new LeadPushResponse('FAIL', 'Invalid JSON format: ' + je.getMessage(), null);
        } catch (DmlException de) {
            log.Status__c = 'FAIL';
            log.Error_Message__c = de.getMessage();
            log.Response__c = de.getStackTraceString();
            insert log;
            RestContext.response.statusCode = 400;
            return new LeadPushResponse('FAIL', de.getMessage(), null);
        } catch (Exception e) {
            log.Status__c = 'FAIL';
            log.Error_Message__c = e.getMessage();
            log.Response__c = e.getStackTraceString();
            insert log;
            RestContext.response.statusCode = 500;
            return new LeadPushResponse('FAIL', 'An unexpected error occurred: ' + e.getMessage(), null);
        }
    }
}