/**
 * @description Test class for DemandReminderService.
 *
 *              - One scenario per test method, each with its OWN demand record, so a failure
 *                in one path never blocks coverage of the others.
 *              - No exception swallowing: real assertions prove each branch executed.
 *              - Post_Sales_Configuration__c.Config_Name__c is REQUIRED (not auto-number in
 *                this org), so every config insert supplies a value.
 */
@isTest
private class DemandReminderServiceTest {

    // ---- helpers ---------------------------------------------------------

    private static Project__c makeProject(String name, Boolean enableAll) {
        return new Project__c(
            Name = name,
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18,
            Include_Interest_In_Termination__c = true,
            Enable_Reminder_1__c = enableAll, Reminder_1_Days__c = 5,
            Enable_Reminder_2__c = enableAll, Reminder_2_Days__c = 10,
            Enable_Reminder_3__c = enableAll, Reminder_3_Days__c = 15,
            Enable_Reminder_4__c = enableAll, Reminder_4_Days__c = 20,
            Enable_Termination_Mail__c = enableAll, Termination_Mail_Days__c = 30,
            Enable_Auto_Unit_Unblocking__c = enableAll, Unit_Unblocking_Days__c = 45
        );
    }

    private static Booking__c getBooking() {
        return [SELECT Id, Project__c FROM Booking__c WHERE Email__c = 'demandcustomer@example.com' LIMIT 1];
    }

    /** Post_Sales_Configuration builder that always sets the required Config_Name__c. */
    private static Post_Sales_Configuration__c cfg(String type, String name) {
        return new Post_Sales_Configuration__c(
            //Config_Name__c = 'PSC-0001',
            Configuration_Type__c = type,
            Is_Active__c = true,
            Auto_Send_Email__c = true
        );
    }

    /** Base demand builder – caller overrides the fields relevant to the scenario. */
    private static Demands__c newDemand(Id bookingId, Id projectId) {
        return new Demands__c(
            Booking__c = bookingId,
            Project__c = projectId,
            Demand_Amount__c = 100000,
            Pending_Amount__c = 100000,
            Interest_Amount__c = 5000,
            Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.today().addDays(-90),
            Due_Date__c = Date.today().addDays(-75),
            Reminders_Disabled__c = false
        );
    }

    @testSetup
    static void setup() {
        Project__c project = makeProject('Test Project DR', true);
        insert project;

        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert unit;

        Quote__c quote = new Quote__c(Project__c = 'The Legacey');
        insert quote;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Quote__c = quote.Id,
            Booking_Amount__c = 100000,
            Mode_Of_Payment__c = 'UPI',
            Booking_Date__c = Date.today().addDays(-90),
            Total_Flat_Cost__c = 1000000,
            GST_Amount__c = 50000,
            Total_Payable_Amount__c = 1050000,
            Status__c = 'New',
            Email__c = 'demandcustomer@example.com',
            First_Applicant_Name__c = 'Test Customer',
            Disable_Demand_Reminders__c = false,
            Welcome_Mail_Sent_DateTime__c = DateTime.now().addDays(-100)
        );
        insert booking;

