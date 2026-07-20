@isTest
public class RelatedSourceTrigger_Test {

    @isTest
    static void test_ReEngaged_CP_Lead_Update_And_Sharing() {

        /* ----------------------------
           Create CP Owner User
        ----------------------------- */
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User cpOwner = new User(
            FirstName = 'CP',
            LastName = 'Owner',
            Email = 'cpowner@test.com',
            Username = 'cpowner' + System.currentTimeMillis() + '@test.com',
            Alias = 'cpown',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert cpOwner;

        /* ----------------------------
           Create Lead (Owner ≠ CP Owner)
        ----------------------------- */
        Lead ld = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Company',
            Phone__c = '9999999999',
            OwnerId = UserInfo.getUserId()
        );
        insert ld;

        /* ----------------------------
           Create Channel Partner
        ----------------------------- */
        Channel_Partner__c cp = new Channel_Partner__c(
            Mobile_Number__c = '8888888888',
            OwnerId = cpOwner.Id
        );
        insert cp;

        /* ----------------------------
           Create custom Lead__c (needed for CLead__c on Related Source
           to avoid StringException in SendLeadDetailsToPulseTeleSystem)
        ----------------------------- */
        Lead__c customLead = new Lead__c(
            Name__c = 'Test Custom Lead',
            Phone__c = '7777777777',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert customLead;

        /* ----------------------------
           Create Related Source (Re-Engaged)
        ----------------------------- */
        Related_Source__c rs = new Related_Source__c(
            Medium__c = 'CHANNEL PARTNERS',
            Channel_Partner__c = cp.Id,
            SLead__c = ld.Id,
            CLead__c = customLead.Id,
            Lead_Type__c = 'Re-Engaged'
        );

        Test.startTest();
        insert rs;

        // Assert BEFORE stopTest — SLeadTrigger queues a @future that
        // deletes the standard Lead at stopTest, so we must query now.
        // The RS trigger runs synchronously, so the Lead update and
        // LeadShare insert are already committed at this point.

        Lead updatedLead = [
            SELECT Re_Engaged_CP_Date__c
            FROM Lead
            WHERE Id = :ld.Id
        ];

        System.assertEquals(
            System.today(),
            updatedLead.Re_Engaged_CP_Date__c,
            'Re-Engaged CP Date should be populated'
        );

        Integer shareCount = [
            SELECT COUNT()
            FROM LeadShare
            WHERE LeadId = :ld.Id
            AND UserOrGroupId = :cpOwner.Id
        ];

        System.assertEquals(
            1,
            shareCount,
            'CP Owner should have Read access to Lead'
        );

        Test.stopTest();
    }
}