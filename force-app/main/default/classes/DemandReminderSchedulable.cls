/**
 * @description Schedulable Apex job that runs daily to process demand reminders
 *              and automatic unit unblocking. Reads project-level configuration
 *              to determine reminder timings and actions.
 *
 *              Schedule examples:
 *              - Daily at 8 AM:  System.schedule('Demand Reminders Daily', '0 0 8 * * ?', new DemandReminderSchedulable());
 *              - Every hour:     System.schedule('Demand Reminders Hourly', '0 0 * * * ?', new DemandReminderSchedulable());
 * @author System
 * @date 2026-03-29
 */
public with sharing class DemandReminderSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        try {
            DemandReminderService.ProcessingResult result = DemandReminderService.processDueReminders();
            System.debug(result.toLogString());
        } catch (Exception e) {
            System.debug('DemandReminderSchedulable error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        // Additional-charge reminders (1st/2nd only — BRD §13.1).
        try {
            Integer ac = AdditionalChargeReminderService.processDueReminders();
            System.debug('Additional charge reminders sent: ' + ac);
        } catch (Exception e) {
            System.debug('AdditionalChargeReminder error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        // Prorata forecast-date reminders (BRD §8.4).
        try {
            Integer fc = ProrataForecastReminderService.processDueForecastReminders();
            System.debug('Prorata forecast reminders sent: ' + fc);
        } catch (Exception e) {
            System.debug('ProrataForecastReminder error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        // Prorata customer-side demands on the milestone demand date (BRD §8.4).
        try {
            Integer cd = ProrataDemandService.raiseDueCustomerDemands();
            System.debug('Prorata customer demands raised: ' + cd);
        } catch (Exception e) {
            System.debug('ProrataDemand error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}