@IsTest
private class UserAvailabilityOffSchedulerTest {

    @TestSetup
    static void makeData() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        List<User> users = new List<User>();
        Long ts = System.currentTimeMillis();
        for (Integer i = 0; i < 3; i++) {
            users.add(new User(
                FirstName         = 'Sched',
                LastName          = 'Tester' + i,
                Alias             = 'sct' + i,
                Email             = 'sched.tester' + i + '@example.invalid.test',
                Username          = 'sched.tester' + i + ts + '@example.invalid.test',
                CommunityNickname = 'sct' + i + ts,
                ProfileId         = p.Id,
                TimeZoneSidKey    = 'Asia/Kolkata',
                LocaleSidKey      = 'en_IN',
                EmailEncodingKey  = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                Availability__c   = false
            ));
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert users;
        }
    }

    static List<User> getTestUsers() {
        return [SELECT Id, IsActive, Availability__c FROM User WHERE Email LIKE 'sched.tester%@example.invalid.test' ORDER BY LastName];
    }

    @IsTest
    static void turnsOffAllAvailableUsersAndClosesHistory() {
        List<User> users = getTestUsers();
        for (User u : users) u.Availability__c = true;
        update users;

        Test.startTest();
        UserAvailabilityOffScheduler.turnOffAllAvailable();
        Test.stopTest();

        Set<Id> ids = new Map<Id, User>(users).keySet();
        for (User u : [SELECT Id, Availability__c FROM User WHERE Id IN :ids]) {
            System.assertEquals(false, u.Availability__c, 'Scheduler should flip Availability__c off.');
        }

        List<User_Availability_History__c> rows = [
            SELECT Executive__c, Is_Active__c, End_Time__c, Turn_Off_Reason__c
            FROM User_Availability_History__c
            WHERE Executive__c IN :ids
        ];
        System.assertEquals(users.size(), rows.size(), 'Each user should have one closed history row.');
        for (User_Availability_History__c r : rows) {
            System.assertEquals(false, r.Is_Active__c, 'Row should be closed.');
            System.assertNotEquals(null, r.End_Time__c, 'End time should be stamped.');
            System.assertEquals(UserAvailabilityOffScheduler.AUTO_REASON, r.Turn_Off_Reason__c, 'Closing reason should match scheduler constant.');
        }
    }

    @IsTest
    static void noOpWhenNoOneAvailable() {
        Integer before = [SELECT COUNT() FROM User_Availability_History__c];

        Test.startTest();
        UserAvailabilityOffScheduler.turnOffAllAvailable();
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM User_Availability_History__c];
        System.assertEquals(before, after, 'No history rows should be created when no user is available.');
    }

    @IsTest
    static void inactiveUserIsSkipped() {
        List<User> users = getTestUsers();
        User toDeactivate = users[0];

        for (User u : users) u.Availability__c = true;
        update users;

        toDeactivate.IsActive = false;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update toDeactivate;
        }

        Test.startTest();
        UserAvailabilityOffScheduler.turnOffAllAvailable();
        Test.stopTest();

        User refreshed = [SELECT Availability__c FROM User WHERE Id = :toDeactivate.Id];
        System.assertEquals(true, refreshed.Availability__c, 'Inactive user should be left untouched by the scheduler.');

        for (User u : [SELECT Id, Availability__c FROM User WHERE Id IN :(new Set<Id>{users[1].Id, users[2].Id})]) {
            System.assertEquals(false, u.Availability__c, 'Active users should be flipped off.');
        }
    }

    @IsTest
    static void schedulableWiring() {
        String cron = '0 0 23 * * ?';
        Test.startTest();
        String jobId = System.schedule('UserAvailabilityOffScheduler test job', cron, new UserAvailabilityOffScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Schedulable should register a job id.');
    }
}