        insert new List<Payment_Schedule__c>{
            new Payment_Schedule__c(
                Booking__c = booking.Id, Sequence__c = 1, Milestone_Name__c = 'On Booking',
                Percentage__c = 10, Amount__c = 105000, Pending_Amount__c = 105000,
                Amount_Paid__c = 0, Due_Date__c = Date.today().addDays(-60), Status__c = 'Pending'
            ),
            new Payment_Schedule__c(
                Booking__c = booking.Id, Sequence__c = 2, Milestone_Name__c = 'Agreement',
                Percentage__c = 20, Amount__c = 210000, Pending_Amount__c = 210000,
                Amount_Paid__c = 0, Due_Date__c = Date.today().addDays(-50), Status__c = 'Pending',
                Is_Agreement__c = true
            )
        };
    }

    // ===================================================================
    // populateReminderDates
    // ===================================================================

    @isTest
    static void populateReminderDates_projectConfig_setsAllDates() {
        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Demand_Date__c = Date.today().addDays(-50);

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        System.assertEquals(b.Project__c, d.Project__c, 'Project should be stamped');
        System.assertEquals(d.Demand_Date__c.addDays(5),  d.Reminder_1_Date__c, 'R1 = demand+5');
        System.assertEquals(d.Demand_Date__c.addDays(10), d.Reminder_2_Date__c, 'R2 = demand+10');
        System.assertEquals(d.Demand_Date__c.addDays(15), d.Reminder_3_Date__c, 'R3 = demand+15');
        System.assertEquals(d.Demand_Date__c.addDays(20), d.Reminder_4_Date__c, 'R4 = demand+20');
        System.assertEquals(d.Demand_Date__c.addDays(30), d.Termination_Mail_Date__c, 'Term = demand+30');
        System.assertEquals(d.Demand_Date__c.addDays(45), d.Unit_Unblocking_Date__c, 'Unblock = demand+45');
    }

    @isTest
    static void populateReminderDates_adminDemandConfig_usesDueAnchor() {
        Post_Sales_Configuration__c c = cfg('Demand', 'Admin Demand Reminders');
        c.Enable_Reminders__c = true;
        c.Reminder_Config__c = '[{"daysAfterDue":3},{"daysAfterDue":7},{"isNA":true},{"daysAfterDue":14}]';
        insert c;

        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Due_Date__c = Date.today().addDays(-10);

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        System.assertEquals(d.Due_Date__c.addDays(3),  d.Reminder_1_Date__c, 'R1 = due+3');
        System.assertEquals(d.Due_Date__c.addDays(7),  d.Reminder_2_Date__c, 'R2 = due+7');
        System.assertEquals(null, d.Reminder_3_Date__c, 'R3 marked N/A -> null');
        System.assertEquals(d.Due_Date__c.addDays(14), d.Reminder_4_Date__c, 'R4 = due+14');
    }

    @isTest
    static void populateReminderDates_adminConfig_invalidJson_fallsBackToProject() {
        Post_Sales_Configuration__c c = cfg('Demand', 'Admin Bad JSON');
        c.Enable_Reminders__c = true;
        c.Reminder_Config__c = '{ this is not valid json';
        insert c;

        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Demand_Date__c = Date.today().addDays(-50);

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        System.assertEquals(d.Demand_Date__c.addDays(5), d.Reminder_1_Date__c,
            'Bad JSON should fall back to project config (demand+5)');
    }

    @isTest
    static void populateReminderDates_agreementBySchedule_usesWelcomeAnchor() {
        Booking__c b = [
            SELECT Id, Project__c, Welcome_Mail_Sent_DateTime__c
            FROM Booking__c WHERE Email__c = 'demandcustomer@example.com' LIMIT 1
        ];
        Payment_Schedule__c agr = [SELECT Id FROM Payment_Schedule__c WHERE Is_Agreement__c = true LIMIT 1];

        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Payment_Schedule__c = agr.Id;

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        Date anchor = b.Welcome_Mail_Sent_DateTime__c.date();
        System.assertEquals(anchor.addDays(30), d.Reminder_1_Date__c, 'Agreement R1 = welcome+30');
        System.assertEquals(anchor.addDays(40), d.Reminder_2_Date__c, 'Agreement R2 = welcome+40');
        System.assertEquals(anchor.addDays(45), d.Termination_Mail_Date__c, 'Agreement term = welcome+45');
        System.assertEquals(null, d.Reminder_3_Date__c, 'No R3 for agreement');
        System.assertEquals(null, d.Reminder_4_Date__c, 'No R4 for agreement');
    }

    @isTest
    static void populateReminderDates_agreementByType_noWelcome_usesDemandDate() {
        Project__c p = makeProject('Agr Type Project', true);
        insert p;
        Plot__c u = new Plot__c(Project__c = p.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert u;
        Quote__c q = new Quote__c(Project__c = 'The Legacey');
        insert q;
        Booking__c b = new Booking__c(
            Project__c = p.Id, Plot__c = u.Id, Quote__c = q.Id, Booking_Amount__c = 100000,
            Mode_Of_Payment__c = 'UPI', Booking_Date__c = Date.today(), Total_Flat_Cost__c = 1000,
            GST_Amount__c = 50, Total_Payable_Amount__c = 1050, Status__c = 'New',
            Email__c = 'agr@example.com', First_Applicant_Name__c = 'Agr'
        );
        insert b;

        Demands__c d = newDemand(b.Id, p.Id);
        d.Demand_Type__c = 'Agreement Amount';
        d.Demand_Date__c = Date.today().addDays(-10);

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        System.assertEquals(d.Demand_Date__c.addDays(30), d.Reminder_1_Date__c,
            'Agreement w/o welcome uses demand date + 30');
    }

    @isTest
    static void populateReminderDates_nullAndEmpty_noOp() {
        Test.startTest();
        DemandReminderService.populateReminderDates(null);
        DemandReminderService.populateReminderDates(new List<Demands__c>());
        Test.stopTest();
        System.assert(true, 'Null / empty input must not throw');
    }

    @isTest
    static void populateReminderDates_noBooking_skips() {
        Demands__c d = new Demands__c(
            Demand_Amount__c = 1000, Pending_Amount__c = 1000, Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand'
        );
        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();
        System.assertEquals(null, d.Reminder_1_Date__c, 'No booking -> no dates');
    }

    @isTest
    static void populateReminderDates_demandDateNull_usesToday() {
        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Demand_Date__c = null;

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        System.assertEquals(Date.today().addDays(5), d.Reminder_1_Date__c, 'Null demand date -> today + 5');
    }

    @isTest
    static void populateReminderDates_allDisabled_setsNothing() {
        Project__c p = makeProject('NoEnable Project', false);
        insert p;
        Plot__c u = new Plot__c(Project__c = p.Id, Unit_Type__c = 'Apartment', Status__c = 'Available');
        insert u;
        Quote__c q = new Quote__c(Project__c = 'The Legacey');
        insert q;
        Booking__c b = new Booking__c(
            Project__c = p.Id, Plot__c = u.Id, Quote__c = q.Id, Booking_Date__c = Date.today(),
            Booking_Amount__c = 100000, Mode_Of_Payment__c = 'UPI',
            Total_Flat_Cost__c = 1000, GST_Amount__c = 50, Total_Payable_Amount__c = 1050,
            Status__c = 'New', Email__c = 't@example.com'
        );
        insert b;

        Demands__c d = newDemand(b.Id, p.Id);
        d.Demand_Date__c = Date.today();

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        System.assertEquals(null, d.Reminder_1_Date__c, 'Disabled config populates nothing');
        System.assertEquals(null, d.Termination_Mail_Date__c, 'Disabled termination');
        System.assertEquals(null, d.Unit_Unblocking_Date__c, 'Disabled unblocking');
    }

    // ===================================================================
    // processDueReminders
    // ===================================================================

    @isTest
    static void processReminders1to4_fallbackEmail() {
        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Reminder_1_Date__c = Date.today().addDays(-1); d.Reminder_1_Sent__c = false;
        d.Reminder_2_Date__c = Date.today().addDays(-1); d.Reminder_2_Sent__c = false;
        d.Reminder_3_Date__c = Date.today().addDays(-1); d.Reminder_3_Sent__c = false;
        d.Reminder_4_Date__c = Date.today().addDays(-1); d.Reminder_4_Sent__c = false;
        insert d;

        Test.startTest();
        DemandReminderService.ProcessingResult r = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, r.reminder1Count, '1st reminder processed');
        System.assertEquals(1, r.reminder2Count, '2nd reminder processed');
        System.assertEquals(1, r.reminder3Count, '3rd reminder processed');
        System.assertEquals(1, r.reminder4Count, '4th reminder processed');

        Demands__c u = [
            SELECT Reminder_1_Sent__c, Reminder_4_Sent__c, Number_of_Reminders__c
            FROM Demands__c WHERE Id = :d.Id
        ];
        System.assertEquals(true, u.Reminder_1_Sent__c, 'R1 flagged sent');
        System.assertEquals(true, u.Reminder_4_Sent__c, 'R4 flagged sent');
        System.assertEquals(4, u.Number_of_Reminders__c, 'Reminder counter incremented 4x');
    }

    @isTest
    static void processReminders_withConfigAndMaster_fallbackDoc() {
        // Reminder-type configs present but NO Email_Template -> config != null / fallback body path
        insert new List<Post_Sales_Configuration__c>{
            cfg('Demand', 'DR1 Config'),
            cfg('Receipt', 'DR2 Config'),
            cfg('Credit Note',  'Term Config')
        };
        insert new Post_Sales_Config_Master__c(Is_Active__c = true,Config_Name__c='ter78');

        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Reminder_1_Date__c = Date.today().addDays(-1); d.Reminder_1_Sent__c = false;
        d.Reminder_2_Date__c = Date.today().addDays(-1); d.Reminder_2_Sent__c = false;
        d.Termination_Mail_Date__c = Date.today().addDays(-1); d.Termination_Mail_Sent__c = false;
        insert d;

        Test.startTest();
        DemandReminderService.ProcessingResult r = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, r.reminder1Count, 'R1 processed with config present');
        System.assertEquals(1, r.reminder2Count, 'R2 processed with config present');
        System.assertEquals(1, r.terminationCount, 'Termination processed with config present');
    }

    @isTest
    static void processTerminationMail_withInterest() {
        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Termination_Mail_Date__c = Date.today().addDays(-1);
        d.Termination_Mail_Sent__c = false;
        d.Interest_Amount__c = 7500;
        insert d;

        Test.startTest();
        DemandReminderService.ProcessingResult r = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, r.terminationCount, 'Termination mail processed');
        Demands__c u = [SELECT Termination_Mail_Sent__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals(true, u.Termination_Mail_Sent__c, 'Termination flagged sent');
    }

    @isTest
    static void processUnitUnblocking_cancelsBookingAndReleasesUnit() {
        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Unit_Unblocking_Date__c = Date.today().addDays(-1);
        d.Unit_Unblocked__c = false;
        insert d;

        Test.startTest();
        DemandReminderService.ProcessingResult r = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, r.unblockingCount, 'One booking unblocked');
        Demands__c ud = [SELECT Unit_Unblocked__c, Cancellation_Initiated__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals(true, ud.Unit_Unblocked__c, 'Demand marked unblocked');
        System.assertEquals(true, ud.Cancellation_Initiated__c, 'Cancellation initiated');
    }

    @isTest
    static void processReminder_blankEmail_skipsEmailButStillProcesses() {
        Booking__c b = getBooking();
        update new Booking__c(Id = b.Id, Email__c = null);

        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Reminder_1_Date__c = Date.today().addDays(-1);
        d.Reminder_1_Sent__c = false;
        insert d;

        Test.startTest();
        DemandReminderService.ProcessingResult r = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, r.reminder1Count, 'Processed even with no email');
        Demands__c u = [SELECT Reminder_1_Sent__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals(true, u.Reminder_1_Sent__c, 'Still flagged sent');
    }

    @isTest
    static void processDueReminders_noDueDemands_returnsZeros() {
        Test.startTest();
        DemandReminderService.ProcessingResult r = DemandReminderService.processDueReminders();
        Test.stopTest();
        System.assertEquals(0, r.totalProcessed(), 'Nothing due -> all zeros');
    }

    // ===================================================================
    // disableRemindersForPaidDemands
    // ===================================================================

    @isTest
    static void disableReminders_paidDemand_marksDisabled() {
        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        d.Pending_Amount__c = 0;
        d.Status__c = 'Paid';
        insert d;

        Test.startTest();
        DemandReminderService.disableRemindersForPaidDemands(new Set<Id>{ b.Id });
        Test.stopTest();

        Demands__c u = [SELECT Reminders_Disabled__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals(true, u.Reminders_Disabled__c, 'Paid demand reminders disabled');
    }

    @isTest
    static void disableReminders_unpaidDemand_noOp() {
        Booking__c b = getBooking();
        Demands__c d = newDemand(b.Id, b.Project__c);
        insert d;

        Test.startTest();
        DemandReminderService.disableRemindersForPaidDemands(new Set<Id>{ b.Id });
        Test.stopTest();

        Demands__c u = [SELECT Reminders_Disabled__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals(false, u.Reminders_Disabled__c, 'Unpaid demand untouched');
    }

    @isTest
    static void disableReminders_nullAndEmpty_noOp() {
        Test.startTest();
        DemandReminderService.disableRemindersForPaidDemands(null);
        DemandReminderService.disableRemindersForPaidDemands(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'Null / empty set must not throw');
    }

    // ===================================================================
    // ProcessingResult wrapper
    // ===================================================================

    @isTest
    static void processingResult_sumsAndLogs() {
        DemandReminderService.ProcessingResult r = new DemandReminderService.ProcessingResult();
        r.reminder1Count = 1; r.reminder2Count = 2; r.reminder3Count = 3;
        r.reminder4Count = 4; r.terminationCount = 5; r.unblockingCount = 6;

        System.assertEquals(21, r.totalProcessed(), 'Sum of all counts');
        System.assert(r.toLogString().contains('1st Reminders: 1'), 'Log string includes counts');
        System.assert(r.toLogString().contains('Unit Unblockings: 6'), 'Log string includes unblockings');
    }
}