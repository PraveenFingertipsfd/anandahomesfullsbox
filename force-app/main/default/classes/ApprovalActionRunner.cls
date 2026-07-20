/**
 * @description Explicit invocable: run a specific Approval Configuration's
 * On_Submit_JSON__c / On_Approval_JSON__c / On_Rejection_JSON__c against a record.
 * Lives in its own class because Apex permits only one @InvocableMethod per class.
 */
public with sharing class ApprovalActionRunner {

    @InvocableMethod(label='Run Approval Action JSON' description='Execute the On Submit / On Approval / On Rejection actions for a record and approval config')
    public static List<ApprovalActionHandler.NotificationResult> runApprovalActions(List<RunActionRequest> requests) {
        List<ApprovalActionHandler.NotificationResult> results = new List<ApprovalActionHandler.NotificationResult>();
        if (requests == null) return results;

        for (RunActionRequest req : requests) {
            ApprovalActionHandler.NotificationResult res = new ApprovalActionHandler.NotificationResult();
            res.success = false;
            try {
                if (req == null || req.recordId == null) {
                    res.message = 'Record ID is required';
                    results.add(res);
                    continue;
                }
                if (req.configId == null) {
                    res.message = 'Approval Configuration ID is required';
                    results.add(res);
                    continue;
                }
                String actionType = String.isBlank(req.actionType) ? 'APPROVAL' : req.actionType.toUpperCase();

                Approval_Configuration__c cfg = [
                    SELECT Id, Process_Label__c,
                           On_Submit_JSON__c, On_Approval_JSON__c, On_Rejection_JSON__c
                    FROM Approval_Configuration__c
                    WHERE Id = :req.configId
                    LIMIT 1
                ];

                String actionsJson;
                if (actionType == 'SUBMISSION' || actionType == 'SUBMIT') {
                    actionsJson = cfg.On_Submit_JSON__c;
                } else if (actionType == 'REJECTION' || actionType == 'REJECTED' || actionType == 'REJECT') {
                    actionsJson = cfg.On_Rejection_JSON__c;
                } else {
                    actionsJson = cfg.On_Approval_JSON__c;
                }

                if (String.isBlank(actionsJson)) {
                    res.success = true;
                    res.message = 'No actions configured for ' + actionType + ' on ' + cfg.Process_Label__c;
                    results.add(res);
                    continue;
                }

                List<String> failures = ApprovalActionHandler.executeActionsFromJson(
                    req.recordId,
                    actionsJson,
                    (cfg.Process_Label__c != null ? cfg.Process_Label__c : 'Approval') + ' / ' + actionType
                );

                if (failures.isEmpty()) {
                    res.success = true;
                    res.message = 'Actions executed successfully for ' + actionType;
                } else {
                    res.success = false;
                    res.message = failures.size() + ' action(s) failed: ' + String.join(failures, '; ');
                }
            } catch (Exception e) {
                res.success = false;
                res.message = 'Error running approval actions: ' + e.getMessage();
                System.debug(e.getStackTraceString());
            }
            results.add(res);
        }
        return results;
    }

    public class RunActionRequest {
        @InvocableVariable(required=true label='Record ID' description='The record the actions act on')
        public Id recordId;

        @InvocableVariable(required=true label='Approval Configuration ID' description='Approval_Configuration__c whose action JSON to run')
        public Id configId;

        @InvocableVariable(required=false label='Action Type' description='APPROVAL (default), REJECTION, or SUBMISSION')
        public String actionType;
    }
}