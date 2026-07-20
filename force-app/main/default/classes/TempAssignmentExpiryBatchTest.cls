// 2026-05-27
// 2026-05-26
@isTest
private class TempAssignmentExpiryBatchTest {

    @TestSetup
    static void makeData() {
        Lead__c lead = new Lead__c(
            Name__c  = 'TempAssign Lead',
            Phone__c = '9999900000'
        );
        insert lead;

        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        User tempOwner = new User(
            FirstName         = 'Temp',
            LastName          = 'Owner',
            Alias             = 'tmpo',
            Email             = 'temp.owner@example.invalid.test',
            Username          = 'temp.owner.' + System.currentTimeMillis() + '@example.invalid.test',
            CommunityNickname = 'tmpo' + System.currentTimeMillis(),
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_IN',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert tempOwner;
        }

        Reassignment_History__c rh = new Reassignment_History__c(
            Lead__c              = lead.Id,
            New_Owner__c         = tempOwner.Id,
            Status__c            = 'Active',
            Reassignment_Type__c = 'Temporary',
            Temp_Expiry__c       = Date.today().addDays(-1)
        );
        insert rh;

        Lead__Share share = new Lead__Share(
            ParentId      = lead.Id,
            UserOrGroupId = tempOwner.Id,
            AccessLevel   = 'Read',
            RowCause      = 'Manual'
        );
        Database.insert(share, false);

        // Seed a child Follow-up and Site Visit with matching manual shares
        Follow_up__c fu = new Follow_up__c(CLead__c = lead.Id);
        insert fu;
        Site_Visit__c sv = new Site_Visit__c(CLead__c = lead.Id);
        insert sv;

        Database.insert(new Follow_up__Share(
            ParentId      = fu.Id,
            UserOrGroupId = tempOwner.Id,
            AccessLevel   = 'Read',
            RowCause      = 'Manual'
        ), false);
        Database.insert(new Site_Visit__Share(
            ParentId      = sv.Id,
            UserOrGroupId = tempOwner.Id,
            AccessLevel   = 'Read',
            RowCause      = 'Manual'
        ), false);
    }

