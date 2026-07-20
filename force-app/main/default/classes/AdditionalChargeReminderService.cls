/**
 * @description Reminder engine for Additional Charges (BRD §13.1 / §81). Additional charges
 *              get ONLY a 1st and 2nd reminder — no interest, no termination mail and no unit
 *              unblocking. Reminder dates are seeded from the Demand Date when the charge is
 *              demanded, and the daily job sends the due reminders.
 * @author System
 */
public with sharing class AdditionalChargeReminderService {

    // Defaults when the project does not configure reminder gaps.
    @TestVisible private static final Integer DEFAULT_REMINDER_1_DAYS = 15;
    @TestVisible private static final Integer DEFAULT_REMINDER_2_DAYS = 30;

    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Paid', 'Cancelled' };

    // ==================== DATE SEEDING (trigger) ====================

    /**
     * @description Seeds Reminder 1/2 dates (and Due Date) when a charge becomes demanded.
     *              Called from AdditionalChargeTrigger (before insert/update).
     */
    public static void populateReminderDates(List<Additional_Charge__c> newList, Map<Id, Additional_Charge__c> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        // Find charges that just became demanded and have no reminder dates yet.
        List<Additional_Charge__c> toSeed = new List<Additional_Charge__c>();
        Set<Id> bookingIds = new Set<Id>();
        for (Additional_Charge__c c : newList) {
            Boolean justDemanded = c.Is_Demanded__c == true
                && (oldMap == null || oldMap.get(c.Id) == null || oldMap.get(c.Id).Is_Demanded__c != true);
            if (justDemanded && c.Reminder_1_Date__c == null) {
                toSeed.add(c);
                if (c.Booking__c != null) bookingIds.add(c.Booking__c);
            }
        }
        if (toSeed.isEmpty()) return;

        Map<Id, Booking__c> bookings = new Map<Id, Booking__c>([
            SELECT Id, Project__r.Reminder_1_Days__c, Project__r.Reminder_2_Days__c
            FROM Booking__c WHERE Id IN :bookingIds
        ]);

        for (Additional_Charge__c c : toSeed) {
            Date anchor = c.Demand_Date__c != null ? c.Demand_Date__c : Date.today();
            Integer d1 = DEFAULT_REMINDER_1_DAYS;
            Integer d2 = DEFAULT_REMINDER_2_DAYS;
            Booking__c b = bookings.get(c.Booking__c);
            if (b != null && b.Project__c != null) {
                if (b.Project__r.Reminder_1_Days__c != null && b.Project__r.Reminder_1_Days__c > 0) {
                    d1 = Integer.valueOf(b.Project__r.Reminder_1_Days__c);
                }
                if (b.Project__r.Reminder_2_Days__c != null && b.Project__r.Reminder_2_Days__c > 0) {
                    d2 = Integer.valueOf(b.Project__r.Reminder_2_Days__c);
                }
            }
            c.Reminder_1_Date__c = anchor.addDays(d1);
            c.Reminder_2_Date__c = anchor.addDays(d2);
            if (c.Due_Date__c == null) c.Due_Date__c = anchor.addDays(d2);
        }
    }

    // ==================== REMINDER PROCESSING (scheduled) ====================

    /**
     * @description Sends due 1st and 2nd additional-charge reminders. Returns the count sent.
     */
    public static Integer processDueReminders() {
        Date today = Date.today();
        Integer sent = 0;

        List<Additional_Charge__c> charges = [
            SELECT Id, Name, Charge_Name__c, Amount__c, GST_Amount__c, Amount_Paid__c,
                   Due_Date__c, Status__c,
                   Reminder_1_Date__c, Reminder_1_Sent__c,
                   Reminder_2_Date__c, Reminder_2_Sent__c,
                   Booking__c, Booking__r.Name, Booking__r.Email__c,
                   Booking__r.First_Applicant_Name__c, Booking__r.OwnerId
            FROM Additional_Charge__c
            WHERE Reminders_Disabled__c = false
            AND Is_Demanded__c = true
            AND Status__c NOT IN :CLOSED_STATUSES
            AND ((Reminder_1_Date__c <= :today AND Reminder_1_Sent__c = false)
                 OR (Reminder_2_Date__c <= :today AND Reminder_2_Sent__c = false))
            LIMIT 200
        ];
        if (charges.isEmpty()) return 0;

        Set<Id> ownerIds = new Set<Id>();
        for (Additional_Charge__c c : charges) {
            if (c.Booking__r != null && c.Booking__r.OwnerId != null) ownerIds.add(c.Booking__r.OwnerId);
        }
        Map<Id, String> ownerEmails = getUserEmails(ownerIds);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Additional_Charge__c> toUpdate = new List<Additional_Charge__c>();

        for (Additional_Charge__c c : charges) {
            Decimal pending = pendingOf(c);
            if (pending <= 0) continue;
            if (c.Booking__r == null || String.isBlank(c.Booking__r.Email__c)) continue;

            String which;
            if (c.Reminder_1_Date__c != null && c.Reminder_1_Date__c <= today && c.Reminder_1_Sent__c != true) {
                which = '1st';
                c.Reminder_1_Sent__c = true;
                c.Reminder_1_Sent_Date__c = System.now();
            } else if (c.Reminder_2_Date__c != null && c.Reminder_2_Date__c <= today && c.Reminder_2_Sent__c != true) {
                which = '2nd (final)';
                c.Reminder_2_Sent__c = true;
                c.Reminder_2_Sent_Date__c = System.now();
            } else {
                continue;
            }

            String ownerEmail = c.Booking__r.OwnerId != null ? ownerEmails.get(c.Booking__r.OwnerId) : null;
            emails.add(buildEmail(c, pending, which, ownerEmail));
            toUpdate.add(c);
            sent++;
        }

        if (!emails.isEmpty()) {
            try { Messaging.sendEmail(emails, false); }
            catch (Exception e) { System.debug('AdditionalChargeReminderService email error: ' + e.getMessage()); }
        }
        if (!toUpdate.isEmpty()) update toUpdate;

        return sent;
    }

    // ==================== HELPERS ====================

    private static Decimal pendingOf(Additional_Charge__c c) {
        Decimal total = nz(c.Amount__c) + nz(c.GST_Amount__c);
        return total - nz(c.Amount_Paid__c);
    }

    private static Messaging.SingleEmailMessage buildEmail(
        Additional_Charge__c c, Decimal pending, String which, String ownerEmail
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ c.Booking__r.Email__c });
        if (String.isNotBlank(ownerEmail)) {
            email.setCcAddresses(new List<String>{ ownerEmail });
        }
        String charge = String.isNotBlank(c.Charge_Name__c) ? c.Charge_Name__c : 'Additional Charge';
        email.setSubject(which + ' Reminder - ' + charge + ' - ' + c.Booking__r.Name);
        String name = c.Booking__r.First_Applicant_Name__c != null ? c.Booking__r.First_Applicant_Name__c : 'Customer';
        String body = '<p>Dear ' + name + ',</p>'
            + '<p>This is a <strong>' + which + ' reminder</strong> for the additional charge '
            + '<strong>' + charge + '</strong> on booking ' + c.Booking__r.Name + '.</p>'
            + '<p>Amount payable: ' + PostSalesConstants.formatCurrency(pending) + '</p>'
            + (c.Due_Date__c != null ? '<p>Due date: ' + c.Due_Date__c.format() + '</p>' : '')
            + '<p>Kindly arrange the payment at the earliest.</p>'
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

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}