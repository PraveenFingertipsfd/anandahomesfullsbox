/**
 * @description Tests for AdditionalChargeReminderService + AdditionalChargeTrigger (BRD §13.1).
 *              Covers reminder-date seeding (default + project-configured gaps) and the daily
 *              due-reminder processing (1st, 2nd, disabled, paid, blank-email, fully-paid).
 */
@isTest
private class AdditionalChargeReminderServiceTest {

    // ==================== TEST DATA HELPERS ====================

    private static Booking__c makeBooking() {
        return makeBooking('cust@example.com', null, null);
    }

    /**
     * @description Creates a Project/Unit/Booking. Optional reminder-day gaps let a test
     *              exercise the project-configured override branch; a blank email lets a
     *              test exercise the "no recipient" skip branch.
     */
    private static Booking__c makeBooking(String email, Integer reminder1Days, Integer reminder2Days) {
        Project__c project = new Project__c(
            Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18,
            Reminder_1_Days__c = reminder1Days, Reminder_2_Days__c = reminder2Days
        );
        insert project;
        // Deliberately NO Plot__c: the after-create flow "Booking After Create Handler" fires
        // only when Plot__c is populated and then requires a Quote (sourceRecordId) we don't
        // have. The reminder logic never reads the unit, so omitting it keeps the insert clean.
        Booking__c b = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'New',
            Email__c = email, First_Applicant_Name__c = 'Jane'
        );
        insert b;
        return b;
    }

    private static Additional_Charge__c makeCharge(Id bookingId) {
        Additional_Charge__c c = new Additional_Charge__c(
            Booking__c = bookingId, Charge_Name__c = 'Extra Parking', Charge_Type__c = 'Additional Car Parking',
            Amount__c = 10000, GST_Amount__c = 1000, Amount_Paid__c = 0, Status__c = 'Draft', Is_Demanded__c = false
        );
        insert c;
        return c;
    }

    /** @description Demands a charge (fires the trigger so reminder dates are seeded). */
    private static Additional_Charge__c demand(Additional_Charge__c c, Date demandDate) {
        c.Is_Demanded__c = true;
        c.Status__c = 'Demanded';
        c.Demand_Date__c = demandDate;
        update c;
        return c;
    }

    // ==================== DATE SEEDING ====================

    @isTest
    static void demanding_seedsDefaultReminderDates() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);

        Test.startTest();
        demand(c, Date.today());
        Test.stopTest();

        Additional_Charge__c after = [
            SELECT Reminder_1_Date__c, Reminder_2_Date__c, Due_Date__c FROM Additional_Charge__c WHERE Id = :c.Id
        ];
        System.assertEquals(Date.today().addDays(15), after.Reminder_1_Date__c, '1st reminder = demand + default 15');
        System.assertEquals(Date.today().addDays(30), after.Reminder_2_Date__c, '2nd reminder = demand + default 30');
        System.assertEquals(Date.today().addDays(30), after.Due_Date__c, 'Due date defaults to 2nd reminder date');
    }

    @isTest
    static void demanding_usesProjectConfiguredGaps() {
        Booking__c b = makeBooking('cust@example.com', 5, 10);
        Additional_Charge__c c = makeCharge(b.Id);

        Test.startTest();
        demand(c, Date.today());
        Test.stopTest();

        Additional_Charge__c after = [
            SELECT Reminder_1_Date__c, Reminder_2_Date__c FROM Additional_Charge__c WHERE Id = :c.Id
        ];
        System.assertEquals(Date.today().addDays(5), after.Reminder_1_Date__c, '1st reminder uses project gap of 5');
        System.assertEquals(Date.today().addDays(10), after.Reminder_2_Date__c, '2nd reminder uses project gap of 10');
    }

    // ==================== REMINDER PROCESSING ====================

    @isTest
    static void processDueReminders_sendsFirstReminder() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        demand(c, Date.today().addDays(-20)); // R1 due (today-5), R2 future (today+10)

        Test.startTest();
        Integer sent = AdditionalChargeReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, sent, 'One (1st) reminder should be sent');
        Additional_Charge__c after = [
            SELECT Reminder_1_Sent__c, Reminder_1_Sent_Date__c, Reminder_2_Sent__c
            FROM Additional_Charge__c WHERE Id = :c.Id
        ];
        System.assertEquals(true, after.Reminder_1_Sent__c, '1st reminder marked sent');
        System.assertNotEquals(null, after.Reminder_1_Sent_Date__c, '1st reminder sent date stamped');
        System.assertEquals(false, after.Reminder_2_Sent__c, 'Only 1st should be sent when 2nd not yet due');
    }

    @isTest
    static void processDueReminders_sendsSecondReminderWhenFirstAlreadySent() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        demand(c, Date.today().addDays(-40)); // R1 (today-25) and R2 (today-10) both due
        // Simulate the 1st reminder having already gone out so only the 2nd should fire now.
        c.Reminder_1_Sent__c = true;
        c.Reminder_1_Sent_Date__c = System.now();
        update c;

        Test.startTest();
        Integer sent = AdditionalChargeReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, sent, 'The 2nd (final) reminder should be sent');
        Additional_Charge__c after = [
            SELECT Reminder_2_Sent__c, Reminder_2_Sent_Date__c FROM Additional_Charge__c WHERE Id = :c.Id
        ];
        System.assertEquals(true, after.Reminder_2_Sent__c, '2nd reminder marked sent');
        System.assertNotEquals(null, after.Reminder_2_Sent_Date__c, '2nd reminder sent date stamped');
    }

    @isTest
    static void remindersDisabled_suppresses() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        demand(c, Date.today().addDays(-20));
        c.Reminders_Disabled__c = true;
        update c;

        Test.startTest();
        Integer sent = AdditionalChargeReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Disabled charge should not send reminders');
    }

    @isTest
    static void paidCharge_noReminder() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        c.Is_Demanded__c = true;
        c.Status__c = 'Paid';
        c.Amount_Paid__c = 11000;
        c.Demand_Date__c = Date.today().addDays(-20);
        update c;

        Test.startTest();
        Integer sent = AdditionalChargeReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Closed/Paid charge is filtered out by the query');
    }

    @isTest
    static void fullyPaidButOpenCharge_skips() {
        // Not in a closed status, but nothing pending -> hits the "pending <= 0" continue branch.
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        c.Amount_Paid__c = 11000; // Amount 10000 + GST 1000
        update c;
        demand(c, Date.today().addDays(-20));

        Test.startTest();
        Integer sent = AdditionalChargeReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Charge with nothing pending should not send a reminder');
    }

    @isTest
    static void blankEmail_skips() {
        Booking__c b = makeBooking(null, null, null); // no customer email
        Additional_Charge__c c = makeCharge(b.Id);
        demand(c, Date.today().addDays(-20));

        Test.startTest();
        Integer sent = AdditionalChargeReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Charge whose booking has no email should be skipped');
    }

    @isTest
    static void processDueReminders_noDueCharges_returnsZero() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        // Demand far in the future so neither reminder is due yet.
        demand(c, Date.today().addDays(60));

        Test.startTest();
        Integer sent = AdditionalChargeReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Nothing due yet -> zero reminders sent');
    }
}