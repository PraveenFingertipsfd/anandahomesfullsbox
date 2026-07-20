/**
 * @description Unified approval-action dispatcher. One record-triggered flow per
 * object can watch any approval status field (or just Approval_Status__c) and
 * call this entry point — it figures out which Approval_Configuration__c is
 * active and runs the matching On_Submit / On_Approval / On_Rejection actions.
 *
 * Resolution order:
 *   1. Generic gate: Approval_Status__c + Approval_Name__c (when both fields exist
 *      and Approval_Status__c is set). Approval_Name__c picks the config; if it's
 *      blank, fall back to the sole active config for the object.
 *   2. Per-process status field: for each active config, read the value of its
 *      Status_Field_API_Name__c off the record. The first one whose value matches
 *      that config's Approved/Rejected/Pending value wins.
 *
 * The dual resolution means admins can wire their approval process's Final
 * Approval Action to ANY status field — Approval_Status__c, a per-process field
 * like Booking_Verification_Approval_Status__c, etc. — and the configured actions
 * still fire.
 *
 * Lives in its own class because Apex permits only one @InvocableMethod per class.
 */
public with sharing class ApprovalGenericStatusHandler {

    @InvocableMethod(label='Run Approval Actions From Generic Status' description='Reads Approval_Status__c + Approval_Name__c (or any per-process status field) off the record and runs the configured submit/approval/rejection actions')
    public static List<ApprovalActionHandler.NotificationResult> runFromGenericStatus(List<GenericStatusRequest> requests) {
        List<ApprovalActionHandler.NotificationResult> results = new List<ApprovalActionHandler.NotificationResult>();
        if (requests == null) return results;

        for (GenericStatusRequest req : requests) {
            ApprovalActionHandler.NotificationResult res = new ApprovalActionHandler.NotificationResult();
            res.success = false;
            try {
                if (req == null || req.recordId == null) {
                    res.message = 'Record ID is required';
                    results.add(res);
                    continue;
                }

                Id recId = req.recordId;
                String objectApiName = recId.getSObjectType().getDescribe().getName();
                System.debug('ApprovalGenericStatusHandler: start recordId=' + recId + ', object=' + objectApiName);

                List<Approval_Configuration__c> active = [
                    SELECT Id, Process_Label__c, Process_Type__c,
                           Status_Field_API_Name__c, Approved_Status_Value__c,
                           Rejected_Status_Value__c, Pending_Status_Value__c,
                           On_Submit_JSON__c, On_Approval_JSON__c, On_Rejection_JSON__c
                    FROM Approval_Configuration__c
                    WHERE Object_API_Name__c = :objectApiName
                    AND Is_Active__c = true
                ];
                if (active.isEmpty()) {
                    res.message = 'No active Approval Configuration for ' + objectApiName;
                    results.add(res);
                    continue;
                }

                Map<String, Schema.SObjectField> fmap = Schema.getGlobalDescribe()
                    .get(objectApiName).getDescribe().fields.getMap();
                Boolean hasGenericStatus = fmap.containsKey('approval_status__c');
                Boolean hasGenericName = fmap.containsKey('approval_name__c');

                Set<String> fieldsToFetch = new Set<String>{ 'Id' };
                if (hasGenericStatus) fieldsToFetch.add('Approval_Status__c');
                if (hasGenericName) fieldsToFetch.add('Approval_Name__c');
                for (Approval_Configuration__c c : active) {
                    if (String.isNotBlank(c.Status_Field_API_Name__c)
                        && fmap.containsKey(c.Status_Field_API_Name__c.toLowerCase())) {
                        fieldsToFetch.add(c.Status_Field_API_Name__c);
                    }
                }

                String query = 'SELECT ' + String.join(new List<String>(fieldsToFetch), ', ')
                    + ' FROM ' + String.escapeSingleQuotes(objectApiName) + ' WHERE Id = :recId LIMIT 1';
                SObject record = Database.query(query);

                // ── Resolve which config + action to run ───────────────────────
                Approval_Configuration__c matchedCfg;
                String actionsJson;
                String actionType;
                String resolutionPath;

                // Tracks whether the generic gate had an explicit signal that the
                // handler couldn't honour (status set but no config picked). Used
                // below to return a loud error vs. a quiet no-op.
                Boolean genericStatusSetButUnresolved = false;
                String genericFailureReason;

                // 1. Generic Approval_Status__c first.
                if (hasGenericStatus) {
                    String genericStatus = (String) record.get('Approval_Status__c');
                    String approvalName = hasGenericName ? (String) record.get('Approval_Name__c') : null;
                    System.debug('ApprovalGenericStatusHandler: Approval_Status__c=' + genericStatus
                        + ', Approval_Name__c=' + approvalName);

                    if (String.isNotBlank(genericStatus)) {
                        String s = genericStatus.toLowerCase();
                        matchedCfg = pickConfigByName(active, approvalName);
                        if (matchedCfg != null) {
                            if (s == 'approved') { actionsJson = matchedCfg.On_Approval_JSON__c; actionType = 'APPROVAL'; }
                            else if (s == 'rejected') { actionsJson = matchedCfg.On_Rejection_JSON__c; actionType = 'REJECTION'; }
                            else if (s == 'pending') { actionsJson = matchedCfg.On_Submit_JSON__c; actionType = 'SUBMISSION'; }
                            else { matchedCfg = null; }
                            if (matchedCfg != null) resolutionPath = 'generic';
                        }
                        if (matchedCfg == null) {
                            genericStatusSetButUnresolved = true;
                            genericFailureReason = String.isBlank(approvalName)
                                ? 'Approval_Status__c="' + genericStatus + '" but Approval_Name__c is blank and ' + active.size()
                                    + ' active configs exist for ' + objectApiName + ' — cannot auto-resolve which one to run.'
                                : 'Approval_Status__c="' + genericStatus + '" but no active config matched Process_Type__c="' + approvalName + '".';
                        }
                    }
                }

                // 2. Per-process status field fallback.
                if (matchedCfg == null) {
                    for (Approval_Configuration__c c : active) {
                        if (String.isBlank(c.Status_Field_API_Name__c)) continue;
                        if (!fieldsToFetch.contains(c.Status_Field_API_Name__c)) continue;
                        String val;
                        try { val = (String) record.get(c.Status_Field_API_Name__c); }
                        catch (Exception ignored) { continue; }
                        if (String.isBlank(val)) continue;

                        if (String.isNotBlank(c.Approved_Status_Value__c)
                            && val.equalsIgnoreCase(c.Approved_Status_Value__c)) {
                            matchedCfg = c; actionsJson = c.On_Approval_JSON__c; actionType = 'APPROVAL';
                            resolutionPath = 'per-process field ' + c.Status_Field_API_Name__c;
                            break;
                        }
                        if (String.isNotBlank(c.Rejected_Status_Value__c)
                            && val.equalsIgnoreCase(c.Rejected_Status_Value__c)) {
                            matchedCfg = c; actionsJson = c.On_Rejection_JSON__c; actionType = 'REJECTION';
                            resolutionPath = 'per-process field ' + c.Status_Field_API_Name__c;
                            break;
                        }
                        if (String.isNotBlank(c.Pending_Status_Value__c)
                            && val.equalsIgnoreCase(c.Pending_Status_Value__c)) {
                            matchedCfg = c; actionsJson = c.On_Submit_JSON__c; actionType = 'SUBMISSION';
                            resolutionPath = 'per-process field ' + c.Status_Field_API_Name__c;
                            break;
                        }
                    }
                }

                if (matchedCfg == null) {
                    // Loud failure when the generic gate was set but unresolvable;
                    // quiet success otherwise (no signal anywhere = nothing to do).
                    if (genericStatusSetButUnresolved) {
                        res.success = false;
                        res.message = genericFailureReason;
                        postDiagnostic(recId, 'UNRESOLVED', genericFailureReason);
                    } else {
                        res.success = true;
                        res.message = 'No Approval Configuration matched the record state — nothing to run';
                    }
                    results.add(res);
                    continue;
                }
                System.debug('ApprovalGenericStatusHandler: matched ' + matchedCfg.Process_Label__c
                    + ' via ' + resolutionPath + ', actionType=' + actionType
                    + ', actions JSON length=' + (actionsJson == null ? 0 : actionsJson.length()));

                if (String.isBlank(actionsJson)) {
                    res.success = true;
                    res.message = 'No actions configured for ' + actionType + ' on ' + matchedCfg.Process_Label__c;
                    postDiagnostic(recId, actionType,
                        'Approval reached ' + actionType + ' but no actions are configured on '
                        + matchedCfg.Process_Label__c + '. Open the config → "Actions when Final '
                        + (actionType == 'APPROVAL' ? 'Approval' : actionType == 'REJECTION' ? 'Rejection' : 'Submission')
                        + '" and save it.');
                    results.add(res);
                    continue;
                }

                List<String> failures = ApprovalActionHandler.executeActionsFromJson(
                    recId, actionsJson,
                    (matchedCfg.Process_Label__c != null ? matchedCfg.Process_Label__c : 'Approval') + ' / ' + actionType
                );

                if (failures.isEmpty()) {
                    res.success = true;
                    res.message = 'Actions executed for ' + actionType + ' on '
                        + matchedCfg.Process_Label__c + ' (resolved via ' + resolutionPath + ')';
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

    /**
     * Pick the config to run when Approval_Status__c is set. If Approval_Name__c
     * is populated, match it against Process_Type__c case-insensitively. If not,
     * fall back to the single active config (only safe when there's exactly one).
     */
    private static Approval_Configuration__c pickConfigByName(List<Approval_Configuration__c> active, String approvalName) {
        if (String.isNotBlank(approvalName)) {
            for (Approval_Configuration__c c : active) {
                if (c.Process_Type__c != null && c.Process_Type__c.equalsIgnoreCase(approvalName)) {
                    return c;
                }
            }
            return null;
        }
        return active.size() == 1 ? active[0] : null;
    }

    /**
     * Post a Chatter note on the record so an admin can see why the configured
     * approval actions didn't fire without trawling debug logs. Uses dynamic
     * SObject creation so the class still compiles in orgs where Chatter
     * (FeedItem) is not enabled — and silently no-ops at runtime there.
     */
    private static void postDiagnostic(Id recordId, String actionType, String message) {
        try {
            Schema.SObjectType feedItemType = Schema.getGlobalDescribe().get('FeedItem');
            if (feedItemType == null) return;
            String body = '[Approval diagnostic / ' + actionType + '] ' + message;
            SObject feedItem = feedItemType.newSObject();
            feedItem.put('ParentId', recordId);
            feedItem.put('Body', body.left(10000));
            insert feedItem;
        } catch (Exception ignored) { /* Chatter not available */ }
    }

    public class GenericStatusRequest {
        @InvocableVariable(required=true label='Record ID' description='The record whose approval status just changed')
        public Id recordId;
    }
}