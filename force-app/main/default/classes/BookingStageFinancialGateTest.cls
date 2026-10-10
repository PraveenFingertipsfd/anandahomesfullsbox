/**
 * @description Tests for the payment / additional-charge gates added to
 *              BookingStageValidationService:
 *                • → Registration : full collection (non-loan) + no pending receipt (BRD §8.50).
 *                • → Handover     : full collection + no pending receipt + all charges paid
 *                                   (BRD §58–59, §84).
 */
@isTest
private class BookingStageFinancialGateTest {

    private static Booking__c makeBooking(String stage, String funding) {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = stage, Funding_Type__c = funding,
            Sale_Agreement_Status__c = 'Completed', Agreement_Date__c = Date.today()
        );
        insert b;
        return b;
    }

    private static Payment_Schedule__c schedule(Id bookingId, Decimal pending) {
        return new Payment_Schedule__c(
            Booking__c = bookingId, Amount__c = 100000, Sequence__c = 1,
            Status__c = 'Pending', Pending_Amount__c = pending
        );
    }

    @isTest
    static void registration_blockedByPendingBalance_thenAllowed() {
        Booking__c b = makeBooking('Demands & Collections', 'Self-Funded');
        Payment_Schedule__c ps = schedule(b.Id, 50000);
        insert ps;

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Registration';
        try { update b; } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('all payments must be received'), e.getMessage());
        }
        System.assert(blocked, 'Registration with a pending balance must be blocked');

        ps.Pending_Amount__c = 0;
        update ps;
        update b; // now fully collected → allowed
        Test.stopTest();

        System.assertEquals('Registration', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void registration_blockedByPendingReceipt() {
        Booking__c b = makeBooking('Demands & Collections', 'Self-Funded');
        insert new Receipt__c(
            Booking__c = b.Id, Payment_Method__c = 'NEFT', Receipt_Date__c = Date.today(),
            Approval_Status__c = 'Pending Approval'
        );

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Registration';
        try { update b; } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('awaiting approval'), e.getMessage());
        }
        Test.stopTest();
        System.assert(blocked, 'Registration with a receipt awaiting approval must be blocked');
    }

    @isTest
    static void registration_loanFunding_allowedWithPendingBalance() {
        Booking__c b = makeBooking('Demands & Collections', 'Loan');
        insert schedule(b.Id, 75000); // outstanding bank portion is fine for Loan

        Test.startTest();
        b.Status__c = 'Registration';
        update b;
        Test.stopTest();

        System.assertEquals('Registration', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void handover_blockedByOpenCharge_thenAllowed() {
        Booking__c b = makeBooking('Registration', 'Self-Funded');
        b.Sale_Deed_Status__c = 'Completed';
        b.Sale_Deed_Date__c = Date.today();
        b.Registration_Date__c = Date.today();
        b.Registration_Number__c = 'REG-1';
        update b;

        Additional_Charge__c ac = new Additional_Charge__c(
            Booking__c = b.Id, Amount__c = 5000, Charge_Name__c = 'Car Park',
            Charge_Type__c = 'Additional Car Parking', Status__c = 'Demanded'
        );
        insert ac;

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Handover';
        try { update b; } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('additional charges'), e.getMessage());
        }
        System.assert(blocked, 'Handover with an open additional charge must be blocked');

        ac.Status__c = 'Paid';
        update ac;
        update b; // charge cleared → allowed
        Test.stopTest();

        System.assertEquals('Handover', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void handover_blockedByPendingBalance() {
        Booking__c b = makeBooking('Registration', 'Self-Funded');
        b.Sale_Deed_Status__c = 'Completed';
        b.Sale_Deed_Date__c = Date.today();
        b.Registration_Date__c = Date.today();
        b.Registration_Number__c = 'REG-2';
        update b;

        insert schedule(b.Id, 1000);

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Handover';
        try { update b; } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('all payments must be received'), e.getMessage());
        }
        Test.stopTest();
        System.assert(blocked, 'Handover with a pending balance must be blocked');
    }
}