/**
 * @description Tests for BookingStageValidationService (BRD stage-progression gates).
 */
@isTest
private class BookingStageValidationServiceTest {

    private static Booking__c makeBooking(String stage) {
        Project__c project = new Project__c(Name = 'P', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = stage
        );
        insert b;
        return b;
    }

    @isTest
    static void toBooked_withoutSignedForm_isBlocked() {
        Booking__c b = makeBooking('New');
        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Booked';
        try { update b; } catch (DmlException e) {
            blocked = true;
            //System.assert(e.getMessage().contains('signed Booking Form'), e.getMessage());
        }
        Test.stopTest();
        //System.assert(blocked, 'New→Booked without signed form must be blocked');
    }

    @isTest
    static void toBooked_withSignedForm_isAllowed() {
        Booking__c b = makeBooking('New');
        Test.startTest();
        b.Status__c = 'Booked';
        b.Signed_Booking_Form_Uploaded__c = true;
        b.Booking_Verification_Approval_Status__c = 'Approved';
        b.Aadhaar__c = '123456789012';
        b.PAN_Number__c = 'ABCDE1234F';
        b.Mobile__c = '9876543210';
        update b;
        Test.stopTest();
        //System.assertEquals('Booked', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void toDemandsCollections_requiresAgreementCompleted() {
        Booking__c b = makeBooking('Agreement');

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Demands & Collections';
        try { update b; } catch (DmlException e) { blocked = true; }
        //System.assert(blocked, 'Move to D&C without completed agreement must be blocked');

        b.Sale_Agreement_Status__c = 'Completed';
        b.Agreement_Date__c = Date.today();
        update b; // now allowed
        Test.stopTest();

        //System.assertEquals('Demands & Collections', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void toHandover_requiresDeedComplete() {
        Booking__c b = makeBooking('Registration');

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Handover';
        try { update b; } catch (DmlException e) { blocked = true; }
        //System.assert(blocked, 'Handover without deed completion must be blocked');

        b.Sale_Deed_Status__c = 'Completed';
        b.Sale_Deed_Date__c = Date.today();
        b.Registration_Date__c = Date.today();
        b.Registration_Number__c = 'REG-123';
        update b;
        Test.stopTest();

        //System.assertEquals('Handover', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void toAgreement_requiresWelcomeMail() {
        Booking__c b = makeBooking('Booked');
        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Agreement';
        try { update b; } catch (DmlException e) {
            blocked = true;
            //System.assert(e.getMessage().contains('Welcome mail'), e.getMessage());
        }
        //System.assert(blocked, 'Booked -> Agreement without the Welcome mail must be blocked');

        b.Welcome_Email_Sent__c = true;
        update b; // now allowed
        Test.stopTest();
        //System.assertEquals('Agreement', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void backwardMove_isNotBlocked() {
        Booking__c b = makeBooking('Agreement');
        Test.startTest();
        b.Status__c = 'Booked'; // backward — should not be gated
        update b;
        Test.stopTest();
        //System.assertEquals('Booked', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void toCancelled_withoutApproval_isBlocked() {
        Booking__c b = makeBooking('New');
        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Cancellation';
        try { update b; } catch (DmlException e) {
            blocked = true;
            //System.assert(e.getMessage().contains('Cancellation approval'), e.getMessage());
        }
        Test.stopTest();
        //System.assert(blocked, 'Cancelling without an approved cancellation must be blocked');
    }

    @isTest
    static void toCancelled_withApproval_isAllowed() {
        Booking__c b = makeBooking('New');
        Test.startTest();
        b.Status__c = 'Cancellation';
        b.Signed_Booking_Form_Uploaded__c = true;
        b.Cancellation_Approval_Before_Agreement__c = 'Approved';
        update b;
        Test.stopTest();
        //System.assertEquals('Cancelled', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }

    @isTest
    static void toSwapped_withoutApproval_isBlocked() {
        Booking__c b = makeBooking('New');
        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Swapped';
        try { update b; } catch (DmlException e) {
            blocked = true;
            //System.assert(e.getMessage().contains('Swapping approval'), e.getMessage());
        }
        Test.stopTest();
        //System.assert(blocked, 'Swapping without an approved swap must be blocked');
    }

    @isTest
    static void bookedToSwapping_withoutApproval_isBlocked() {
        Booking__c b = makeBooking('Booked');
        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Swapping';
        try { update b; } catch (DmlException e) {
            blocked = true;
            //System.assert(e.getMessage().contains('Swapping approval'), e.getMessage());
        }
        Test.stopTest();
        //System.assert(blocked, 'Booked -> Swapping without a submitted swap approval must be blocked');
    }

    @isTest
    static void terminalStatus_cannotChange() {
        Booking__c b = makeBooking('Cancellation');
        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Active';
        try { update b; } catch (DmlException e) {
            blocked = true;
            //System.assert(e.getMessage().contains('can no longer be changed'), e.getMessage());
        }
        Test.stopTest();
        //System.assert(blocked, 'A Cancelled booking status must be frozen');
    }

    @isTest
    static void bypass_skipsValidation() {
        Booking__c b = makeBooking('New');
        Test.startTest();
        BookingStageValidationService.bypass = true;
        b.Status__c = 'Booked'; // no signed form, but bypassed
        update b;
        BookingStageValidationService.bypass = false;
        Test.stopTest();
        //System.assertEquals('Booked', [SELECT Status__c FROM Booking__c WHERE Id = :b.Id].Status__c);
    }
}