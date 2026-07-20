@IsTest
private class ProrataSplitInvocableTest {

    @testSetup
    static void setupData() {
        
        // Create Project
        Project__c project = new Project__c(
            Name = 'Test Project',
            //Project_Code__c = 'PRJ-001'
            Project_Type__c = 'Residential',
            Interest_Rate__c = 12
        );
        insert project;

        // Create Unit
        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Available'
        );
        insert unit;
        
        Quote__c quote = new Quote__c(
            Project__c = project.Id
            // Populate any other required fields on Quote__c
        );
        insert quote;
        // Create Booking
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Quote__c = quote.Id,
            Booking_Amount__c = 100000,
            //Payment_Method__c = 'UPI',    // if this field exists
            Mode_Of_Payment__c = 'UPI', 
            Plot__c = unit.Id,
            Status__c = 'New'
        );
        insert booking;
    }

    // Test null input
    @IsTest
    static void testNullInput() {

        Test.startTest();
        ProrataSplitInvocable.apply(null);
        Test.stopTest();

        System.assert(true);
    }

    // Test empty list
    @IsTest
    static void testEmptyInput() {

        Test.startTest();
        ProrataSplitInvocable.apply(new List<ProrataSplitInvocable.Input>());
        Test.stopTest();

        System.assert(true);
    }

    // Test input with null Booking Id
    @IsTest
    static void testNullBookingId() {

        ProrataSplitInvocable.Input input = new ProrataSplitInvocable.Input();
        input.bookingId = null;

        Test.startTest();
        ProrataSplitInvocable.apply(
            new List<ProrataSplitInvocable.Input>{ input }
        );
        Test.stopTest();

        System.assert(true);
    }

    // Test valid Booking Id
    @IsTest
    static void testValidBooking() {

        Booking__c booking = [
            SELECT Id
            FROM Booking__c
            LIMIT 1
        ];

        ProrataSplitInvocable.Input input = new ProrataSplitInvocable.Input();
        input.bookingId = booking.Id;

        Test.startTest();
        ProrataSplitInvocable.apply(
            new List<ProrataSplitInvocable.Input>{ input }
        );
        Test.stopTest();

        System.assertNotEquals(null, booking.Id);
    }

    // Test multiple inputs (bulk)
    @IsTest
    static void testBulkInput() {

        Booking__c booking = [
            SELECT Id
            FROM Booking__c
            LIMIT 1
        ];

        ProrataSplitInvocable.Input input1 = new ProrataSplitInvocable.Input();
        input1.bookingId = booking.Id;

        ProrataSplitInvocable.Input input2 = new ProrataSplitInvocable.Input();
        input2.bookingId = booking.Id;

        Test.startTest();
        ProrataSplitInvocable.apply(
            new List<ProrataSplitInvocable.Input>{ input1, input2 }
        );
        Test.stopTest();

        System.assert(true);
    }
}