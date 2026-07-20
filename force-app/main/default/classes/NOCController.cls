/**
 * @description Controller for the Capri NOC generator LWC (BRD §7.40).
 *
 *              Lets the CRM Executive raise a No-Objection Certificate for a booking's unit
 *              with a predefined mail body and the option to attach the unit's prior
 *              cancellations and swaps. The NOC is created in Pending approval state routed to
 *              the booking's CRM Manager; once approved it can be sent to the applicants.
 * @author System
 */
public with sharing class NOCController {

    // ============================================================================
    //  >>> SET THE NOC APPROVAL NAME HERE <<<
    //  Create the approval on the NOC object and put its Name here. It matches either:
    //    • the API/Developer Name of a standard Approval Process built on NOC__c
    //      (Setup > Approval Processes), OR
    //    • the "Process Label" of an Approval Configuration for NOC__c
    //      (Post Sales Admin > Approval Config).
    //  When a NOC is generated it is submitted to that approval and routed to the
    //  booking's CRM Manager (filled into the Approver 1 user lookup). (BUG-0655)
    // ============================================================================
    private static final String NOC_APPROVAL_NAME = 'NOC_Approval';

    // ─── Wrappers ────────────────────────────────────────────────────────────────

    public class HistoryItem {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String detail;
    }

    public class NOCContext {
        @AuraEnabled public Id bookingId;
        @AuraEnabled public Id unitId;
        @AuraEnabled public String unitName;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String applicantEmail;
        @AuraEnabled public String defaultMailBody;
        @AuraEnabled public List<HistoryItem> cancellations;
        @AuraEnabled public List<HistoryItem> swaps;
        @AuraEnabled public List<NOCSummary> existingNOCs;
    }

    public class NOCSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String nocType;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Boolean sent;
    }

    // ─── Read ────────────────────────────────────────────────────────────────────

    /**
     * @description Loads everything the NOC screen needs for a booking: unit + applicant
     *              details, the unit's prior cancellations and swaps, a predefined mail body
     *              and any NOCs already raised.
     */
    @AuraEnabled(cacheable=true)
    public static NOCContext getNOCContext(Id bookingId) {
        if (bookingId == null) {
            throw new AuraHandledException('Booking ID is required.');
        }

        List<Booking__c> bookings = [
            SELECT Id, Name, Plot__c, Plot__r.Name, First_Applicant_Name__c, Email__c
            FROM Booking__c WHERE Id = :bookingId LIMIT 1
        ];
        if (bookings.isEmpty()) {
            throw new AuraHandledException('Booking not found.');
        }
        Booking__c b = bookings[0];

        NOCContext ctx = new NOCContext();
        ctx.bookingId = b.Id;
        ctx.unitId = b.Plot__c;
        ctx.unitName = b.Plot__r != null ? b.Plot__r.Name : null;
        ctx.applicantName = b.First_Applicant_Name__c;
        ctx.applicantEmail = b.Email__c;
        ctx.cancellations = new List<HistoryItem>();
        ctx.swaps = new List<HistoryItem>();
        ctx.existingNOCs = new List<NOCSummary>();

        // Prior cancellations for this unit (excluding the current booking).
        if (b.Plot__c != null) {
            for (Booking__c c : [
                SELECT Id, Name, First_Applicant_Name__c, Cancellation_Date__c, Cancellation_Reason__c
                FROM Booking__c
                WHERE Plot__c = :b.Plot__c
                AND Id != :b.Id
                AND (Status__c = 'Cancellation')
                ORDER BY Cancellation_Date__c DESC NULLS LAST
            ]) {
                HistoryItem hi = new HistoryItem();
                hi.recordId = c.Id;
                hi.name = c.Name;
                hi.detail = 'Cancelled'
                    + (c.Cancellation_Date__c != null ? ' on ' + c.Cancellation_Date__c.format() : '')
                    + (String.isNotBlank(c.Cancellation_Reason__c) ? ' — ' + c.Cancellation_Reason__c : '');
                ctx.cancellations.add(hi);
            }

            // Swaps that touched this unit.
            for (Swap_History__c s : [
                SELECT Id, Name, Swap_Date__c, Swap_Reason__c, Old_Plot__c, New_Plot__c
                FROM Swap_History__c
                WHERE Old_Plot__c = :b.Plot__c OR New_Plot__c = :b.Plot__c
                ORDER BY Swap_Date__c DESC NULLS LAST
            ]) {
                HistoryItem hi = new HistoryItem();
                hi.recordId = s.Id;
                hi.name = s.Name;
                hi.detail = 'Swap'
                    + (s.Swap_Date__c != null ? ' on ' + s.Swap_Date__c.format() : '')
                    + (String.isNotBlank(s.Swap_Reason__c) ? ' — ' + s.Swap_Reason__c : '');
                ctx.swaps.add(hi);
            }
        }

        // Existing NOCs for this booking.
        for (NOC__c n : [
            SELECT Id, Name, NOC_Type__c, Approval_Status__c, Sent_Date__c
            FROM NOC__c WHERE Booking__c = :b.Id ORDER BY CreatedDate DESC
        ]) {
            NOCSummary ns = new NOCSummary();
            ns.id = n.Id;
            ns.name = n.Name;
            ns.nocType = n.NOC_Type__c;
            ns.approvalStatus = n.Approval_Status__c;
            ns.sent = n.Sent_Date__c != null;
            ctx.existingNOCs.add(ns);
        }

        ctx.defaultMailBody = buildDefaultBody(ctx);
        return ctx;
    }

    private static String buildDefaultBody(NOCContext ctx) {
        String name = String.isNotBlank(ctx.applicantName) ? ctx.applicantName : 'Sir/Madam';
        String unit = String.isNotBlank(ctx.unitName) ? ctx.unitName : 'the unit';
        return 'Dear ' + name + ',\n\n'
            + 'This is to certify that we have no objection with respect to unit ' + unit
            + '. This No-Objection Certificate is issued at your request for the purpose of '
            + 'mortgage / registration formalities.\n\n'
            + 'Regards,\nAnanda Homes';
    }

    // ─── Write ───────────────────────────────────────────────────────────────────

    /**
     * @description Creates a NOC in Pending approval state for the CRM Manager.
     * @param bookingId           Booking the NOC is for
     * @param nocType             NOC_Type__c picklist value (e.g. 'Capri NOC')
     * @param mailBody            Editable mail body
     * @param cancellationIds     Selected prior-cancellation Booking ids (first is linked)
     * @param swapIds             Selected Swap_History ids (first is linked)
     * @return The created NOC__c Id
     */
    @AuraEnabled
    public static Id createNOC(
        Id bookingId, String nocType, String mailBody,
        List<Id> cancellationIds, List<Id> swapIds
    ) {
        if (bookingId == null) throw new AuraHandledException('Booking ID is required.');
        if (String.isBlank(nocType)) throw new AuraHandledException('NOC Type is required.');

        List<Booking__c> bookings = [
            SELECT Id, Plot__c, CRM_Manager__c FROM Booking__c WHERE Id = :bookingId LIMIT 1
        ];
        if (bookings.isEmpty()) throw new AuraHandledException('Booking not found.');
        Booking__c b = bookings[0];

        // The NOC is approved by the booking's CRM Manager (Approver 1). Without one there is
        // no one to route the approval to — fail fast with a clear message (BUG-0655).
        if (b.CRM_Manager__c == null) {
            throw new AuraHandledException(
                'Cannot submit the NOC for approval: no CRM Manager is assigned on the booking. '
                + 'Set the booking\'s CRM Manager and try again.'
            );
        }

        NOC__c noc = new NOC__c();
        noc.Booking__c = bookingId;
        noc.Plot__c = b.Plot__c;
        noc.NOC_Type__c = nocType;
        noc.Mail_Body__c = appendReferences(mailBody, cancellationIds, swapIds);
        noc.Approval_Status__c = 'Pending';
        noc.Approver_1__c = b.CRM_Manager__c;
        noc.Generated_Date__c = Date.today();
        if (cancellationIds != null && !cancellationIds.isEmpty()) {
            noc.Related_Cancellation_Booking__c = cancellationIds[0];
        }
        if (swapIds != null && !swapIds.isEmpty()) {
            noc.Related_Swap_History__c = swapIds[0];
        }

        insert noc;

        // Submit the NOC to the config-driven approval engine so an approval record is actually
        // created and routed to the approver (BUG-0655).
        submitNocForApproval(noc.Id);

        return noc.Id;
    }

    /**
     * @description Puts the generated NOC into the approval flow. The NOC is created with
     *              Approval_Status__c = Pending and Approver_1__c = the booking's CRM Manager,
     *              which is the routing the approval you build on the NOC object uses.
     *
     *              If an active Approval Configuration exists for NOC__c, the config-driven engine
     *              is used to submit it; otherwise this no-ops and the Pending + Approver gate
     *              stands (the approval you create in the org drives it from there). Failures are
     *              surfaced so a NOC is never left silently un-submitted.
     */
    private static void submitNocForApproval(Id nocId) {
        List<Approval_Configuration__c> configs = [
            SELECT Id FROM Approval_Configuration__c
            WHERE Process_Label__c = :NOC_APPROVAL_NAME AND Is_Active__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            configs = [
                SELECT Id FROM Approval_Configuration__c
                WHERE Object_API_Name__c = 'NOC__c' AND Is_Active__c = true
                LIMIT 1
            ];
        }
        if (configs.isEmpty()) {
            return; // No config engine set up — the Pending + Approver gate stands.
        }

        try {
            DynamicApprovalService.submitForApproval(nocId, configs[0].Id, 'NOC submitted for approval');
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(
                'The NOC was generated but could not be submitted for approval: ' + e.getMessage()
                + ' Please check the NOC approval configuration and that the booking has a '
                + 'CRM Manager assigned.'
            );
        }
    }

    /**
     * @description Appends the full list of selected cancellation/swap references to the
     *              mail body so multi-selection is preserved even though the object holds
     *              only a single primary lookup for each.
     */
    private static String appendReferences(String body, List<Id> cancellationIds, List<Id> swapIds) {
        String result = body != null ? body : '';
        List<String> refs = new List<String>();

        if (cancellationIds != null && !cancellationIds.isEmpty()) {
            List<String> names = new List<String>();
            for (Booking__c c : [SELECT Name FROM Booking__c WHERE Id IN :cancellationIds]) {
                names.add(c.Name);
            }
            if (!names.isEmpty()) refs.add('Related cancellations: ' + String.join(names, ', '));
        }
        if (swapIds != null && !swapIds.isEmpty()) {
            List<String> names = new List<String>();
            for (Swap_History__c s : [SELECT Name FROM Swap_History__c WHERE Id IN :swapIds]) {
                names.add(s.Name);
            }
            if (!names.isEmpty()) refs.add('Related swaps: ' + String.join(names, ', '));
        }

        if (!refs.isEmpty()) {
            result += '\n\n---\n' + String.join(refs, '\n');
        }
        return result;
    }

    /**
     * @description Sends an approved NOC to the booking applicant(s). Only permitted once the
     *              NOC has been approved by the CRM Manager (BRD §7.40). The booking owner is
     *              intentionally not copied, consistent with the receipt-email rule.
     * @param nocId NOC to send
     */
    @AuraEnabled
    public static void sendNOC(Id nocId) {
        if (nocId == null) throw new AuraHandledException('NOC ID is required.');

        List<NOC__c> nocs = [
            SELECT Id, Name, NOC_Type__c, Approval_Status__c, Mail_Body__c, Sent_Date__c,
                   Booking__r.Email__c, Booking__r.First_Applicant_Name__c, Booking__r.Name
            FROM NOC__c WHERE Id = :nocId LIMIT 1
        ];
        if (nocs.isEmpty()) throw new AuraHandledException('NOC not found.');
        NOC__c noc = nocs[0];

        if (noc.Approval_Status__c != 'Approved') {
            throw new AuraHandledException('NOC can only be sent after CRM Manager approval.');
        }
        if (noc.Booking__r == null || String.isBlank(noc.Booking__r.Email__c)) {
            throw new AuraHandledException('No applicant email address on the booking.');
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ noc.Booking__r.Email__c });
        email.setSubject(noc.NOC_Type__c + ' - ' + noc.Booking__r.Name);
        String body = noc.Mail_Body__c != null ? noc.Mail_Body__c : '';
        email.setHtmlBody(body.replace('\n', '<br/>'));
        email.setSaveAsActivity(true);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);

        update new NOC__c(Id = noc.Id, Sent_Date__c = Date.today());
    }
}