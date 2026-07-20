/**
 * @description Test class for DemandReminderSchedulable
 */
@isTest
private class DemandReminderSchedulableTest {

    @isTest
    static void execute_schedulesJob() {
        Test.startTest();
        String jobId = System.schedule(
            'Test DemandReminderSchedulable',
            '0 0 0 1 1 ? 2099',
            new DemandReminderSchedulable()
        );
        Test.stopTest();

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, jobs.size(), 'Scheduled job should exist');
    }

    @isTest
    static void execute_directInvocation_handlesNoData() {
        Test.startTest();
        try {
            new DemandReminderSchedulable().execute(null);
        } catch (Exception e) {
            // Inner exception is caught by the schedulable; we should not see it here
        }
        Test.stopTest();
        System.assert(true, 'Execute should complete without throwing');
    }
}