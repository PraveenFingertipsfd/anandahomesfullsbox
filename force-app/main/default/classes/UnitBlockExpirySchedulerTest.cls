@isTest
private class UnitBlockExpirySchedulerTest {

    static final String CRON_EXP = '0 0 1 * * ? 2099';

    @TestSetup
    static void seedBlocks() {
        Project__c project = new Project__c(Name = 'UBES Project', Project_Type__c = 'Residential');
        insert project;

        Block__c block = new Block__c(Name = 'A', Project__c = project.Id);
        insert block;

        Plot__c plot = new Plot__c(
            Name = '101',
            Status__c = 'Blocked',
            Project__c = project.Id,
            Block__c = 'A4',
            Plot_Type__c = 'Residential',
            Block1__c = block.Id,
            BHK_Type__c = '3 BHK + 2T'
        );
        insert plot;

        Datetime today6am = Datetime.newInstance(Date.today(), Time.newInstance(6, 0, 0, 0));
        Unit_Block_History__c ubh = new Unit_Block_History__c(
            Unit__c = plot.Id,
            Status__c = 'Blocked',
            Block_Duration__c = 5,
            Blocked_Time__c = today6am.addDays(-5),
            Blocked_Expiry_Date__c = today6am
        );
        insert ubh;
    }

    @isTest
    static void revokeExpiredBlocksFlipsStatus() {
        Test.startTest();
        Integer revoked = UnitBlockExpiryScheduler.revokeExpiredBlocks();
        Test.stopTest();

        System.assertEquals(1, revoked, 'Exactly one expired block revoked');
        Unit_Block_History__c after = [SELECT Status__c, Revoke_Reason__c FROM Unit_Block_History__c LIMIT 1];
        System.assertEquals('Revoked', after.Status__c, 'Status set to Revoked');
        System.assertEquals(UnitBlockExpiryScheduler.EXPIRED_REASON, after.Revoke_Reason__c, 'Revoke reason stamped');
    }

    @isTest
    static void revokeExpiredBlocksWithNoneReturnsZero() {
        delete [SELECT Id FROM Unit_Block_History__c];

        Test.startTest();
        Integer revoked = UnitBlockExpiryScheduler.revokeExpiredBlocks();
        Test.stopTest();

        System.assertEquals(0, revoked, 'No expired rows so zero returned');
    }

    @isTest
    static void schedulerExecutes() {
        Test.startTest();
        String jobId = System.schedule(
            'Unit Block Expiry Test',
            CRON_EXP,
            new UnitBlockExpiryScheduler()
        );
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(CRON_EXP, ct.CronExpression, 'Cron registered');
    }
}