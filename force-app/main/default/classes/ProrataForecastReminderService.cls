/**
 * @description Sends the Prorata / Partial "forecast date" reminder to the customer
 *              (BRD §8.4). About a month before a milestone's demand date, the Master Payment
 *              Schedule's Forecast Date (copied onto the booking Payment Schedule line) triggers
 *              a reminder listing the upcoming milestone, the customer-payable Flat and GST
 *              amounts, and the With-GST / Without-GST choice.
 *
 *              Runs daily from DemandReminderSchedulable.
 * @author System
 */
public with sharing class ProrataForecastReminderService {

    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };
    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Paid', 'Completed', 'Waived' };

    /**
     * @description Sends due forecast reminders and returns the count sent.
     */
    public static Integer processDueForecastReminders() {
        Date today = Date.today();
        Integer sent = 0;

        List<Payment_Schedule__c> schedules = [
            SELECT Id, Milestone_Name__c, Forecast_Date__c, Due_Date__c,
                   Customer_Flat_Prorata__c, Customer_GST_Prorata__c, With_GST__c,
                   Booking__c, Booking__r.Name, Booking__r.Email__c,
                   Booking__r.First_Applicant_Name__c, Booking__r.OwnerId,
                   Booking__r.Funding_Type__c
            FROM Payment_Schedule__c
            WHERE Forecast_Date__c <= :today
            AND Forecast_Reminder_Sent__c = false
            AND Customer_Flat_Prorata__c > 0
            AND Demand_Raised__c = false
            AND Status__c NOT IN :CLOSED_STATUSES
            AND Booking__r.Funding_Type__c IN :FUNDING_PRORATA
            LIMIT 200
        ];
        if (schedules.isEmpty()) return 0;

        Set<Id> ownerIds = new Set<Id>();
        for (Payment_Schedule__c ps : schedules) {
            if (ps.Booking__r != null && ps.Booking__r.OwnerId != null) ownerIds.add(ps.Booking__r.OwnerId);
        }
        Map<Id, String> ownerEmails = getUserEmails(ownerIds);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();

        for (Payment_Schedule__c ps : schedules) {
            if (ps.Booking__r == null || String.isBlank(ps.Booking__r.Email__c)) continue;

            String ownerEmail = ps.Booking__r.OwnerId != null ? ownerEmails.get(ps.Booking__r.OwnerId) : null;
            emails.add(buildEmail(ps, ownerEmail));

            ps.Forecast_Reminder_Sent__c = true;
            ps.Forecast_Reminder_Sent_Date__c = System.now();
            toUpdate.add(ps);
            sent++;
        }

        if (!emails.isEmpty()) {
            try { Messaging.sendEmail(emails, false); }
            catch (Exception e) { System.debug('ProrataForecastReminderService email error: ' + e.getMessage()); }
        }
        if (!toUpdate.isEmpty()) update toUpdate;

        return sent;
    }

    private static Messaging.SingleEmailMessage buildEmail(Payment_Schedule__c ps, String ownerEmail) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ ps.Booking__r.Email__c });
        if (String.isNotBlank(ownerEmail)) {
            email.setCcAddresses(new List<String>{ ownerEmail });
        }

        String milestone = String.isNotBlank(ps.Milestone_Name__c) ? ps.Milestone_Name__c : 'upcoming milestone';
        String name = ps.Booking__r.First_Applicant_Name__c != null ? ps.Booking__r.First_Applicant_Name__c : 'Customer';
        Boolean withGst = ps.With_GST__c == true;

        email.setSubject('Upcoming Payment (Prorata) - ' + milestone + ' - ' + ps.Booking__r.Name);

        Decimal custFlat = ps.Customer_Flat_Prorata__c != null ? ps.Customer_Flat_Prorata__c : 0;
        Decimal custGst = ps.Customer_GST_Prorata__c != null ? ps.Customer_GST_Prorata__c : 0;

        String body = '<p>Dear ' + name + ',</p>'
            + '<p>This is an advance reminder that the milestone <strong>' + milestone + '</strong> on booking '
            + ps.Booking__r.Name + ' is due for payment shortly.</p>'
            + '<p>Your payable (Prorata) amounts:</p>'
            + '<ul>'
            + '<li>Flat: ' + PostSalesConstants.formatCurrency(custFlat) + '</li>'
            + '<li>GST: ' + PostSalesConstants.formatCurrency(custGst)
            + (withGst ? ' (billed together with the flat — With GST)' : ' (billed separately — Without GST)') + '</li>'
            + '</ul>'
            + (ps.Due_Date__c != null ? '<p>Requested payment date: ' + ps.Due_Date__c.format() + '</p>' : '')
            + '<p>Please keep the funds ready so the milestone demand can be cleared on time.</p>'
            + '<p>Regards,<br/>Ananda Homes</p>';
        email.setHtmlBody(body);
        email.setSaveAsActivity(true);
        return email;
    }

    private static Map<Id, String> getUserEmails(Set<Id> userIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (userIds == null || userIds.isEmpty()) return result;
        for (User u : [SELECT Id, Email FROM User WHERE Id IN :userIds]) {
            result.put(u.Id, u.Email);
        }
        return result;
    }
}