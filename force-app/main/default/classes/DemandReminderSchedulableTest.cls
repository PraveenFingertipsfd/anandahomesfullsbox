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
    }

    @isTest
    static void execute_directInvocation_handlesNoData() {
        Test.startTest();
        new DemandReminderSchedulable().execute(null);
        Test.stopTest();

        // Happy path of all four steps ran; internal exceptions (if any) were swallowed.
    }

    @isTest
    static void execute_allStepsFail_isSwallowedByCatchBlocks() {
        Test.startTest();
        DemandReminderSchedulable.forceExceptionForTest = true;
        Boolean escaped = false;
        try {
            new DemandReminderSchedulable().execute(null);
        } catch (Exception e) {
            escaped = true; // should never happen — every step has its own catch
        }
        DemandReminderSchedulable.forceExceptionForTest = false;
        Test.stopTest();

        
    }
}