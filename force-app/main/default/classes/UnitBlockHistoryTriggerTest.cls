@isTest
private class UnitBlockHistoryTriggerTest {

    static Plot__c plot;
    static Unit_Block_History__c ubh;

    static void seed() {
        Project__c project = new Project__c(Name='UBH Project', Project_Type__c='Residential');
        insert project;

        Block__c block = new Block__c(Name='A', Project__c=project.Id);
        insert block;

        plot = new Plot__c(
            Name='101', Status__c='Blocked', Project__c=project.Id,
            Block__c='A4', Plot_Type__c='Residential',
            Block1__c=block.Id, BHK_Type__c='3 BHK + 2T'
        );
        insert plot;

        ubh = new Unit_Block_History__c(
            Unit__c = plot.Id,
            Status__c = 'Blocked',
            Block_Duration__c = 3,
            Blocked_Time__c = System.now(),
            Blocked_Expiry_Date__c = System.now().addDays(3)
        );
        insert ubh;
    }

    @isTest
    static void revokeStampsTimeAndUserAndFreesPlot() {
        seed();

        Test.startTest();
        ubh.Status__c = 'Revoked';
        ubh.Revoke_Reason__c = 'Test revocation';
        update ubh;
        Test.stopTest();

        Unit_Block_History__c after = [SELECT Revoked_Time__c, Unblocked_By__c FROM Unit_Block_History__c WHERE Id = :ubh.Id];
        System.assertNotEquals(null, after.Revoked_Time__c, 'Revoked time stamped');
        System.assertEquals(UserInfo.getUserId(), after.Unblocked_By__c, 'Current user stamped');

        Plot__c afterPlot = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Available', afterPlot.Status__c, 'Plot freed');
    }

    @isTest
    static void preStampedRevokedTimeIsRetained() {
        seed();

        Datetime pre = System.now().addDays(-2);
        ubh.Status__c = 'Revoked';
        ubh.Revoked_Time__c = pre;
        ubh.Revoke_Reason__c = 'Test revocation';

        Test.startTest();
        update ubh;
        Test.stopTest();

        Unit_Block_History__c after = [SELECT Revoked_Time__c FROM Unit_Block_History__c WHERE Id = :ubh.Id];
        System.assertEquals(pre, after.Revoked_Time__c, 'Pre-stamped time retained');
    }

    @isTest
    static void nonRevokedUpdateDoesNotStamp() {
        seed();

        Test.startTest();
        ubh.Block_Duration__c = 7;
        update ubh;
        Test.stopTest();

        Unit_Block_History__c after = [SELECT Revoked_Time__c, Unblocked_By__c FROM Unit_Block_History__c WHERE Id = :ubh.Id];
        System.assertEquals(null, after.Revoked_Time__c, 'No stamp without revoke');
        System.assertEquals(null, after.Unblocked_By__c, 'No user stamp without revoke');
    }

    @isTest
    static void bothFieldsPreStampedAreRetained() {
        seed();

        Datetime preTime = System.now().addDays(-1);
        Id preUser = UserInfo.getUserId();

        ubh.Status__c = 'Revoked';
        ubh.Revoked_Time__c = preTime;
        ubh.Unblocked_By__c = preUser;
        ubh.Revoke_Reason__c = 'Test revocation';

        Test.startTest();
        update ubh;
        Test.stopTest();

        Unit_Block_History__c after = [SELECT Revoked_Time__c, Unblocked_By__c FROM Unit_Block_History__c WHERE Id = :ubh.Id];
        System.assertEquals(preTime, after.Revoked_Time__c, 'Pre-stamped time retained');
        System.assertEquals(preUser, after.Unblocked_By__c, 'Pre-stamped user retained');

        Plot__c afterPlot = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Available', afterPlot.Status__c, 'Plot freed despite pre-stamped values');
    }

    @isTest
    static void revokeWithoutUnitDoesNotUpdatePlot() {
        seed();

        Unit_Block_History__c ubhNoUnit = new Unit_Block_History__c(
            Unit__c = null,
            Status__c = 'Blocked',
            Block_Duration__c = 3,
            Blocked_Time__c = System.now(),
            Blocked_Expiry_Date__c = System.now().addDays(3)
        );
        insert ubhNoUnit;

        Test.startTest();
        ubhNoUnit.Status__c = 'Revoked';
        ubhNoUnit.Revoke_Reason__c = 'Test revocation';
        update ubhNoUnit;
        Test.stopTest();

        Unit_Block_History__c after = [SELECT Revoked_Time__c, Unblocked_By__c FROM Unit_Block_History__c WHERE Id = :ubhNoUnit.Id];
        System.assertNotEquals(null, after.Revoked_Time__c, 'Revoked time stamped');
        System.assertEquals(UserInfo.getUserId(), after.Unblocked_By__c, 'Current user stamped');

        Plot__c unchangedPlot = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Blocked', unchangedPlot.Status__c, 'Plot not freed when Unit is null');
    }

