@isTest
private class LeadTriggerTest {

    // ──────────────────────────────────────────────────────────────────────
    // BEFORE INSERT: Admin profile → RecordType assignment + RoundRobin
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testBeforeInsert_AdminProfile_PreSales() {
        Lead__c ld = new Lead__c(
            Name__c = 'PreSales Insert Lead',
            Phone__c = '9000200001',
            Allocated_Project__c = 'The Ozone Heights'
        );

        Test.startTest();
        insert ld;
        Test.stopTest();

        Lead__c inserted = [SELECT RecordType.Name FROM Lead__c WHERE Id = :ld.Id];
        System.assertNotEquals(null, inserted.RecordType.Name, 'RecordType should be set');
    }

    @isTest
    static void testBeforeInsert_AdminProfile_WalkIn() {
        Lead__c ld = new Lead__c(
            Name__c = 'WalkIn Insert Lead',
            Phone__c = '9000200002',
            Allocated_Project__c = 'The Ozone Heights',
            Lead_source__c = 'Walk-in'
        );

        Test.startTest();
        insert ld;
        Test.stopTest();

        Lead__c inserted = [SELECT Lead_Status__c, RecordType.Name FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals('New Sales Enquiry', inserted.Lead_Status__c);
    }

    // ──────────────────────────────────────────────────────────────────────
    // BEFORE INSERT: Non-admin profile → Lead_Assigned__c = true
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testBeforeInsert_NonAdminProfile() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Pre-Sales Executive' LIMIT 1];
        if (profiles.isEmpty()) return;

        User preSalesUser = new User(
            FirstName = 'PS', LastName = 'Exec',
            Username = 'psexec' + System.currentTimeMillis() + '@test.com',
            Email = 'psexec@test.com', Alias = 'psexe',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = profiles[0].Id
        );
        insert preSalesUser;

        System.runAs(preSalesUser) {
            Lead__c ld = new Lead__c(
                Name__c = 'NonAdmin Lead',
                Phone__c = '9000200003',
                Allocated_Project__c = 'The Ozone Heights'
            );

            Test.startTest();
            insert ld;
            Test.stopTest();

            Lead__c inserted = [SELECT Lead_Assigned__c FROM Lead__c WHERE Id = :ld.Id];
            System.assertEquals(true, inserted.Lead_Assigned__c, 'Non-admin insert should set Lead_Assigned__c = true');
        }
    }

    @isTest
    static void testBeforeInsert_NonAdmin_WalkIn() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Pre-Sales Executive' LIMIT 1];
        if (profiles.isEmpty()) return;

        User preSalesUser = new User(
            FirstName = 'PS', LastName = 'WalkExec',
            Username = 'pswalk' + System.currentTimeMillis() + '@test.com',
            Email = 'pswalk@test.com', Alias = 'pswlk',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = profiles[0].Id
        );
        insert preSalesUser;

