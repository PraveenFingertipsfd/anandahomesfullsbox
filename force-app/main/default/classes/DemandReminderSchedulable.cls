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

    /** @description Test-only fault injection: when true, each step throws so the
     *               error-handling paths can be exercised. Never set in production code. */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    private class ForcedTestException extends Exception {}

    private static void throwIfForced() {
        if (forceExceptionForTest) {
            throw new ForcedTestException('Forced test exception');
        }
    }

    public void execute(SchedulableContext sc) {
        try {
            throwIfForced();
            DemandReminderService.ProcessingResult result = DemandReminderService.processDueReminders();
            System.debug(result.toLogString());
        } catch (Exception e) {
            System.debug('DemandReminderSchedulable error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        // Additional-charge reminders (1st/2nd only — BRD §13.1).
        try {
            throwIfForced();
            Integer ac = AdditionalChargeReminderService.processDueReminders();
            System.debug('Additional charge reminders sent: ' + ac);
        } catch (Exception e) {
            System.debug('AdditionalChargeReminder error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        // Prorata forecast-date reminders (BRD §8.4).
        try {
            throwIfForced();
            Integer fc = ProrataForecastReminderService.processDueForecastReminders();
            System.debug('Prorata forecast reminders sent: ' + fc);
        } catch (Exception e) {
            System.debug('ProrataForecastReminder error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        // Prorata customer-side demands on the milestone demand date (BRD §8.4).
        try {
            throwIfForced();
            Integer cd = ProrataDemandService.raiseDueCustomerDemands();
            System.debug('Prorata customer demands raised: ' + cd);
        } catch (Exception e) {
            System.debug('ProrataDemand error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}