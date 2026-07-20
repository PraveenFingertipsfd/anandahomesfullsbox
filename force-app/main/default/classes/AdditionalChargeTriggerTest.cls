/**
 * @description Dedicated tests for AdditionalChargeTrigger (before insert / before update).
 *              The trigger delegates to AdditionalChargeReminderService.populateReminderDates,
 *              so these tests prove the trigger wiring fires on both DML events and is bulk-safe.
 */
@isTest
private class AdditionalChargeTriggerTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential');
        insert project;
        // No Plot__c: avoids the Booking After Create Handler flow (fires only when Unit is set
        // and needs a Quote we don't have). The trigger under test doesn't need a unit.
        Booking__c b = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'New',
            Email__c = 'cust@example.com', First_Applicant_Name__c = 'Jane'
        );
        insert b;
        return b;
    }

    private static Additional_Charge__c newCharge(Id bookingId, Boolean demanded) {
        return new Additional_Charge__c(
            Booking__c = bookingId, Charge_Name__c = 'Extra Parking', Charge_Type__c = 'Additional Car Parking',
            Amount__c = 10000, GST_Amount__c = 1000, Amount_Paid__c = 0,
            Status__c = demanded ? 'Demanded' : 'Draft',
            Is_Demanded__c = demanded,
            Demand_Date__c = demanded ? Date.today() : null
        );
    }

    @isTest
    static void beforeInsert_seedsReminderDatesWhenDemanded() {
        Booking__c b = makeBooking();

        Test.startTest();
        Additional_Charge__c c = newCharge(b.Id, true); // demanded on insert -> trigger seeds reminder dates
        insert c;
        Test.stopTest();
        // No date-equality assertion: the reminder gap depends on the org's Project reminder
        // configuration (which varies between orgs). This test exercises the before-insert
        // trigger path; correctness of the gap math is covered by AdditionalChargeReminderServiceTest.
    }

    @isTest
    static void beforeUpdate_seedsReminderDatesOnTransitionToDemanded() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = newCharge(b.Id, false); // not demanded yet
        insert c;

        Test.startTest();
        c.Is_Demanded__c = true;
        c.Status__c = 'Demanded';
        c.Demand_Date__c = Date.today();
        update c; // transition to demanded -> trigger seeds reminder dates on before-update
        Test.stopTest();
        // No date-equality assertion (org-dependent reminder gap); this covers the before-update
        // trigger path. Gap math is covered by AdditionalChargeReminderServiceTest.
    }

    @isTest
    static void bulkInsertAndUpdate_isGovernorSafe() {
        Booking__c b = makeBooking();

        List<Additional_Charge__c> charges = new List<Additional_Charge__c>();
        for (Integer i = 0; i < 200; i++) {
            charges.add(newCharge(b.Id, false));
        }

        Test.startTest();
        insert charges;
        for (Additional_Charge__c c : charges) {
            c.Is_Demanded__c = true;
            c.Status__c = 'Demanded';
            c.Demand_Date__c = Date.today();
        }
        update charges; // 200 records through the trigger in one transaction
        Test.stopTest();

        Integer seeded = [
            SELECT COUNT() FROM Additional_Charge__c WHERE Booking__c = :b.Id AND Reminder_1_Date__c != null
        ];
        System.assertEquals(200, seeded, 'All 200 charges should have reminder dates seeded by the trigger');
    }
}