        System.runAs(preSalesUser) {
            Lead__c ld = new Lead__c(
                Name__c = 'NonAdmin WalkIn Lead',
                Phone__c = '9000200004',
                Allocated_Project__c = 'The Ozone Heights',
                Lead_source__c = 'Walk-in'
            );

            Test.startTest();
            insert ld;
            Test.stopTest();

            Lead__c inserted = [SELECT Lead_Status__c FROM Lead__c WHERE Id = :ld.Id];
            System.assertEquals('New Sales Enquiry', inserted.Lead_Status__c);
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // AFTER INSERT: afterinsertLogic2 creates Related_Source__c
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testAfterInsert_CreatesRelatedSource() {
        Lead__c ld = new Lead__c(
            Name__c = 'AfterInsert Lead',
            Phone__c = '9000200005',
            Allocated_Project__c = 'The Ozone Heights',
            Primary_Source__c = 'Digital',
            Primary_Sub_Source__c = 'Google'
        );

        Test.startTest();
        insert ld;
        Test.stopTest();

        List<Related_Source__c> rsList = [SELECT Id, CLead__c FROM Related_Source__c WHERE CLead__c = :ld.Id];
        System.assert(!rsList.isEmpty(), 'Related_Source__c should be created on lead insert');
    }

    // ──────────────────────────────────────────────────────────────────────
    // BEFORE UPDATE: phone/email change duplicate validation
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testBeforeUpdate_PhoneChange() {
        Lead__c ld = new Lead__c(
            Name__c = 'Update Phone Lead',
            Phone__c = '9000200006',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        Test.startTest();
        ld.Phone__c = '9000200007';
        update ld;
        Test.stopTest();

        Lead__c updated = [SELECT Phone__c FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals('9000200007', updated.Phone__c);
    }

    @isTest
    static void testBeforeUpdate_EmailChange() {
        Lead__c ld = new Lead__c(
            Name__c = 'Update Email Lead',
            Phone__c = '9000200008',
            Email__c = 'old@test.com',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        Test.startTest();
        ld.Email__c = 'new@test.com';
        update ld;
        Test.stopTest();
    }

    @isTest
    static void testBeforeUpdate_SecondaryPhoneChange() {
        Lead__c ld = new Lead__c(
            Name__c = 'Update SecPhone Lead',
            Phone__c = '9000200009',
            Secondary_Phone__c = '9000200010',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        Test.startTest();
        ld.Secondary_Phone__c = '9000200011';
        update ld;
        Test.stopTest();
    }

    @isTest
    static void testBeforeUpdate_SecondaryEmailChange() {
        Lead__c ld = new Lead__c(
            Name__c = 'Update SecEmail Lead',
            Phone__c = '9000200012',
            Secondary_Email__c = 'oldsec@test.com',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        Test.startTest();
        ld.Secondary_Email__c = 'newsec@test.com';
        update ld;
        Test.stopTest();
    }

    // ──────────────────────────────────────────────────────────────────────
    // AFTER UPDATE: status change to Unqualified/Closed Lost
    // Cancels scheduled SVs and open (Scheduled/Pending) follow-ups
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testAfterUpdate_StatusToUnqualified() {
        Lead__c ld = new Lead__c(
            Name__c = 'Unqualified Lead',
            Phone__c = '9000200020',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        Site_Visit__c sv = new Site_Visit__c(CLead__c = ld.Id, Status__c = 'Scheduled', Date__c = System.now().addDays(3));
        insert sv;

        // Insert one at a time — FollowUpHandler.updateLeadFollowupDates fails on
        // multiple follow-ups for the same lead in a single DML (duplicate id in list)
        Follow_up__c fuScheduled = new Follow_up__c(CLead__c = ld.Id, Status__c = 'Scheduled', Scheduled_Date__c = System.now().addDays(1));
        insert fuScheduled;
        Follow_up__c fuPending = new Follow_up__c(CLead__c = ld.Id, Status__c = 'Pending', Scheduled_Date__c = System.now().addDays(2));
        insert fuPending;
        Follow_up__c fuCompleted = new Follow_up__c(
            CLead__c = ld.Id, Status__c = 'Completed', Scheduled_Date__c = System.now().addDays(3),
            Completed_Date__c = System.now().addDays(4), Comments__c = 'Done', Call_Duration_In_Mins__c = 5
        );
        insert fuCompleted;

        Test.startTest();
        ld.Lead_Status__c = 'Unqualified';
        ld.Unqualified_Reason__c = 'Booked with Competitor';
        update ld;
        Test.stopTest();

        Site_Visit__c updatedSV = [SELECT Status__c FROM Site_Visit__c WHERE Id = :sv.Id];
        System.assertEquals('Cancelled', updatedSV.Status__c, 'Scheduled SV should be cancelled');

        Map<Id, Follow_up__c> fuMap = new Map<Id, Follow_up__c>(
            [SELECT Id, Status__c, Comments__c FROM Follow_up__c WHERE CLead__c = :ld.Id]
        );
        System.assertEquals('Cancelled', fuMap.get(fuScheduled.Id).Status__c, 'Scheduled FU should be cancelled');
        System.assertEquals('The system has cancelled the follow-up as the Lead stage was updated',
            fuMap.get(fuScheduled.Id).Comments__c, 'System comment should be stamped on blank Comments');
        System.assertEquals('Cancelled', fuMap.get(fuPending.Id).Status__c, 'Pending FU should be cancelled');
        System.assertEquals('Completed', fuMap.get(fuCompleted.Id).Status__c, 'Completed FU should stay Completed');
        System.assertEquals('Done', fuMap.get(fuCompleted.Id).Comments__c, 'Completed FU comment should be untouched');
    }

    @isTest
    static void testAfterUpdate_StatusToClosedLost_CancelsOpenFollowups() {
        // Walk-in → Sales record type; 'Closed Lost' is only valid on the Sales record type
        Lead__c ld = new Lead__c(
            Name__c = 'ClosedLost Lead',
            Phone__c = '9000200021',
            Allocated_Project__c = 'The Ozone Heights',
            Lead_source__c = 'Walk-in'
        );
        insert ld;

        // Scheduled FU with a user comment — status must change but the comment must be preserved
        Follow_up__c fuScheduled = new Follow_up__c(
            CLead__c = ld.Id, Status__c = 'Scheduled', Scheduled_Date__c = System.now().addDays(1),
            Comments__c = 'Customer asked to call next week'
        );
        insert fuScheduled;
        Follow_up__c fuPending = new Follow_up__c(CLead__c = ld.Id, Status__c = 'Pending', Scheduled_Date__c = System.now().addDays(2));
        insert fuPending;

        Test.startTest();
        ld.Lead_Status__c = 'Closed Lost';
        ld.Closed_Lost_Reason__c = 'Booked with Competitor';
        update ld;
        Test.stopTest();

        Map<Id, Follow_up__c> fuMap = new Map<Id, Follow_up__c>(
            [SELECT Id, Status__c, Comments__c FROM Follow_up__c WHERE CLead__c = :ld.Id]
        );
        System.assertEquals('Cancelled', fuMap.get(fuScheduled.Id).Status__c, 'Scheduled FU should be cancelled on Closed Lost');
        System.assertEquals('Customer asked to call next week', fuMap.get(fuScheduled.Id).Comments__c,
            'Existing user comment should be preserved');
        System.assertEquals('Cancelled', fuMap.get(fuPending.Id).Status__c, 'Pending FU should be cancelled on Closed Lost');
    }

    @isTest
    static void testAfterUpdate_StatusToBooked_FollowupsStayOpen() {
        // Walk-in → Sales record type; 'Booked' is only valid on the Sales record type
        Lead__c ld = new Lead__c(
            Name__c = 'Booked Lead',
            Phone__c = '9000200022',
            Allocated_Project__c = 'The Ozone Heights',
            Lead_source__c = 'Walk-in'
        );
        insert ld;

        Site_Visit__c sv = new Site_Visit__c(CLead__c = ld.Id, Status__c = 'Scheduled', Date__c = System.now().addDays(3));
        insert sv;

        Follow_up__c fuScheduled = new Follow_up__c(CLead__c = ld.Id, Status__c = 'Scheduled', Scheduled_Date__c = System.now().addDays(1));
        insert fuScheduled;
        Follow_up__c fuPending = new Follow_up__c(CLead__c = ld.Id, Status__c = 'Pending', Scheduled_Date__c = System.now().addDays(2));
        insert fuPending;

        Test.startTest();
        ld.Lead_Status__c = 'Booked';
        update ld;
        Test.stopTest();

        // Site visit cancellation still applies to Booked (existing behaviour)…
        Site_Visit__c updatedSV = [SELECT Status__c FROM Site_Visit__c WHERE Id = :sv.Id];
        System.assertEquals('Cancelled', updatedSV.Status__c, 'Scheduled SV should be cancelled on Booked');

        // …but follow-ups must stay open on Booked
        Map<Id, Follow_up__c> fuMap = new Map<Id, Follow_up__c>(
            [SELECT Id, Status__c FROM Follow_up__c WHERE CLead__c = :ld.Id]
        );
        System.assertEquals('Scheduled', fuMap.get(fuScheduled.Id).Status__c, 'Scheduled FU should stay open on Booked');
        System.assertEquals('Pending', fuMap.get(fuPending.Id).Status__c, 'Pending FU should stay open on Booked');
    }

    // ──────────────────────────────────────────────────────────────────────
    // AFTER UPDATE: owner change (ownerChange set)
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testAfterUpdate_OwnerChange() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User newOwner = new User(
            FirstName = 'New', LastName = 'Owner',
            Username = 'newowner' + System.currentTimeMillis() + '@test.com',
            Email = 'newowner@test.com', Alias = 'nownr',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert newOwner;

        Lead__c ld = new Lead__c(
            Name__c = 'Owner Change Lead',
            Phone__c = '9000200030',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        Test.startTest();
        ld.OwnerId = newOwner.Id;
        update ld;
        Test.stopTest();

        Lead__c updated = [SELECT OwnerId FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals(newOwner.Id, updated.OwnerId);
    }

    // ──────────────────────────────────────────────────────────────────────
    // BEFORE DELETE: prevent deletion when child records exist
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testBeforeDelete_WithChildRecords() {
        Lead__c ld = new Lead__c(
            Name__c = 'Delete Blocked Lead',
            Phone__c = '9000200040',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        Site_Visit__c sv = new Site_Visit__c(CLead__c = ld.Id, Status__c = 'Completed');
        insert sv;

        Test.startTest();
        try {
            delete ld;
            System.assert(false, 'Should have thrown DML error');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('delete related child records'),
                'Should block deletion when child records exist');
        }
        Test.stopTest();
    }

    @isTest
    static void testBeforeDelete_NoChildRecords() {
        Lead__c ld = new Lead__c(
            Name__c = 'Delete OK Lead',
            Phone__c = '9000200041',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert ld;

        // Delete related source records created by trigger
        List<Related_Source__c> rs = [SELECT Id FROM Related_Source__c WHERE CLead__c = :ld.Id];
        if (!rs.isEmpty()) delete rs;

        Test.startTest();
        delete ld;
        Test.stopTest();

        List<Lead__c> deleted = [SELECT Id FROM Lead__c WHERE Id = :ld.Id];
        System.assertEquals(0, deleted.size(), 'Lead should be deleted when no child records exist');
    }

    // ──────────────────────────────────────────────────────────────────────
    // AFTER UPDATE: CP owner change leads (Criteria_Date__c branch)
    // ──────────────────────────────────────────────────────────────────────

    @isTest
    static void testAfterUpdate_CPOwnerChangeLeads() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User cpOwner = new User(
            FirstName = 'CP', LastName = 'Own',
            Username = 'cpown' + System.currentTimeMillis() + '@test.com',
            Email = 'cpown@test.com', Alias = 'cpown',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        User newOwner = new User(
            FirstName = 'New', LastName = 'Own2',
            Username = 'newown2' + System.currentTimeMillis() + '@test.com',
            Email = 'newown2@test.com', Alias = 'nwon2',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert new List<User>{ cpOwner, newOwner };

        Channel_Partner__c cp = new Channel_Partner__c(
            Mobile_Number__c = '9000200050',
            OwnerId = cpOwner.Id
        );
        insert cp;

        Lead__c ld = new Lead__c(
            Name__c = 'CP OwnerChange Lead',
            Phone__c = '9000200051',
            Allocated_Project__c = 'The Ozone Heights',
            Primary_Source__c = 'CP',
            Re_Engaged_CP_Date__c = Date.today()
        );
        insert ld;

        Related_Source__c rs = new Related_Source__c(
            CLead__c = ld.Id,
            Channel_Partner__c = cp.Id
        );
        insert rs;

        Test.startTest();
        ld.OwnerId = newOwner.Id;
        update ld;
        Test.stopTest();
    }
}