/**
 * @description Controller for the First Applicant Change LWC (BRD §12A). Lets the CRM
 *              Executive raise a request to replace the first applicant on a booking (without
 *              changing the unit), routed for approval to the CRM Manager (L1) and Admin/MD (L2).
 * @author System
 */
public without sharing class FirstApplicantChangeController {

    // ============================================================================
    //  >>> SET THE FIRST APPLICANT CHANGE APPROVAL NAME HERE <<<
    //  Create the approval on the First_Applicant_Change__c object and put its Name here.
    //  It matches either:
    //    • the API/Developer Name of a standard Approval Process built on
    //      First_Applicant_Change__c (Setup > Approval Processes), OR
    //    • the "Process Label" of an Approval Configuration for First_Applicant_Change__c.
    //  When a request is created it is submitted to that approval and routed to the
    //  booking's CRM Manager (Approver 1) / Admin-MD (Approver 2).
    // ============================================================================
    private static final String FAC_APPROVAL_NAME = 'First Applicant Change Approval';

    public class FACContext {
        @AuraEnabled public Id bookingId;
        @AuraEnabled public String currentApplicant;
        @AuraEnabled public Boolean signedFormUploaded;
        @AuraEnabled public List<FACSummary> changes;
    }

    public class FACSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String oldApplicant;
        @AuraEnabled public String newApplicant;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Boolean newFormUploaded;
    }

    @AuraEnabled(cacheable=true)
    public static FACContext getContext(Id bookingId) {
        if (bookingId == null) throw new AuraHandledException('Booking ID is required.');

        List<Booking__c> bookings = [
            SELECT Id, First_Applicant_Name__c, Signed_Booking_Form_Uploaded__c
            FROM Booking__c WHERE Id = :bookingId LIMIT 1
        ];
        if (bookings.isEmpty()) throw new AuraHandledException('Booking not found.');

        FACContext ctx = new FACContext();
        ctx.bookingId = bookingId;
        ctx.currentApplicant = bookings[0].First_Applicant_Name__c;
        ctx.signedFormUploaded = bookings[0].Signed_Booking_Form_Uploaded__c == true;
        ctx.changes = new List<FACSummary>();

        for (First_Applicant_Change__c fac : [
            SELECT Id, Name, Old_First_Applicant__c, New_First_Applicant_Name__c,
                   Approval_Status__c, New_Booking_Form_Uploaded__c
            FROM First_Applicant_Change__c
            WHERE Booking__c = :bookingId
            ORDER BY CreatedDate DESC
        ]) {
            FACSummary s = new FACSummary();
            s.id = fac.Id;
            s.name = fac.Name;
            s.oldApplicant = fac.Old_First_Applicant__c;
            s.newApplicant = fac.New_First_Applicant_Name__c;
            s.approvalStatus = fac.Approval_Status__c;
            s.newFormUploaded = fac.New_Booking_Form_Uploaded__c == true;
            ctx.changes.add(s);
        }
        return ctx;
    }

    /**
     * @description Creates a Pending First Applicant Change routed to CRM Manager (Approver 1)
     *              and Admin/MD (Approver 2). Overload without new email/mobile.
     *              Not @AuraEnabled (Apex forbids overloaded @AuraEnabled methods); the
     *              LWC uses the 5-arg version below.
     */
    public static Id createChange(Id bookingId, String newApplicantName, String reason) {
        return createChange(bookingId, newApplicantName, null, null, reason);
    }

    /**
     * @description Creates a Pending First Applicant Change routed to CRM Manager (Approver 1)
     *              and Admin/MD (Approver 2).
     */
    @AuraEnabled
    public static Id createChange(Id bookingId, String newApplicantName, String newEmail, String newMobile, String reason) {
        if (bookingId == null) throw new AuraHandledException('Booking ID is required.');
        if (String.isBlank(newApplicantName)) throw new AuraHandledException('New first applicant name is required.');

        List<Booking__c> bookings = [
            SELECT Id, First_Applicant_Name__c, Email__c, Mobile__c, CRM_Manager__c, Admin_MD__c
            FROM Booking__c WHERE Id = :bookingId LIMIT 1
        ];
        if (bookings.isEmpty()) throw new AuraHandledException('Booking not found.');
        Booking__c b = bookings[0];

        // The request is approved by the booking's CRM Manager (Approver 1). Without one there is
        // no one to route the approval to — fail fast with a clear message.
        if (b.CRM_Manager__c == null) {
            throw new AuraHandledException(
                'Cannot submit the First Applicant Change for approval: no CRM Manager is assigned '
                + 'on the booking. Set the booking\'s CRM Manager and try again.'
            );
        }

        // Insert the request and snapshot the current details, then submit it to the approval built
        // on the First_Applicant_Change__c object (routed to the CRM Manager / Admin-MD). On approval
        // FirstApplicantChangeService swaps the booking to the new applicant.
        First_Applicant_Change__c fac = new First_Applicant_Change__c();
        fac.Booking__c = bookingId;
        fac.Old_First_Applicant__c = b.First_Applicant_Name__c;
        fac.Old_Email__c = b.Email__c;
        fac.Old_Mobile__c = b.Mobile__c;
        fac.New_First_Applicant_Name__c = newApplicantName;
        fac.New_First_Applicant_Email__c = newEmail;
        fac.New_First_Applicant_Mobile__c = newMobile;
        fac.Reason__c = reason;
        fac.Approval_Status__c = 'Pending';
        fac.Approver_1__c = b.CRM_Manager__c;
        fac.Approver_2__c = b.Admin_MD__c;

        insert fac;

        submitFacForApproval(fac.Id);
        return fac.Id;
    }

    /**
     * @description Puts the request into the approval flow. It is created with Approval_Status__c
     *              = Pending, Approver_1__c = CRM Manager and Approver_2__c = Admin-MD, which is the
     *              routing the approval you build on the First_Applicant_Change__c object uses.
     *
     *              If an active Approval Configuration exists for First_Applicant_Change__c, the
     *              config-driven engine submits it; otherwise this no-ops and the Pending + Approver
     *              gate stands (the approval you create in the org drives it from there). Failures
     *              are surfaced so a request is never left silently un-submitted.
     */
    private static void submitFacForApproval(Id facId) {
        List<Approval_Configuration__c> configs = [
            SELECT Id FROM Approval_Configuration__c
            WHERE Process_Label__c = :FAC_APPROVAL_NAME AND Is_Active__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            configs = [
                SELECT Id FROM Approval_Configuration__c
                WHERE Object_API_Name__c = 'First_Applicant_Change_Approval' AND Is_Active__c = true
                LIMIT 1
            ];
        }
        if (configs.isEmpty()) {
            return; // No config engine set up — the Pending + Approver gate stands.
        }

        try {
            DynamicApprovalService.submitForApproval(facId, configs[0].Id, 'First Applicant Change submitted for approval');
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(
                'The request was created but could not be submitted for approval: ' + e.getMessage()
                + ' Please check the First Applicant Change approval configuration and that the '
                + 'booking has a CRM Manager assigned.'
            );
        }
    }
}