@isTest
public class UserAvailabilityControllerTest {
	 public static testMethod void userstatustest(){
         List<User> all = UserAvailabilityController.getAllUsers('System Administrator');
         System.assertNotEquals(null, all, 'getAllUsers returned list');

         List<User> mine = UserAvailabilityController.getMyUsers();
         System.assertNotEquals(null, mine, 'getMyUsers returned list');

         User u = [SELECT Id,Name,Availability__c,is_working__c FROM User WHERE Id=:userinfo.getuserid()];
         UserAvailabilityController.updateUser('test',u);

         // Cover is_working__c == false branch
         u.is_working__c = false;
         UserAvailabilityController.updateUser2(u);

         // Verify Availability__c was set to false
         User verifyFalse = [SELECT Availability__c FROM User WHERE Id = :u.Id];
         System.assertEquals(false, verifyFalse.Availability__c, 'Availability__c should be false when is_working__c is false');

         // Cover is_working__c == true branch
         u = [SELECT Id,Name,Availability__c,is_working__c FROM User WHERE Id=:userinfo.getuserid()];
         u.is_working__c = true;
         UserAvailabilityController.updateUser2(u);

         // Verify Availability__c was set to true
         User verifyTrue = [SELECT Availability__c FROM User WHERE Id = :u.Id];
         System.assertEquals(true, verifyTrue.Availability__c, 'Availability__c should be true when is_working__c is true');
         //test.stoptest();
     }

     /** Covers getAllUsers with profile that returns no matches → empty list. */
     @isTest
     static void testGetAllUsers_NoMatch() {
         Test.startTest();
         List<User> result = UserAvailabilityController.getAllUsers('NonExistentProfile_XYZ_123');
         Test.stopTest();

         System.assertEquals(0, result.size(), 'Should return empty list for unknown profile');
     }

     /** Covers getMyUsers head-profile branch (Manager.ManagerId condition).
      *  Skipped gracefully if 'Presales Head' profile doesn't exist in this org.
      */
     @isTest
     static void testGetMyUsers_HeadProfile() {
         List<Profile> profiles = [SELECT Id FROM Profile WHERE Name IN ('Presales Head', 'Sales Head', 'Site visit Head', 'Recovery Head') LIMIT 1];
         if (profiles.isEmpty()) return;

         User headUser = new User(
             FirstName = 'Head', LastName = 'User',
             Email = 'headuser@testex.com',
             Username = 'headuser' + System.currentTimeMillis() + '@testex.com',
             Alias = 'hduser',
             EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
             LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles',
             ProfileId = profiles[0].Id
         );
         insert headUser;

         System.runAs(headUser) {
             Test.startTest();
             List<User> result = UserAvailabilityController.getMyUsers();
             Test.stopTest();
             System.assertNotEquals(null, result, 'Result should not be null');
         }
     }
}