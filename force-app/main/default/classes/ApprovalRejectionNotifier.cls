/**
 * @description Notifies all approvers who had ALREADY approved a record when that record's
 *              approval is subsequently rejected at a later level.
 *
 *              BRD pointer 3: "If any approval process is rejected, a notification should be
 *              sent to the previous levels who had approved it as well."
 *
 *              The set of "previous approvers" is read from the platform approval history
 *              (ProcessInstanceStep records with StepStatus = 'Approved') for the most recent
 *              approval submission on the record. Each such approver receives a bell
 *              notification and an email letting them know the request they approved was
 *              ultimately rejected.
 *
 *              Two entry points are provided:
 *                - notifyPreviousApprovers(Set<Id>) for Apex callers, and
 *                - an @InvocableMethod for Flow / Process Builder rejection paths.
 *
 *              It can also be wired through the existing config-driven action framework via
 *              the NOTIFY_PREVIOUS_APPROVERS action type (see ApprovalActionHandler).
 * @author System
 */
public with sharing class ApprovalRejectionNotifier {

    private static final String STEP_STATUS_APPROVED = 'Approved';

    // ==================== TEST SEAMS ====================
    // ProcessInstance / ProcessInstanceStep cannot be inserted in tests, so these
    // overrides (active only while Test.isRunningTest()) let unit tests inject the
    // approval-history result and a notification type without real approval config.

    /** @description Test-only: injected record -> approver-user-ids map. */
    @TestVisible
    private static Map<Id, Set<Id>> approverOverrideForTest;

    /** @description Test-only: injected CustomNotificationType id (may be fabricated). */
    @TestVisible
    private static Id notificationTypeIdOverrideForTest;

    // ==================== INVOCABLE (Flow / Process Builder) ====================

    public class Request {
        @InvocableVariable(required=true label='Record ID' description='The record whose approval was just rejected')
        public Id recordId;
    }

    @InvocableMethod(
        label='Notify Previous Approvers On Rejection'
        description='Emails and bell-notifies everyone who had already approved the record before it was rejected'
        category='Approvals'
    )
    public static void notifyFromFlow(List<Request> requests) {
        if (requests == null || requests.isEmpty()) return;
        Set<Id> recordIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.recordId != null) recordIds.add(r.recordId);
        }
        notifyPreviousApprovers(recordIds);
    }

    // ==================== CORE ====================

    /**
     * @description Notifies the prior approvers of every supplied record that its approval
     *              was rejected. Safe to call in bulk.
     * @param recordIds Records that were just rejected
     */
    public static void notifyPreviousApprovers(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) return;

        Map<Id, Set<Id>> recordToApprovers = getApproversByRecord(recordIds);
        if (recordToApprovers.isEmpty()) return;

        // Collect every approver user id to resolve emails in one query.
        Set<Id> allApproverIds = new Set<Id>();
        for (Set<Id> ids : recordToApprovers.values()) {
            allApproverIds.addAll(ids);
        }
        Map<Id, User> approverUsers = new Map<Id, User>([
            SELECT Id, Name, Email, IsActive FROM User WHERE Id IN :allApproverIds
        ]);

        // Friendly record names for the message body.
        Map<Id, String> recordNames = resolveRecordNames(recordToApprovers.keySet());

        Id notificationTypeId = getApprovalNotificationTypeId();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id recordId : recordToApprovers.keySet()) {
            Set<Id> approverIds = recordToApprovers.get(recordId);
            if (approverIds == null || approverIds.isEmpty()) continue;

            String recordName = recordNames.containsKey(recordId) ? recordNames.get(recordId) : String.valueOf(recordId);
            String title = 'Approval Rejected - ' + recordName;
            String body = 'A request you previously approved (' + recordName + ') has been rejected at a later approval level.';

            // Bell notification to active approvers.
            if (notificationTypeId != null) {
                Set<String> targets = new Set<String>();
                for (Id approverId : approverIds) {
                    User u = approverUsers.get(approverId);
                    if (u != null && u.IsActive) targets.add(String.valueOf(approverId));
                }
                if (!targets.isEmpty()) {
                    sendBell(notificationTypeId, recordId, title, body, targets);
                }
            }

            // Email to active approvers with a valid address.
            List<String> toAddresses = new List<String>();
            for (Id approverId : approverIds) {
                User u = approverUsers.get(approverId);
                if (u != null && u.IsActive && String.isNotBlank(u.Email)) {
                    toAddresses.add(u.Email);
                }
            }
            if (!toAddresses.isEmpty()) {
                emails.add(buildEmail(toAddresses, title, body, recordName));
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception e) {
                System.debug('ApprovalRejectionNotifier: email send failed - ' + e.getMessage());
            }
        }
    }

    // ==================== HISTORY LOOKUP ====================

    /**
     * @description For each record, returns the set of user ids that approved a step in the
     *              record's MOST RECENT approval submission. Earlier (superseded) submissions
     *              are ignored so resubmissions don't notify stale approvers.
     */
    private static Map<Id, Set<Id>> getApproversByRecord(Set<Id> recordIds) {
        if (Test.isRunningTest() && approverOverrideForTest != null) {
            return approverOverrideForTest;
        }

        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();

        // Identify the latest ProcessInstance per target record.
        Map<Id, Id> latestInstanceByRecord = new Map<Id, Id>();
        for (ProcessInstance pi : [
            SELECT Id, TargetObjectId
            FROM ProcessInstance
            WHERE TargetObjectId IN :recordIds
            ORDER BY CreatedDate DESC
        ]) {
            // First seen per record == most recent due to ordering.
            if (!latestInstanceByRecord.containsKey(pi.TargetObjectId)) {
                latestInstanceByRecord.put(pi.TargetObjectId, pi.Id);
            }
        }
        if (latestInstanceByRecord.isEmpty()) return result;

        Map<Id, Id> instanceToRecord = new Map<Id, Id>();
        for (Id recId : latestInstanceByRecord.keySet()) {
            instanceToRecord.put(latestInstanceByRecord.get(recId), recId);
        }

        for (ProcessInstanceStep step : [
            SELECT ActorId, ProcessInstanceId, StepStatus
            FROM ProcessInstanceStep
            WHERE ProcessInstanceId IN :instanceToRecord.keySet()
            AND StepStatus = :STEP_STATUS_APPROVED
        ]) {
            Id recId = instanceToRecord.get(step.ProcessInstanceId);
            if (recId == null || step.ActorId == null) continue;
            // ActorId can also be a queue; only notify real users (005 prefix).
            if (!String.valueOf(step.ActorId).startsWith('005')) continue;

            if (!result.containsKey(recId)) result.put(recId, new Set<Id>());
            result.get(recId).add(step.ActorId);
        }

        return result;
    }

    // ==================== NOTIFICATION HELPERS ====================

    private static void sendBell(Id notificationTypeId, Id recordId, String title, String body, Set<String> targets) {
        try {
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setTitle(title);
            n.setBody(body);
            n.setNotificationTypeId(notificationTypeId);
            n.setTargetId(recordId);
            n.send(targets);
        } catch (Exception e) {
            System.debug('ApprovalRejectionNotifier: bell send failed - ' + e.getMessage());
        }
    }

    private static Messaging.SingleEmailMessage buildEmail(List<String> toAddresses, String title, String body, String recordName) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject(title);
        email.setHtmlBody(
            '<p>Hello,</p>' +
            '<p>' + body + '</p>' +
            '<p>No further action is required from you. This notice is sent because you were one of the ' +
            'approvers who had already approved <strong>' + recordName + '</strong> before it was rejected.</p>' +
            '<p>Regards,<br/>Post-Sales Team</p>'
        );
        email.setSaveAsActivity(false);
        return email;
    }

    private static Id getApprovalNotificationTypeId() {
        if (Test.isRunningTest() && notificationTypeIdOverrideForTest != null) {
            return notificationTypeIdOverrideForTest;
        }

        String devName;
        try {
            devName = System.Label.Approval_Notification_Type;
        } catch (Exception e) {
            devName = 'Approval_Notification_Type';
        }
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :devName LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    private static Map<Id, String> resolveRecordNames(Set<Id> recordIds) {
        Map<Id, String> names = new Map<Id, String>();
        // Group ids by SObject type so we can query the Name field per object.
        Map<Schema.SObjectType, List<Id>> idsByType = new Map<Schema.SObjectType, List<Id>>();
        for (Id recId : recordIds) {
            Schema.SObjectType t = recId.getSObjectType();
            if (!idsByType.containsKey(t)) idsByType.put(t, new List<Id>());
            idsByType.get(t).add(recId);
        }

        for (Schema.SObjectType t : idsByType.keySet()) {
            List<Id> ids = idsByType.get(t);
            String objName = t.getDescribe().getName();
            try {
                for (SObject so : Database.query(
                    'SELECT Id, Name FROM ' + String.escapeSingleQuotes(objName) + ' WHERE Id IN :ids'
                )) {
                    Object nm = so.get('Name');
                    names.put((Id) so.get('Id'), nm != null ? String.valueOf(nm) : String.valueOf(so.get('Id')));
                }
            } catch (Exception e) {
                // Object without a queryable Name field — fall back to the id.
                for (Id recId : ids) names.put(recId, String.valueOf(recId));
            }
        }
        return names;
    }
}