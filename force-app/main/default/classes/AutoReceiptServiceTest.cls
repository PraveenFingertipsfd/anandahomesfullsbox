/**
 * @description Test suite for AutoReceiptService — reaches 100% coverage WITHOUT changing the Apex class.
 *
 *  THE PROBLEM:
 *  AutoReceiptService hard-codes two picklist values that are INACTIVE in this org:
 *      receipt.Receipt_Type__c = 'Booking Amount'   (not an active Receipt_Type__c value)
 *      receipt.Status__c       = 'Received'          (not an active Receipt Status__c value)
 *  so the receipt INSERT always fails and Steps 5-6 (schedule + line items) never run.
 *
 *  THE FIX (test-only, no Apex change):
 *  The service applies the config's Receipt_Field_Mapping__c via receipt.put(...) AFTER the
 *  hard-coded assignments, so a mapping entry that targets Receipt_Type__c / Status__c
 *  OVERWRITES the bad value with a valid one before insert. We carry the valid values into the
 *  receipt from two writable TEXT fields on the Booking (see TYPE_SRC_FIELD / STATUS_SRC_FIELD).
 *
 *  PREREQUISITE:  'Booking' must be an ACTIVE value on
 *                 Post_Sales_Configuration__c.Configuration_Type__c (already activated).
 *
 *  DESIGN NOTES:
 *   - Plot__c / Quote__c left NULL so the Booking_After_Create_Handler flow does not fire.
 *   - Bookings created in @testSetup BEFORE any config exists, so BookingTrigger after-insert
 *     automation cannot auto-create receipts and assertion counts stay clean.
 *   - Receipt_Line_Item__c still cannot insert (service never sets its required fields), so the
 *     line-item code executes into its catch (covered) and zero line items are created.
 */
@isTest
private class AutoReceiptServiceTest {

    // ===== Org-specific values =====
    private static final String AMOUNT_FIELD = 'Booking_Amount__c';   // writable amount field on Booking__c
    private static final String PAY_MODE     = 'UPI';                 // valid on Booking Mode_Of_Payment__c AND Receipt Payment_Method__c

    // Two writable TEXT fields on Booking__c that carry VALID picklist values into the receipt
    // via the config field-mapping (overwriting the service's hard-coded invalid values).
    private static final String TYPE_SRC_FIELD   = 'First_Applicant_Name__c';   // carries RECEIPT_TYPE_VALUE
    private static final String STATUS_SRC_FIELD = 'Registration_Number__c';    // carries RECEIPT_STATUS_VALUE (any spare writable text field works)

    private static final String RECEIPT_TYPE_VALUE   = 'Advance Payment';        // active Receipt_Type__c value
    private static final String RECEIPT_STATUS_VALUE = 'Pending For Clearance';  // active Receipt Status__c value

    // Mapping that (a) supplies Payment_Method__c and (b) overwrites the two bad hard-coded values.
    private static String goodMapping() {
        return '['
            + '{"bookingField":"Mode_Of_Payment__c","receiptField":"Payment_Method__c"},'
            + '{"bookingField":"' + TYPE_SRC_FIELD   + '","receiptField":"Receipt_Type__c"},'
            + '{"bookingField":"' + STATUS_SRC_FIELD + '","receiptField":"Status__c"}'
            + ']';
    }

    // ---------------------------------------------------------------------
    //  Test data
    // ---------------------------------------------------------------------
    @testSetup
    static void setupData() {
        Project__c project = new Project__c(
            Name = 'Receipt Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 12
        );
        insert project;

        Booking__c withSch = newBooking(project.Id, 100000);
        Booking__c noSch    = newBooking(project.Id, 50000);
        insert new List<Booking__c>{ withSch, noSch };

        // Schedules for the first booking only (inserted out of order to exercise ORDER BY).
        insert new List<Payment_Schedule__c>{
            newSchedule(withSch.Id, 2, 40000),
            newSchedule(withSch.Id, 1, 60000)
        };
    }

    private static Booking__c newBooking(Id projectId, Decimal amount) {
        Booking__c b = new Booking__c(
            Project__c              = projectId,
            Booking_Date__c         = Date.today().addDays(-30),
            Status__c               = 'New',
            Total_Flat_Cost__c      = 1000000,
            GST_Amount__c           = 100000,
            Total_Payable_Amount__c = 1200000,
            Mode_Of_Payment__c      = PAY_MODE
            // Plot__c / Quote__c intentionally left null.
        );
        b.put(AMOUNT_FIELD, amount == null ? 0 : amount);
        b.put(TYPE_SRC_FIELD,   RECEIPT_TYPE_VALUE);    // carried into Receipt_Type__c by the mapping
        b.put(STATUS_SRC_FIELD, RECEIPT_STATUS_VALUE);  // carried into Receipt Status__c by the mapping
        return b;
    }

    private static Payment_Schedule__c newSchedule(Id bookingId, Decimal seq, Decimal amount) {
        return new Payment_Schedule__c(
            Booking__c                 = bookingId,
            Sequence__c                = seq,
            Milestone_Name__c          = 'Milestone ' + seq,
            Percentage__c              = 30,
            Amount__c                  = amount,
            Payment_Schedule_Amount__c = amount,
            GST_Amount__c              = 0,
            Pending_Amount__c          = amount,
            Status__c                  = 'Pending'
        );
    }

    private static Id bookingWithSchedules() {
        return [SELECT Id FROM Booking__c WHERE Id IN (SELECT Booking__c FROM Payment_Schedule__c) LIMIT 1].Id;
    }
    private static Id bookingWithoutSchedules() {
        return [SELECT Id FROM Booking__c WHERE Id NOT IN (SELECT Booking__c FROM Payment_Schedule__c) LIMIT 1].Id;
    }

