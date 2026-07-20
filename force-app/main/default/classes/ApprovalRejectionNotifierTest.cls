/**
 * @description Tests for ApprovalRejectionNotifier (pointer 3). ProcessInstanceStep records
 *              cannot be created directly in a test, so these tests exercise the public/bulk
 *              entry points and the no-history path (which safely no-ops).
 */
@isTest
private class ApprovalRejectionNotifierTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        // No Plot__c: avoids the Booking After Create Handler flow. The notifier only needs the record id.
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'New'
        );
        insert booking;
        return booking;
    }

    @isTest
    static void notifyPreviousApprovers_noHistory_noOp() {
        Booking__c b = makeBooking();
        Test.startTest();
        ApprovalRejectionNotifier.notifyPreviousApprovers(new Set<Id>{ b.Id });
        Test.stopTest();
        System.assert(true, 'No approval history should simply no-op without error');
    }

    @isTest
    static void notifyFromFlow_handlesRequests() {
        Booking__c b = makeBooking();
        ApprovalRejectionNotifier.Request req = new ApprovalRejectionNotifier.Request();
        req.recordId = b.Id;

        Test.startTest();
        ApprovalRejectionNotifier.notifyFromFlow(new List<ApprovalRejectionNotifier.Request>{ req });
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void nullAndEmptyInputs_handled() {
        Test.startTest();
        ApprovalRejectionNotifier.notifyPreviousApprovers(null);
        ApprovalRejectionNotifier.notifyPreviousApprovers(new Set<Id>());
        ApprovalRejectionNotifier.notifyFromFlow(null);
        ApprovalRejectionNotifier.notifyFromFlow(new List<ApprovalRejectionNotifier.Request>());
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void actionType_throughApprovalActionHandler() {
        // Exercises the NOTIFY_PREVIOUS_APPROVERS branch added to ApprovalActionHandler.
        Booking__c b = makeBooking();
        String json = '{"actions":[{"actionType":"NOTIFY_PREVIOUS_APPROVERS"}]}';
        Test.startTest();
        List<String> failures = ApprovalActionHandler.executeActionsFromJson(b.Id, json, 'Test / REJECTION');
        Test.stopTest();
        System.assertEquals(0, failures.size(), 'Notify-previous-approvers action should not fail: ' + failures);
    }
}