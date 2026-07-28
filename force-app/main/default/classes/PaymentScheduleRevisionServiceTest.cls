/**
 * @description Tests for PaymentScheduleRevisionService — staging payment-schedule edits as a
 *              revision and applying them only after approval (BRD 8.2).
 */
@isTest
private class PaymentScheduleRevisionServiceTest {

    private static Booking__c booking;
    private static Payment_Schedule__c ps;

    private static void buildData() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Funding_Type__c = 'Self'
        );
        insert booking;
        ps = new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = 1, Milestone_Name__c = 'Foundation',
            Amount__c = 1000, Payment_Schedule_Amount__c = 1000, Pending_Amount__c = 1000,
            Amount_Paid__c = 0, Status__c = 'Pending'
        );
        insert ps;
    }

    private static PaymentScheduleRevisionService.RevisionLine line(Id id, Decimal amount) {
        PaymentScheduleRevisionService.RevisionLine l = new PaymentScheduleRevisionService.RevisionLine();
        l.id = id;
        l.amount = amount;
        l.baseAmount = amount;
        return l;
    }

    @isTest
    static void stage_createsPendingRevision_withoutTouchingSchedule() {
        buildData();

        Test.startTest();
        Id revId = PaymentScheduleRevisionService.stageAndSubmit(
            booking.Id,
            new List<PaymentScheduleRevisionService.RevisionLine>{ line(ps.Id, 500) },
            'Adjusting milestone'
        );
        Test.stopTest();

        Payment_Schedule_Revision__c rev = [
            SELECT Approval_Status__c, Applied__c, Booking__c, Proposed_Changes_JSON__c
            FROM Payment_Schedule_Revision__c WHERE Id = :revId
        ];
        System.assertEquals('Pending', rev.Approval_Status__c, 'Revision should be Pending');
        System.assertEquals(false, rev.Applied__c, 'Revision should not be applied yet');
        System.assertEquals(booking.Id, rev.Booking__c);

        // The live schedule must be unchanged until approval.
        System.assertEquals(1000, [SELECT Amount__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Amount__c,
            'Schedule amount must not change before approval');
    }

    @isTest
    static void approve_appliesValuesToSchedule() {
        buildData();
        Id revId = PaymentScheduleRevisionService.stageAndSubmit(
            booking.Id,
            new List<PaymentScheduleRevisionService.RevisionLine>{ line(ps.Id, 500) },
            null
        );

        Test.startTest();
        Payment_Schedule_Revision__c rev = new Payment_Schedule_Revision__c(
            Id = revId, Approval_Status__c = 'Approved'
        );
        update rev;
        Test.stopTest();

        System.assertEquals(500, [SELECT Amount__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Amount__c,
            'Approved amount should now be applied');
        System.assertEquals(true, [SELECT Applied__c FROM Payment_Schedule_Revision__c WHERE Id = :revId].Applied__c,
            'Revision should be marked applied');
    }

    @isTest
    static void rejected_doesNotApply() {
        buildData();
        Id revId = PaymentScheduleRevisionService.stageAndSubmit(
            booking.Id,
            new List<PaymentScheduleRevisionService.RevisionLine>{ line(ps.Id, 500) },
            null
        );

        Test.startTest();
        update new Payment_Schedule_Revision__c(Id = revId, Approval_Status__c = 'Rejected');
        Test.stopTest();

        System.assertEquals(1000, [SELECT Amount__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Amount__c,
            'Rejected revision must not change the schedule');
    }

    @isTest
    static void stage_noChanges_throws() {
        buildData();
        Test.startTest();
        Boolean threw = false;
        try {
            PaymentScheduleRevisionService.stageAndSubmit(
                booking.Id, new List<PaymentScheduleRevisionService.RevisionLine>(), null
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Empty change set should throw');
    }

    @isTest
    static void stage_nullBooking_throws() {
        Test.startTest();
        Boolean threw = false;
        try {
            PaymentScheduleRevisionService.stageAndSubmit(
                null, new List<PaymentScheduleRevisionService.RevisionLine>{ line(null, 1) }, null
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null booking should throw');
    }
}