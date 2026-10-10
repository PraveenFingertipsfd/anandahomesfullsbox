/**
 * @description Notifies all related booking owners when a Construction Milestone is marked
 *              Completed.
 *
 *              BRD 8.43 - 8.44: "When a construction milestone is completed, CRM Manager
 *              updates Milestone Status to Completed and enters completion date. All related
 *              booking owners receive milestone completion notification."
 *
 *              A booking is considered "related" to a completed Construction Milestone when it
 *              has a Payment Schedule line carrying the same Milestone Name and the booking
 *              belongs to the same Project as the milestone (Payment Schedule has no direct
 *              lookup to Construction Milestone in this data model, so name + project is the
 *              correlation used elsewhere for demands).
 *
 *              Each related booking owner receives a bell notification and an email.
 * @author System
 */
public with sharing class MilestoneCompletionNotifier {

    private static final String STATUS_COMPLETED = 'Completed';

    /** @description Test-only: injected CustomNotificationType id (may be fabricated) so the
     *               bell path can be exercised in orgs without the notification type. */
    @TestVisible
    private static Id notificationTypeIdOverrideForTest;

    /**
     * @description Sends completion notifications for every milestone whose status just
     *              changed to Completed.
     * @param newMilestones Trigger.new
     * @param oldMap        Trigger.oldMap
     */
    public static void notifyForCompletedMilestones(
        List<Construction_Milestone__c> newMilestones, Map<Id, Construction_Milestone__c> oldMap
    ) {
        if (newMilestones == null || oldMap == null) return;

        List<Construction_Milestone__c> justCompleted = new List<Construction_Milestone__c>();
        for (Construction_Milestone__c m : newMilestones) {
            Construction_Milestone__c old = oldMap.get(m.Id);
            if (old == null) continue;
            if (STATUS_COMPLETED.equalsIgnoreCase(m.Milestone_Status__c)
                && !STATUS_COMPLETED.equalsIgnoreCase(old.Milestone_Status__c)) {
                justCompleted.add(m);
            }
        }
        if (justCompleted.isEmpty()) return;

        notify(justCompleted);
    }

    /**
     * @description Core notification routine. Bulk-safe.
     * @param milestones Milestones that have just been completed
     */
    public static void notify(List<Construction_Milestone__c> milestones) {
        if (milestones == null || milestones.isEmpty()) return;

        // Correlate milestones to bookings by Project + Milestone Name.
        Set<Id> projectIds = new Set<Id>();
        Set<String> milestoneNames = new Set<String>();
        Map<Id, Construction_Milestone__c> byId = new Map<Id, Construction_Milestone__c>();
        for (Construction_Milestone__c m : milestones) {
            if (m.Project__c != null) projectIds.add(m.Project__c);
            if (String.isNotBlank(m.Milestone_Name__c)) milestoneNames.add(m.Milestone_Name__c);
            byId.put(m.Id, m);
        }
        if (projectIds.isEmpty() || milestoneNames.isEmpty()) return;

        // Bookings (via their payment schedules) that include this milestone in the project.
        // Map booking owner -> set of milestone names completed, for a friendly message.
        Map<Id, Set<String>> bookingToMilestoneNames = new Map<Id, Set<String>>();
        for (Payment_Schedule__c ps : [
            SELECT Booking__c, Milestone_Name__c, Booking__r.OwnerId
            FROM Payment_Schedule__c
            WHERE Booking__c != null
            AND Milestone_Name__c IN :milestoneNames
            AND Booking__r.Project__c IN :projectIds
        ]) {
            if (!bookingToMilestoneNames.containsKey(ps.Booking__c)) {
                bookingToMilestoneNames.put(ps.Booking__c, new Set<String>());
            }
            bookingToMilestoneNames.get(ps.Booking__c).add(ps.Milestone_Name__c);
        }
        if (bookingToMilestoneNames.isEmpty()) return;

        // Resolve booking owners + booking names for the messages.
        Map<Id, Booking__c> bookings = new Map<Id, Booking__c>([
            SELECT Id, Name, OwnerId, Owner.Email, Owner.IsActive
            FROM Booking__c
            WHERE Id IN :bookingToMilestoneNames.keySet()
        ]);

        Id notificationTypeId = getNotificationTypeId();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id bookingId : bookingToMilestoneNames.keySet()) {
            Booking__c b = bookings.get(bookingId);
            if (b == null || b.OwnerId == null) continue;

            String milestoneText = String.join(new List<String>(bookingToMilestoneNames.get(bookingId)), ', ');
            String title = 'Construction Milestone Completed';
            String body = 'Milestone(s) completed for booking ' + b.Name + ': ' + milestoneText + '.';

            // Bell notification (only real, active users).
            if (notificationTypeId != null && String.valueOf(b.OwnerId).startsWith('005')
                && b.Owner != null && b.Owner.IsActive == true) {
                sendBell(notificationTypeId, bookingId, title, body, new Set<String>{ String.valueOf(b.OwnerId) });
            }

            // Email to the active owner with a valid address.
            if (b.Owner != null && b.Owner.IsActive == true && String.isNotBlank(b.Owner.Email)) {
                emails.add(buildEmail(new List<String>{ b.Owner.Email }, title, body));
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception e) {
                System.debug('MilestoneCompletionNotifier: email send failed - ' + e.getMessage());
            }
        }
    }

    // ==================== HELPERS ====================
    @TestVisible
    private static void sendBell(Id typeId, Id targetId, String title, String body, Set<String> recipients) {
        try {
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setTitle(title);
            n.setBody(body);
            n.setNotificationTypeId(typeId);
            n.setTargetId(targetId);
            n.send(recipients);
        } catch (Exception e) {
            System.debug('MilestoneCompletionNotifier: bell send failed - ' + e.getMessage());
        }
    }

    private static Messaging.SingleEmailMessage buildEmail(List<String> toAddresses, String title, String body) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject(title);
        email.setHtmlBody('<p>Hello,</p><p>' + body + '</p><p>Regards,<br/>Post-Sales Team</p>');
        email.setSaveAsActivity(false);
        return email;
    }

    private static Id getNotificationTypeId() {
        if (Test.isRunningTest() && notificationTypeIdOverrideForTest != null) {
            return notificationTypeIdOverrideForTest;
        }

        String devName;
        try {
            devName = System.Label.Approval_Notification_Type;
        } catch (Exception e) {
            devName = 'Approval_Notification';
        }
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :devName LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }
}