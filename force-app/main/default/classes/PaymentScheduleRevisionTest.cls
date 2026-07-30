/**
 * @description Test class for PaymentScheduleRevisionCompareController.
 * @author System
 */
@isTest
private class PaymentScheduleRevisionTest{

    private static Payment_Schedule_Revision__c makeRevision(String jsonBody) {
        Booking__c booking = new Booking__c(
            
        );
        insert booking;

        Payment_Schedule_Revision__c rev = new Payment_Schedule_Revision__c(
            Booking__c = booking.Id,
            Approval_Status__c = 'Pending',
            Revision_Reason__c = 'Test Reason',
            Proposed_Changes_JSON__c = jsonBody
        );
        insert rev;
        return rev;
    }

    private static PaymentScheduleRevisionService.RevisionLine makeLine(Decimal seed) {
        PaymentScheduleRevisionService.RevisionLine line = new PaymentScheduleRevisionService.RevisionLine();
        line.percentage    = seed;
        line.baseAmount    = seed * 1000;
        line.gstAmount     = seed * 50;
        line.tdsAmount     = seed * 10;
        line.amount        = seed * 1060;
        line.bankFlat      = seed * 500;
        line.customerFlat  = seed * 560;
        line.bankGst       = seed * 25;
        line.customerGst   = seed * 25;
        return line;
    }

    @isTest
    static void testValidPayloadWithChanges() {
        PaymentScheduleRevisionService.RevisionPayload payload = new PaymentScheduleRevisionService.RevisionPayload();
        payload.totals = new PaymentScheduleRevisionService.RevisionTotals();
        payload.lines = new List<PaymentScheduleRevisionService.RevisionLineDiff>();

        // Line where values changed
        PaymentScheduleRevisionService.RevisionLineDiff diff1 = new PaymentScheduleRevisionService.RevisionLineDiff();
        diff1.milestoneName = 'Milestone 1';
        diff1.oldValues = makeLine(10);
        diff1.newValues = makeLine(20);
        payload.lines.add(diff1);

        // Line where values unchanged
        PaymentScheduleRevisionService.RevisionLineDiff diff2 = new PaymentScheduleRevisionService.RevisionLineDiff();
        diff2.milestoneName = 'Milestone 2';
        diff2.oldValues = makeLine(15);
        diff2.newValues = makeLine(15);
        payload.lines.add(diff2);

        Payment_Schedule_Revision__c rev = makeRevision(JSON.serialize(payload));

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(rev);
        PaymentScheduleRevisionCompareController ctrl = new PaymentScheduleRevisionCompareController(stdCtrl);
        List<PaymentScheduleRevisionCompareController.LineRow> rows = ctrl.lineRows;
        PaymentScheduleRevisionService.RevisionTotals tot = ctrl.totals;
        Test.stopTest();
    }

    @isTest
    static void testNullOldAndNewValues() {
        PaymentScheduleRevisionService.RevisionPayload payload = new PaymentScheduleRevisionService.RevisionPayload();
        payload.lines = new List<PaymentScheduleRevisionService.RevisionLineDiff>();

        // New milestone added (no old values)
        PaymentScheduleRevisionService.RevisionLineDiff added = new PaymentScheduleRevisionService.RevisionLineDiff();
        added.milestoneName = 'New Milestone';
        added.oldValues = null;
        added.newValues = makeLine(30);
        payload.lines.add(added);

        // Milestone removed (no new values)
        PaymentScheduleRevisionService.RevisionLineDiff removed = new PaymentScheduleRevisionService.RevisionLineDiff();
        removed.milestoneName = 'Removed Milestone';
        removed.oldValues = makeLine(40);
        removed.newValues = null;
        payload.lines.add(removed);

        Payment_Schedule_Revision__c rev = makeRevision(JSON.serialize(payload));

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(rev);
        PaymentScheduleRevisionCompareController ctrl = new PaymentScheduleRevisionCompareController(stdCtrl);
        Test.stopTest();
    }

    @isTest
    static void testBlankJson() {
        Payment_Schedule_Revision__c rev = makeRevision(null);

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(rev);
        PaymentScheduleRevisionCompareController ctrl = new PaymentScheduleRevisionCompareController(stdCtrl);
        Test.stopTest();
    }

    @isTest
    static void testInvalidJson() {
        Payment_Schedule_Revision__c rev = makeRevision('this is not valid json {{');

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(rev);
        PaymentScheduleRevisionCompareController ctrl = new PaymentScheduleRevisionCompareController(stdCtrl);
        Test.stopTest();
    }

    @isTest
    static void testPayloadWithNullLines() {
        PaymentScheduleRevisionService.RevisionPayload payload = new PaymentScheduleRevisionService.RevisionPayload();
        payload.totals = new PaymentScheduleRevisionService.RevisionTotals();
        payload.lines = null;

        Payment_Schedule_Revision__c rev = makeRevision(JSON.serialize(payload));

        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(rev);
        PaymentScheduleRevisionCompareController ctrl = new PaymentScheduleRevisionCompareController(stdCtrl);
        Test.stopTest();
    }
}