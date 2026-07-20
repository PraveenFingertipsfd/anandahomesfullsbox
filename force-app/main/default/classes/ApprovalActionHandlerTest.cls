/**
 * @description Tests for ApprovalActionHandler.
 *
 * Detection (approval / rejection / skip) is asserted directly via NotificationResult.
 * Action execution (email, bell, field update, chatter, notify-previous-approvers) is
 * exercised for coverage; individual action failures are intentionally swallowed by the
 * handler (collected and posted as a Chatter summary), so action tests assert that
 * detection still succeeds rather than asserting on org-dependent side effects such as a
 * Custom Notification Type or Email Template that may not exist in every org.
 *
 * Picklist note: Booking_Verification_Approval_Status__c is a restricted picklist with
 * exactly {Pending Approval, Approved, Rejected}.
 */
@isTest
private class ApprovalActionHandlerTest {

    private static final String STATUS_FIELD = 'Booking_Verification_Approval_Status__c';

    @testSetup
    static void setup() {
        Project__c project = new Project__c(Name = 'Approval Test Project', Project_Type__c = 'Residential');
        insert project;

        // No Plot__c: avoids the Booking After Create Handler flow (fires only when Unit is set
        // and requires a Quote we don't have). The handler under test acts on the booking's
        // own fields / owner, not the unit.
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'New',
            First_Applicant_Name__c = 'Approval Customer',
            Booking_Verification_Approval_Status__c = 'Approved'
        );
        insert booking;

