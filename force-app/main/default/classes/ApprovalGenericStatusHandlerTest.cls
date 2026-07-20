/**
 * @description Tests for ApprovalGenericStatusHandler.runFromGenericStatus
 * (the generic Approval_Status__c + Approval_Name__c dispatcher).
 */
@isTest
private class ApprovalGenericStatusHandlerTest {

    @testSetup
    static void setup() {
        Project__c project = new Project__c(
            Name = 'Generic Status Test Project',
            Project_Type__c = 'Residential'
        );
        insert project;

        // No Plot__c: avoids the Booking After Create Handler flow. The handler reads the
        // booking's approval-status fields, not its unit.
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'New',
            Approval_Status__c = 'Pending',
            Approval_Name__c = 'Generic_Status_Test'
        );
        insert booking;

        // Three payloads, each writes a distinct chatter so we can tell paths apart
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Booking__c',
            Process_Type__c = 'Generic_Status_Test',
            Process_Label__c = 'Generic Status Test',
            Status_Field_API_Name__c = 'Booking_Verification_Approval_Status__c',
            Approved_Status_Value__c = 'Approved',
            Rejected_Status_Value__c = 'Rejected',
            Pending_Status_Value__c = 'Pending Approval',
            Is_Active__c = true,
            On_Submit_JSON__c = buildChatterJson('Generic: submit path'),
            On_Approval_JSON__c = buildChatterJson('Generic: approval path'),
            On_Rejection_JSON__c = buildChatterJson('Generic: rejection path')
        );
        insert cfg;
    }

    private static String buildChatterJson(String message) {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem item = new ApprovalActionHandler.ActionItem();
        item.actionType = 'CHATTER_POST';
        item.chatterMessage = message;
        cfg.actions.add(item);
        return JSON.serialize(cfg);
    }

    private static ApprovalGenericStatusHandler.GenericStatusRequest req(Id recordId) {
        ApprovalGenericStatusHandler.GenericStatusRequest r = new ApprovalGenericStatusHandler.GenericStatusRequest();
        r.recordId = recordId;
        return r;
    }

    @isTest
    static void runFromGenericStatus_nullRecordId_returnsError() {
        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(null) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(false, results[0].success, 'null record id should not succeed');
        System.assert(results[0].message.containsIgnoreCase('record'), 'message should mention record id');
    }

    @isTest
    static void runFromGenericStatus_nullRequestList_returnsEmpty() {
        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'null request list should yield empty results');
    }

    @isTest
    static void runFromGenericStatus_pendingStatus_firesSubmitPayload() {
        // Default seed leaves Approval_Status__c = Pending
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success, 'submission path should succeed');
        System.assert(results[0].message.containsIgnoreCase('submission'), 'message should mention SUBMISSION');
    }

    @isTest
    static void runFromGenericStatus_approvedStatus_firesApprovalPayload() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Approval_Status__c = 'Approved';
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success, 'approval path should succeed');
        System.assert(results[0].message.containsIgnoreCase('approval'), 'message should mention APPROVAL');
    }

    @isTest
    static void runFromGenericStatus_rejectedStatus_firesRejectionPayload() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Approval_Status__c = 'Rejected';
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success, 'rejection path should succeed');
        System.assert(results[0].message.containsIgnoreCase('rejection'), 'message should mention REJECTION');
    }

    @isTest
    static void runFromGenericStatus_blankStatus_noOpsCleanly() {
        // Blank Approval_Status__c with no per-process status field matching any
        // active config's Approved/Rejected/Pending value should be a benign no-op.
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Approval_Status__c = null;
        // Setup left Booking_Verification_Approval_Status__c null too, so the
        // per-process fallback finds nothing either.
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success, 'no state to act on is a benign no-op');
        System.assert(
            results[0].message.containsIgnoreCase('nothing to run')
                || results[0].message.containsIgnoreCase('matched'),
            'message should explain why nothing happened: ' + results[0].message
        );
    }

    @isTest
    static void runFromGenericStatus_blankApprovalName_fallsBackToSingleConfig() {
        // When Approval_Name__c is blank (e.g. submission went through the native
        // Salesforce 'Submit for Approval' button), the handler falls back to the
        // single active Approval Configuration for the object. Setup inserts
        // exactly one active config, so this fallback should kick in.
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Approval_Name__c = null;
        b.Approval_Status__c = 'Approved';
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success,
            'blank Approval_Name__c with exactly one active config should fall back and succeed');
        System.assert(results[0].message.containsIgnoreCase('approval'),
            'message should reference the approval action: ' + results[0].message);
    }

    @isTest
    static void runFromGenericStatus_blankApprovalNameMultipleConfigs_returnsError() {
        // With more than one active config, the handler can't disambiguate and
        // returns an explanatory error.
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Booking__c',
            Process_Type__c = 'Second_Process',
            Process_Label__c = 'Second Process',
            Status_Field_API_Name__c = 'Booking_Verification_Approval_Status__c',
            Approved_Status_Value__c = 'Approved',
            Rejected_Status_Value__c = 'Rejected',
            Pending_Status_Value__c = 'Pending Approval',
            Is_Active__c = true,
            On_Approval_JSON__c = buildChatterJson('Second: approval')
        );

        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Approval_Name__c = null;
        b.Approval_Status__c = 'Approved';
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(false, results[0].success,
            'blank Approval_Name__c with multiple active configs should not auto-resolve');
        System.assert(results[0].message.containsIgnoreCase('auto-resolve')
            || results[0].message.containsIgnoreCase('blank'),
            'message should explain why disambiguation failed: ' + results[0].message);
    }

    @isTest
    static void runFromGenericStatus_perProcessFieldFallback_runsActions() {
        // When Approval_Status__c is blank and the per-process status field (e.g.
        // Booking_Verification_Approval_Status__c) is set to the config's
        // Approved_Status_Value__c, the per-process fallback path should pick up
        // the config and run On_Approval_JSON__c. This is the path that makes the
        // handler work for approval processes whose Final Approval Action updates
        // a named field rather than the generic Approval_Status__c.
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Approval_Status__c = null;
        b.Approval_Name__c = null;
        b.Booking_Verification_Approval_Status__c = 'Approved';
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success,
            'per-process field match should run On_Approval actions: ' + results[0].message);
        System.assert(results[0].message.containsIgnoreCase('approval'),
            'message should reference the APPROVAL action: ' + results[0].message);
    }

    @isTest
    static void runFromGenericStatus_objectWithNoConfig_returnsError() {
        // Project__c has no active Approval Configuration, so the handler returns early with
        // an explanatory "no active configuration" message before any status resolution.
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(project.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(false, results[0].success,
            'an object with no active approval configuration should not succeed');
        System.assert(results[0].message.containsIgnoreCase('no active'),
            'message should explain there is no active configuration: ' + results[0].message);
    }

    @isTest
    static void runFromGenericStatus_blankActionJson_returnsBenignSuccess() {
        Approval_Configuration__c cfg = [SELECT Id FROM Approval_Configuration__c LIMIT 1];
        cfg.On_Submit_JSON__c = null;
        update cfg;

        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalGenericStatusHandler.runFromGenericStatus(
                new List<ApprovalGenericStatusHandler.GenericStatusRequest>{ req(b.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result');
        System.assertEquals(true, results[0].success, 'no-op when payload is blank');
        System.assert(results[0].message.containsIgnoreCase('no actions'),
            'message should explain the no-op');
    }
}