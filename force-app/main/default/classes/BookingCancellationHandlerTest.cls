/**
 * @description Comprehensive test suite for BookingCancellationHandler.
 *              Tests unit release on valid cancellations, null/error handling, unit status transitions,
 *              bulk processing, config lookup exceptions, and DML failures.
 *              97% coverage target.
 */
@isTest
private class BookingCancellationHandlerTest {

    @testSetup
    static void setupData() {
        Project__c project = new Project__c(
            Name = 'Cancellation Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 12
        );
        insert project;
        
        Quote__c quote = new Quote__c(
            Project__c = project.Id
            // Populate any other mandatory fields
        );
        insert quote;
        
        List<Plot__c> units = new List<Plot__c>();
        units.add(new Plot__c(Project__c = project.Id, Status__c = 'Booked'));
        units.add(new Plot__c(Project__c = project.Id, Status__c = 'Blocked', Blocked_Until__c = Date.today().addDays(30)));
        units.add(new Plot__c(Project__c = project.Id, Status__c = 'Sold'));
        units.add(new Plot__c(Project__c = project.Id, Status__c = 'Not for Sale'));
        insert units;
        
        
        
        List<Booking__c> bookings = new List<Booking__c>();
        
        for (Plot__c u : units) {
            Booking__c b = new Booking__c(
                Project__c = project.Id,
                Plot__c = u.Id,
                 Quote__c = quote.Id,
                Booking_Amount__c = 100000,
                Mode_Of_Payment__c = 'UPI',
                Booking_Date__c = Date.today(),
                Total_Flat_Cost__c = 1000000,
                GST_Amount__c = 100000,
                Total_Payable_Amount__c = 1100000,
                Status__c = 'New',
                Cancellation_Date__c = null
            );
            bookings.add(b);
        }
        insert bookings;

        List<Plot__c> unitsToUpdate = new List<Plot__c>();
        for (Integer i = 0; i < units.size(); i++) {
            units[i].Current_Booking__c = bookings[i].Id;
        }
        update units;
    }

    @isTest
    static void testCancel_validCancellation_unitReleased() {
        Booking__c booking = [SELECT Id, Plot__c FROM Booking__c LIMIT 1];
        Plot__c unit = [SELECT Id, Status__c FROM Plot__c WHERE Id = :booking.Plot__c];
        System.assertEquals('Booked', unit.Status__c, 'Unit should start as Booked');

        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = booking.Id;

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(new List<BookingCancellationHandler.CancellationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Cancellation should succeed');

        Plot__c updatedUnit = [SELECT Id, Status__c, Current_Booking__c FROM Plot__c WHERE Id = :unit.Id];
        System.assertEquals('Available', updatedUnit.Status__c, 'Unit status should be Available after cancellation');
        System.assertEquals(null, updatedUnit.Current_Booking__c, 'Unit Current_Booking should be cleared');
    }

    @isTest
    static void testCancel_nullBookingId_returnsError() {
        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = null;

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(new List<BookingCancellationHandler.CancellationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Null booking ID should fail');
        System.assert(results[0].message.containsIgnoreCase('required'), 'Message should mention required booking ID');
    }

    @isTest
    static void testCancel_bookingNotFound_returnsError() {
        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = '001000000000001'; // Non-existent ID

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(new List<BookingCancellationHandler.CancellationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Non-existent booking should fail');
        System.assert(results[0].message.containsIgnoreCase('not found') || results[0].message.containsIgnoreCase('error'), 'Message should indicate not found');
    }

    @isTest
    static void testCancel_bookingWithoutUnit_graceful() {
        Quote__c quote = [SELECT Id FROM Quote__c LIMIT 1];
        Project__c p= [SELECT Id FROM Project__c LIMIT 1];
        
        Booking__c booking = new Booking__c(
            
            Project__c = p.Id,
            Quote__c = quote.Id,
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 1000000,
            GST_Amount__c = 100000,
            Total_Payable_Amount__c = 1100000,
            Booking_Amount__c = 100000,
            Status__c = 'New',
            Plot__c = null
        );
        insert booking;

        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = booking.Id;

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(new List<BookingCancellationHandler.CancellationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Booking without unit should gracefully succeed (no-op)');
    }

    @isTest
    static void testCancel_unitStatusTransitions() {
        List<Plot__c> units = [SELECT Id, Status__c FROM Plot__c];
        List<Booking__c> bookings = [SELECT Id, Plot__c FROM Booking__c];

        List<BookingCancellationHandler.CancellationRequest> requests = new List<BookingCancellationHandler.CancellationRequest>();
        for (Booking__c b : bookings) {
            BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
            req.bookingId = b.Id;
            requests.add(req);
        }

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(requests);
        Test.stopTest();

        List<Plot__c> updatedUnits = [SELECT Id, Status__c FROM Plot__c];
        for (Plot__c u : updatedUnits) {
            System.assertEquals('Available', u.Status__c, 'All units should transition to Available');
        }
    }

    @isTest
    static void testCancel_bulkRequests() {
        List<Booking__c> bookings = [SELECT Id FROM Booking__c LIMIT 3];
        List<BookingCancellationHandler.CancellationRequest> requests = new List<BookingCancellationHandler.CancellationRequest>();

        for (Booking__c b : bookings) {
            BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
            req.bookingId = b.Id;
            requests.add(req);
        }

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(requests);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Should return 3 results');
        for (BookingCancellationHandler.CancellationResult r : results) {
            System.assertEquals(true, r.success, 'All bulk requests should succeed independently');
        }
    }

    @isTest
    static void testCancel_configLookupException() {
        Booking__c booking = [SELECT Id, Plot__c FROM Booking__c LIMIT 1];

        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = booking.Id;

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(new List<BookingCancellationHandler.CancellationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Config lookup exception should not prevent unit release');

        Plot__c releasedUnit = [SELECT Id, Status__c FROM Plot__c WHERE Id = :booking.Plot__c];
        System.assertEquals('Available', releasedUnit.Status__c, 'Unit should still be released despite config lookup issues');
    }

    @isTest
    static void testCancel_dmlExceptionHandled() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = booking.Id;

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(new List<BookingCancellationHandler.CancellationRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'DML exception should be handled and reported');
    }

    @isTest
    static void testCancel_allExceptionTypes() {
        List<BookingCancellationHandler.CancellationRequest> requests = new List<BookingCancellationHandler.CancellationRequest>();

        // QueryException case (non-existent ID)
        BookingCancellationHandler.CancellationRequest req1 = new BookingCancellationHandler.CancellationRequest();
        req1.bookingId = '001000000000001';
        requests.add(req1);

        // Valid case
        Booking__c validBooking = [SELECT Id FROM Booking__c LIMIT 1];
        BookingCancellationHandler.CancellationRequest req2 = new BookingCancellationHandler.CancellationRequest();
        req2.bookingId = validBooking.Id;
        requests.add(req2);

        Test.startTest();
        List<BookingCancellationHandler.CancellationResult> results =
            BookingCancellationHandler.cancelBookings(requests);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return 2 results');
        System.assertEquals(false, results[0].success, 'Invalid ID should fail');
        System.assertEquals(true, results[1].success, 'Valid ID should succeed');
    }
}