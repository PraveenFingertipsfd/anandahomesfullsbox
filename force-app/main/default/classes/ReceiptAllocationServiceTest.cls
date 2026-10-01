/**
 * @description Tests for ReceiptAllocationService - allocation runs only when a Receipt becomes
 *              Approved (via ReceiptTrigger after-update), never on creation or rejection.
 */
@isTest
private class ReceiptAllocationServiceTest {

    @testSetup
    static void setup() {
        Booking__c b = postSalesTestDataFactory.createFullBooking('Receipt Alloc Project');

        // One open payment schedule for the allocation to apply against (base + GST split).
        insert new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 1,
            S_No__c = 1,
            Milestone_Name__c = 'Milestone 1',
            Amount__c = 50000,
            Pending_Amount__c = 50000,
            Payment_Schedule_Amount__c = 47619,
            GST_Amount__c = 2381,
            Payment_Schedule_Amount_Pending__c = 47619,
            GST_Amount_Pending__c = 2381,
            Status__c = 'Pending',
            Due_Date__c = Date.today()
        );
    }

    /** A fresh Pending-Approval receipt with no line items yet. */
    private static Receipt__c newPendingReceipt(Id bookingId, String txnRef) {
        Receipt__c r = new Receipt__c(
            Booking__c = bookingId,
            Receipt_Date__c = Date.today(),
            Amount_Received__c = 50000,
            Total_Amount__c = 50000,
            TDS_Deducted__c = 0,
            Transaction_Reference__c = txnRef,
            Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_PENDING_APPROVAL,
            Use_Advances__c = false,
            Use_Credits__c = false
        );
        insert r;
        return r;
    }

    private static Integer lineItemCount(Id receiptId) {
        return [SELECT COUNT() FROM Receipt_Line_Item__c WHERE Receipt__c = :receiptId];
    }

    @isTest
    static void allocatesWhenApproved() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Receipt__c r = newPendingReceipt(b.Id, 'TXN-APPROVE');
        System.assertEquals(0, lineItemCount(r.Id), 'No line items should exist before approval');

        Test.startTest();
        r.Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_APPROVED;
        update r;
        Test.stopTest();

        System.assert(lineItemCount(r.Id) > 0,
            'Approving the receipt should create Receipt Line Items (allocation ran)');
    }

    @isTest
    static void noAllocationWhenRejected() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Receipt__c r = newPendingReceipt(b.Id, 'TXN-REJECT');

        Test.startTest();
        r.Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_REJECTED;
        update r;
        Test.stopTest();

        System.assertEquals(0, lineItemCount(r.Id),
            'Rejecting the receipt must not create line items');
    }

    @isTest
    static void bypassSkipsAllocation() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Receipt__c r = newPendingReceipt(b.Id, 'TXN-BYPASS');

        Test.startTest();
        ReceiptAllocationService.bypass = true;
        try {
            r.Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_APPROVED;
            update r;
        } finally {
            ReceiptAllocationService.bypass = false;
        }
        Test.stopTest();

        System.assertEquals(0, lineItemCount(r.Id),
            'bypass = true must skip allocation');
    }

    @isTest
    static void noReAllocationWhenAlreadyApproved() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Receipt__c r = newPendingReceipt(b.Id, 'TXN-NOCHANGE');

        // First approval allocates once.
        r.Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_APPROVED;
        update r;
        Integer afterApprove = lineItemCount(r.Id);
        System.assert(afterApprove > 0, 'First approval should allocate');

        Test.startTest();
        // A later update that does NOT change the status (old = new = Approved) must not re-allocate.
        r.Remarks__c = 'touched';
        update r;
        Test.stopTest();

        System.assertEquals(afterApprove, lineItemCount(r.Id),
            'A non-approval update must not re-allocate (no duplicate line items)');
    }

    @isTest
    static void directCall_isNullSafe() {
        Test.startTest();
        ReceiptAllocationService.allocateOnApproval(null, null);
        // oldMap missing the record id -> the loop just skips it, no error.
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Receipt__c r = newPendingReceipt(b.Id, 'TXN-NULLSAFE');
        r.Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_APPROVED;
        ReceiptAllocationService.allocateOnApproval(new List<Receipt__c>{ r }, new Map<Id, Receipt__c>());
        Test.stopTest();

        System.assertEquals(0, lineItemCount(r.Id),
            'With no matching old record, no transition is detected and nothing is allocated');
    }
}
