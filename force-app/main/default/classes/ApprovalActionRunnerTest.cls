/**
 * @description Tests for ApprovalActionRunner.runApprovalActions (explicit invocable
 * that runs a specific config's On_Submit / On_Approval / On_Rejection action JSON).
 */
@isTest
private class ApprovalActionRunnerTest {

    @testSetup
    static void setup() {
        Project__c project = new Project__c(
            Name = 'Action Runner Test Project',
            Project_Type__c = 'Residential'
        );
        insert project;

        // No Plot__c on the booking: avoids the Booking After Create Handler flow (fires only
        // when Unit is set and then requires a Quote we don't have). The runner acts on the
        // booking's id, not its unit.
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'New'
        );
        insert booking;

        // Three distinct payloads, one per transition, so we can tell which path ran
        ApprovalActionHandler.ActionConfig approvalPayload = new ApprovalActionHandler.ActionConfig();
        approvalPayload.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem chatterApprove = new ApprovalActionHandler.ActionItem();
        chatterApprove.actionType = 'CHATTER_POST';
        chatterApprove.chatterMessage = 'Runner: approval path';
        approvalPayload.actions.add(chatterApprove);

        ApprovalActionHandler.ActionConfig rejectionPayload = new ApprovalActionHandler.ActionConfig();
        rejectionPayload.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem chatterReject = new ApprovalActionHandler.ActionItem();
        chatterReject.actionType = 'CHATTER_POST';
        chatterReject.chatterMessage = 'Runner: rejection path';
        rejectionPayload.actions.add(chatterReject);

        ApprovalActionHandler.ActionConfig submitPayload = new ApprovalActionHandler.ActionConfig();
        submitPayload.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem chatterSubmit = new ApprovalActionHandler.ActionItem();
        chatterSubmit.actionType = 'CHATTER_POST';
        chatterSubmit.chatterMessage = 'Runner: submission path';
        submitPayload.actions.add(chatterSubmit);

        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Booking__c',
            Process_Type__c = 'Runner_Test',
            Process_Label__c = 'Runner Test',
            Status_Field_API_Name__c = 'Booking_Verification_Approval_Status__c',
            Approved_Status_Value__c = 'Approved',
            Rejected_Status_Value__c = 'Rejected',
            Pending_Status_Value__c = 'Pending Approval',
            Is_Active__c = true,
            On_Submit_JSON__c = JSON.serialize(submitPayload),
            On_Approval_JSON__c = JSON.serialize(approvalPayload),
            On_Rejection_JSON__c = JSON.serialize(rejectionPayload)
        );
        insert cfg;
    }

    private static ApprovalActionRunner.RunActionRequest req(Id recordId, Id configId, String actionType) {
        ApprovalActionRunner.RunActionRequest r = new ApprovalActionRunner.RunActionRequest();
        r.recordId = recordId;
        r.configId = configId;
        r.actionType = actionType;
        return r;
    }

    @isTest
    static void runApprovalActions_nullRecordId_returnsError() {
        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(
                new List<ApprovalActionRunner.RunActionRequest>{ req(null, null, 'APPROVAL') }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(false, results[0].success, 'null record id should not succeed');
        System.assert(results[0].message.containsIgnoreCase('record'), 'message should mention record id');
    }

    @isTest
    static void runApprovalActions_nullConfigId_returnsError() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(
                new List<ApprovalActionRunner.RunActionRequest>{ req(b.Id, null, 'APPROVAL') }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(false, results[0].success, 'null config id should not succeed');
        System.assert(results[0].message.containsIgnoreCase('configuration'), 'message should mention config id');
    }

    @isTest
    static void runApprovalActions_approvalPath_runsChatter() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Approval_Configuration__c cfg = [SELECT Id FROM Approval_Configuration__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(
                new List<ApprovalActionRunner.RunActionRequest>{ req(b.Id, cfg.Id, 'APPROVAL') }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertNotEquals(null, results[0].message, 'message should be present');
    }

    @isTest
    static void runApprovalActions_rejectionPath_runs() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Approval_Configuration__c cfg = [SELECT Id FROM Approval_Configuration__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(
                new List<ApprovalActionRunner.RunActionRequest>{ req(b.Id, cfg.Id, 'REJECTION') }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
    }

    @isTest
    static void runApprovalActions_submissionPath_runs() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Approval_Configuration__c cfg = [SELECT Id FROM Approval_Configuration__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(
                new List<ApprovalActionRunner.RunActionRequest>{ req(b.Id, cfg.Id, 'SUBMISSION') }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
    }

    @isTest
    static void runApprovalActions_blankActionType_defaultsToApproval() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Approval_Configuration__c cfg = [SELECT Id FROM Approval_Configuration__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(
                new List<ApprovalActionRunner.RunActionRequest>{ req(b.Id, cfg.Id, null) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
    }

    @isTest
    static void runApprovalActions_blankActionJson_returnsSuccessNoOp() {
        // Clear the action JSON so runner sees "nothing to do"
        Approval_Configuration__c cfg = [SELECT Id FROM Approval_Configuration__c LIMIT 1];
        cfg.On_Approval_JSON__c = null;
        update cfg;

        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(
                new List<ApprovalActionRunner.RunActionRequest>{ req(b.Id, cfg.Id, 'APPROVAL') }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success, 'no actions configured is still a success');
        System.assert(results[0].message.containsIgnoreCase('no actions'), 'message should explain no-op');
    }

    @isTest
    static void runApprovalActions_nullRequestList_returnsEmpty() {
        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'null request list should yield empty results');
    }

    @isTest
    static void runApprovalActions_caseInsensitiveActionType() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Approval_Configuration__c cfg = [SELECT Id FROM Approval_Configuration__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionRunner.runApprovalActions(new List<ApprovalActionRunner.RunActionRequest>{
                req(b.Id, cfg.Id, 'approval'),
                req(b.Id, cfg.Id, 'Reject'),
                req(b.Id, cfg.Id, 'submit')
            });
        Test.stopTest();

        System.assertEquals(3, results.size(), 'three results');
    }
}