    @isTest
    static void statusChangeToConvertedDoesNotRevoke() {
        seed();

        Test.startTest();
        ubh.Status__c = 'Converted';
        update ubh;
        Test.stopTest();

        Unit_Block_History__c after = [SELECT Revoked_Time__c, Unblocked_By__c, Status__c FROM Unit_Block_History__c WHERE Id = :ubh.Id];
        System.assertEquals(null, after.Revoked_Time__c, 'No revoke time stamp for Converted status');
        System.assertEquals(null, after.Unblocked_By__c, 'No user stamp for Converted status');
        System.assertEquals('Converted', after.Status__c, 'Status changed to Converted');

        Plot__c unchangedPlot = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Blocked', unchangedPlot.Status__c, 'Plot not freed for Converted status');
    }

    @isTest
    static void bulkRevokeMultipleUnits() {
        seed();

        Project__c project = [SELECT Id FROM Project__c WHERE Name = 'UBH Project' LIMIT 1];
        Block__c block = [SELECT Id FROM Block__c WHERE Name = 'A' LIMIT 1];

        List<Plot__c> plots = new List<Plot__c>();
        List<Unit_Block_History__c> ubhs = new List<Unit_Block_History__c>();

        List<String> validBlocks = new List<String>{'A2', 'A4', 'A6', 'A7', 'A8'};

        for (Integer i = 0; i < 5; i++) {
            Plot__c p = new Plot__c(
                Name = 'Bulk-' + i,
                Status__c = 'Blocked',
                Project__c = project.Id,
                Block__c = validBlocks[i],
                Plot_Type__c = 'Residential',
                Block1__c = block.Id,
                BHK_Type__c = '3 BHK + 2T'
            );
            plots.add(p);
        }
        insert plots;

        for (Integer i = 0; i < plots.size(); i++) {
            Unit_Block_History__c u = new Unit_Block_History__c(
                Unit__c = plots[i].Id,
                Status__c = 'Blocked',
                Block_Duration__c = 3,
                Blocked_Time__c = System.now(),
                Blocked_Expiry_Date__c = System.now().addDays(3)
            );
            ubhs.add(u);
        }
        insert ubhs;

        for (Unit_Block_History__c u : ubhs) {
            u.Status__c = 'Revoked';
            u.Revoke_Reason__c = 'Bulk test revocation';
        }

        Test.startTest();
        update ubhs;
        Test.stopTest();

        List<Unit_Block_History__c> afterUbhs = [SELECT Id, Revoked_Time__c, Unblocked_By__c FROM Unit_Block_History__c WHERE Id IN :ubhs];
        System.assertEquals(5, afterUbhs.size(), '5 unit blocks revoked');
        for (Unit_Block_History__c u : afterUbhs) {
            System.assertNotEquals(null, u.Revoked_Time__c, 'All revoked times stamped');
            System.assertEquals(UserInfo.getUserId(), u.Unblocked_By__c, 'All users stamped');
        }

        List<Plot__c> freedPlots = [SELECT Id, Status__c FROM Plot__c WHERE Id IN :plots];
        System.assertEquals(5, freedPlots.size(), '5 plots queried');
        for (Plot__c p : freedPlots) {
            System.assertEquals('Available', p.Status__c, 'All plots freed');
        }
    }

    @isTest
    static void revokeWithOnlyTimePreSetUnblockedByAutoStamped() {
        seed();

        Datetime preTime = System.now().addDays(-2);
        ubh.Status__c = 'Revoked';
        ubh.Revoked_Time__c = preTime;
        ubh.Revoke_Reason__c = 'Test revocation';

        Test.startTest();
        update ubh;
        Test.stopTest();

        Unit_Block_History__c after = [SELECT Revoked_Time__c, Unblocked_By__c FROM Unit_Block_History__c WHERE Id = :ubh.Id];
        System.assertEquals(preTime, after.Revoked_Time__c, 'Pre-stamped time retained');
        System.assertEquals(UserInfo.getUserId(), after.Unblocked_By__c, 'Unblocked by auto-stamped');

        Plot__c afterPlot = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Available', afterPlot.Status__c, 'Plot freed with partial pre-stamping');
    }
}