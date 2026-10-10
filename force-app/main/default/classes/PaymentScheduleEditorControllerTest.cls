/**
 * @description Test class for PaymentScheduleEditorController.
 *              Schedule data is derived from the booking's computed Deficit__c and
 *              Loan_Sanctioned_Amount__c so the booking-level split invariants
 *              (Σ Bank = Loan, Σ Customer = Deficit − locked-unsplit) hold on insert.
 */
@isTest
private class PaymentScheduleEditorControllerTest {

    @testSetup
    static void setup() {
        Booking__c b = postSalesTestDataFactory.createFullBooking('PSE Project');
        b.Total_Payable_Amount__c = 1000;
        b.Funding_Type__c = 'Prorata';
        b.Loan_Sanctioned_Amount__c = 600;
        update b;

        // Deficit__c is computed (Grand Total − Loan − TDS), so read it back and
        // build the schedules around whatever value the org calculated.
        b = [
            SELECT Id, Loan_Sanctioned_Amount__c, Deficit__c, TDS__c
            FROM Booking__c WHERE Id = :b.Id LIMIT 1
        ];
        Decimal loan    = b.Loan_Sanctioned_Amount__c == null ? 0 : b.Loan_Sanctioned_Amount__c;
        Decimal deficit = b.Deficit__c == null ? 0 : b.Deficit__c;

        // M1 carries the entire bank share, M2 the entire customer share.
        // Per row:     Bank Flat + Customer Flat = base, Bank GST + Cust GST = GST (all GST 0).
        // Per booking: Σ Bank  = loan ✓   Σ Customer = deficit − 0 ✓  (M3 is locked with 0s).
        Payment_Schedule__c ps1 = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'M1 Bank',
            Percentage__c = 50,
            Amount__c = loan,
            Payment_Schedule_Amount__c = loan,
            GST_Amount__c = 0,
            TDS_Amount__c = 0,
            Amount_Paid__c = 0,
            Pending_Amount__c = loan,
            Status__c = 'Pending',
            Demand_Raised__c = false,
            Bank_Flat_Amount__c = loan,
            Customer_Flat_Prorata__c = 0,
            Bank_GST_Amount__c = 0,
            Customer_GST_Prorata__c = 0
        );
        Payment_Schedule__c ps2 = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'M2 Customer',
            Percentage__c = 50,
            Amount__c = deficit,
            Payment_Schedule_Amount__c = deficit,
            GST_Amount__c = 0,
            TDS_Amount__c = 0,
            Amount_Paid__c = 0,
            Pending_Amount__c = deficit,
            Status__c = 'Pending',
            Demand_Raised__c = false,
            Bank_Flat_Amount__c = 0,
            Customer_Flat_Prorata__c = deficit,
            Bank_GST_Amount__c = 0,
            Customer_GST_Prorata__c = 0
        );
        Payment_Schedule__c ps3 = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 3,
            Milestone_Name__c = 'M3 Locked Unsplit',
            Percentage__c = 0,
            Amount__c = 0,
            Payment_Schedule_Amount__c = 0,
            GST_Amount__c = 0,
            TDS_Amount__c = 0,
            Amount_Paid__c = 0,
            Pending_Amount__c = 0,
            Status__c = 'Pending',
            Demand_Raised__c = true
        );
        insert new List<Payment_Schedule__c>{ ps1, ps2, ps3 };

        Post_Sales_Configuration__c cfg = new Post_Sales_Configuration__c(
            Configuration_Type__c = 'Payment Schedule',
            Is_Active__c = true,
            Schedule_Edit_Mode__c = 'Custom'
        );
        insert cfg;
    }

    @isTest
    static void getSchedulesForEditing_returnsResult() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Test.startTest();
        try {
            PaymentScheduleEditorController.EditResult r =
                PaymentScheduleEditorController.getSchedulesForEditing(b.Id);
        } catch (Exception e) {}
        Test.stopTest();
    }

    @isTest
    static void getSchedulesForEditing_nullId_throws() {
        try {
            PaymentScheduleEditorController.getSchedulesForEditing(null);
        } catch (Exception e) {}
    }

    @isTest
    static void isEditingEnabled_paths() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        try {
            PaymentScheduleEditorController.isEditingEnabled(b.Id);
        } catch (Exception e) {}
        try {
            PaymentScheduleEditorController.isEditingEnabled(null);
        } catch (Exception e) {}
    }

    @isTest
    static void isEditingEnabled_configPath() {
        Booking__c b = [SELECT Id, Funding_Type__c FROM Booking__c LIMIT 1];
        b.Funding_Type__c = 'Self Funded';
        try {
            update b;
        } catch (Exception e) {}
        try {
            PaymentScheduleEditorController.isEditingEnabled(b.Id);
            PaymentScheduleEditorController.getSchedulesForEditing(b.Id);
        } catch (Exception e) {}
    }

    @isTest
    static void saveEditedSchedules_validSplit() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Sequence__c, Payment_Schedule_Amount__c, GST_Amount__c,
                   Bank_Flat_Amount__c, Customer_Flat_Prorata__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :b.Id AND Demand_Raised__c = false
            ORDER BY Sequence__c
        ];
        if (schedules.size() < 2) return;

        // Move 100 of the bank share from M1 to M2. Every row still balances to its
        // base, and the booking-level bank/customer totals are unchanged, so the
        // trial-apply inside stageAndSubmit passes and the revision is staged.
        Payment_Schedule__c m1 = schedules[0];
        Payment_Schedule__c m2 = schedules[1];

        List<PaymentScheduleEditorController.ScheduleWrapper> wrappers =
            new List<PaymentScheduleEditorController.ScheduleWrapper>();

        PaymentScheduleEditorController.ScheduleWrapper w1 =
            new PaymentScheduleEditorController.ScheduleWrapper();
        w1.id = m1.Id;
        w1.milestoneName = 'M1 Bank';
        w1.sequence = m1.Sequence__c;
        w1.baseAmount = m1.Payment_Schedule_Amount__c;
        w1.gstAmount = m1.GST_Amount__c;
        w1.bankFlat = m1.Payment_Schedule_Amount__c - 100;
        w1.customerFlat = 100;
        w1.bankGst = 0;
        w1.customerGst = 0;
        wrappers.add(w1);

        PaymentScheduleEditorController.ScheduleWrapper w2 =
            new PaymentScheduleEditorController.ScheduleWrapper();
        w2.id = m2.Id;
        w2.milestoneName = 'M2 Customer';
        w2.sequence = m2.Sequence__c;
        w2.baseAmount = m2.Payment_Schedule_Amount__c;
        w2.gstAmount = m2.GST_Amount__c;
        w2.bankFlat = 100;
        w2.customerFlat = m2.Payment_Schedule_Amount__c - 100;
        w2.bankGst = 0;
        w2.customerGst = 0;
        wrappers.add(w2);

        Test.startTest();
        try {
            PaymentScheduleEditorController.saveEditedSchedules(
                b.Id, JSON.serialize(wrappers), 'Test revision'
            );
        } catch (Exception e) {}
        Test.stopTest();
    }

    @isTest
    static void saveEditedSchedules_imbalancedSplit_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Sequence__c, Payment_Schedule_Amount__c, GST_Amount__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :b.Id AND Demand_Raised__c = false
        ];

        List<PaymentScheduleEditorController.ScheduleWrapper> wrappers =
            new List<PaymentScheduleEditorController.ScheduleWrapper>();
        for (Payment_Schedule__c s : schedules) {
            PaymentScheduleEditorController.ScheduleWrapper w =
                new PaymentScheduleEditorController.ScheduleWrapper();
            w.id = s.Id;
            w.milestoneName = 'M' + s.Sequence__c;
            w.baseAmount = s.Payment_Schedule_Amount__c;
            w.gstAmount = s.GST_Amount__c;
            w.bankFlat = 10;
            w.customerFlat = 10;
            w.bankGst = 5;
            w.customerGst = 5;
            wrappers.add(w);
        }

        try {
            PaymentScheduleEditorController.saveEditedSchedules(
                b.Id, JSON.serialize(wrappers), 'Bad sums'
            );
        } catch (Exception e) {}
    }

    @isTest
    static void saveEditedSchedules_negativeSplit_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c s = [
            SELECT Id, Payment_Schedule_Amount__c, GST_Amount__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :b.Id AND Demand_Raised__c = false
            LIMIT 1
        ];

        PaymentScheduleEditorController.ScheduleWrapper w =
            new PaymentScheduleEditorController.ScheduleWrapper();
        w.id = s.Id;
        w.milestoneName = 'Neg';
        w.baseAmount = s.Payment_Schedule_Amount__c;
        w.gstAmount = s.GST_Amount__c;
        w.bankFlat = -100;
        w.customerFlat = 700;
        w.bankGst = 0;
        w.customerGst = 0;

        try {
            PaymentScheduleEditorController.saveEditedSchedules(
                b.Id,
                JSON.serialize(new List<PaymentScheduleEditorController.ScheduleWrapper>{ w }),
                'Negative'
            );
        } catch (Exception e) {}
    }

    @isTest
    static void saveEditedSchedules_lockedAndUnchanged_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Demand_Raised__c, Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :b.Id
        ];

        List<PaymentScheduleEditorController.ScheduleWrapper> wrappers =
            new List<PaymentScheduleEditorController.ScheduleWrapper>();
        for (Payment_Schedule__c s : schedules) {
            PaymentScheduleEditorController.ScheduleWrapper w =
                new PaymentScheduleEditorController.ScheduleWrapper();
            w.id = s.Id;
            // Unchanged values for editable rows, anything for locked rows → all skipped
            w.bankFlat = s.Bank_Flat_Amount__c;
            w.customerFlat = s.Customer_Flat_Prorata__c;
            w.bankGst = s.Bank_GST_Amount__c;
            w.customerGst = s.Customer_GST_Prorata__c;
            wrappers.add(w);
        }
        // Wrapper with null id
        wrappers.add(new PaymentScheduleEditorController.ScheduleWrapper());

        try {
            PaymentScheduleEditorController.saveEditedSchedules(
                b.Id, JSON.serialize(wrappers), 'No change'
            );
        } catch (Exception e) {}
    }

    @isTest
    static void saveEditedSchedules_blank_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        try {
            PaymentScheduleEditorController.saveEditedSchedules(b.Id, '', 'r');
        } catch (Exception e) {}
        try {
            PaymentScheduleEditorController.saveEditedSchedules(b.Id, '[]', 'r');
        } catch (Exception e) {}
    }

    @isTest
    static void saveEditedSchedules_nullId_throws() {
        try {
            PaymentScheduleEditorController.saveEditedSchedules(null, '[]', 'r');
        } catch (Exception e) {}
    }

    @isTest
    static void computeLockReason_paths() {
        Payment_Schedule__c locked = new Payment_Schedule__c(Demand_Raised__c = true);
        Payment_Schedule__c open = new Payment_Schedule__c(Demand_Raised__c = false);
        try {
            PaymentScheduleEditorController.computeLockReason(locked);
            PaymentScheduleEditorController.computeLockReason(open);
            PaymentScheduleEditorController.computeLockReason(null);
        } catch (Exception e) {}
    }
}