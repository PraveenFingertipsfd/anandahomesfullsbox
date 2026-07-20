/**
 * @description Tests for ReceiptApprovalGateService (BRD 5.12 - 5.15 receipt locking rules).
 */
@isTest
private class ReceiptApprovalGateServiceTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'New'
        );
        insert b;
        return b;
    }

    private static Receipt__c newReceipt(Id bookingId, String approvalStatus) {
        return new Receipt__c(
            Booking__c = bookingId,
            Payment_Method__c = 'NEFT',
            Receipt_Date__c = Date.today(),
            Approval_Status__c = approvalStatus
        );
    }

    @isTest
    static void newReceipt_blockedWhenPendingExists() {
        Booking__c b = makeBooking();
        insert newReceipt(b.Id, 'Pending Approval');

        Test.startTest();
        Boolean blocked = false;
        try {
            insert newReceipt(b.Id, 'Pending Approval');
        } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('awaiting approval'), e.getMessage());
        }
        Test.stopTest();
        System.assert(blocked, 'A second receipt must be blocked while one is pending approval');
    }

    @isTest
    static void newReceipt_allowedWhenExistingApproved() {
        Booking__c b = makeBooking();
        insert newReceipt(b.Id, 'Approved');

        Test.startTest();
        insert newReceipt(b.Id, 'Pending Approval'); // allowed — prior one is approved
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :b.Id]);
    }

    @isTest
    static void pendingReceipt_cannotBeEdited() {
        Booking__c b = makeBooking();
        Receipt__c r = newReceipt(b.Id, 'Pending Approval');
        insert r;

        Test.startTest();
        Boolean blocked = false;
        r.Receipt_Date__c = Date.today().addDays(-1); // edit a field while still pending
        try {
            update r;
        } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('awaiting approval'), e.getMessage());
        }
        Test.stopTest();
        System.assert(blocked, 'Editing a pending receipt must be blocked');
    }

    @isTest
    static void pendingReceipt_canTransitionToApproved() {
        Booking__c b = makeBooking();
        Receipt__c r = newReceipt(b.Id, 'Pending Approval');
        insert r;

        Test.startTest();
        r.Approval_Status__c = 'Approved'; // the approval engine completing the request
        update r;
        Test.stopTest();

        System.assertEquals('Approved', [SELECT Approval_Status__c FROM Receipt__c WHERE Id = :r.Id].Approval_Status__c);
    }

    @isTest
    static void rejectedReceipt_isFrozen() {
        Booking__c b = makeBooking();
        Receipt__c r = newReceipt(b.Id, 'Rejected');
        insert r;

        Test.startTest();
        Boolean blocked = false;
        r.Receipt_Date__c = Date.today().addDays(-2);
        try {
            update r;
        } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('Rejected'), e.getMessage());
        }
        Test.stopTest();
        System.assert(blocked, 'A rejected receipt must not be modifiable');
    }

    @isTest
    static void bypass_skipsAllGates() {
        Booking__c b = makeBooking();
        insert newReceipt(b.Id, 'Pending Approval');

        Test.startTest();
        ReceiptApprovalGateService.bypass = true;
        insert newReceipt(b.Id, 'Pending Approval'); // would normally be blocked
        ReceiptApprovalGateService.bypass = false;
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :b.Id]);
    }
}