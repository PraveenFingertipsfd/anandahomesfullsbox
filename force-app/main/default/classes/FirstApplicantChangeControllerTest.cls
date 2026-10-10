/**
 * @description Tests for FirstApplicantChangeController (BRD §12A).
 */
@isTest
private class FirstApplicantChangeControllerTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            First_Applicant_Name__c = 'Old Name', CRM_Manager__c = UserInfo.getUserId(),
            Admin_MD__c = UserInfo.getUserId()
        );
        insert b;
        return b;
    }

    @isTest
    static void createChange_createsPending() {
        Booking__c b = makeBooking();
        Test.startTest();
        Id facId = FirstApplicantChangeController.createChange(b.Id, 'New Name', 'Marriage');
        Test.stopTest();

        First_Applicant_Change__c fac = [
            SELECT Old_First_Applicant__c, New_First_Applicant_Name__c, Reason__c,
                   Approval_Status__c, Approver_1__c, Approver_2__c
            FROM First_Applicant_Change__c WHERE Id = :facId
        ];
        System.assertEquals('Old Name', fac.Old_First_Applicant__c);
        System.assertEquals('New Name', fac.New_First_Applicant_Name__c);
        System.assertEquals('Pending', fac.Approval_Status__c);
        System.assertEquals(UserInfo.getUserId(), fac.Approver_1__c);
        System.assertEquals(UserInfo.getUserId(), fac.Approver_2__c);
    }

    @isTest
    static void getContext_returnsApplicantAndChanges() {
        Booking__c b = makeBooking();
        FirstApplicantChangeController.createChange(b.Id, 'New Name', 'Reason');

        Test.startTest();
        FirstApplicantChangeController.FACContext ctx = FirstApplicantChangeController.getContext(b.Id);
        Test.stopTest();

        System.assertEquals('Old Name', ctx.currentApplicant);
        System.assertEquals(1, ctx.changes.size());
        System.assertEquals('New Name', ctx.changes[0].newApplicant);
    }

    @isTest
    static void validationErrors() {
        Booking__c b = makeBooking();
        Integer errors = 0;
        Test.startTest();
        try { FirstApplicantChangeController.createChange(null, 'X', 'r'); } catch (Exception e) { errors++; }
        try { FirstApplicantChangeController.createChange(b.Id, '', 'r'); } catch (Exception e) { errors++; }
        try { FirstApplicantChangeController.getContext(null); } catch (Exception e) { errors++; }
        Test.stopTest();
        System.assertEquals(3, errors);
    }
}