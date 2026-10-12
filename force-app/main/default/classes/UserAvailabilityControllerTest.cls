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

     private static User buildTelephoneUser(String aliasSeed, Boolean working, Boolean available) {
         return new User(
             FirstName = 'Tel', LastName = aliasSeed,
             Email = aliasSeed + '@testex.com',
             Username = aliasSeed + System.currentTimeMillis() + '@testex.com',
             Alias = aliasSeed.left(8),
             EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
             LocaleSidKey = 'en_US', TimeZoneSidKey = 'Asia/Kolkata',
             ProfileId = UserInfo.getProfileId(),
             Telephone_User__c = true,
             is_working__c = working,
             Availability__c = available
         );
     }

     /** Covers the Telephone User filter, the working-candidate list and a successful backup assignment. */
     @isTest
     static void testTelephoneUserFlow() {
         User onLeave = buildTelephoneUser('onleave', false, false);
         User working = buildTelephoneUser('working', true, true);
         User offDuty = buildTelephoneUser('offduty', false, true);
         insert new List<User>{ onLeave, working, offDuty };

         Test.startTest();
         List<User> telUsers = UserAvailabilityController.getAllUsers(UserAvailabilityController.TELEPHONE_USER_FILTER);
         List<User> candidates = UserAvailabilityController.getWorkingTelephoneUsers(onLeave.Id);
         User updated = UserAvailabilityController.assignBackupCaller(onLeave.Id, working.Id);
         Test.stopTest();

         Set<Id> telIds = new Map<Id, User>(telUsers).keySet();
         System.assert(telIds.contains(onLeave.Id) && telIds.contains(working.Id) && telIds.contains(offDuty.Id),
                       'Telephone User filter should return every telephone user');
         for (User u : telUsers) {
             System.assertEquals(true, u.Telephone_User__c, 'Only telephone users should be returned');
         }

         Set<Id> candidateIds = new Map<Id, User>(candidates).keySet();
         System.assert(candidateIds.contains(working.Id), 'Working telephone user should be a candidate');
         System.assert(!candidateIds.contains(offDuty.Id), 'Non-working telephone user should not be a candidate');
         System.assert(!candidateIds.contains(onLeave.Id), 'User should not be their own candidate');

         System.assertEquals(working.Id, updated.Todays_Backup_Caller__c, 'Backup caller should be saved');

         // Reverse direction is blocked: onLeave already has working as backup.
         List<User> reverse = UserAvailabilityController.getWorkingTelephoneUsers(working.Id);
         System.assert(!new Map<Id, User>(reverse).keySet().contains(onLeave.Id),
                       'A user whose backup is the target should not be offered as a candidate');

         // Turning Working on clears the backup caller (UserTrigger before update).
         User backToWork = [SELECT Id, Name, is_working__c, Availability__c, Todays_Backup_Caller__c FROM User WHERE Id = :onLeave.Id];
         backToWork.is_working__c = true;
         UserAvailabilityController.updateUser2(backToWork);
         User cleared = [SELECT Todays_Backup_Caller__c, is_working__c FROM User WHERE Id = :onLeave.Id];
         System.assertEquals(true, cleared.is_working__c, 'Working should now be on');
         System.assertEquals(null, cleared.Todays_Backup_Caller__c, 'Backup caller should be cleared when Working turns on');
     }

     /** Covers validation branches of assignBackupCaller. */
     @isTest
     static void testAssignBackupCaller_Validation() {
         User onLeave = buildTelephoneUser('vleave', false, false);
         User notWorking = buildTelephoneUser('vnotwork', false, false);
         insert new List<User>{ onLeave, notWorking };

         Test.startTest();
         assertAssignFails(null, notWorking.Id, 'null user');
         assertAssignFails(onLeave.Id, null, 'null backup');
         assertAssignFails(onLeave.Id, onLeave.Id, 'self backup');
         assertAssignFails(onLeave.Id, notWorking.Id, 'backup not working');
         Test.stopTest();

         User check = [SELECT Todays_Backup_Caller__c FROM User WHERE Id = :onLeave.Id];
         System.assertEquals(null, check.Todays_Backup_Caller__c, 'No backup should be saved on validation failure');
     }

     private static void assertAssignFails(Id userId, Id backupId, String scenario) {
         try {
             UserAvailabilityController.assignBackupCaller(userId, backupId);
             System.assert(false, 'Expected AuraHandledException for ' + scenario);
         } catch (AuraHandledException e) {
             System.assertNotEquals(null, e.getMessage(), 'Message expected for ' + scenario);
         }
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