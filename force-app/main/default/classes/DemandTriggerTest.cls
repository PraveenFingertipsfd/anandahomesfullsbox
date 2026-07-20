/**
 * @description Tests that DemandTrigger populates the reminder cadence by Demand Type on insert
 *              (BRD pointer 5): Agreement Amount uses Welcome Mail + 30/40/45; other demands use
 *              the project reminder configuration.
 */
@isTest
private class DemandTriggerTest {

    private static Booking__c setup(DateTime welcomeDateTime) {
        Project__c project = new Project__c(
            Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18,
            Enable_Reminder_1__c = true, Reminder_1_Days__c = 15
        );
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Welcome_Mail_Sent_DateTime__c = welcomeDateTime
        );
        insert b;
        return b;
    }

    @isTest
    static void agreementDemand_usesWelcomePlus30_40_45() {
        DateTime welcome = DateTime.now().addDays(-5);
        Booking__c b = setup(welcome);

        Test.startTest();
        Demands__c d = new Demands__c(
            Booking__c = b.Id, Demand_Amount__c = 100000, Demand_Type__c = 'Agreement Amount',
            Demand_Date__c = Date.today(), Status__c = 'Raised'
        );
        insert d;
        Test.stopTest();

        Demands__c saved = [
            SELECT Reminder_1_Date__c, Reminder_2_Date__c, Termination_Mail_Date__c, Reminder_3_Date__c
            FROM Demands__c WHERE Id = :d.Id
        ];
        Date anchor = welcome.date();
        System.assertEquals(anchor.addDays(30), saved.Reminder_1_Date__c, '1st = Welcome + 30');
        System.assertEquals(anchor.addDays(40), saved.Reminder_2_Date__c, '2nd = Welcome + 40');
        System.assertEquals(anchor.addDays(45), saved.Termination_Mail_Date__c, 'Termination = Welcome + 45');
        System.assertEquals(null, saved.Reminder_3_Date__c, 'No 3rd reminder for agreement demand');
    }

    @isTest
    static void demandOnAgreementSchedule_usesWelcomeCadence() {
        DateTime welcome = DateTime.now().addDays(-2);
        Booking__c b = setup(welcome);

        // A payment-schedule line flagged as the Agreement milestone.
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = b.Id, Sequence__c = 1, Milestone_Name__c = 'Agreement',
            Amount__c = 100000, Status__c = 'Pending', Is_Agreement__c = true
        );
        insert ps;

        Test.startTest();
        // Demand Type is NOT 'Agreement Amount' — the Is_Agreement schedule flag drives it.
        Demands__c d = new Demands__c(
            Booking__c = b.Id, Payment_Schedule__c = ps.Id, Demand_Amount__c = 100000,
            Demand_Type__c = 'Individual Demand', Demand_Date__c = Date.today(), Status__c = 'Raised'
        );
        insert d;
        Test.stopTest();

        Demands__c saved = [
            SELECT Reminder_1_Date__c, Reminder_2_Date__c, Termination_Mail_Date__c
            FROM Demands__c WHERE Id = :d.Id
        ];
        Date anchor = welcome.date();
        System.assertEquals(anchor.addDays(30), saved.Reminder_1_Date__c, 'Is_Agreement schedule → Welcome + 30');
        System.assertEquals(anchor.addDays(40), saved.Reminder_2_Date__c, 'Welcome + 40');
        System.assertEquals(anchor.addDays(45), saved.Termination_Mail_Date__c, 'Welcome + 45');
    }

    @isTest
    static void demandReminders_useConfiguredDaysAfterDue() {
        Booking__c b = setup(DateTime.now());
        // Admin "Demand Reminders" config: Due + 7, (N/A), Due + 21, Due + 30.
        insert new Post_Sales_Configuration__c(
            Configuration_Type__c = 'Demand', Is_Active__c = true, Enable_Reminders__c = true,
            Reminder_Config__c =
                '[{"isNA":false,"daysAfterDue":7},{"isNA":true,"daysAfterDue":14},'
                + '{"isNA":false,"daysAfterDue":21},{"isNA":false,"daysAfterDue":30}]'
        );

        Date due = Date.today().addDays(5);
        Test.startTest();
        Demands__c d = new Demands__c(
            Booking__c = b.Id, Demand_Amount__c = 100000, Demand_Type__c = 'Individual Demand',
            Demand_Date__c = Date.today(), Due_Date__c = due, Status__c = 'Raised'
        );
        insert d;
        Test.stopTest();

        Demands__c s = [
            SELECT Reminder_1_Date__c, Reminder_2_Date__c, Reminder_3_Date__c, Reminder_4_Date__c
            FROM Demands__c WHERE Id = :d.Id
        ];
        System.assertEquals(due.addDays(7), s.Reminder_1_Date__c, 'Due + 7 from config');
        System.assertEquals(null, s.Reminder_2_Date__c, 'N/A reminder is skipped');
        System.assertEquals(due.addDays(21), s.Reminder_3_Date__c, 'Due + 21 from config');
        System.assertEquals(due.addDays(30), s.Reminder_4_Date__c, 'Due + 30 from config');
    }

    @isTest
    static void milestoneDemand_usesProjectConfig() {
        Booking__c b = setup(DateTime.now());

        Test.startTest();
        Demands__c d = new Demands__c(
            Booking__c = b.Id, Demand_Amount__c = 200000, Demand_Type__c = 'Individual Demand',
            Demand_Date__c = Date.today(), Status__c = 'Raised'
        );
        insert d;
        Test.stopTest();

        Demands__c saved = [SELECT Reminder_1_Date__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals(Date.today().addDays(15), saved.Reminder_1_Date__c,
            'Milestone demand uses project Reminder_1_Days (Demand Date + 15)');
    }
}