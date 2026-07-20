@IsTest
private class UserAvailabilityHistoryHandlerTest {

    @TestSetup
    static void makeData() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        List<User> users = new List<User>();
        for (Integer i = 0; i < 3; i++) {
            users.add(new User(
                FirstName      = 'Avail',
                LastName       = 'Tester' + i,
                Alias          = 'avt' + i,
                Email          = 'avail.tester' + i + '@example.invalid.test',
                Username       = 'avail.tester' + i + System.currentTimeMillis() + '@example.invalid.test',
                CommunityNickname = 'avt' + i + System.currentTimeMillis(),
                ProfileId      = p.Id,
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey   = 'en_IN',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                Availability__c = false
            ));
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert users;
        }
    }

    static List<User> getTestUsers() {
        return [SELECT Id, Availability__c FROM User WHERE Email LIKE 'avail.tester%@example.invalid.test' ORDER BY LastName];
    }

    @IsTest
    static void flipOnInsertsActiveHistory() {
        List<User> users = getTestUsers();
        User u = users[0];

        Test.startTest();
        u.Availability__c = true;
        update u;
        Test.stopTest();

        List<User_Availability_History__c> rows = [
            SELECT Id, Executive__c, Is_Active__c, Log_Date__c, Start_Time__c, End_Time__c
            FROM User_Availability_History__c
            WHERE Executive__c = :u.Id
        ];
        System.assertEquals(1, rows.size(), 'Exactly one history row should be created on flip-on.');
        System.assertEquals(true, rows[0].Is_Active__c, 'New row should be active.');
        System.assertEquals(Date.today(), rows[0].Log_Date__c, 'Log date should be today.');
        System.assertNotEquals(null, rows[0].Start_Time__c, 'Start time should be populated.');
        System.assertEquals(null, rows[0].End_Time__c, 'End time should be null until flip-off.');
    }

    @IsTest
    static void flipOffClosesOpenHistory() {
        List<User> users = getTestUsers();
        User u = users[0];

        u.Availability__c = true;
        update u;

        Test.startTest();
        u.Availability__c = false;
        update u;
        Test.stopTest();

        List<User_Availability_History__c> rows = [
            SELECT Id, Is_Active__c, End_Time__c
            FROM User_Availability_History__c
            WHERE Executive__c = :u.Id
        ];
        System.assertEquals(1, rows.size(), 'Still one row after flip-off.');
        System.assertEquals(false, rows[0].Is_Active__c, 'Row should be marked inactive.');
        System.assertNotEquals(null, rows[0].End_Time__c, 'End time should be stamped.');
    }

    @IsTest
    static void reToggleCreatesSecondRow() {
        List<User> users = getTestUsers();
        User u = users[0];

        u.Availability__c = true;
        update u;

        u.Availability__c = false;
        update u;

        Test.startTest();
        u.Availability__c = true;
        update u;
        Test.stopTest();

        List<User_Availability_History__c> rows = [
            SELECT Id, Is_Active__c, End_Time__c, Start_Time__c
            FROM User_Availability_History__c
            WHERE Executive__c = :u.Id
            ORDER BY Start_Time__c ASC
        ];
        System.assertEquals(2, rows.size(), 'Second toggle-on should create a new row.');
        System.assertEquals(false, rows[0].Is_Active__c, 'First row remains closed.');
        System.assertNotEquals(null, rows[0].End_Time__c, 'First row keeps its end time.');
        System.assertEquals(true, rows[1].Is_Active__c, 'Second row is active.');
        System.assertEquals(null, rows[1].End_Time__c, 'Second row has no end time yet.');
    }

    @IsTest
    static void noHistoryWhenAvailabilityUnchanged() {
        List<User> users = getTestUsers();
        User u = users[0];

        Test.startTest();
        u.LastName = 'ChangedName';
        update u;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM User_Availability_History__c WHERE Executive__c = :u.Id];
        System.assertEquals(0, count, 'No history row should be created when Availability__c is unchanged.');
    }

    @IsTest
    static void flipOffStampsTurnOffReason() {
        List<User> users = getTestUsers();
        User u = users[0];

        u.Availability__c = true;
        update u;

        Test.startTest();
        UserAvailabilityHistoryHandler.turnOffReason = 'Stepping out for lunch';
        u.Availability__c = false;
        update u;
        Test.stopTest();

        User_Availability_History__c row = [
            SELECT Is_Active__c, End_Time__c, Turn_Off_Reason__c
            FROM User_Availability_History__c
            WHERE Executive__c = :u.Id
            LIMIT 1
        ];
        System.assertEquals(false, row.Is_Active__c, 'Row should be closed.');
        System.assertNotEquals(null, row.End_Time__c, 'End time should be stamped.');
        System.assertEquals('Stepping out for lunch', row.Turn_Off_Reason__c, 'Reason should land on closed row.');
    }

    @IsTest
    static void bulkFlipOnAndOff() {
        List<User> users = getTestUsers();
        Set<Id> userIds = new Set<Id>();
        for (User u : users) {
            u.Availability__c = true;
            userIds.add(u.Id);
        }

        Test.startTest();
        update users;

        Integer openCount = [SELECT COUNT() FROM User_Availability_History__c WHERE Executive__c IN :userIds AND Is_Active__c = true];
        System.assertEquals(users.size(), openCount, 'One open row per flipped-on user.');

        for (User u : users) {
            u.Availability__c = false;
        }
        update users;
        Test.stopTest();

        Integer closedCount = [SELECT COUNT() FROM User_Availability_History__c WHERE Executive__c IN :userIds AND Is_Active__c = false AND End_Time__c != null];
        System.assertEquals(users.size(), closedCount, 'All previously open rows should be closed.');
    }
}