/**
 * @description Comprehensive test suite for AutoDemandBatch.
 *              Tests demand creation from Payment_Schedules with matching Auto_Demand_Date__c,
 *              filtering logic (Demand_Raised, Pending_Amount, Status, Is_Cancelled),
 *              aggregation, grace period resolution, reminder date population, and bulk scenarios.
 *              85%+ coverage target.
 */
@isTest
private class AutoDemandBatchTest {

    @testSetup
    static void setupData() {
        Project__c project = new Project__c(
            Name = 'Auto Demand Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 12,
            Enable_Reminder_1__c = true,
            Reminder_1_Days__c = 7,
            Enable_Reminder_2__c = true,
            Reminder_2_Days__c = 14
        );
        insert project;

        Post_Sales_Config_Master__c config = new Post_Sales_Config_Master__c(
            Config_Name__c = 'Auto Demand Config',
            Grace_Period_Days__c = 10,
            Is_Active__c = true
        );
        insert config;

        List<Booking__c> bookings = new List<Booking__c>();
        for (Integer i = 1; i <= 5; i++) {
            bookings.add(new Booking__c(
                Project__c = project.Id,
                Booking_Date__c = Date.today().addDays(-60),
                Total_Flat_Cost__c = 10000000,
                GST_Amount__c = 500000,
                Total_Payable_Amount__c = 10500000,
                Status__c = 'New'
            ));
        }
        insert bookings;

        List<Payment_Schedule__c> schedules = new List<Payment_Schedule__c>();

        // Booking 0: 3 schedules for today (aggregation test)
        for (Integer i = 1; i <= 3; i++) {
            schedules.add(new Payment_Schedule__c(
                Booking__c = bookings[0].Id,
                Sequence__c = i,
                Milestone_Name__c = 'Milestone ' + i,
                Percentage__c = 20,
                Amount__c = 500000,
                Payment_Schedule_Amount__c = 475000,
                GST_Amount__c = 25000,
                Pending_Amount__c = 500000,
                Payment_Schedule_Amount_Pending__c = 475000,
                GST_Amount_Pending__c = 25000,
                Status__c = 'Pending',
                Auto_Demand_Date__c = Date.today(),
                Demand_Raised__c = false
            ));
        }

        // Booking 1: 1 schedule for tomorrow (should be excluded)
        schedules.add(new Payment_Schedule__c(
            Booking__c = bookings[1].Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Future Milestone',
            Percentage__c = 20,
            Amount__c = 500000,
            Pending_Amount__c = 500000,
            Status__c = 'Pending',
            Auto_Demand_Date__c = Date.today().addDays(1),
            Demand_Raised__c = false
        ));

        // Booking 2: 1 schedule for past date (no match)
        schedules.add(new Payment_Schedule__c(
            Booking__c = bookings[2].Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Past Milestone',
            Percentage__c = 20,
            Amount__c = 500000,
            Pending_Amount__c = 500000,
            Status__c = 'Pending',
            Auto_Demand_Date__c = Date.today().addDays(-10),
            Demand_Raised__c = false
        ));

        // Booking 3: 1 schedule with Demand_Raised=true (should be excluded)
        schedules.add(new Payment_Schedule__c(
            Booking__c = bookings[3].Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Already Raised',
            Percentage__c = 20,
            Amount__c = 500000,
            Pending_Amount__c = 500000,
            Status__c = 'Demand Raised',
            Auto_Demand_Date__c = Date.today(),
            Demand_Raised__c = true
        ));

        // Booking 4: 1 schedule with Pending_Amount=0 (should be excluded)
        schedules.add(new Payment_Schedule__c(
            Booking__c = bookings[4].Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Zero Pending',
            Percentage__c = 20,
            Amount__c = 500000,
            Pending_Amount__c = 0,
            Status__c = 'Paid',
            Auto_Demand_Date__c = Date.today(),
            Demand_Raised__c = false
        ));

        insert schedules;

        Booking__c cancelledBooking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today().addDays(-60),
            Total_Flat_Cost__c = 10000000,
            GST_Amount__c = 500000,
            Total_Payable_Amount__c = 10500000,
            Status__c = 'Cancellation'
        );
        insert cancelledBooking;

