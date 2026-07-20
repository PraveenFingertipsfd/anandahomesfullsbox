/**
 * @description Flow entry point for the config-driven approval engine. Lets a Flow (or Process
 *              Builder) submit a record for approval through DynamicApprovalService instead of
 *              the LWC button.
 *
 *              The Approval Configuration to use is resolved in this order:
 *                1. an explicit Configuration Id, if supplied;
 *                2. the active config for the record's object whose Process Type matches the
 *                   supplied Process Type;
 *                3. the single active config for the record's object (if only one exists).
 * @author System
 */
public with sharing class ApprovalSubmissionInvocable {

    public class Request {
        @InvocableVariable(required=true label='Record Id'
            description='The record to submit for approval')
        public Id recordId;

        @InvocableVariable(label='Process Type'
            description='Approval_Configuration__c.Process_Type__c to pick the config (use when the object has more than one process)')
        public String processType;

        @InvocableVariable(label='Approval Configuration Id'
            description='Optional. Overrides Process Type — submit using this exact configuration')
        public Id configId;

        @InvocableVariable(label='Comments')
        public String comments;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
        @InvocableVariable public Id processInstanceId;
    }

    @InvocableMethod(label='Submit For Dynamic Approval'
        description='Submits a record for approval using the config-driven Approval Configuration engine')
    public static List<Result> submit(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) return results;

        for (Request req : requests) {
            Result res = new Result();
            try {
                if (req == null || req.recordId == null) {
                    res.success = false;
                    res.message = 'Record Id is required.';
                    results.add(res);
                    continue;
                }

                Id cfgId = req.configId != null ? req.configId : resolveConfigId(req.recordId, req.processType);
                if (cfgId == null) {
                    res.success = false;
                    res.message = 'No active Approval Configuration was found for this record'
                        + (String.isNotBlank(req.processType) ? ' and process "' + req.processType + '"' : '')
                        + '.';
                    results.add(res);
                    continue;
                }

                DynamicApprovalController.ApprovalResult ar =
                    DynamicApprovalService.submitForApproval(req.recordId, cfgId, req.comments);
                res.success = ar != null ? ar.success : false;
                res.message = ar != null ? ar.message : 'No result returned.';
                res.processInstanceId = ar != null ? ar.processInstanceId : null;
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    /**
     * @description Finds the active Approval Configuration for the record's object, optionally
     *              filtered to a Process Type. Returns null if none / ambiguous.
     */
    private static Id resolveConfigId(Id recordId, String processType) {
        String objApi = recordId.getSObjectType().getDescribe().getName();
        List<Approval_Configuration__c> cfgs = [
            SELECT Id, Process_Type__c
            FROM Approval_Configuration__c
            WHERE Object_API_Name__c = :objApi AND Is_Active__c = true
            ORDER BY Sequence_Order__c NULLS LAST
        ];
        if (cfgs.isEmpty()) return null;

        if (String.isNotBlank(processType)) {
            for (Approval_Configuration__c c : cfgs) {
                if (processType.equalsIgnoreCase(c.Process_Type__c)) return c.Id;
            }
            return null; // process type requested but not configured
        }
        return cfgs[0].Id; // single / first active config for the object
    }
}