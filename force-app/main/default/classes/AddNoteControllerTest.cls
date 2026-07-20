@isTest
public class AddNoteControllerTest {

    @isTest
    public static void updateLastNoteAppendsAndFetchReturns() {
        Lead__c ld = new Lead__c(
            Name__c = 'Test Lead',
            Last_Note__c = '',
            Source_Type__c = 'Digital Marketing',
            Lead_source__c = 'Website',
            Phone__c = '1234567890'
        );
        insert ld;

        Test.startTest();
        AddNoteController.updateLastNote(ld.Id, 'First Note');
        AddNoteController.updateLastNote(ld.Id, 'Second Note');
        List<String> notes = AddNoteController.fetchLeadLastNotes(ld.Id);
        Boolean privileged = AddNoteController.isPrivilegedUser();
        Test.stopTest();

        Lead__c after = [SELECT Last_Note__c FROM Lead__c WHERE Id = :ld.Id];
        System.assert(after.Last_Note__c.contains('First Note'), 'First note appended');
        System.assert(after.Last_Note__c.contains('Second Note'), 'Second note appended');
        System.assertEquals(2, notes.size(), 'fetchLeadLastNotes returns both notes filtered');
        System.assert(notes[0].contains('Second Note'), 'Reverse order (newest first)');
        System.assertNotEquals(null, privileged, 'isPrivilegedUser returns boolean');
    }

    @isTest
    public static void businessProfilesArePrivileged() {
        Profile preSales = [SELECT Id FROM Profile WHERE Name = 'Pre-Sales Executive' LIMIT 1];
        Profile assocMgr = [SELECT Id FROM Profile WHERE Name = 'Associate Manager' LIMIT 1];

        User preSalesUser = new User(
            FirstName = 'Test', LastName = 'PreSales',
            Email = 'testpresales@test.com',
            Username = 'testpresales.' + DateTime.now().getTime() + '@test.com',
            Alias = 'tpresal', ProfileId = preSales.Id,
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        User assocMgrUser = new User(
            FirstName = 'Test', LastName = 'AssocMgr',
            Email = 'testassocmgr@test.com',
            Username = 'testassocmgr.' + DateTime.now().getTime() + '@test.com',
            Alias = 'tassocm', ProfileId = assocMgr.Id,
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert new List<User>{ preSalesUser, assocMgrUser };

        System.runAs(preSalesUser) {
            System.assertEquals(true, AddNoteController.isPrivilegedUser(),
                'Pre-Sales Executive can add/clear remarks');
        }
        System.runAs(assocMgrUser) {
            System.assertEquals(true, AddNoteController.isPrivilegedUser(),
                'Associate Manager can add/clear remarks');
        }
    }

    @isTest
    public static void fetchOnEmptyNoteReturnsEmpty() {
        Lead__c ld = new Lead__c(
            Name__c = 'Test Lead 2',
            Source_Type__c = 'Digital Marketing',
            Lead_source__c = 'Website',
            Phone__c = '1234567891'
        );
        insert ld;

        List<String> notes = AddNoteController.fetchLeadLastNotes(ld.Id);
        System.assertEquals(0, notes.size(), 'No notes returns empty list');
    }
}