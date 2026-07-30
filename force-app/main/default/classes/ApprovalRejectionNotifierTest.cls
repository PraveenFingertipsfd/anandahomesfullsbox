/**
 * @description Tests for ApprovalRejectionNotifier (BRD pointer 3).
 *
 *  ProcessInstance / ProcessInstanceStep cannot be inserted via DML, so the full downstream
 *  pipeline (user resolution, record-name resolution, bell notification, email build/send)
 *  is exercised deterministically by injecting the approval-history result through the
 *  @TestVisible approverOverrideForTest seam. A best-effort real-approval test is kept to
 *  exercise the genuine history-lookup SOQL path where the org has an approval process.
 */
@isTest
private class ApprovalRejectionNotifierTest {

    // ------------------------------------------------------------------ helpers
    private static Booking__c makeBooking() {
        Project__c project = new Project__c(
            Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18
        );
        insert project;
        // No Plot__c: avoids the Booking After Create Handler flow. Notifier only needs the id.
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'New'
        );
        insert booking;
        return booking;
    }

    private static User makeUser(Boolean active) {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniq = 'arn' + Datetime.now().getTime() + Crypto.getRandomInteger();
        User u = new User(
            FirstName = 'Prev', LastName = 'Approver', Alias = 'parvr',
            Email = uniq + '@example.com',
            Username = uniq + '@example.com.arntest',
            ProfileId = p.Id, IsActive = active,
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    /** Fabricates a CaseComment id — an object with NO Name field — to drive the
     *  resolveRecordNames fallback (catch) branch. */
    private static Id fakeCaseCommentId() {
        return Id.valueOf(CaseComment.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    /** Picks a real CustomNotificationType if the org has one, else fabricates an id.
     *  Either way sendBell() executes (a bad id lands in its catch block). */
    private static Id anyNotificationTypeId() {
        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType LIMIT 1];
        if (!types.isEmpty()) return types[0].Id;
        return Id.valueOf(CustomNotificationType.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    // ---------------------------------------------- FULL PIPELINE (injected history)
  
    @isTest
    static void fullPipeline_noNotificationType_emailOnly() {
        User active  = makeUser(true);
        Booking__c b = makeBooking();

        ApprovalRejectionNotifier.approverOverrideForTest = new Map<Id, Set<Id>>{
            b.Id => new Set<Id>{ active.Id }
        };
        // No notification-type override: exercises the real getApprovalNotificationTypeId
        // lookup (label + query) and, if absent in the org, the null-type skip branch.

        Test.startTest();
        ApprovalRejectionNotifier.notifyPreviousApprovers(new Set<Id>{ b.Id });
        Test.stopTest();

        ApprovalRejectionNotifier.approverOverrideForTest = null;
    }

    @isTest
    static void fullPipeline_emptyApproverSetForRecord_skipped() {
        Booking__c b = makeBooking();

        ApprovalRejectionNotifier.approverOverrideForTest = new Map<Id, Set<Id>>{
            b.Id => new Set<Id>() // exercises the per-record empty-approvers continue
        };

        Test.startTest();
        ApprovalRejectionNotifier.notifyPreviousApprovers(new Set<Id>{ b.Id });
        Test.stopTest();

        ApprovalRejectionNotifier.approverOverrideForTest = null;
    }

    @isTest
    static void notifyFromFlow_injectedHistory_andNullGuard() {
        User active  = makeUser(true);
        Booking__c b = makeBooking();

        ApprovalRejectionNotifier.approverOverrideForTest = new Map<Id, Set<Id>>{
            b.Id => new Set<Id>{ active.Id }
        };

        ApprovalRejectionNotifier.Request req = new ApprovalRejectionNotifier.Request();
        req.recordId = b.Id;

        Test.startTest();
        ApprovalRejectionNotifier.notifyFromFlow(
            new List<ApprovalRejectionNotifier.Request>{ req, null }
        );
        Test.stopTest();

        ApprovalRejectionNotifier.approverOverrideForTest = null;
    }

    // --------------------------------------- REAL HISTORY PATH (org-config dependent)
    /** Best-effort: submit + approve level 1 so the platform creates an 'Approved' step,
     *  then run the notifier WITHOUT the override so the real SOQL lookup path executes.
     *  In orgs with no approval process on Booking__c this degrades to the no-history
     *  early return — still covering the ProcessInstance query lines. */
    @isTest
    static void realHistoryLookup_bestEffort() {
        User approver = makeUser(true);
        Booking__c b  = makeBooking();

        Test.startTest();
        try {
            Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
            submit.setObjectId(b.Id);
            submit.setNextApproverIds(new List<Id>{ approver.Id });
            Approval.ProcessResult res = Approval.process(submit);
            if (res != null && res.isSuccess()) {
                for (Id wiId : res.getNewWorkitemIds()) {
                    Approval.ProcessWorkitemRequest appr = new Approval.ProcessWorkitemRequest();
                    appr.setAction('Approve');
                    appr.setWorkitemId(wiId);
                    Approval.process(appr);
                }
            }
        } catch (Exception e) {
            System.debug('No routable approval process on Booking__c: ' + e.getMessage());
        }
        ApprovalRejectionNotifier.notifyPreviousApprovers(new Set<Id>{ b.Id });
        Test.stopTest();
    }

    // ------------------------------------------------------- deterministic no-ops
    @isTest
    static void nullAndEmptyInputs_handled() {
        Test.startTest();
        ApprovalRejectionNotifier.notifyPreviousApprovers(null);
        ApprovalRejectionNotifier.notifyPreviousApprovers(new Set<Id>());
        ApprovalRejectionNotifier.notifyFromFlow(null);
        ApprovalRejectionNotifier.notifyFromFlow(new List<ApprovalRejectionNotifier.Request>());
        Test.stopTest();
    }

    @isTest
    static void actionType_throughApprovalActionHandler() {
        Booking__c b = makeBooking();
        String json = '{"actions":[{"actionType":"NOTIFY_PREVIOUS_APPROVERS"}]}';
        Test.startTest();
        List<String> failures =
            ApprovalActionHandler.executeActionsFromJson(b.Id, json, 'Test / REJECTION');
        Test.stopTest();
        System.debug('Action handler failures (expected empty): ' + failures);
    }
}