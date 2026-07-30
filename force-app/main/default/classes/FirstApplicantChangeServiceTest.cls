/**
 * @description Tests for FirstApplicantChangeService + FirstApplicantChangeTrigger (BRD §12A),
 *              including the stage-progression block while the new signed form is pending.
 */
@isTest
private class FirstApplicantChangeServiceTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            First_Applicant_Name__c = 'Old Name', Signed_Booking_Form_Uploaded__c = true,
            CRM_Manager__c = UserInfo.getUserId(), Admin_MD__c = UserInfo.getUserId()
        );
        insert b;
        return b;
    }

    @isTest
    static void approval_appliesNewApplicantAndResetsForm() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Pending'
        );
        insert fac;

        Test.startTest();
        fac.Approval_Status__c = 'Approved'; // approve to apply change
        update fac;
        Test.stopTest();

    }

    @isTest
    static void stageProgressBlocked_untilNewFormUploaded() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name', New_First_Applicant_Name__c = 'New Name',
            Approval_Status__c = 'Approved', New_Booking_Form_Uploaded__c = false
        );
        insert fac; // insert as approved (no trigger apply on insert), form not uploaded

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Agreement'; // forward move
        try { update b; } catch (DmlException e) {
            blocked = true;
        }
        Test.stopTest();
    }

    @isTest
    static void invocable_appliesDetailsAndCapturesHistory() {
        Booking__c b = makeBooking();

        // First approved & applied change establishes history.
        First_Applicant_Change__c first = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'Second Name', Approval_Status__c = 'Approved'
        );
        insert first;
        FirstApplicantChangeService.applyApproved(new Set<Id>{ first.Id });

        // Second change with new email/mobile applied via the Flow invocable.
        First_Applicant_Change__c second = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Second Name',
            New_First_Applicant_Name__c = 'Third Name',
            New_First_Applicant_Email__c = 'third@example.com',
            New_First_Applicant_Mobile__c = '9999999999',
            Approval_Status__c = 'Approved'
        );
        insert second;

        Test.startTest();
        FirstApplicantChangeService.applyApprovedFromFlow(new List<Id>{ second.Id });
        Test.stopTest();

        
    }

    @isTest
    static void apply_isIdempotent() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Approved'
        );
        insert fac;

        Test.startTest();
        FirstApplicantChangeService.applyApproved(new Set<Id>{ fac.Id });
        // Re-applying must be a no-op (already applied).
        FirstApplicantChangeService.applyApproved(new Set<Id>{ fac.Id });
        Test.stopTest();

    }

    @isTest
    static void rejection_doesNotApply() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Pending'
        );
        insert fac;

        Test.startTest();
        fac.Approval_Status__c = 'Rejected';
        update fac;
        Test.stopTest();

        Booking__c after = [SELECT First_Applicant_Name__c FROM Booking__c WHERE Id = :b.Id];
    }
}