        schedules = new List<Payment_Schedule__c>();
        schedules.add(new Payment_Schedule__c(
            Booking__c = cancelledBooking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Cancelled Booking',
            Percentage__c = 20,
            Amount__c = 500000,
            Pending_Amount__c = 500000,
            Status__c = 'Pending',
            Auto_Demand_Date__c = Date.today(),
            Demand_Raised__c = false
        ));
        insert schedules;
    }

    @isTest
    static void testBatch_singleScheduleCreatesOneDemand() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Demands__c> demands = [SELECT Id, Demand_Amount__c FROM Demands__c];
        System.assertEquals(4, demands.size(), '4 demands should be created (3 from booking0 aggregated + single from others)');
    }

    @isTest
    static void testBatch_multipleSchedulesSameBookingAggregated() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Demands__c> demands = [
            SELECT Id, Demand_Amount__c, Booking__c
            FROM Demands__c
            WHERE Booking__c IN (SELECT Id FROM Booking__c WHERE Status__c = 'New')
            LIMIT 1
        ];
        System.assertEquals(1, demands.size(), 'Multiple schedules for same booking should aggregate to 1 demand');
        System.assertEquals(1500000, demands[0].Demand_Amount__c, 'Demand_Amount should be sum of 3 schedules (500k * 3)');
    }

    @isTest
    static void testBatch_futureDate_noDemandsCreated() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Payment_Schedule__c future = [
            SELECT Demand_Raised__c
            FROM Payment_Schedule__c
            WHERE Auto_Demand_Date__c = :Date.today().addDays(1)
        ];
        System.assertEquals(false, future.Demand_Raised__c, 'Future auto demand date should not create demand');
    }

    @isTest
    static void testBatch_demandRaisedFlagSkips() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Payment_Schedule__c already = [
            SELECT Demand_Raised__c
            FROM Payment_Schedule__c
            WHERE Milestone_Name__c = 'Already Raised'
        ];
        System.assertEquals(true, already.Demand_Raised__c, 'Already-raised schedules should not be reprocessed');
    }

    @isTest
    static void testBatch_zeroPendingExcluded() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Payment_Schedule__c zeroPending = [
            SELECT Demand_Raised__c
            FROM Payment_Schedule__c
            WHERE Milestone_Name__c = 'Zero Pending'
        ];
        System.assertEquals(false, zeroPending.Demand_Raised__c, 'Zero pending schedules excluded');
    }

    @isTest
    static void testBatch_cancelledBookingExcluded() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Payment_Schedule__c cancelled = [
            SELECT Demand_Raised__c
            FROM Payment_Schedule__c
            WHERE Milestone_Name__c = 'Cancelled Booking'
        ];
        System.assertEquals(false, cancelled.Demand_Raised__c, 'Schedules for cancelled bookings excluded');
    }

    @isTest
    static void testBatch_gracePeriodFromConfig() {
        Post_Sales_Config_Master__c config = [SELECT Grace_Period_Days__c FROM Post_Sales_Config_Master__c LIMIT 1];
        config.Grace_Period_Days__c = 10;
        update config;

        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Demands__c> demands = [SELECT Due_Date__c FROM Demands__c LIMIT 1];
        Date expectedDue = Date.today().addDays(10);
        System.assertEquals(expectedDue, demands[0].Due_Date__c, 'Due date should be Demand_Date + configured grace period');
    }

    @isTest
    static void testBatch_gracePeriodFallback() {
        Post_Sales_Config_Master__c config = [SELECT Grace_Period_Days__c FROM Post_Sales_Config_Master__c LIMIT 1];
        config.Is_Active__c = false;
        update config;

        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Demands__c> demands = [SELECT Due_Date__c FROM Demands__c LIMIT 1];
        Date expectedDue = Date.today().addDays(PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS);
        System.assertEquals(expectedDue, demands[0].Due_Date__c, 'Should fallback to default grace period (15 days)');
    }

    @isTest
    static void testBatch_reminderDatesPopulated() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Demands__c> demands = [SELECT Reminder_1_Date__c, Reminder_2_Date__c FROM Demands__c];
        for (Demands__c d : demands) {
            System.assertNotEquals(null, d.Reminder_1_Date__c, 'Reminder_1_Date should be populated by DemandTrigger');
            System.assertNotEquals(null, d.Reminder_2_Date__c, 'Reminder_2_Date should be populated by DemandTrigger');
        }
    }

    @isTest
    static void testBatch_bulkAggregation() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Integer demandCount = [SELECT COUNT() FROM Demands__c];
        System.assertEquals(4, demandCount, 'Should create 4 demands total (1 aggregated from booking0 + 3 single schedules)');

        Integer scheduleCount = [SELECT COUNT() FROM Payment_Schedule__c WHERE Demand_Raised__c = true];
        System.assertEquals(4, scheduleCount, '4 schedules should be marked as demand raised');
    }

    @isTest
    static void testBatch_emptyScope_handles() {
        delete [SELECT Id FROM Payment_Schedule__c WHERE Auto_Demand_Date__c = :Date.today()];

        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Integer demandCount = [SELECT COUNT() FROM Demands__c];
        System.assertEquals(0, demandCount, 'Empty scope should not create any demands');
    }

    @isTest
    static void testBatch_customDemandDate() {
        Date tomorrow = Date.today().addDays(1);

        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch(tomorrow);
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Demands__c> demands = [SELECT Demand_Date__c FROM Demands__c];
        System.assertEquals(1, demands.size(), 'Should pick up the schedule with Auto_Demand_Date = tomorrow');
        System.assertEquals(tomorrow, demands[0].Demand_Date__c, 'Demand_Date should match the parameter');
    }
}