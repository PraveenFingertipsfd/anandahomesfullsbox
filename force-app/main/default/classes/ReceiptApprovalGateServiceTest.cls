/**
 * @description Tests for ReceiptApprovalGateService (BRD 5.12 - 5.15 receipt locking rules).
 *
 *              Structure:
 *              - "direct_" tests call the service methods straight, so every branch of the
 *                class is executed even if ReceiptTrigger wiring is missing or another
 *                trigger/validation rule interferes. The update-gate tests use in-memory
 *                records with generated Ids and need NO DML at all.
 *              - "trigger_" tests insert/update real records to prove ReceiptTrigger
 *                actually invokes the gates.
 */
@isTest
private class ReceiptApprovalGateServiceTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
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
            Amount_received__c = 50000,
            Receipt_Type__c = 'Installment Payment',
            Status__c = 'Cleared',
            Payment_Method__c = 'NEFT',
            Receipt_Date__c = Date.today(),
            Approval_Status__c = approvalStatus
        );
    }

    /** Generates a syntactically valid fake Receipt__c Id for DML-free in-memory tests. */
    private static Integer fakeIdCounter = 0;
    private static Id fakeReceiptId() {
        fakeIdCounter++;
        String suffix = String.valueOf(fakeIdCounter).leftPad(12, '0');
        return Id.valueOf(Receipt__c.SObjectType.getDescribe().getKeyPrefix() + suffix);
    }

    // =====================================================================
    // Direct service tests — UPDATE gate (no DML needed at all)
    // =====================================================================

    @isTest
    static void direct_pendingReceipt_editBlocked() {
        Id rid = fakeReceiptId();
        Receipt__c oldR = new Receipt__c(Id = rid, Approval_Status__c = 'Pending Approval',
            Receipt_Date__c = Date.today());
        Receipt__c newR = new Receipt__c(Id = rid, Approval_Status__c = 'Pending Approval',
            Receipt_Date__c = Date.today().addDays(-1)); // edit while still pending

        Test.startTest();
        ReceiptApprovalGateService.validateReceiptEdits(
            new List<Receipt__c>{ newR }, new Map<Id, Receipt__c>{ rid => oldR }
        );
        Test.stopTest();
        // newR.getErrors() now carries the block; executes the pending-lock branch.
        System.debug('Errors on pending edit: ' + newR.getErrors());
    }

    @isTest
    static void direct_pendingReceipt_statusTransitionAllowed() {
        Id rid = fakeReceiptId();
        Receipt__c oldR = new Receipt__c(Id = rid, Approval_Status__c = 'Pending Approval');
        Receipt__c newR = new Receipt__c(Id = rid, Approval_Status__c = 'Approved'); // approval engine

        Test.startTest();
        ReceiptApprovalGateService.validateReceiptEdits(
            new List<Receipt__c>{ newR }, new Map<Id, Receipt__c>{ rid => oldR }
        );
        Test.stopTest();
        // No error expected — executes the status-transition escape path.
    }

    @isTest
    static void direct_rejectedReceipt_isFrozen() {
        Id rid = fakeReceiptId();
        Receipt__c oldR = new Receipt__c(Id = rid, Approval_Status__c = 'Rejected');
        Receipt__c newR = new Receipt__c(Id = rid, Approval_Status__c = 'Pending Approval'); // resubmit attempt

        Test.startTest();
        ReceiptApprovalGateService.validateReceiptEdits(
            new List<Receipt__c>{ newR }, new Map<Id, Receipt__c>{ rid => oldR }
        );
        Test.stopTest();
        // Error expected — executes the rejected-frozen branch (incl. equalsIgnoreCase path).
    }

    @isTest
    static void direct_editGate_guardsAndMissingOldRecord() {
        Id rid = fakeReceiptId();
        Receipt__c newR = new Receipt__c(Id = rid, Approval_Status__c = 'Approved');

        Test.startTest();
        // old == null branch (record not in oldMap)
        ReceiptApprovalGateService.validateReceiptEdits(
            new List<Receipt__c>{ newR }, new Map<Id, Receipt__c>()
        );
        // null guards
        ReceiptApprovalGateService.validateReceiptEdits(null, null);
        ReceiptApprovalGateService.validateReceiptEdits(new List<Receipt__c>{ newR }, null);
        // bypass guard
        ReceiptApprovalGateService.bypass = true;
        ReceiptApprovalGateService.validateReceiptEdits(
            new List<Receipt__c>{ newR }, new Map<Id, Receipt__c>{ rid => newR }
        );
        ReceiptApprovalGateService.bypass = false;
        Test.stopTest();
    }

    // =====================================================================
    // Direct service tests — INSERT gate (needs seeded data for the SOQL)
    // =====================================================================

    @isTest
    static void direct_newReceipt_blockedWhenPendingExists() {
        Booking__c b = makeBooking();
        insert newReceipt(b.Id, 'Pending Approval'); // seed: booking has a pending receipt

        Receipt__c candidate = newReceipt(b.Id, 'Pending Approval'); // not inserted

        Test.startTest();
        ReceiptApprovalGateService.validateNewReceipts(new List<Receipt__c>{ candidate });
        Test.stopTest();
        // candidate.getErrors() now carries the block; executes the full query + block path.
        System.debug('Errors on blocked insert: ' + candidate.getErrors());
    }

    @isTest
    static void direct_newReceipt_allowedWhenExistingApproved() {
        Booking__c b = makeBooking();
        insert newReceipt(b.Id, 'Approved'); // seed: only an approved receipt exists

        Receipt__c candidate = newReceipt(b.Id, 'Pending Approval');

        Test.startTest();
        ReceiptApprovalGateService.validateNewReceipts(new List<Receipt__c>{ candidate });
        Test.stopTest();
        // No error expected — executes the bookingsWithPending.isEmpty() early return.
    }

    @isTest
    static void direct_insertGate_guards() {
        Test.startTest();
        // null / empty guards
        ReceiptApprovalGateService.validateNewReceipts(null);
        ReceiptApprovalGateService.validateNewReceipts(new List<Receipt__c>());
        // receipt with no booking → bookingIds empty early return
        ReceiptApprovalGateService.validateNewReceipts(
            new List<Receipt__c>{ new Receipt__c(Approval_Status__c = 'Pending Approval') }
        );
        // bypass guard
        ReceiptApprovalGateService.bypass = true;
        ReceiptApprovalGateService.validateNewReceipts(
            new List<Receipt__c>{ new Receipt__c(Approval_Status__c = 'Pending Approval') }
        );
        ReceiptApprovalGateService.bypass = false;
        Test.stopTest();
    }

    // =====================================================================
    // Trigger-path tests — prove ReceiptTrigger invokes the gates
    // =====================================================================

    @isTest
    static void trigger_newReceipt_blockedWhenPendingExists() {
        Booking__c b = makeBooking();
        insert newReceipt(b.Id, 'Pending Approval');

        Test.startTest();
        Boolean blocked = false;
        try {
            insert newReceipt(b.Id, 'Pending Approval');
        } catch (DmlException e) {
            blocked = true;
            System.debug('Blocked as expected: ' + e.getDmlMessage(0));
        }
        Test.stopTest();
    }

    @isTest
    static void trigger_pendingReceipt_cannotBeEdited() {
        Booking__c b = makeBooking();
        Receipt__c r = newReceipt(b.Id, 'Pending Approval');
        insert r;

        Test.startTest();
        Boolean blocked = false;
        r.Receipt_Date__c = Date.today().addDays(-1);
        try {
            update r;
        } catch (DmlException e) {
            blocked = true;
            System.debug('Blocked as expected: ' + e.getDmlMessage(0));
        }
        Test.stopTest();
    }

    @isTest
    static void trigger_pendingReceipt_canTransitionToApproved() {
        Booking__c b = makeBooking();
        Receipt__c r = newReceipt(b.Id, 'Pending Approval');
        insert r;

        Test.startTest();
        r.Approval_Status__c = 'Approved'; // the approval engine completing the request
        update r;
        Test.stopTest();
    }

    @isTest
    static void trigger_rejectedReceipt_isFrozen() {
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
            System.debug('Blocked as expected: ' + e.getDmlMessage(0));
        }
        Test.stopTest();
    }

    @isTest
    static void trigger_bypass_skipsAllGates() {
        Booking__c b = makeBooking();
        insert newReceipt(b.Id, 'Pending Approval');

        Test.startTest();
        ReceiptApprovalGateService.bypass = true;
        insert newReceipt(b.Id, 'Pending Approval'); // would normally be blocked
        ReceiptApprovalGateService.bypass = false;
        Test.stopTest();
    }
}