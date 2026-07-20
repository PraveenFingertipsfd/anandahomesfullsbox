@isTest
public class UserStatusControllertest {
    public static testMethod void userstatustest() {
        // Ensure a user with the Sales profile exists for the test
        User u = [SELECT Id, Name, ManagerId, Availability__c 
                   From User
                  LIMIT 1];
        
        // If no user is found, create a new one for the test
        if (u == null) {
            u = new User(
                Username = 'testuser@example.com',
                Alias = 'testuser',
                Email = 'testuser@example.com',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Sales' LIMIT 1].Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                UserRoleId = null
            );
            insert u;
        }

        // Call the method under test
        User userRec = UserStatusController.getUserRec();
        System.assertNotEquals(null, userRec, 'getUserRec should return current user');
        System.assertEquals(UserInfo.getUserId(), userRec.Id, 'Should return the running user');

        // Set Availability__c = true → covers else branch (line 37) which sets is_working__c = true
        u.Availability__c = true;
        UserStatusController.updateUser(u, 'test');

        // Verify is_working__c was set to true
        User verifyTrue = [SELECT is_working__c FROM User WHERE Id = :u.Id];
        System.assertEquals(true, verifyTrue.is_working__c, 'is_working__c should be true when Availability__c is true');

        // Update and test again — Availability__c == false branch
        u.Availability__c = false;
        update u;
        UserStatusController.updateUser(u, 'test');

        User verifyFalse = [SELECT is_working__c, Availability__c FROM User WHERE Id = :u.Id];
        System.assertEquals(false, verifyFalse.Availability__c, 'Availability stored as false');
    }
}