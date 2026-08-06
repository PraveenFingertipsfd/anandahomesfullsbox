/**
 * @description REST endpoint for the telephony provider's Log Push API.
 *              Receives one call-detail record per POST using the provider's standard
 *              parameter names and stores it as a Call_Detail__c, linked to the Lead__c
 *              whose phone matches the caller number (when one exists).
 *              Mirrors the request/response and Apex_Log__c conventions of LeadPushAPI.
 */
@RestResource(urlMapping='/LogPush')
global without sharing class LogPushAPI {

    global class LogPushRequest {
        public String call_date;            // yyyy-MM-dd
        public String call_time;            // HH:mm:ss
        public String caller_number;
        public String call_direction;       // inbound / outbound
        public String called_number;
        public String call_status;          // answered / missed / busy ...
        public String agent_number;
        public String call_transfer_status;
        public String caller_duration;      // seconds
        public String recording_url;
        public String call_uuid;
        public String hangup_cause;
        public String menu_extension;
    }

    global class LogPushResponse {
        public String status;
        public String message;
        public String callDetailId;

        public LogPushResponse(String status, String message, String callDetailId) {
            this.status = status;
            this.message = message;
            this.callDetailId = callDetailId;
        }
    }

    @HttpPost
    global static LogPushResponse pushLog() {
        RestRequest req = RestContext.request;
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c = 'LogPushAPI.pushLog';
        log.Request__c = req.requestBody != null ? req.requestBody.toString().left(131072) : '';

        try {
            LogPushRequest payload =
                (LogPushRequest) JSON.deserialize(req.requestBody.toString(), LogPushRequest.class);

            if (String.isBlank(payload.call_uuid)) {
                return fail(log, 400, 'call_uuid is required.');
            }
            if (String.isBlank(payload.caller_number)) {
                return fail(log, 400, 'caller_number is required.');
            }

            // Idempotency: the provider may retry a push — one Call Detail per call_uuid.
            List<Call_Detail__c> existing = [
                SELECT Id FROM Call_Detail__c WHERE ucid__c = :payload.call_uuid LIMIT 1
            ];
            if (!existing.isEmpty()) {
                log.Status__c = 'SUCCESS';
                log.Response__c = 'Duplicate call_uuid; existing record returned.';
                insert log;
                RestContext.response.statusCode = 200;
                return new LogPushResponse('SUCCESS',
                    'Call log already recorded for this call_uuid.', existing[0].Id);
            }

            Call_Detail__c cd = new Call_Detail__c();
            cd.ucid__c                 = payload.call_uuid;
            cd.Call_ID__c              = payload.call_uuid;
            cd.Call_From__c            = payload.caller_number;
            cd.Customer_Number__c      = payload.caller_number;
            cd.Call_To__c              = payload.called_number;
            cd.Landing_Number__c       = payload.called_number;
            cd.Call_Type__c            = payload.call_direction;
            cd.Call_Status__c          = payload.call_status;
            cd.Agent_Number__c         = payload.agent_number;
            cd.Call_Transfer_Status__c = payload.call_transfer_status;
            cd.Hangup_Cause__c         = payload.hangup_cause;
            cd.Extension__c            = payload.menu_extension;
            cd.Recording_File__c       = payload.recording_url;

            if (String.isNotBlank(payload.caller_duration)
                && payload.caller_duration.isNumeric()) {
                cd.Duration__c = Decimal.valueOf(payload.caller_duration);
            }

            cd.Call_Start_Time__c = parseStart(payload.call_date, payload.call_time);
            if (cd.Call_Start_Time__c != null && cd.Duration__c != null) {
                cd.Call_End_Time__c = cd.Call_Start_Time__c.addSeconds(cd.Duration__c.intValue());
            }

            // Link to the Lead whose phone matches the caller (last 10 digits, so the
            // match works whether the provider sends +91XXXXXXXXXX or XXXXXXXXXX).
            String digits = payload.caller_number.replaceAll('[^0-9]', '');
            String last10 = digits.length() > 10 ? digits.substring(digits.length() - 10) : digits;
            if (String.isNotBlank(last10)) {
                String phoneLike = '%' + last10;
                List<Lead__c> leads = [
                    SELECT Id FROM Lead__c
                    WHERE Phone__c LIKE :phoneLike OR Secondary_Phone__c LIKE :phoneLike
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!leads.isEmpty()) {
                    cd.Lead__c = leads[0].Id;
                }
            }

            insert cd;

            log.Status__c = 'SUCCESS';
            log.Response__c = 'Call Detail created: ' + cd.Id;
            insert log;

            RestContext.response.statusCode = 200;
            return new LogPushResponse('SUCCESS', 'Call log recorded successfully.', cd.Id);

        } catch (JSONException je) {
            return fail(log, 400, 'Invalid JSON payload: ' + je.getMessage());
        } catch (Exception e) {
            return fail(log, 500, 'An unexpected error occurred: ' + e.getMessage());
        }
    }

    /** Parse "yyyy-MM-dd" + "HH:mm:ss" into a DateTime; null when unparseable. */
    private static Datetime parseStart(String callDate, String callTime) {
        if (String.isBlank(callDate)) return null;
        try {
            String t = String.isBlank(callTime) ? '00:00:00' : callTime;
            return Datetime.valueOf(callDate + ' ' + t);
        } catch (Exception e) {
            return null;
        }
    }

    private static LogPushResponse fail(Apex_Log__c log, Integer statusCode, String message) {
        log.Status__c = 'FAIL';
        log.Error_Message__c = message;
        insert log;
        RestContext.response.statusCode = statusCode;
        return new LogPushResponse('FAIL', message, null);
    }
}
