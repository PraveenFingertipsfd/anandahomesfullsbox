/**
 * @description Tests for ProrataInvariantService / PaymentScheduleTrigger (BRD §8.3.1).
 */
@isTest
private class ProrataInvariantServiceTest {

    private static Booking__c booking;

    private static void buildProrataBooking() {
        Project__c project = new Project__c(Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Funding_Type__c = 'Prorata',
            // Deficit__c is a formula = Total_Flat_Cost - Customer_Margin - Loan_Sanctioned.
            // Set the inputs so Deficit computes to 40 and Loan Sanctioned is 60.
            Total_Flat_Cost__c = 110, Customer_Margin__c = 10, Loan_Sanctioned_Amount__c = 60
        );
        insert booking;
    }

    private static Payment_Schedule__c split(Integer seq, String name, Decimal base, Decimal gst,
            Decimal bankFlat, Decimal custFlat, Decimal bankGst, Decimal custGst) {
        return new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = seq, Milestone_Name__c = name,
            Amount__c = base + gst, Payment_Schedule_Amount__c = base, GST_Amount__c = gst,
            Pending_Amount__c = base + gst, Amount_Paid__c = 0, Status__c = 'Pending', Due_Date__c = Date.today(),
            Bank_Flat_Amount__c = bankFlat, Customer_Flat_Prorata__c = custFlat,
            Bank_GST_Amount__c = bankGst, Customer_GST_Prorata__c = custGst
        );
    }

    @isTest
    static void balancedSplit_isAccepted() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 50, 5, 30, 20, 3, 2),
            split(2, '5th Floor', 50, 5, 30, 20, 3, 2)
        };
        Test.startTest();
        insert rows; // sums: bankFlat=60=Loan, custFlat=40=Deficit, per-milestone balanced
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id]);
    }

    @isTest
    static void perMilestoneImbalance_isBlocked() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            // Foundation: 30 + 15 = 45 != base 50  -> per-milestone violation
            split(1, 'Foundation', 50, 5, 30, 15, 3, 2),
            split(2, '5th Floor', 50, 5, 30, 20, 3, 2)
        };
        Test.startTest();
        Boolean blocked = false;
        try { insert rows; } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('Flat amount') || e.getMessage().contains('not balanced'),
                'Expected balance error: ' + e.getMessage());
        }
        Test.stopTest();
        System.assert(blocked, 'Per-milestone imbalance must be blocked');
    }

    @isTest
    static void bookingSumMismatch_isBlocked() {
        buildProrataBooking();
        // Per-milestone balanced, but totals (bankFlat 40, custFlat 60) != Loan 60 / Deficit 40.
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 50, 5, 20, 30, 3, 2),
            split(2, '5th Floor', 50, 5, 20, 30, 3, 2)
        };
        Test.startTest();
        Boolean blocked = false;
        try { insert rows; } catch (DmlException e) { blocked = true; }
        Test.stopTest();
        System.assert(blocked, 'Booking-level sum mismatch must be blocked');
    }

    @isTest
    static void nonProrataBooking_isIgnored() {
        Project__c project = new Project__c(Name = 'P2', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Funding_Type__c = 'Self-Funded'
        );
        insert booking;

        // Deliberately unbalanced prorata fields, but Self funding -> not enforced.
        Test.startTest();
        insert split(1, 'Foundation', 50, 5, 99, 99, 9, 9);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id]);
    }

    @isTest
    static void splitChangeOnDemandedMilestone_isBlocked() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 50, 5, 30, 20, 3, 2),
            split(2, '5th Floor', 50, 5, 30, 20, 3, 2)
        };
        insert rows;

        // Mark Foundation as demanded (no split change -> allowed).
        rows[0].Demand_Raised__c = true;
        update rows[0];

        Test.startTest();
        Boolean blocked = false;
        rows[0].Customer_Flat_Prorata__c = 25; // change split on a demanded milestone
        rows[0].Bank_Flat_Amount__c = 25;
        try { update rows[0]; } catch (DmlException e) { blocked = true; }
        Test.stopTest();
        System.assert(blocked, 'Changing split on a demanded milestone must be blocked');
    }

    @isTest
    static void bypass_skipsValidation() {
        buildProrataBooking();
        Test.startTest();
        ProrataInvariantService.bypass = true;
        insert split(1, 'Foundation', 50, 5, 99, 99, 9, 9); // unbalanced but bypassed
        ProrataInvariantService.bypass = false;
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id]);
    }
}