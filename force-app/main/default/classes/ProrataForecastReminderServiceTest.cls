/**
 * @description Tests for ProrataForecastReminderService (BRD §8.4).
 *
 *              Payment_Schedule__c.Forecast_Date__c is a cross-object formula
 *              (= Master_Payment_Schedule__r.Forecast_Date__c), so these tests create a
 *              Master Payment Schedule with the desired Forecast Date and link it to the
 *              booking payment-schedule line.
 */
@isTest
private class ProrataForecastReminderServiceTest {

    private static Project__c project;

    private static Booking__c makeProrataBooking() {
        project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Email__c = 'cust@example.com', First_Applicant_Name__c = 'Jane', Funding_Type__c = 'Prorata'
        );
        insert b;
        return b;
    }

    private static Master_Payment_Schedule__c makeMaster(Date forecastDate) {
        Master_Payment_Schedule__c m = new Master_Payment_Schedule__c(
            Project__c = project.Id,
            Sequence__c = 1,
            Percentage__c = 10,
            Forecast_Date__c = forecastDate,
            Is_Active__c = true
        );
        insert m;
        return m;
    }

    private static Payment_Schedule__c makeSchedule(Id bookingId, Id masterId, Decimal custFlat) {
        ProrataInvariantService.bypass = true; // setup data; invariant balance not under test here
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bookingId, Sequence__c = 1, Milestone_Name__c = 'Foundation',
            Amount__c = 100, Payment_Schedule_Amount__c = 90, GST_Amount__c = 10,
            Pending_Amount__c = 100, Amount_Paid__c = 0, Status__c = 'Pending',
            Master_Payment_Schedule__c = masterId,
            Customer_Flat_Prorata__c = custFlat,
            Customer_GST_Prorata__c = 5, With_GST__c = false, Demand_Raised__c = false
        );
        insert ps;
        ProrataInvariantService.bypass = false;
        return ps;
    }

    @isTest
    static void forecastDue_sendsReminder() {
        Booking__c b = makeProrataBooking();
        Master_Payment_Schedule__c m = makeMaster(Date.today());
        Payment_Schedule__c ps = makeSchedule(b.Id, m.Id, 40);

        Test.startTest();
        Integer sent = ProrataForecastReminderService.processDueForecastReminders();
        Test.stopTest();

        System.assertEquals(1, sent, 'Forecast reminder should be sent');
        Payment_Schedule__c after = [SELECT Forecast_Reminder_Sent__c FROM Payment_Schedule__c WHERE Id = :ps.Id];
        System.assertEquals(true, after.Forecast_Reminder_Sent__c);
    }

    @isTest
    static void notDue_noReminder() {
        Booking__c b = makeProrataBooking();
        Master_Payment_Schedule__c m = makeMaster(Date.today().addDays(10)); // forecast in future
        makeSchedule(b.Id, m.Id, 40);

        Test.startTest();
        Integer sent = ProrataForecastReminderService.processDueForecastReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Future forecast date should not send');
    }

    @isTest
    static void noCustomerProrata_noReminder() {
        Booking__c b = makeProrataBooking();
        Master_Payment_Schedule__c m = makeMaster(Date.today());
        makeSchedule(b.Id, m.Id, 0); // no customer-payable prorata

        Test.startTest();
        Integer sent = ProrataForecastReminderService.processDueForecastReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'No customer prorata amount means no forecast reminder');
    }
}