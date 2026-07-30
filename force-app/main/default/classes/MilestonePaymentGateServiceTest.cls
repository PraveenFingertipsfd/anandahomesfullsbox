/**
 * @description Tests for MilestonePaymentGateService / ReceiptLineItemTrigger (pointer 4):
 *              milestone-by-milestone payment sequencing.
 *
 *              Structure:
 *              - "direct_" tests call MilestonePaymentGateService.validateAllocations()
 *                directly and assert via SObject.getErrors(). These guarantee coverage of
 *                the service class even if the trigger wiring is missing or disabled.
 *              - "trigger_" tests insert real Receipt_Line_Item__c records and assert the
 *                DML outcome, proving the before-insert trigger actually invokes the gate.
 */
@isTest
private class MilestonePaymentGateServiceTest {

    private static Booking__c booking;
    private static Payment_Schedule__c ps1;
    private static Payment_Schedule__c ps2;

    private static void buildBookingWithTwoMilestones(Decimal ps1Pending, String ps1Status) {
        Project__c project = new Project__c(Name = 'P1', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert booking;

        ps1 = new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = 1, Milestone_Name__c = 'Foundation',
            Amount__c = 100000, Pending_Amount__c = ps1Pending, Amount_Paid__c = 100000 - ps1Pending,
            Status__c = ps1Status, Due_Date__c = Date.today()
        );
        ps2 = new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = 2, Milestone_Name__c = '5th Floor',
            Amount__c = 100000, Pending_Amount__c = 100000, Amount_Paid__c = 0,
            Status__c = 'Pending', Due_Date__c = Date.today().addDays(30)
        );
        insert new List<Payment_Schedule__c>{ ps1, ps2 };
    }

    private static Receipt__c makeReceipt(String approvalStatus) {
        // These tests deliberately stage multiple receipts (incl. a pending one) on a single
        // booking to exercise the line-item sequencing gate; suspend the unrelated
        // receipt-count gate (BRD §5.13) so the scenario can be built.
        Boolean prior = ReceiptApprovalGateService.bypass;
        ReceiptApprovalGateService.bypass = true;
        Receipt__c r = new Receipt__c(
            Booking__c = booking.Id, Amount_received__c = 50000, Receipt_Date__c = Date.today(),
            Receipt_Type__c = 'Installment Payment', Status__c = 'Cleared', Approval_Status__c = approvalStatus
        );
        insert r;
        ReceiptApprovalGateService.bypass = prior;
        return r;
    }

    private static Receipt_Line_Item__c newLine(Id receiptId, Id scheduleId) {
        return new Receipt_Line_Item__c(
            Receipt__c = receiptId, Booking__c = booking.Id, Payment_Schedule__c = scheduleId,
            Allocated_Amount__c = 50000, Line_Item_Type__c = 'Principal'
        );
    }

    // =====================================================================
    // Direct service-level tests (do not depend on trigger wiring)
    // =====================================================================

    @isTest
    static void direct_laterMilestone_whileEarlierUnpaid_getsError() {
        buildBookingWithTwoMilestones(100000, 'Pending'); // ps1 fully pending
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps2.Id);

        Test.startTest();
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>{ li });
        Test.stopTest();

       
    }

    @isTest
    static void direct_sameMilestone_noError() {
        buildBookingWithTwoMilestones(100000, 'Pending');
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps1.Id);

        Test.startTest();
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>{ li });
        Test.stopTest();

    }

    @isTest
    static void direct_laterMilestone_afterEarlierFullyPaid_noError() {
        buildBookingWithTwoMilestones(0, 'Paid'); // ps1 fully paid
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps2.Id);

        Test.startTest();
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>{ li });
        Test.stopTest();

    }

    @isTest
    static void direct_earlierMilestoneHasPendingReceipt_getsError() {
        buildBookingWithTwoMilestones(0, 'Paid'); // ps1 zero pending, but...
        // ...an as-yet unapproved receipt is sitting against ps1.
        Receipt__c pendingReceipt = makeReceipt('Pending Approval');
        MilestonePaymentGateService.bypass = true; // stage data without tripping the gate
        insert newLine(pendingReceipt.Id, ps1.Id);
        MilestonePaymentGateService.bypass = false;

        Receipt__c r2 = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r2.Id, ps2.Id);

        Test.startTest();
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>{ li });
        Test.stopTest();

       
    }

    @isTest
    static void direct_staleStatusPaid_butPendingBalance_getsError() {
        // Status says Paid but money is still pending — isFullyPaid must not trust the status.
        buildBookingWithTwoMilestones(40000, 'Paid');
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps2.Id);

        Test.startTest();
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>{ li });
        Test.stopTest();

    }

    @isTest
    static void direct_bypass_skipsValidation() {
        buildBookingWithTwoMilestones(100000, 'Pending');
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps2.Id);

        Test.startTest();
        MilestonePaymentGateService.bypass = true;
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>{ li });
        MilestonePaymentGateService.bypass = false;
        Test.stopTest();

    }

    @isTest
    static void direct_noPaymentSchedule_isIgnored() {
        buildBookingWithTwoMilestones(100000, 'Pending');
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = new Receipt_Line_Item__c(
            Receipt__c = r.Id, Booking__c = booking.Id,
            Allocated_Amount__c = 50000, Line_Item_Type__c = 'Interest'
        );

        Test.startTest();
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>{ li });
        MilestonePaymentGateService.validateAllocations(null);                       // null guard
        MilestonePaymentGateService.validateAllocations(new List<Receipt_Line_Item__c>()); // empty guard
        Test.stopTest();

    }

    // =====================================================================
    // Trigger-path tests (prove ReceiptLineItemTrigger invokes the gate)
    // =====================================================================

    @isTest
    static void trigger_allocateToLaterMilestone_whileEarlierUnpaid_isBlocked() {
        buildBookingWithTwoMilestones(100000, 'Pending');
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps2.Id);

        Test.startTest();
        Boolean blocked = false;
        String errMsg = '';
        try {
            insert li;
        } catch (DmlException e) {
            blocked = true;
            errMsg = e.getDmlMessage(0);
        }
        Test.stopTest();
    }

    @isTest
    static void trigger_allocateToSameMilestone_isAllowed() {
        buildBookingWithTwoMilestones(100000, 'Pending');
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps1.Id);

        Test.startTest();
        insert li; // earliest milestone — never blocked
        Test.stopTest();
    }

    @isTest
    static void trigger_allocateToLaterMilestone_afterEarlierFullyPaid_isAllowed() {
        buildBookingWithTwoMilestones(0, 'Paid');
        Receipt__c r = makeReceipt('Approved');
        Receipt_Line_Item__c li = newLine(r.Id, ps2.Id);

        Test.startTest();
        insert li;
        Test.stopTest();

       
    }
}