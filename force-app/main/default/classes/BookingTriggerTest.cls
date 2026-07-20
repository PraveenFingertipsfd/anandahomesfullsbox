@IsTest
public class BookingTriggerTest {
    
    @TestSetup
    static void setup() {
        // Set up Projects
        Project__c pr = new Project__c(Name = 'Aarya', Project_Type__c = 'Residential');
        insert pr;
        
        Project__c pr1 = new Project__c(Name = 'Arto Helix', Project_Type__c = 'Residential');
        insert pr1;
        
        // Set up Blocks
        Block__c blk1 = new Block__c(Name = 'A', Project__c = pr.Id);
        insert blk1;
        
        // Set up Plots
        Plot__c pl = new Plot__c(Name = '101', Status__c = 'Available', Project__c = pr.Id, Block1__c = blk1.Id);
        insert pl;
        
        Plot__c pl2 = new Plot__c(Name = '202', Status__c = 'Available', Project__c = pr1.Id, Block1__c = blk1.Id);
        insert pl2;
        
        // Set up Booking records
        Booking__c booking1 = new Booking__c(Followup_Date__c = system.today(), Project1__c = pr.Id, Plot__c = pl.Id, Stage__c = 'New Booking');
        insert booking1;
        
        Booking__c booking2 = new Booking__c(Followup_Date__c = system.today(), Project1__c = pr1.Id, Plot__c = pl2.Id, Stage__c = 'New Booking', Is_Swap__c = false);
        insert booking2;
    }
    
    @IsTest
    static void testBookingInsert() {
        // Testing insert behavior
        Booking__c newBooking = new Booking__c(Followup_Date__c = system.today(), Project1__c = [SELECT Id FROM Project__c LIMIT 1].Id, Plot__c = [SELECT Id FROM Plot__c LIMIT 1].Id, Stage__c = 'New Booking');
        Test.startTest();
        insert newBooking;
        Test.stopTest();
        
        // Check expected outcomes here, e.g.:
        System.assertNotEquals(null, newBooking.Id);
    }
    
    @IsTest
    static void testBookingUpdate() {
        Booking__c booking = [SELECT Id, Stage__c, Plot__c FROM Booking__c LIMIT 1];
        Plot__c newPlot = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];

        Test.startTest();
        booking.Plot__c = newPlot.Id;
        booking.Swap_Unit_Status__c = 'Approved';
        update booking;
        Test.stopTest();

        Booking__c after = [SELECT Plot__c, Swap_Unit_Status__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Approved', after.Swap_Unit_Status__c, 'Swap status persisted by trigger');
        System.assertEquals(newPlot.Id, after.Plot__c, 'Plot link persisted');
    }

    @IsTest
    static void testBookingCancellation() {
        Booking__c booking = [SELECT Id, Stage__c FROM Booking__c LIMIT 1];
        Test.startTest();
        booking.Stage__c = 'Cancellation';
        update booking;
        Test.stopTest();

        Booking__c after = [SELECT Stage__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Cancellation', after.Stage__c, 'Cancellation persisted');
    }
}