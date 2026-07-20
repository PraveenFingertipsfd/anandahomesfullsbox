@isTest
private class UserTriggerTest {

    @TestSetup
    static void seed() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        User u = new User(
            FirstName='User', LastName='TrigTester', Alias='utrg',
            Email='user.trig@example.invalid.test',
            Username='user.trig' + System.currentTimeMillis() + '@example.invalid.test',
            CommunityNickname='utrg' + System.currentTimeMillis(),
            ProfileId=p.Id, TimeZoneSidKey='Asia/Kolkata',
            LocaleSidKey='en_IN', EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US', Availability__c=false
        );
        System.runAs(new User(Id=UserInfo.getUserId())) {
            insert u;
        }
    }

    static User getTestUser() {
        return [SELECT Id, Availability__c FROM User WHERE Email='user.trig@example.invalid.test' LIMIT 1];
    }

    @isTest
    static void availabilityFlipOnViaTriggerInsertsHistory() {
        User u = getTestUser();

        Test.startTest();
        u.Availability__c = true;
        update u;
        Test.stopTest();

        List<User_Availability_History__c> rows = [
            SELECT Is_Active__c, Start_Time__c, End_Time__c
            FROM User_Availability_History__c WHERE Executive__c = :u.Id
        ];
        System.assertEquals(1, rows.size(), 'One history row inserted via trigger');
        System.assertEquals(true, rows[0].Is_Active__c, 'Row active');
        System.assertNotEquals(null, rows[0].Start_Time__c, 'Start time set');
    }

    @isTest
    static void availabilityFlipOffClosesHistory() {
        User u = getTestUser();
        u.Availability__c = true;
        update u;

        Test.startTest();
        u.Availability__c = false;
        update u;
        Test.stopTest();

        User_Availability_History__c row = [
            SELECT Is_Active__c, End_Time__c
            FROM User_Availability_History__c WHERE Executive__c = :u.Id LIMIT 1
        ];
        System.assertEquals(false, row.Is_Active__c, 'Row closed');
        System.assertNotEquals(null, row.End_Time__c, 'End time stamped');
    }

    @isTest
    static void nonAvailabilityUpdateMakesNoHistory() {
        User u = getTestUser();

        Test.startTest();
        u.LastName = 'Renamed';
        update u;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM User_Availability_History__c WHERE Executive__c = :u.Id];
        System.assertEquals(0, count, 'No history without availability change');
    }

    @isTest
    static void bulkAvailabilityFlipOnInsertsMultipleHistories() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];

        List<User> users = new List<User>();
        for (Integer i = 0; i < 5; i++) {
            User u = new User(
                FirstName = 'Bulk', LastName = 'User' + i, Alias = 'bu' + i,
                Email = 'bulk.user' + i + '@example.invalid.test',
                Username = 'bulk.user' + i + System.currentTimeMillis() + '@example.invalid.test',
                CommunityNickname = 'bu' + i + System.currentTimeMillis(),
                ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_IN', EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US', Availability__c = false
            );
            users.add(u);
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert users;
        }

        Test.startTest();
        for (User u : users) {
            u.Availability__c = true;
        }
        update users;
        Test.stopTest();

        List<User_Availability_History__c> rows = [
            SELECT Is_Active__c, Start_Time__c, Log_Date__c, Executive__c
            FROM User_Availability_History__c WHERE Executive__c IN :users
        ];

        System.assertEquals(5, rows.size(), '5 history records inserted');
        for (User_Availability_History__c row : rows) {
            System.assertEquals(true, row.Is_Active__c, 'Row active');
            System.assertNotEquals(null, row.Start_Time__c, 'Start time stamped');
            System.assertNotEquals(null, row.Log_Date__c, 'Log date stamped');
        }
    }

    @isTest
    static void bulkAvailabilityFlipOffClosesMultipleHistories() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];

        List<User> users = new List<User>();
        for (Integer i = 0; i < 5; i++) {
            User u = new User(
                FirstName = 'BulkOff', LastName = 'User' + i, Alias = 'bo' + i,
                Email = 'bulkoff.user' + i + '@example.invalid.test',
                Username = 'bulkoff.user' + i + System.currentTimeMillis() + '@example.invalid.test',
                CommunityNickname = 'bo' + i + System.currentTimeMillis(),
                ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_IN', EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US', Availability__c = false
            );
            users.add(u);
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert users;
        }

        for (User u : users) {
            u.Availability__c = true;
        }
        update users;

        Test.startTest();
        for (User u : users) {
            u.Availability__c = false;
        }
        update users;
        Test.stopTest();

        List<User_Availability_History__c> rows = [
            SELECT Is_Active__c, End_Time__c, Executive__c
            FROM User_Availability_History__c WHERE Executive__c IN :users
        ];

        System.assertEquals(5, rows.size(), '5 history records updated');
        for (User_Availability_History__c row : rows) {
            System.assertEquals(false, row.Is_Active__c, 'Row closed');
            System.assertNotEquals(null, row.End_Time__c, 'End time stamped');
        }
    }

    @isTest
    static void turnOffWithReasonStampsTurnOffReasonField() {
        User u = getTestUser();

        u.Availability__c = true;
        update u;

        Test.startTest();
        UserAvailabilityHistoryHandler.turnOffReason = 'Shift ended';
        u.Availability__c = false;
        update u;
        Test.stopTest();

        User_Availability_History__c row = [
            SELECT Turn_Off_Reason__c FROM User_Availability_History__c WHERE Executive__c = :u.Id LIMIT 1
        ];

        System.assertEquals('Shift ended', row.Turn_Off_Reason__c, 'Turn off reason stamped');

        UserAvailabilityHistoryHandler.turnOffReason = null;
    }

    @isTest
    static void multipleToggleCyclesCreatesMultipleHistoryRows() {
        User u = getTestUser();

        Test.startTest();
        u.Availability__c = true;
        update u;

        List<User_Availability_History__c> afterFirstToggle = [
            SELECT Is_Active__c FROM User_Availability_History__c WHERE Executive__c = :u.Id
        ];
        System.assertEquals(1, afterFirstToggle.size(), '1 history after first toggle on');
        System.assertEquals(true, afterFirstToggle[0].Is_Active__c, 'First record active');

        u.Availability__c = false;
        update u;

        List<User_Availability_History__c> afterSecondToggle = [
            SELECT Is_Active__c FROM User_Availability_History__c WHERE Executive__c = :u.Id
        ];
        System.assertEquals(1, afterSecondToggle.size(), '1 history after toggle off (same record updated)');
        System.assertEquals(false, afterSecondToggle[0].Is_Active__c, 'First record closed');

        u.Availability__c = true;
        update u;
        Test.stopTest();

        List<User_Availability_History__c> afterThirdToggle = [
            SELECT Is_Active__c FROM User_Availability_History__c WHERE Executive__c = :u.Id
        ];
        System.assertEquals(2, afterThirdToggle.size(), '2 histories after toggle back on');

        Integer activeCount = 0;
        for (User_Availability_History__c row : afterThirdToggle) {
            if (row.Is_Active__c) {
                activeCount++;
            }
        }
        System.assertEquals(1, activeCount, '1 active and 1 closed record');
    }

    @isTest
    static void concurrentFlipsOnAndOffInSameTransaction() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];

        User userA = new User(
            FirstName = 'Concurrent', LastName = 'UserA', Alias = 'ca',
            Email = 'concurrent.a@example.invalid.test',
            Username = 'concurrent.a' + System.currentTimeMillis() + '@example.invalid.test',
            CommunityNickname = 'ca' + System.currentTimeMillis(),
            ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', Availability__c = false
        );

        User userB = new User(
            FirstName = 'Concurrent', LastName = 'UserB', Alias = 'cb',
            Email = 'concurrent.b@example.invalid.test',
            Username = 'concurrent.b' + System.currentTimeMillis() + '@example.invalid.test',
            CommunityNickname = 'cb' + System.currentTimeMillis(),
            ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', Availability__c = true
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{userA, userB};
        }

        User_Availability_History__c historyB = new User_Availability_History__c(
            Executive__c = userB.Id,
            Is_Active__c = true,
            Log_Date__c = Date.today(),
            Start_Time__c = System.now().addHours(-1)
        );
        insert historyB;

        Test.startTest();
        userA.Availability__c = true;
        userB.Availability__c = false;
        update new List<User>{userA, userB};
        Test.stopTest();

        List<User_Availability_History__c> rowsA = [
            SELECT Is_Active__c FROM User_Availability_History__c WHERE Executive__c = :userA.Id
        ];
        System.assertEquals(1, rowsA.size(), 'User A has 1 history (turned on)');
        System.assertEquals(true, rowsA[0].Is_Active__c, 'User A history is active');

        List<User_Availability_History__c> rowsB = [
            SELECT Is_Active__c FROM User_Availability_History__c WHERE Executive__c = :userB.Id
        ];
        System.assertEquals(1, rowsB.size(), 'User B has 1 history (turned off)');
        System.assertEquals(false, rowsB[0].Is_Active__c, 'User B history is closed');
    }

    @isTest
    static void nullAndEmptyReasonNotStamped() {
        User u = getTestUser();

        u.Availability__c = true;
        update u;

        Test.startTest();

        UserAvailabilityHistoryHandler.turnOffReason = null;
        u.Availability__c = false;
        update u;

        User_Availability_History__c row = [
            SELECT Turn_Off_Reason__c FROM User_Availability_History__c WHERE Executive__c = :u.Id LIMIT 1
        ];
        System.assertEquals(null, row.Turn_Off_Reason__c, 'Null reason not stamped');

        u.Availability__c = true;
        update u;

        UserAvailabilityHistoryHandler.turnOffReason = '   ';
        u.Availability__c = false;
        update u;

        List<User_Availability_History__c> rows = [
            SELECT Turn_Off_Reason__c FROM User_Availability_History__c WHERE Executive__c = :u.Id
            ORDER BY Start_Time__c DESC
        ];
        System.assertEquals(2, rows.size(), 'Two history records for user');
        System.assertEquals(null, rows[0].Turn_Off_Reason__c, 'Empty/whitespace reason not stamped');

        Test.stopTest();

        UserAvailabilityHistoryHandler.turnOffReason = null;
    }
}