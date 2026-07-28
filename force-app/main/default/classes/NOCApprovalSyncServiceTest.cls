/**
 * @description Tests for NOCApprovalSyncService — syncing NOC approval status to the booking.
 */
@isTest
private class NOCApprovalSyncServiceTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;
        return b;
    }

    @isTest
    static void nocApproval_syncsToBooking() {
        Booking__c b = makeBooking();
        NOC__c noc = new NOC__c(Booking__c = b.Id, NOC_Type__c = 'Capri NOC', Approval_Status__c = 'Pending');
        insert noc;

        Test.startTest();
        update new NOC__c(Id = noc.Id, Approval_Status__c = 'Approved');
        Test.stopTest();

        System.assertEquals('Approved',
            [SELECT NOC_Approval_Status__c FROM Booking__c WHERE Id = :b.Id].NOC_Approval_Status__c,
            'Booking NOC status should reflect the approved NOC');
    }

    @isTest
    static void insertSyncsAndUnchangedStatusUpdateKeepsIt() {
        Booking__c b = makeBooking();
        NOC__c noc = new NOC__c(Booking__c = b.Id, NOC_Type__c = 'Capri NOC', Approval_Status__c = 'Pending');
        insert noc; // insert syncs Pending to the booking

        Test.startTest();
        update new NOC__c(Id = noc.Id, Mail_Body__c = 'changed body'); // status unchanged
        Test.stopTest();

        System.assertEquals('Pending',
            [SELECT NOC_Approval_Status__c FROM Booking__c WHERE Id = :b.Id].NOC_Approval_Status__c,
            'Insert sets it; a non-status update must not change it');
    }
}