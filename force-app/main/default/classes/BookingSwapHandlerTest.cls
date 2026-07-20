/**
 * @description Test class for BookingSwapHandler
 */
@isTest
private class BookingSwapHandlerTest {

    @testSetup
    static void setup() {
        Project__c project = new Project__c(
            Name = 'Swap Test Project',
            Project_Type__c = 'Residential'
        );
        insert project;

        Plot__c oldUnit = new Plot__c(
            Project__c = project.Id,
            Status__c = 'Booked'
        );
        Plot__c newUnit = new Plot__c(
            Project__c = project.Id,
            Status__c = 'Available'
        );
        insert new List<Plot__c>{ oldUnit, newUnit };
            
        // Create Quote
        Quote__c quote = new Quote__c(
            Project__c = project.Id
            // Populate any other mandatory fields if required
        );
        insert quote;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = oldUnit.Id,
             Quote__c = quote.Id,
            Booking_Amount__c = 100000,
            //Payment_Method__c = 'UPI',    // if this field exists
            Mode_Of_Payment__c = 'UPI',
            Booking_Date__c = Date.today().addDays(-30),
            Status__c = 'New'
        );
        insert booking;
    }

    @isTest
    static void swapBookings_validRequest_clonesBooking() {
        // Regression: the swap path used to die on an uncatchable "field 'Matching_Criteria__c'
        // can not be sorted" error (PostSalesAdminController.resolveConfigurationForRecord). With
        // the ORDER BY fixed, the swap runs to completion here.
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Plot__c newUnit = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];

        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = newUnit.Id;
        req.newBookingStatus = 'Booked';

        Test.startTest();
        List<BookingSwapHandler.SwapResult> results =
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        System.assert(results[0].success, 'Swap should succeed: ' + results[0].message);
        System.assertNotEquals(null, results[0].newBookingId, 'A new (cloned) booking is created');
    }

    @isTest
    static void swapBookings_nullOldBookingId_throws() {
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = null;
        req.newUnitId = null;
        req.newBookingStatus = null;

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('Old Booking ID is required'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Null booking id should throw a swap exception');
    }

    @isTest
    static void swapBookings_missingNewUnit_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = null;
        req.newBookingStatus = 'Draft';

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('Swap To Unit'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Missing new unit should throw a swap exception');
    }

    @isTest
    static void swapBookings_missingStatus_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Plot__c u = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = u.Id;
        req.newBookingStatus = '';

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('New Booking Status is required'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Blank status should throw a swap exception');
    }
}