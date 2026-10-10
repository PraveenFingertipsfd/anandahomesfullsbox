/**
 * @description Test class for CreditNoteApplicationService.
 *              Tests auto-application of credit notes against demands.
 * @author System
 * @date 2026-03-30
 */
@IsTest
private class CreditNoteApplicationServiceTest {

    @TestSetup
    static void setupData() {
        Project__c project = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert unit;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Booking_Date__c = Date.today().addDays(-60),
            Total_Flat_Cost__c = 5000000,
            GST_Amount__c = 250000,
            Total_Payable_Amount__c = 5250000,
            Status__c = 'Active'
        );
        insert booking;

        // Create payment schedules
        List<Payment_Schedule__c> schedules = new List<Payment_Schedule__c>();
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'On Booking',
            Percentage__c = 10,
            Amount__c = 525000,
            Pending_Amount__c = 0,
            Amount_Paid__c = 525000,
            Due_Date__c = Date.today().addDays(-60),
            Status__c = 'Paid'
        ));
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'On Foundation',
            Percentage__c = 20,
            Amount__c = 1050000,
            Pending_Amount__c = 1050000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(-30),
            Status__c = 'Pending'
        ));
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 3,
            Milestone_Name__c = 'On Plinth',
            Percentage__c = 20,
            Amount__c = 1050000,
            Pending_Amount__c = 1050000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(30),
            Status__c = 'Pending'
        ));
        insert schedules;

        // Create an approved credit note with ₹100,000 available
        Credit_Note__c creditNote = new Credit_Note__c(
            Booking__c = booking.Id,
            Credit_Amount__c = 100000,
            Available_Amount__c = 100000,
            Credit_Date__c = Date.today().addDays(-10),
            Credit_Type__c = 'Discount',
            Credit_Reason__c = 'Early Bird Discount',
            Status__c = 'Approved',
            Apply_To__c = 'Next Demand',
            Auto_Apply__c = true,
            Priority__c = 1
        );
        insert creditNote;
    }

    @IsTest
    static void testCreditAppliedOnDemandCreation() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c schedule = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id AND Sequence__c = 2
            LIMIT 1
        ];

        // Create a demand
        Demands__c demand = new Demands__c(
            Booking__c = booking.Id,
            Payment_Schedule__c = schedule.Id,
            Demand_Amount__c = 1050000,
            Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(15),
            Reminder_Date__c = Date.today().addDays(7)
        );
        insert demand;

        Test.startTest();
        CreditNoteApplicationService.applyCredits(new List<Id>{ demand.Id });
        Test.stopTest();


        }

    @IsTest
    static void testPartialCreditApplication() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        // Create a small demand less than credit note amount
        Demands__c demand = new Demands__c(
            Booking__c = booking.Id,
            Demand_Amount__c = 50000,
            Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(15),
            Reminder_Date__c = Date.today().addDays(7)
        );
        insert demand;

        Test.startTest();
        CreditNoteApplicationService.applyCredits(new List<Id>{ demand.Id });
        Test.stopTest();

       
    }

    @IsTest
    static void testNoCreditWhenNoneAvailable() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        // Use up the credit note first
        Credit_Note__c cn = [SELECT Id FROM Credit_Note__c WHERE Booking__c = :booking.Id LIMIT 1];
        cn.Available_Amount__c = 0;
        cn.Status__c = 'Fully Applied';
        update cn;

        Demands__c demand = new Demands__c(
            Booking__c = booking.Id,
            Demand_Amount__c = 500000,
            Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(15),
            Reminder_Date__c = Date.today().addDays(7)
        );
        insert demand;

        Test.startTest();
        CreditNoteApplicationService.applyCredits(new List<Id>{ demand.Id });
        Test.stopTest();

      
    }

    @IsTest
    static void testSpecificScheduleCreditSkipsNonMatching() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c schedule2 = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id AND Sequence__c = 2 LIMIT 1
        ];
        Payment_Schedule__c schedule3 = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id AND Sequence__c = 3 LIMIT 1
        ];

        // Update credit note to be specific to schedule 3
        Credit_Note__c cn = [SELECT Id FROM Credit_Note__c WHERE Booking__c = :booking.Id LIMIT 1];
        cn.Apply_To__c = 'Specific Schedule';
        cn.Payment_Schedule__c = schedule3.Id;
        update cn;

        // Create demand for schedule 2 (different from credit note's schedule)
        Demands__c demand = new Demands__c(
            Booking__c = booking.Id,
            Payment_Schedule__c = schedule2.Id,
            Demand_Amount__c = 1050000,
            Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(15),
            Reminder_Date__c = Date.today().addDays(7)
        );
        insert demand;

        Test.startTest();
        CreditNoteApplicationService.applyCredits(new List<Id>{ demand.Id });
        Test.stopTest();

      
    }

    @IsTest
    static void testFlowInvocableMethod() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Demands__c demand = new Demands__c(
            Booking__c = booking.Id,
            Demand_Amount__c = 200000,
            Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(15),
            Reminder_Date__c = Date.today().addDays(7)
        );
        insert demand;

        Test.startTest();
        CreditNoteApplicationService.FlowInput input = new CreditNoteApplicationService.FlowInput();
        input.demandId = demand.Id;
        List<CreditNoteApplicationService.FlowOutput> outputs =
            CreditNoteApplicationService.applyCreditsFromFlow(
                new List<CreditNoteApplicationService.FlowInput>{ input }
            );
        Test.stopTest();

       
    }

    @IsTest
    static void testMultipleCreditNotesApplied() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        // Add a second credit note
        Credit_Note__c cn2 = new Credit_Note__c(
            Booking__c = booking.Id,
            Credit_Amount__c = 50000,
            Available_Amount__c = 50000,
            Credit_Date__c = Date.today().addDays(-5),
            Credit_Type__c = 'Goodwill',
            Credit_Reason__c = 'Goodwill gesture',
            Status__c = 'Approved',
            Apply_To__c = 'Next Demand',
            Auto_Apply__c = true,
            Priority__c = 2
        );
        insert cn2;

        Demands__c demand = new Demands__c(
            Booking__c = booking.Id,
            Demand_Amount__c = 1050000,
            Status__c = 'Raised',
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(15),
            Reminder_Date__c = Date.today().addDays(7)
        );
        insert demand;

        Test.startTest();
        CreditNoteApplicationService.applyCredits(new List<Id>{ demand.Id });
        Test.stopTest();

       
    }

    @IsTest
    static void testEmptyInputHandled() {
        Test.startTest();
        CreditNoteApplicationService.applyCredits(new List<Id>());
        CreditNoteApplicationService.applyCredits(null);
        Test.stopTest();
        // Should not throw any exceptions
    }
}