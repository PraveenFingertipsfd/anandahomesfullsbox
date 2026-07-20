/**
 * @description Test class for AutoDemandSchedulable
 */
@isTest
private class AutoDemandSchedulableTest {

    @isTest
    static void execute_schedulesBatch() {
        Test.startTest();
        String jobId = System.schedule(
            'Test AutoDemandSchedulable',
            '0 0 0 1 1 ? 2099',
            new AutoDemandSchedulable()
        );
        Test.stopTest();

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, jobs.size(), 'Scheduled job should exist');
    }
}