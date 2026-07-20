/**
 * @description One-call bootstrapper for all Post-Sales scheduled jobs. Schedulable
 *              classes ship in the package but a deployment does not start them — this
 *              class registers the daily/hourly CRON jobs in a single call.
 *
 *              Run once after deployment (Execute Anonymous, or the
 *              "Schedule Post-Sales Jobs" GitHub Actions step):
 *                  PostSalesJobScheduler.scheduleAll();
 *
 *              Re-running is safe: each job's existing schedule is aborted and
 *              recreated, so the cadence is always brought in line with this class.
 * @author System
 */
public with sharing class PostSalesJobScheduler {

    /**
     * @description Job definitions: friendly name -> CRON expression. Edit the CRON
     *              here to change cadence org-wide.
     */
    @TestVisible
    private static Map<String, String> jobCron = new Map<String, String>{
        'PostSales - Demand Reminders'      => '0 0 8 * * ?',   // daily 08:00
        'PostSales - Interest Calculation'  => '0 30 0 * * ?',  // daily 00:30
        'PostSales - Auto Demand'           => '0 0 1 * * ?',   // daily 01:00
        'PostSales - Complaint Escalation'  => '0 0 * * * ?',   // hourly
        'PostSales - Snag Escalation'       => '0 15 * * * ?'   // hourly at :15
    };

    /**
     * @description Schedules (or reschedules) every Post-Sales job.
     * @return A human-readable summary of what was scheduled.
     */
    public static String scheduleAll() {
        List<String> done = new List<String>();

        done.add(scheduleOne('PostSales - Demand Reminders', new DemandReminderSchedulable()));
        done.add(scheduleOne('PostSales - Interest Calculation', new InterestCalculationSchedulable()));
        done.add(scheduleOne('PostSales - Auto Demand', new AutoDemandSchedulable()));
        

        return 'Scheduled ' + done.size() + ' job(s):\n• ' + String.join(done, '\n• ');
    }

    /**
     * @description Aborts any existing job with the given name then schedules the
     *              supplied Schedulable using the configured CRON.
     */
    private static String scheduleOne(String jobName, Schedulable job) {
        abortExisting(jobName);
        String cron = jobCron.containsKey(jobName) ? jobCron.get(jobName) : '0 0 8 * * ?';
        try {
            Id jobId = System.schedule(jobName, cron, job);
            return jobName + ' (' + cron + ') [' + jobId + ']';
        } catch (Exception e) {
            return jobName + ' FAILED: ' + e.getMessage();
        }
    }

    /**
     * @description Aborts any scheduled CronTrigger that shares this name so the
     *              re-schedule does not hit a duplicate-name error.
     */
    private static void abortExisting(String jobName) {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ];
        for (CronTrigger ct : existing) {
            try {
                System.abortJob(ct.Id);
            } catch (Exception e) {
                System.debug('Could not abort job ' + jobName + ': ' + e.getMessage());
            }
        }
    }
}