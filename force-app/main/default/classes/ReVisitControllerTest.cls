@isTest
public class ReVisitControllerTest {

    // Covers the SVRecord.Revisit_Details__c == null path
    public static testMethod void getFollowUpDetailstest() {
        Lead lead = new Lead();
        lead.Lastname = 'Test Lead';
        lead.Company = 'TestCompany';
        lead.Phone__c = '9090909090';
        lead.Secondary_Phone__c = '9898989898';
        lead.Email = 'standarduser@testorgfil.com';
        insert lead;

        Site_Visit__c sv = new Site_Visit__c();
        sv.Date__c = System.now() + 3;
        sv.Status__c = 'Scheduled';
        sv.Project__c = 'The Ozone Heights';
        sv.SLead__c = lead.Id;
        insert sv;

        ReVisitController.updateLastNote(sv.Id, 'test', System.now());

        Site_Visit__c updated = [SELECT Revisit_Details__c FROM Site_Visit__c WHERE Id = :sv.Id];
        System.assertNotEquals(null, updated.Revisit_Details__c, 'Revisit notes initialized');
        System.assert(updated.Revisit_Details__c.contains('test'), 'Note text appended');
    }

    // Covers the else if (!SVRecord.Revisit_Details__c.trim().equals('')) path
    // (when Revisit_Details__c already has content, noteCount is incremented)
    @isTest
    static void testUpdateLastNote_ExistingNotes() {
        Lead lead = new Lead();
        lead.Lastname = 'Test Lead2';
        lead.Company = 'TestCompany';
        lead.Phone__c = '9191919191';
        lead.Email = 'revisit2@testorgfil.com';
        insert lead;

        Site_Visit__c sv = new Site_Visit__c();
        sv.Date__c = System.now() + 3;
        sv.Status__c = 'Scheduled';
        sv.Project__c = 'The Ozone Heights';
        sv.SLead__c = lead.Id;
        sv.Revisit_Details__c = '\nRe-Visit 1: (April 16, 2026 10:00:00 AM) : Initial note here';
        insert sv;

        Test.startTest();
        // Revisit_Details__c is now non-null and non-blank → triggers else if branch
        ReVisitController.updateLastNote(sv.Id, 'Second revisit note', System.now());
        Test.stopTest();

        Site_Visit__c updated = [SELECT Revisit_Details__c FROM Site_Visit__c WHERE Id = :sv.Id];
        System.assert(updated.Revisit_Details__c.contains('Re-Visit 2:'), 'Second note should increment count to 2');
    }
}