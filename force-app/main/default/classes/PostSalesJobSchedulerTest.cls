/**
 * @description Tests for PostSalesJobScheduler.
 */
@isTest
private class PostSalesJobSchedulerTest {

    @isTest
    static void scheduleAll_registersJobs() {
        Test.startTest();
        String summary = PostSalesJobScheduler.scheduleAll();
        Test.stopTest();

        System.assert(summary.contains('Demand Reminders'), 'Summary should list the demand reminder job');

        Integer scheduled = [
            SELECT COUNT() FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'PostSales -%'
        ];
        System.assert(scheduled >= 1, 'At least one Post-Sales job should be scheduled');
    }

    @isTest
    static void scheduleAll_isIdempotent() {
        Test.startTest();
        PostSalesJobScheduler.scheduleAll();
        // Second call must not throw a duplicate-name error.
        String summary = PostSalesJobScheduler.scheduleAll();
        Test.stopTest();

        System.assertNotEquals(null, summary);
    }
}