@IsTest
private class SiteVisitTriggerTest {
    
    // If your object has required fields, set them in this method.
    private static Site_Visit__c makeVisit() {
        Site_Visit__c sv = new Site_Visit__c();
        // TODO: If Site_Visit__c has any required fields in your org,
        // set them here. Example:
        // sv.Account__c = someAccountId;
        // sv.Visit_Date__c = Date.today();
        return sv;
    }

    @IsTest
    static void testSingleInsert() {
        Test.startTest();
        Site_Visit__c sv = makeVisit();
        insert sv; // should invoke after-insert trigger path
        Test.stopTest();

        // Basic sanity check: record was inserted
        System.assertNotEquals(null, sv.Id, 'Site_Visit__c should be inserted successfully.');
    }

    @IsTest
    static void testBulkInsert() {
        List<Site_Visit__c> toInsert = new List<Site_Visit__c>();
        for (Integer i = 0; i < 200; i++) {
            toInsert.add(makeVisit());
        }

        Test.startTest();
        insert toInsert; // bulk path for the trigger
        Test.stopTest();

        // Verify all were inserted
        Integer insertedCount = [SELECT COUNT() FROM Site_Visit__c WHERE Id IN :toInsert];
        System.assertEquals(200, insertedCount, 'All Site_Visit__c records should be inserted in bulk.');
    }



	@isTest
    static void test_SiteVisitCompleted_UpdateLead() {
    
       //lead...
        Lead__c l = new Lead__c(
            Name__c = 'Test Lead',
            Phone__c = '9977556688'
        );
        insert l;
    
        ///site visit...
        Site_Visit__c sv = new Site_Visit__c(
            CLead__c = l.Id,
            Status__c = 'Scheduled'
        );
        insert sv;
    
        // Update Site Visit → Change to Completed
        sv.Status__c = 'Completed';
    
        // Add Mandatory Fields for Validation Rule
        sv.Feedback__c = 'Good Visit';
        sv.Site_Visit_Rating__c = 'Hot'; 
    
        update sv;
    
        // Fetch Lead after trigger logic
        Lead__c updatedLead = [
            SELECT Id, Site_Visit_Done__c 
            FROM Lead__c
            WHERE Id = :l.Id
        ];
    
        System.assertEquals('Yes', updatedLead.Site_Visit_Done__c);
    
        // Validate Completed Date is set...
        Site_Visit__c updatedSV = [
            SELECT SV_Completed_Date_Time__c 
            FROM Site_Visit__c 
            WHERE Id = :sv.Id
        ];
    
        System.assertNotEquals(null, updatedSV.SV_Completed_Date_Time__c);
    }

    @isTest
    static void test_AlreadyCompleted_Record() {

        // Lead...
        Lead__c l = new Lead__c(
            Name__c = 'Old Completed Lead',
            Phone__c = '9988778899'
        );
        insert l;

        // Site visit already completed BEFORE INSERT...
        Site_Visit__c sv = new Site_Visit__c(
            //Name = 'SV Completed',
            CLead__c = l.Id,
            Status__c = 'Completed'
        );
        insert sv;

        // Validate Lead updated during AFTER INSERT...
        Lead__c updatedLead = [SELECT Site_Visit_Done__c FROM Lead__c WHERE Id = :l.Id];

        System.assertEquals('Yes', updatedLead.Site_Visit_Done__c,
            'Lead must be updated when Site Visit is inserted as Completed');
    }

		
}