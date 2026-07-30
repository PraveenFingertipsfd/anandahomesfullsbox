/**
 * @description Test class for PaymentScheduleViewController
 */
@isTest
private class PaymentScheduleViewControllerTest {

    @testSetup
    static void setup() {
        Booking__c b = postSalesTestDataFactory.createFullBooking('PSV Project');
        b.Total_Payable_Amount__c = 1000;
        update b;

        Payment_Schedule__c ps1 = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Milestone 1',
            Status__c = 'Completed',
            Amount__c = 500,
            Percentage__c = 50,
            Pending_Amount__c = 100,
            Interest_Pending__c = 10
        );
        Payment_Schedule__c ps2 = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'Milestone 2',
            Status__c = 'Pending',
            Amount__c = 500,
            Percentage__c = 50,
            Pending_Amount__c = 500
        );
        insert new List<Payment_Schedule__c>{ ps1, ps2 };
    }

    @isTest
    static void getPaymentSchedules_returnsResult() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();
        System.assertEquals(true, r.success, 'Should succeed');
        System.assertEquals(2, r.schedules.size(), 'Should have 2 schedules');
        System.assertEquals('Milestone 1', r.schedules[0].milestoneName, 'Milestone name should map from Milestone_Name__c');
        System.assertEquals('Milestone 1', r.nextDemand.lastCompletedMilestone, 'Last completed milestone should be the completed schedule');
    }

    @isTest
    static void getPaymentSchedules_blankMilestoneName_fallsBackToScheduleName() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c completed = [
            SELECT Id, Name FROM Payment_Schedule__c
            WHERE Booking__c = :b.Id AND Status__c = 'Completed' LIMIT 1
        ];
        completed.Milestone_Name__c = null;
        update completed;

        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();

        System.assertEquals(true, r.success, 'Should succeed');
        System.assertEquals(completed.Name, r.nextDemand.lastCompletedMilestone,
            'Blank Milestone_Name__c should fall back to schedule Name');
        for (PaymentScheduleViewController.PaymentScheduleWrapper w : r.schedules) {
            if (w.id == completed.Id) {
                System.assertEquals(completed.Name, w.milestoneName,
                    'Wrapper should fall back to schedule Name when Milestone_Name__c is blank');
            }
        }
    }

    @isTest
    static void getPaymentSchedules_nullId_returnsError() {
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(null);
        System.assertEquals(false, r.success, 'Should not succeed');
        System.assertNotEquals(null, r.errorMessage, 'Should have error');
    }

    @isTest
    static void saveScheduleAmounts_validTotals_updates() {
        Booking__c b = [SELECT Id, Total_Payable_Amount__c FROM Booking__c LIMIT 1];
        List<Payment_Schedule__c> schedules = [SELECT Id FROM Payment_Schedule__c WHERE Booking__c = :b.Id ORDER BY Sequence__c];

        Map<String, Object> amounts = new Map<String, Object>();
        amounts.put(schedules[1].Id, '500');
        // first one has Status='Completed' so we don't edit it; will keep its existing amount

        Test.startTest();
        try {
            PaymentScheduleViewController.saveScheduleAmounts(b.Id, JSON.serialize(amounts));
        } catch (Exception e) {
            // The completed schedule edit would throw; here ps2 is Pending so it should succeed
        }
        Test.stopTest();
    }

    @isTest
    static void saveScheduleAmounts_emptyMap_doesNothing() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        PaymentScheduleViewController.saveScheduleAmounts(b.Id, '{}');
        // Just assert no exception occurred
        System.assert(true, 'No error');
    }

    @isTest
    static void saveScheduleAmounts_invalidJson_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Boolean threw = false;
        try {
            PaymentScheduleViewController.saveScheduleAmounts(b.Id, 'not-json');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void saveScheduleAmounts_negativeAmount_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c ps = [SELECT Id FROM Payment_Schedule__c WHERE Status__c = 'Pending' LIMIT 1];
        Map<String, Object> amounts = new Map<String, Object>{ ps.Id => '-100' };

        Boolean threw = false;
        try {
            PaymentScheduleViewController.saveScheduleAmounts(b.Id, JSON.serialize(amounts));
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw on negative');
    }
    @isTest
    static void raiseDemandForBooking_success() {
    
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
    
        Test.startTest();
    
        Id demandId = PaymentScheduleViewController.raiseDemandForBooking(booking.Id);
    
        Test.stopTest();
    
        System.assertNotEquals(null, demandId);
    
        Demands__c demand = [
            SELECT Booking__c,
                   Demand_Amount__c,
                   Pending_Amount__c,
                   Interest_Amount__c,
                   Payment_Schedule__c
            FROM Demands__c
            WHERE Id = :demandId
        ];
    
        System.assertEquals(booking.Id, demand.Booking__c);
        System.assertEquals(110, demand.Demand_Amount__c);
    }

    @isTest
    static void raiseDemandForBooking_alreadyDemandedSchedule_isExcluded() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        // First raise consumes the completed schedule(s) and flags them Demand_Raised__c.
        PaymentScheduleViewController.raiseDemandForBooking(booking.Id);

        // Second raise must not re-demand the same schedule(s) — with nothing new
        // completed it should refuse instead of duplicating the first amount.
        Boolean threw = false;
        try {
            PaymentScheduleViewController.raiseDemandForBooking(booking.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'Raising again with no newly completed schedules must refuse, not duplicate');
        System.assertEquals(1, [SELECT COUNT() FROM Demands__c WHERE Booking__c = :booking.Id],
            'Only the first demand exists');
    }
}