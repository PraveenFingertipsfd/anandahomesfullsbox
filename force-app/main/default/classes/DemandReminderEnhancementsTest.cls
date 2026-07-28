/**
 * @description Tests for the DemandReminderService enhancements:
 *                - pointer 5: Agreement Amount demand reminders anchored to Welcome Mail
 *                  date (+30 / +40 / +45 days), and
 *                - pointer 6: booking-level Disable Demand Reminders suppresses all reminders.
 */
@isTest
private class DemandReminderEnhancementsTest {

    private static Booking__c makeBooking(DateTime welcomeDate, Boolean disableReminders) {
        Project__c project = new Project__c(
            Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18,
            Enable_Reminder_1__c = true, Reminder_1_Days__c = 15,
            Enable_Reminder_2__c = true, Reminder_2_Days__c = 30,
            Enable_Termination_Mail__c = true, Termination_Mail_Days__c = 45
        );
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Email__c = 'applicant@example.com',
            Welcome_Mail_Sent_DateTime__c = welcomeDate,
            Disable_Demand_Reminders__c = disableReminders
        );
        insert booking;
        return booking;
    }

    @isTest
    static void agreementAmountDemand_anchorsRemindersToWelcomeMail() {
        DateTime welcome = DateTime.newInstance(2026, 1, 1, 9, 0, 0);
        Booking__c b = makeBooking(welcome, false);

        Demands__c d = new Demands__c(
            Booking__c = b.Id,
            Demand_Type__c = 'Agreement Amount',
            Demand_Amount__c = 500000,
            Pending_Amount__c = 500000,
            Demand_Date__c = Date.today(),
            Status__c = 'Raised'
        );

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        Date anchor = welcome.date();
        System.assertEquals(anchor.addDays(30), d.Reminder_1_Date__c, '1st reminder = Welcome + 30');
        System.assertEquals(anchor.addDays(40), d.Reminder_2_Date__c, '2nd reminder = Welcome + 40');
        System.assertEquals(anchor.addDays(45), d.Termination_Mail_Date__c, 'Termination = Welcome + 45');
        System.assertEquals(null, d.Reminder_3_Date__c, 'No 3rd reminder for agreement amount');
        System.assertEquals(null, d.Reminder_4_Date__c, 'No 4th reminder for agreement amount');
    }

    @isTest
    static void standardDemand_usesProjectConfig() {
        Booking__c b = makeBooking(null, false);
        Demands__c d = new Demands__c(
            Booking__c = b.Id, Demand_Type__c = 'Individual Demand',
            Demand_Amount__c = 100000, Pending_Amount__c = 100000,
            Demand_Date__c = Date.today(), Status__c = 'Raised'
        );

        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>{ d });
        Test.stopTest();

        System.assertEquals(Date.today().addDays(15), d.Reminder_1_Date__c, 'Standard demand uses project days');
        System.assertEquals(Date.today().addDays(30), d.Reminder_2_Date__c);
    }

    @isTest
    static void disableDemandReminders_suppressesProcessing() {
        Booking__c b = makeBooking(null, true); // reminders disabled at booking level

        Demands__c d = new Demands__c(
            Booking__c = b.Id, Demand_Type__c = 'Individual Demand',
            Demand_Amount__c = 100000, Pending_Amount__c = 100000,
            Demand_Date__c = Date.today(), Status__c = 'Raised',
            Reminder_1_Date__c = Date.today().addDays(-1),
            Reminder_1_Sent__c = false, Reminders_Disabled__c = false
        );
        insert d;

        Test.startTest();
        DemandReminderService.ProcessingResult result = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(0, result.reminder1Count, 'Booking-level disable should suppress the reminder');
        Demands__c after = [SELECT Reminder_1_Sent__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals(false, after.Reminder_1_Sent__c, 'Reminder must not be marked sent');
    }

    @isTest
    static void remindersEnabled_processesDueReminder() {
        Booking__c b = makeBooking(null, false);
        Demands__c d = new Demands__c(
            Booking__c = b.Id, Demand_Type__c = 'Individual Demand',
            Demand_Amount__c = 100000, Pending_Amount__c = 100000,
            Demand_Date__c = Date.today(), Status__c = 'Raised',
            Reminder_1_Date__c = Date.today().addDays(-1),
            Reminder_1_Sent__c = false, Reminders_Disabled__c = false
        );
        insert d;

        Test.startTest();
        DemandReminderService.ProcessingResult result = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertEquals(1, result.reminder1Count, 'Enabled booking should process the due reminder');
    }
}