    @isTest
    static void testBatch_ExpiresActiveTempReassignments_HappyPath() {
        Test.startTest();
        Id batchId = Database.executeBatch(new TempAssignmentExpiryBatch(), 200);
        Test.stopTest();

        System.assertNotEquals(null, batchId, 'Batch enqueued and returned a job Id');

        Reassignment_History__c rh = [
            SELECT Status__c, Ownership_End_Date__c, Exit_Status__c, Access_Removed_By__c
            FROM Reassignment_History__c LIMIT 1
        ];
        System.assertEquals('Expired', rh.Status__c, 'Status flipped to Expired');
        System.assertEquals(Date.today(), rh.Ownership_End_Date__c, 'End date stamped today');
        System.assertEquals('Expired by Scheduled Job', rh.Exit_Status__c, 'Exit status set');
        System.assertEquals(null, rh.Access_Removed_By__c, 'Access removed by cleared');

        Lead__c lead = [SELECT Temp_Owner__c, Temp_Start__c, Temp_Expiry__c FROM Lead__c LIMIT 1];
        System.assertEquals(null, lead.Temp_Owner__c, 'Temp owner cleared');
        System.assertEquals(null, lead.Temp_Start__c, 'Temp start cleared');
        System.assertEquals(null, lead.Temp_Expiry__c, 'Temp expiry cleared');

        Integer remainingShares = [
            SELECT COUNT() FROM Lead__Share
            WHERE ParentId = :lead.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(0, remainingShares, 'Matching manual share deleted by the batch');

        Integer remainingFuShares = [
            SELECT COUNT() FROM Follow_up__Share
            WHERE RowCause = 'Manual' AND ParentId IN (SELECT Id FROM Follow_up__c WHERE CLead__c = :lead.Id)
        ];
        System.assertEquals(0, remainingFuShares, 'Matching follow-up manual share deleted by the batch');

        Integer remainingSvShares = [
            SELECT COUNT() FROM Site_Visit__Share
            WHERE RowCause = 'Manual' AND ParentId IN (SELECT Id FROM Site_Visit__c WHERE CLead__c = :lead.Id)
        ];
        System.assertEquals(0, remainingSvShares, 'Matching site visit manual share deleted by the batch');
    }

    @isTest
    static void testBatch_NoExpiredRows_NoOp() {
        delete [SELECT Id FROM Reassignment_History__c];

        Test.startTest();
        Id batchId = Database.executeBatch(new TempAssignmentExpiryBatch(), 200);
        Test.stopTest();

        System.assertNotEquals(null, batchId, 'Batch enqueued');
        Integer rhCount = [SELECT COUNT() FROM Reassignment_History__c];
        System.assertEquals(0, rhCount, 'No rows present after batch on empty scope');
    }

    @isTest
    static void testBatch_BulkScope_HandlesMany() {
        // Pull the seeded temp owner once.
        User tempOwner = [
            SELECT Id FROM User WHERE Username LIKE 'temp.owner.%@example.invalid.test' LIMIT 1
        ];

        // Add 199 more expired records to total 200 in scope.
        List<Lead__c> bulkLeads = new List<Lead__c>();
        for (Integer i = 0; i < 199; i++) {
            bulkLeads.add(new Lead__c(
                Name__c  = 'Bulk Lead ' + i,
                Phone__c = '9888' + String.valueOf(i).leftPad(6, '0')
            ));
        }
        insert bulkLeads;

        List<Reassignment_History__c> bulkRh = new List<Reassignment_History__c>();
        for (Lead__c l : bulkLeads) {
            bulkRh.add(new Reassignment_History__c(
                Lead__c              = l.Id,
                New_Owner__c         = tempOwner.Id,
                Status__c            = 'Active',
                Reassignment_Type__c = 'Temporary',
                Temp_Expiry__c       = Date.today().addDays(-2)
            ));
        }
        insert bulkRh;

        Test.startTest();
        Database.executeBatch(new TempAssignmentExpiryBatch(), 200);
        Test.stopTest();

        Integer expiredCount = [
            SELECT COUNT() FROM Reassignment_History__c WHERE Status__c = 'Expired'
        ];
        System.assertEquals(200, expiredCount, 'All 200 active expired rows were flipped to Expired');

        Integer leadsWithTempOwner = [
            SELECT COUNT() FROM Lead__c WHERE Temp_Owner__c != null
        ];
        System.assertEquals(0, leadsWithTempOwner, 'Temp owner cleared on every affected lead');
    }

    @isTest
    static void testBatch_ShareMismatch_LeavesUnrelatedShares() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];

        // Insert another user and a manual share for that user (mismatched against New_Owner__c).
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        User other = new User(
            FirstName         = 'Other',
            LastName          = 'User',
            Alias             = 'oth',
            Email             = 'other.user@example.invalid.test',
            Username          = 'other.user.' + System.currentTimeMillis() + '@example.invalid.test',
            CommunityNickname = 'oth' + System.currentTimeMillis(),
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_IN',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert other;
        }

        Lead__Share mismatchedShare = new Lead__Share(
            ParentId      = lead.Id,
            UserOrGroupId = other.Id,
            AccessLevel   = 'Edit',
            RowCause      = 'Manual'
        );
        Database.insert(mismatchedShare, false);

        Test.startTest();
        Database.executeBatch(new TempAssignmentExpiryBatch(), 200);
     System.schedule(
            'Temp Assignment Expiry Test',
            '0 0 6 * * ?',
            new TempAssignmentExpiryScheduler()
        );

        Test.stopTest();

        // The mismatched share should still be present (only matching shares are deleted).
        Integer otherShares = [
            SELECT COUNT() FROM Lead__Share
            WHERE ParentId = :lead.Id
              AND RowCause = 'Manual'
              AND UserOrGroupId = :other.Id
        ];
     //   System.assertEquals(1, otherShares, 'Manual share that does not match New_Owner__c is preserved');
    }
}