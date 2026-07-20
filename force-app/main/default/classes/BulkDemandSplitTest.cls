/**
 * @description Tests the demand-raise breakdown added to BulkDemandController.createBulkDemands:
 *              Base/GST/TDS are filled on the Demand, and Prorata/Partial bookings raise only the
 *              Bank portion (Demand_Audience = Bank), while Self/Loan raise the full customer demand.
 */
@isTest
private class BulkDemandSplitTest {

    private static Booking__c makeBooking(String funding) {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Funding_Type__c = funding
        );
        insert b;
        return b;
    }

    private static String requestFor(Id bookingId, Id scheduleId, Decimal demandAmount) {
        BulkDemandController.BookingDemandItem item = new BulkDemandController.BookingDemandItem();
        item.bookingId = bookingId;
        item.demandAmount = demandAmount;
        item.scheduleIds = new List<Id>{ scheduleId };
        BulkDemandController.BulkDemandRequest req = new BulkDemandController.BulkDemandRequest();
        req.bookings = new List<BulkDemandController.BookingDemandItem>{ item };
        req.demandType = 'Bulk Demand';
        return JSON.serialize(req);
    }

    @isTest
    static void selfFunded_fillsBaseGstAndCustomerAudience() {
        Booking__c b = makeBooking('Self');
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = b.Id, Sequence__c = 1, Status__c = 'Pending', Amount__c = 84000,
            Payment_Schedule_Amount_Pending__c = 80000, GST_Amount_Pending__c = 4000, TDS_Amount_Pending__c = 0
        );
        insert ps;

        Test.startTest();
        BulkDemandController.createBulkDemands(requestFor(b.Id, ps.Id, 84000));
        Test.stopTest();

        Demands__c d = [
            SELECT Base_Amount__c, GST_Amount__c, Demand_Amount__c, Pending_Amount__c,
                   Demand_Audience__c, Funding_Type__c, Payment_Schedule__c
            FROM Demands__c WHERE Booking__c = :b.Id
        ];
        System.assertEquals(80000, d.Base_Amount__c, 'Base from schedule pending');
        System.assertEquals(4000, d.GST_Amount__c, 'GST from schedule pending');
        System.assertEquals(84000, d.Demand_Amount__c, 'Full demand for Self');
        System.assertEquals(84000, d.Pending_Amount__c, 'Pending seeded');
        System.assertEquals('Customer', d.Demand_Audience__c);
        System.assertEquals(ps.Id, d.Payment_Schedule__c);
    }

    @isTest
    static void prorata_raisesBankPortionOnly() {
        Booking__c b = makeBooking('Prorata');
        ProrataInvariantService.bypass = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = b.Id, Sequence__c = 1, Status__c = 'Pending', Amount__c = 84000,
            Payment_Schedule_Amount__c = 80000, GST_Amount__c = 4000,
            Bank_Flat_Amount__c = 50000, Bank_GST_Amount__c = 2500,
            Customer_Flat_Prorata__c = 30000, Customer_GST_Prorata__c = 1500
        );
        insert ps;
        ProrataInvariantService.bypass = false;

        Test.startTest();
        // Client may send the full milestone amount; the server must demand only the bank portion.
        BulkDemandController.createBulkDemands(requestFor(b.Id, ps.Id, 84000));
        Test.stopTest();

        Demands__c d = [
            SELECT Base_Amount__c, GST_Amount__c, Demand_Amount__c, Pending_Amount__c,
                   Demand_Audience__c, Demand_Type__c
            FROM Demands__c WHERE Booking__c = :b.Id
        ];
        System.assertEquals(50000, d.Base_Amount__c, 'Bank Flat only');
        System.assertEquals(2500, d.GST_Amount__c, 'Bank GST only');
        System.assertEquals(52500, d.Demand_Amount__c, 'Bank total (Flat + GST)');
        System.assertEquals(52500, d.Pending_Amount__c);
        System.assertEquals('Bank', d.Demand_Audience__c);
        System.assertEquals('Bank Demand', d.Demand_Type__c);
    }
}