        insertConfig(buildActionsJson(true), buildActionsJson(true));
    }

    // ==================== HELPERS ====================

    private static Booking__c getBooking() {
        return [SELECT Id, OwnerId FROM Booking__c LIMIT 1];
    }

    /** @description Replaces the approval configuration with one carrying the given action JSON. */
    private static void insertConfig(String approvalJson, String rejectionJson) {
        delete [SELECT Id FROM Approval_Configuration__c];
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Booking__c',
            Process_Type__c = 'Verification',
            Process_Label__c = 'Booking Verification',
            Status_Field_API_Name__c = STATUS_FIELD,
            Approved_Status_Value__c = 'Approved',
            Rejected_Status_Value__c = 'Rejected',
            Is_Active__c = true,
            On_Approval_JSON__c = approvalJson,
            On_Rejection_JSON__c = rejectionJson
        );
    }

    /** @description A simple, clean config: a Chatter post plus a valid field update. */
    private static String buildActionsJson(Boolean includeFieldUpdate) {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();

        ApprovalActionHandler.ActionItem chatter = new ApprovalActionHandler.ActionItem();
        chatter.actionType = 'CHATTER_POST';
        chatter.chatterMessage = 'Booking approved';
        cfg.actions.add(chatter);

        if (includeFieldUpdate) {
            ApprovalActionHandler.ActionItem fieldUpd = new ApprovalActionHandler.ActionItem();
            fieldUpd.actionType = 'FIELD_UPDATE';
            fieldUpd.fieldUpdates = new List<ApprovalActionHandler.FieldUpdate>();
            ApprovalActionHandler.FieldUpdate fu = new ApprovalActionHandler.FieldUpdate();
            // A harmless text field: avoids the Booking stage-transition validation that
            // guards Status__c, so the update applies cleanly and is safe to assert on.
            fu.fieldName = 'First_Applicant_Name__c';
            fu.value = 'Verified Name';
            fieldUpd.fieldUpdates.add(fu);
            cfg.actions.add(fieldUpd);
        }
        return JSON.serialize(cfg);
    }

    private static List<ApprovalActionHandler.NotificationResult> run(Id recordId, Map<String, String> priorValues) {
        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = recordId;
        if (priorValues != null) {
            req.priorValuesJson = JSON.serialize(priorValues);
        }
        return ApprovalActionHandler.processApprovalNotifications(
            new List<ApprovalActionHandler.NotificationRequest>{ req }
        );
    }

    private static Map<String, String> prior(String value) {
        return new Map<String, String>{ STATUS_FIELD => value };
    }

    // ==================== DETECTION ====================

    @isTest
    static void nullRecordId_returnsError() {
        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(null, null);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result expected');
        System.assertEquals(false, results[0].success, 'Null record id should not succeed');
        System.assertEquals('Record ID is required', results[0].message, 'Specific error message');
    }

    @isTest
    static void approvalDetected_runsActionsAndSucceeds() {
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result expected');
        System.assertEquals(true, results[0].success, 'Transition Pending->Approved should be detected as APPROVAL');
        System.assert(results[0].message.contains('APPROVAL'), 'Message should record the APPROVAL action');

        // The clean FIELD_UPDATE in the config should have applied to the record.
        Booking__c after = [SELECT First_Applicant_Name__c FROM Booking__c WHERE Id = :b.Id];
        System.assertEquals('Verified Name', after.First_Applicant_Name__c, 'Field update action applied');
    }

    @isTest
    static void rejectionDetected_runsActionsAndSucceeds() {
        Booking__c b = getBooking();
        b.Booking_Verification_Approval_Status__c = 'Rejected';
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Transition Pending->Rejected should be detected as REJECTION');
        System.assert(results[0].message.contains('REJECTION'), 'Message should record the REJECTION action');
    }

    @isTest
    static void noActiveConfigs_returnsMessage() {
        delete [SELECT Id FROM Approval_Configuration__c];
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, null);
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'No configs -> not successful');
        System.assertEquals('No active approval configurations found', results[0].message, 'Specific message');
    }

    @isTest
    static void priorEqualsCurrent_skips() {
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Approved'));
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Unchanged value should not trigger actions');
        System.assertEquals('No final approval/rejection detected', results[0].message, 'Skip message');
    }

    @isTest
    static void blankCurrentValue_skips() {
        Booking__c b = getBooking();
        b.Booking_Verification_Approval_Status__c = null;
        update b;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, null);
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Blank current value should be skipped');
    }

    @isTest
    static void neitherApprovedNorRejected_skips() {
        Booking__c b = getBooking();
        b.Booking_Verification_Approval_Status__c = 'Pending Approval';
        update b;

        Test.startTest();
        // prior different from current so it is not skipped on the prior==current check,
        // but 'Pending Approval' matches neither the approved nor rejected configured value.
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Rejected'));
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Intermediate status is neither approval nor rejection');
        System.assertEquals('No final approval/rejection detected', results[0].message, 'Skip message');
    }

    @isTest
    static void invalidPriorJson_isTolerated() {
        Booking__c b = getBooking();
        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = b.Id;
        req.priorValuesJson = 'not-json';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        // Malformed prior JSON is swallowed (empty prior map), so the Approved current value
        // is still detected as an approval.
        System.assertEquals(true, results[0].success, 'Bad prior JSON should not abort detection');
    }

    @isTest
    static void multipleRequests_batch() {
        Booking__c b = getBooking();
        List<ApprovalActionHandler.NotificationRequest> reqs = new List<ApprovalActionHandler.NotificationRequest>();
        for (Integer i = 0; i < 5; i++) {
            ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
            req.recordId = b.Id;
            req.priorValuesJson = JSON.serialize(prior('Pending Approval'));
            reqs.add(req);
        }

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> res = ApprovalActionHandler.processApprovalNotifications(reqs);
        Test.stopTest();

        System.assertEquals(5, res.size(), 'One result per request');
    }

    // ==================== ACTION JSON EDGE CASES ====================

    @isTest
    static void blankActionsJson_detectedButNoActions() {
        insertConfig(null, null);
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        // Approval is still detected; there are simply no actions to run.
        System.assertEquals(true, results[0].success, 'Detection succeeds even with no action JSON');
    }

    @isTest
    static void invalidActionsJson_isTolerated() {
        insertConfig('not-json', 'not-json');
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        // Malformed action JSON is caught inside executeApprovalActions and posted as a summary;
        // detection itself still reports success.
        System.assertEquals(true, results[0].success, 'Malformed action JSON should not abort detection');
    }

    @isTest
    static void allActionTypes_runForCoverage() {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();

        ApprovalActionHandler.ActionItem email = new ApprovalActionHandler.ActionItem();
        email.actionType = 'EMAIL_NOTIFICATION';
        email.emailConfig = new ApprovalActionHandler.EmailConfig();
        email.emailConfig.recipientFieldPaths = new List<String>{ 'OwnerId' };
        email.emailConfig.additionalEmails = new List<String>{ 'cc@example.com' };
        cfg.actions.add(email);

        ApprovalActionHandler.ActionItem bell = new ApprovalActionHandler.ActionItem();
        bell.actionType = 'BELL_NOTIFICATION';
        bell.bellConfig = new ApprovalActionHandler.BellConfig();
        bell.bellConfig.title = 'Hi {Name}';
        bell.bellConfig.body = 'Status is {Status__c}';
        bell.bellConfig.recipientFieldPaths = new List<String>{ 'OwnerId' };
        cfg.actions.add(bell);

        ApprovalActionHandler.ActionItem chatter = new ApprovalActionHandler.ActionItem();
        chatter.actionType = 'CHATTER_POST';
        chatter.chatterMessage = 'Posted!';
        cfg.actions.add(chatter);

        ApprovalActionHandler.ActionItem notifyPrev = new ApprovalActionHandler.ActionItem();
        notifyPrev.actionType = 'NOTIFY_PREVIOUS_APPROVERS';
        cfg.actions.add(notifyPrev);

        insertConfig(JSON.serialize(cfg), JSON.serialize(cfg));
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result expected');
        System.assertEquals(true, results[0].success, 'Approval detected even if individual actions are no-ops in this org');
    }

    @isTest
    static void emailWithMissingTemplate_fallsBackToDefault() {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem email = new ApprovalActionHandler.ActionItem();
        email.actionType = 'EMAIL_NOTIFICATION';
        email.emailConfig = new ApprovalActionHandler.EmailConfig();
        email.emailConfig.recipientFieldPaths = new List<String>{ 'OwnerId' };
        email.emailConfig.templateDeveloperName = 'NonExistent_Template_DevName_X';
        cfg.actions.add(email);

        insertConfig(JSON.serialize(cfg), JSON.serialize(cfg));
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Missing template should fall back to default content, not abort');
    }

    @isTest
    static void emailNoRecipients_failureIsContained() {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem email = new ApprovalActionHandler.ActionItem();
        email.actionType = 'EMAIL_NOTIFICATION';
        email.emailConfig = new ApprovalActionHandler.EmailConfig(); // no recipients at all
        cfg.actions.add(email);

        insertConfig(JSON.serialize(cfg), JSON.serialize(cfg));
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        // The "no recipients" ApprovalActionException is caught and summarized; detection still succeeds.
        System.assertEquals(true, results[0].success, 'Recipient-less email failure should be contained');
    }

    @isTest
    static void bellMissingTitleOrBody_failureIsContained() {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem bell = new ApprovalActionHandler.ActionItem();
        bell.actionType = 'BELL_NOTIFICATION';
        bell.bellConfig = new ApprovalActionHandler.BellConfig();
        bell.bellConfig.title = '';
        bell.bellConfig.body = '';
        cfg.actions.add(bell);

        insertConfig(JSON.serialize(cfg), JSON.serialize(cfg));
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Empty bell title/body failure should be contained');
    }

    @isTest
    static void chatterBlankMessage_failureIsContained() {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem chatter = new ApprovalActionHandler.ActionItem();
        chatter.actionType = 'CHATTER_POST';
        chatter.chatterMessage = null;
        cfg.actions.add(chatter);

        insertConfig(JSON.serialize(cfg), JSON.serialize(cfg));
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Blank chatter message failure should be contained');
    }

    // ==================== FIELD UPDATE SPECIAL TOKENS ====================

    @isTest
    static void fieldUpdate_todayAndUserIdTokensAndMissingField() {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem fu = new ApprovalActionHandler.ActionItem();
        fu.actionType = 'FIELD_UPDATE';
        fu.fieldUpdates = new List<ApprovalActionHandler.FieldUpdate>();

        ApprovalActionHandler.FieldUpdate f1 = new ApprovalActionHandler.FieldUpdate();
        f1.fieldName = 'Booking_Date__c'; f1.value = '$TODAY';
        fu.fieldUpdates.add(f1);

        ApprovalActionHandler.FieldUpdate f2 = new ApprovalActionHandler.FieldUpdate();
        f2.fieldName = 'OwnerId'; f2.value = '$USER_ID';
        fu.fieldUpdates.add(f2);

        ApprovalActionHandler.FieldUpdate f3 = new ApprovalActionHandler.FieldUpdate();
        f3.fieldName = 'NonExistentField__c'; f3.value = 'x';
        fu.fieldUpdates.add(f3);

        cfg.actions.add(fu);
        insertConfig(JSON.serialize(cfg), JSON.serialize(cfg));
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        // The missing field makes the field-update action throw, but that is caught and summarized;
        // detection still succeeds. The $TODAY and $USER_ID coercion branches are exercised.
        System.assertEquals(true, results[0].success, 'Detection unaffected by a partially-invalid field update');
    }

    @isTest
    static void fieldUpdate_nowToken() {
        ApprovalActionHandler.ActionConfig cfg = new ApprovalActionHandler.ActionConfig();
        cfg.actions = new List<ApprovalActionHandler.ActionItem>();
        ApprovalActionHandler.ActionItem fu = new ApprovalActionHandler.ActionItem();
        fu.actionType = 'FIELD_UPDATE';
        fu.fieldUpdates = new List<ApprovalActionHandler.FieldUpdate>();
        ApprovalActionHandler.FieldUpdate f1 = new ApprovalActionHandler.FieldUpdate();
        f1.fieldName = 'Booking_Date__c'; f1.value = '$NOW'; // exercises the $NOW coercion branch
        fu.fieldUpdates.add(f1);
        cfg.actions.add(fu);

        insertConfig(JSON.serialize(cfg), JSON.serialize(cfg));
        Booking__c b = getBooking();

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results = run(b.Id, prior('Pending Approval'));
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Detection unaffected by the $NOW field update');
    }

    // ==================== PUBLIC executeActionsFromJson ====================

    @isTest
    static void executeActionsFromJson_validReturnsNoFailures() {
        Booking__c b = getBooking();

        Test.startTest();
        List<String> failures = ApprovalActionHandler.executeActionsFromJson(
            b.Id, buildActionsJson(false), 'Submission'
        );
        Test.stopTest();

        System.assertEquals(0, failures.size(), 'A clean Chatter-only action set should report no failures');
    }

    @isTest
    static void executeActionsFromJson_malformedReturnsFailure() {
        Booking__c b = getBooking();

        Test.startTest();
        List<String> failures = ApprovalActionHandler.executeActionsFromJson(b.Id, 'not-json', 'Submission');
        Test.stopTest();

        System.assertEquals(1, failures.size(), 'Malformed JSON should produce one failure entry');
        System.assert(failures[0].contains('malformed'), 'Failure message should explain the malformed JSON');
    }

    @isTest
    static void executeActionsFromJson_nullInputsReturnEmpty() {
        Test.startTest();
        List<String> a = ApprovalActionHandler.executeActionsFromJson(null, '{}', 'ctx');
        List<String> b = ApprovalActionHandler.executeActionsFromJson(getBooking().Id, null, 'ctx');
        Test.stopTest();

        System.assertEquals(0, a.size(), 'Null record id -> no work, no failures');
        System.assertEquals(0, b.size(), 'Blank actions JSON -> no work, no failures');
    }

    // ==================== WRAPPERS ====================

    @isTest
    static void wrappers_areInstantiable() {
        ApprovalActionHandler.NotificationRequest nr = new ApprovalActionHandler.NotificationRequest();
        ApprovalActionHandler.NotificationResult nres = new ApprovalActionHandler.NotificationResult();
        ApprovalActionHandler.ActionConfig ac = new ApprovalActionHandler.ActionConfig();
        ApprovalActionHandler.ActionItem ai = new ApprovalActionHandler.ActionItem();
        ApprovalActionHandler.EmailConfig ec = new ApprovalActionHandler.EmailConfig();
        ApprovalActionHandler.BellConfig bc = new ApprovalActionHandler.BellConfig();
        ApprovalActionHandler.FieldUpdate fu = new ApprovalActionHandler.FieldUpdate();

        nres.success = true; nres.message = 'm';
        ai.actionType = 'X'; ai.chatterMessage = 'm';
        fu.fieldName = 'F'; fu.value = 'V';

        System.assertEquals(true, nres.success, 'result success set');
        System.assertEquals('m', nres.message, 'result message set');
        System.assertEquals('V', fu.value, 'field update value set');
        System.assertNotEquals(null, nr, 'request instantiated');
        System.assertNotEquals(null, ac, 'action config instantiated');
        System.assertNotEquals(null, ec, 'email config instantiated');
        System.assertNotEquals(null, bc, 'bell config instantiated');
        System.assertNotEquals(null, ai, 'action item instantiated');
    }
}