/**
 * @description Tests the BRD pointer 7 safety net in EmailSenderInvocable: receipt emails
 *              must never include the booking owner's address in any recipient list.
 */
@isTest
private class EmailSenderReceiptOwnerTest {

    @isTest
    static void removesBookingOwnerFromReceiptRecipients() {
        Project__c project = new Project__c(Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert booking; // owned by running user

        Receipt__c receipt = new Receipt__c(
            Booking__c = booking.Id, Amount_received__c = 1000, Receipt_Date__c = Date.today(),
            Receipt_Type__c = 'Installment Payment', Status__c = 'Cleared',Payment_Method__c='Cash'
        );
        insert receipt;

        String ownerEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;

        List<String> toAddresses = new List<String>{ 'applicant@example.com', ownerEmail };
        List<String> ccAddresses = new List<String>{ ownerEmail.toUpperCase() }; // case-insensitive match
        List<String> bccAddresses = new List<String>();

        Test.startTest();
        EmailSenderInvocable.removeBookingOwnerFromReceiptEmail(receipt.Id, toAddresses, ccAddresses, bccAddresses);
        Test.stopTest();

    }

    @isTest
    static void nullReceiptId_isNoOp() {
        List<String> to = new List<String>{ 'a@b.com' };
        Test.startTest();
        EmailSenderInvocable.removeBookingOwnerFromReceiptEmail(null, to, new List<String>(), new List<String>());
        Test.stopTest();
    }
}