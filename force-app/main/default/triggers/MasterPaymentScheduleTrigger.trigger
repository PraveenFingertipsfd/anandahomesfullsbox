trigger MasterPaymentScheduleTrigger on Master_Payment_Schedule__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
        Map<Id, Boolean> masterInterestMap = new Map<Id, Boolean>();
        Map<String, Id> projectWithSchedule = new Map<String, Id>();
        Map<Id, String> notificationsToSend = new Map<Id, String>();

        // Process each Master_Payment_Schedule__c record
        for (Master_Payment_Schedule__c master : Trigger.new) {
            Master_Payment_Schedule__c oldMaster = Trigger.oldMap.get(master.Id);

            // Check if the status has changed to 'Completed'
            if (master.Status__c != oldMaster.Status__c && master.Status__c == 'Completed') {
                // Query and update related Payment_Schedule__c records
                List<Payment_Schedule__c> relatedSchedules = [
                    SELECT Id, Payment_Due_Date__c 
                    FROM Payment_Schedule__c 
                    WHERE Master_Payment_Schedule__c = :master.Id
                ];

                for (Payment_Schedule__c schedule : relatedSchedules) {
                    schedule.Payment_Due_Date__c = master.Due_Date__c;
                    schedule.Status__c = 'Completed';
                    schedulesToUpdate.add(schedule);
                }

                // Track project with schedule for notifications
                if (master.Due_Date__c != null) {
                    projectWithSchedule.put(master.Project_Name__c, master.Id);
                }

                // Prepare notification content
                String notificationBody = 'Payment Milestone ' + master.Name +
                    ' for ' + master.Project_Name__c + ' has been completed';
                notificationsToSend.put(master.Id, notificationBody);
            }

            // Track changes in Include_Interest__c
            if (master.Include_Interest__c != oldMaster.Include_Interest__c) {
                masterInterestMap.put(master.Id, master.Include_Interest__c);
            }
        }

        // Update schedules if needed
        if (!schedulesToUpdate.isEmpty()) {
            update schedulesToUpdate;
        }

        // Handle Include_Interest__c updates
        if (!masterInterestMap.isEmpty()) {
            List<Payment_Schedule__c> relatedSchedules = [
                SELECT Id, Include_Interest__c, Master_Payment_Schedule__c
                FROM Payment_Schedule__c
                WHERE Master_Payment_Schedule__c IN :masterInterestMap.keySet()
            ];

            for (Payment_Schedule__c schedule : relatedSchedules) {
                schedule.Include_Interest__c = masterInterestMap.get(schedule.Master_Payment_Schedule__c);
            }

            if (!relatedSchedules.isEmpty()) {
                update relatedSchedules;
            }
        }

        // Send notifications
       /* if (!projectWithSchedule.isEmpty()) {
            List<Booking__c> bookings = [
                SELECT Id, OwnerId 
                FROM Booking__c 
                WHERE Project__c IN :projectWithSchedule.keySet()
            ];

            if (!bookings.isEmpty()) {
                Set<String> userIds = new Set<String>();
                for (Booking__c booking : bookings) {
                    userIds.add(booking.OwnerId);
                }

                for (Id masterId : notificationsToSend.keySet()) {
                    BookingController.sendCustomNotification(
                        userIds,
                        'Master Payment Schedule Update',
                        notificationsToSend.get(masterId),
                        masterId,
                        'Master_Payment_Schedule_Notification'
                    );
                }
            }
        }*/
    }
}