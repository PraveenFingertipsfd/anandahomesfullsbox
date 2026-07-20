/**
 * @description Test class for InterestCalculationSchedulable
 */
@isTest
private class InterestCalculationSchedulableTest {

    @isTest
    static void execute_schedulesBatch() {
        Test.startTest();
        String jobId = System.schedule(
            'Test InterestCalculationSchedulable',
            '0 0 0 1 1 ? 2099',
            new InterestCalculationSchedulable()
        );
        Test.stopTest();

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, jobs.size(), 'Scheduled job should exist');
    }
}