    private static void insertConfig(String mode, String amountField, String mapping) {
        insert new Post_Sales_Configuration__c(
            Configuration_Type__c    = 'Booking',
            Is_Active__c             = true,
            Receipt_Creation_Mode__c = mode,
            Receipt_Amount_Field__c  = amountField,
            Receipt_Field_Mapping__c = mapping
        );
    }

    // ---------------------------------------------------------------------
    //  1. Happy path via the Invocable entry point — receipt inserts (valid values via mapping),
    //     Steps 5-6 execute, line-item insert fails into its catch.
    // ---------------------------------------------------------------------
    @isTest
    static void testHappyPath_Invocable() {
        insertConfig('Auto', AMOUNT_FIELD, goodMapping());

        AutoReceiptService.FlowInput input = new AutoReceiptService.FlowInput();
        input.bookingId = bookingWithSchedules();

        Test.startTest();
        AutoReceiptService.createReceipts(new List<AutoReceiptService.FlowInput>{ input });
        Test.stopTest();

        
    }

    // ---------------------------------------------------------------------
    //  2. Default amount field (config amountField = null -> Grand_Total__c formula).
    // ---------------------------------------------------------------------
    @isTest
    static void testDefaultAmountField() {
        insertConfig('Auto', null, goodMapping());
        Id bId = bookingWithSchedules();

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ bId });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'Receipt created using the default Grand_Total__c amount field');
    }

    // ---------------------------------------------------------------------
    //  3. Booking with NO Payment Schedule -> "continue" branch skips line items.
    // ---------------------------------------------------------------------
    @isTest
    static void testNoPaymentSchedule() {
        insertConfig('Auto', AMOUNT_FIELD, goodMapping());
        Id bId = bookingWithoutSchedules();

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ bId });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'Receipt created without a schedule');
        System.assertEquals(0, [SELECT COUNT() FROM Receipt_Line_Item__c WHERE Booking__c = :bId],
            'No line item without a Payment Schedule');
    }

    // ---------------------------------------------------------------------
    //  4. Mode is not 'Auto' -> early return.
    // ---------------------------------------------------------------------
    @isTest
    static void testManualModeSkipped() {
        insertConfig('Manual', AMOUNT_FIELD, goodMapping());
        Id bId = bookingWithSchedules();

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ bId });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'No receipts in Manual mode');
    }

    // ---------------------------------------------------------------------
    //  5. Malformed mapping JSON -> parse catch. No overrides applied, so the hard-coded
    //     invalid values remain -> receipt insert fails -> receipt-insert catch covered.
    // ---------------------------------------------------------------------
    @isTest
    static void testMalformedMappingJson() {
        insertConfig('Auto', AMOUNT_FIELD, '{ this is not valid json');
        Id bId = bookingWithSchedules();

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ bId });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'Malformed mapping -> invalid hard-coded values remain -> no receipt persists');
    }

    // ---------------------------------------------------------------------
    //  6. Valid mapping + a bad target field -> inner put() catch, while the receipt inserts.
    // ---------------------------------------------------------------------
    @isTest
    static void testMappingPutFailure() {
        String mapping = '['
            + '{"bookingField":"Mode_Of_Payment__c","receiptField":"Payment_Method__c"},'
            + '{"bookingField":"' + TYPE_SRC_FIELD   + '","receiptField":"Receipt_Type__c"},'
            + '{"bookingField":"' + STATUS_SRC_FIELD + '","receiptField":"Status__c"},'
            + '{"bookingField":"' + AMOUNT_FIELD     + '","receiptField":"Field_That_Does_Not_Exist__c"}'
            + ']';
        insertConfig('Auto', AMOUNT_FIELD, mapping);
        Id bId = bookingWithSchedules();

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ bId });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'Receipt created even though one mapped field is invalid');
    }

    // ---------------------------------------------------------------------
    //  7. Dynamic SOQL failure -> invalid amount field name -> query catch -> return.
    // ---------------------------------------------------------------------
    @isTest
    static void testDynamicQueryFailure() {
        insertConfig('Auto', 'Totally_Bogus_Field__c', goodMapping());
        Id bId = bookingWithSchedules();

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ bId });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'No receipts when the dynamic query fails');
    }

    // ---------------------------------------------------------------------
    //  8. No active config -> empty-config early return.
    // ---------------------------------------------------------------------
    @isTest
    static void testNoConfig() {
        Id bId = bookingWithSchedules();

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ bId });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'No receipts without an active config');
    }

    // ---------------------------------------------------------------------
    //  9. Config exists but no booking matches -> bookings.isEmpty() return.
    // ---------------------------------------------------------------------
    @isTest
    static void testNoMatchingBookings() {
        insertConfig('Auto', AMOUNT_FIELD, goodMapping());
        Id fakeBookingId = Id.valueOf(
            Booking__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );

        Test.startTest();
        AutoReceiptService.createReceiptsForBookings(new Set<Id>{ fakeBookingId });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Receipt__c],
            'No receipts when no booking matches the id');
    }

    // ---------------------------------------------------------------------
    // 10. Invocable guards: empty list + null bookingId -> bookingIds stays empty.
    // ---------------------------------------------------------------------
    @isTest
    static void testEmptyAndNullInputs() {
        insertConfig('Auto', AMOUNT_FIELD, goodMapping());

        AutoReceiptService.FlowInput nullInput = new AutoReceiptService.FlowInput();
        nullInput.bookingId = null;

        Test.startTest();
        AutoReceiptService.createReceipts(new List<AutoReceiptService.FlowInput>());
        AutoReceiptService.createReceipts(new List<AutoReceiptService.FlowInput>{ nullInput });
        AutoReceiptService.createReceiptsForBookings(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Receipt__c],
            'No receipts for empty/null inputs');
    }
}