/**
 * @description Tests for ProrataDemandService — split Bank / Customer prorata demands (BRD §8.4).
 */
@isTest
private class ProrataDemandServiceTest {

    private static Booking__c booking;
    private static Project__c project;

    private static void buildData(String funding) {
        project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Funding_Type__c = funding,
            Loan_Sanctioned_Amount__c = 2000000
        );
        insert booking;
    }

    private static Payment_Schedule__c makeSchedule(String milestone, Date due) {
        ProrataInvariantService.bypass = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = 1, Milestone_Name__c = milestone,
            Amount__c = 4200000, Payment_Schedule_Amount__c = 4000000, GST_Amount__c = 200000,
            Bank_Flat_Amount__c = 2000000, Bank_GST_Amount__c = 100000,
            Customer_Flat_Prorata__c = 2000000, Customer_GST_Prorata__c = 100000,
            With_GST__c = true, Status__c = 'Pending', Due_Date__c = due
        );
        insert ps;
        ProrataInvariantService.bypass = false;
        return ps;
    }

    @isTest
    static void bankDemand_isRaisedFromSplit() {
        buildData('Prorata');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(1, n, 'One bank demand expected');
        Demands__c d = [
            SELECT Demand_Type__c, Base_Amount__c, GST_Amount__c, Demand_Amount__c, Payment_Schedule__c
            FROM Demands__c WHERE Booking__c = :booking.Id
        ];
        System.assertEquals('Bank Demand', d.Demand_Type__c);
        System.assertEquals(2000000, d.Base_Amount__c, 'Bank Flat');
        System.assertEquals(100000, d.GST_Amount__c, 'Bank GST');
        System.assertEquals(2100000, d.Demand_Amount__c, 'Bank Flat + GST');
        System.assertEquals(true, [SELECT Bank_Demand_Raised__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Bank_Demand_Raised__c);
    }

    @isTest
    static void customerDemand_isRaisedFromSplit() {
        buildData('Partial');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseCustomerDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(1, n, 'One customer demand expected');
        Demands__c d = [SELECT Demand_Type__c, Demand_Amount__c FROM Demands__c WHERE Booking__c = :booking.Id];
        System.assertEquals('Customer Prorata Demand', d.Demand_Type__c);
        System.assertEquals(2100000, d.Demand_Amount__c, 'Customer Flat + GST');
        System.assertEquals(true, [SELECT Customer_Demand_Raised__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Customer_Demand_Raised__c);
    }

    @isTest
    static void demand_isNotRaisedTwice() {
        buildData('Prorata');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Integer second = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(0, second, 'Bank demand must not be raised twice');
        System.assertEquals(1, [SELECT COUNT() FROM Demands__c WHERE Booking__c = :booking.Id]);
    }

    @isTest
    static void nonProrataBooking_isSkipped() {
        buildData('Self-Funded');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(0, n, 'Self-funded bookings have no split demands');
    }

    @isTest
    static void completedMilestone_raisesBankDemand() {
        buildData('Prorata');
        makeSchedule('Foundation', Date.today());
        Construction_Milestone__c m = new Construction_Milestone__c(
            Milestone_Name__c = 'Foundation', Project__c = project.Id, Milestone_Status__c = 'In Progress'
        );
        insert m;

        Test.startTest();
        m.Milestone_Status__c = 'Completed';
        m.Actual_Completion_Date__c = Date.today();
        update m;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Demands__c WHERE Booking__c = :booking.Id AND Demand_Type__c = 'Bank Demand'],
            'Completing the milestone should raise the bank demand');
    }

    @isTest
    static void dueCustomerDemands_areRaised() {
        buildData('Prorata');
        makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseDueCustomerDemands();
        Test.stopTest();

        System.assertEquals(1, n, 'Customer demand should be raised on the demand date');
    }
}