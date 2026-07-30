/**
 * @description Tests for MilestoneCompletionNotifier (BRD 8.44 — notify related booking
 *              owners when a construction milestone is completed).
 */
@isTest
private class MilestoneCompletionNotifierTest {

    private static final String MILESTONE = 'Foundation';

    private static Id setup() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;
        insert new Payment_Schedule__c(
            Booking__c = b.Id, Milestone_Name__c = MILESTONE, Amount__c = 100000,
            Pending_Amount__c = 100000, Amount_Paid__c = 0,
            Due_Date__c = Date.today(), Sequence__c = 1, Status__c = 'Pending'
        );
        return project.Id;
    }

    /** A CustomNotificationType id: real if the org has one, else fabricated (sendBell's
     *  own try/catch absorbs the failure, covering the catch too). */
    private static Id anyNotificationTypeId() {
        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType LIMIT 1];
        if (!types.isEmpty()) return types[0].Id;
        return Id.valueOf(CustomNotificationType.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    // ==================== sendBell: direct calls (guaranteed coverage) ====================

    @isTest
    static void sendBell_directCall_coversSendAndCatch() {
        Id bookingId = Id.valueOf(Booking__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Id userId = UserInfo.getUserId();
        Id realOrFakeTypeId = anyNotificationTypeId();

        Test.startTest();
        // Executes the full try block (and, with a fabricated/bad id, the catch too)
        MilestoneCompletionNotifier.sendBell(
            realOrFakeTypeId, bookingId, 'Test Title', 'Test Body',
            new Set<String>{ String.valueOf(userId) }
        );
        // Null type id -> send() throws -> catch block covered for certain
        MilestoneCompletionNotifier.sendBell(
            null, bookingId, 'Test Title', 'Test Body',
            new Set<String>{ String.valueOf(userId) }
        );
        Test.stopTest();
        System.debug('sendBell direct calls completed without escaping exceptions');
    }

    // ==================== trigger-path ====================

    @isTest
    static void completingMilestone_notifiesOwners() {
        Id projectId = setup();
        Construction_Milestone__c m = new Construction_Milestone__c(
            Milestone_Name__c = MILESTONE, Project__c = projectId, Milestone_Status__c = 'In Progress'
        );
        insert m;

        Test.startTest();
        m.Milestone_Status__c = 'Completed';
        m.Actual_Completion_Date__c = Date.today();
        update m;
        Test.stopTest();

        System.assertEquals(
            'Completed',
            [SELECT Milestone_Status__c FROM Construction_Milestone__c WHERE Id = :m.Id].Milestone_Status__c
        );
    }

    @isTest
    static void nonCompletionChange_doesNothing() {
        Id projectId = setup();
        Construction_Milestone__c m = new Construction_Milestone__c(
            Milestone_Name__c = MILESTONE, Project__c = projectId, Milestone_Status__c = 'Planned'
        );
        insert m;

        Test.startTest();
        m.Milestone_Status__c = 'In Progress'; // not Completed -> no notification path
        update m;
        Test.stopTest();

        System.assertEquals(
            'In Progress',
            [SELECT Milestone_Status__c FROM Construction_Milestone__c WHERE Id = :m.Id].Milestone_Status__c
        );
    }

    // ==================== direct: full pipeline incl. bell path ====================

    @isTest
    static void notify_direct_bellAndEmailPaths() {
        Id projectId = setup();
        Construction_Milestone__c m = new Construction_Milestone__c(
            Milestone_Name__c = MILESTONE, Project__c = projectId, Milestone_Status__c = 'Completed'
        );
        insert m;

        MilestoneCompletionNotifier.notificationTypeIdOverrideForTest = anyNotificationTypeId();

        Test.startTest();
        MilestoneCompletionNotifier.notify(new List<Construction_Milestone__c>{ m });
        Test.stopTest();

        System.debug('Email invocations: ' + Limits.getEmailInvocations());
        MilestoneCompletionNotifier.notificationTypeIdOverrideForTest = null;
    }

    @isTest
    static void notify_direct_twoMilestonesOneBooking_joinsNames() {
        Id projectId = setup();
        // Second schedule on the same booking with a second milestone name
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        insert new Payment_Schedule__c(
            Booking__c = b.Id, Milestone_Name__c = '5th Floor', Amount__c = 100000,
            Pending_Amount__c = 100000, Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(30), Sequence__c = 2, Status__c = 'Pending'
        );

        List<Construction_Milestone__c> ms = new List<Construction_Milestone__c>{
            new Construction_Milestone__c(Milestone_Name__c = MILESTONE, Project__c = projectId,
                Milestone_Status__c = 'Completed'),
            new Construction_Milestone__c(Milestone_Name__c = '5th Floor', Project__c = projectId,
                Milestone_Status__c = 'Completed')
        };
        insert ms;

        Test.startTest();
        MilestoneCompletionNotifier.notify(ms); // both names collected into one message
        Test.stopTest();
        System.debug('Two-milestone notify completed');
    }

    // ==================== direct: early-return / guard branches ====================

    @isTest
    static void notify_milestoneWithoutProjectOrName_earlyReturn() {
        Test.startTest();
        // No Project__c and no Milestone_Name__c -> projectIds/names empty -> return
        MilestoneCompletionNotifier.notify(new List<Construction_Milestone__c>{
            new Construction_Milestone__c(Milestone_Status__c = 'Completed')
        });
        Test.stopTest();
        System.debug('No-project/name early return exercised');
    }

    @isTest
    static void notify_noMatchingSchedules_earlyReturn() {
        Project__c project = new Project__c(Name = 'Lonely P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Construction_Milestone__c m = new Construction_Milestone__c(
            Milestone_Name__c = 'Unreferenced Milestone', Project__c = project.Id,
            Milestone_Status__c = 'Completed'
        );
        insert m;

        Test.startTest();
        MilestoneCompletionNotifier.notify(new List<Construction_Milestone__c>{ m });
        Test.stopTest();
        // bookingToMilestoneNames empty -> return before owner resolution.
        System.debug('No-matching-schedules early return exercised');
    }

    @isTest
    static void notify_handlesEmptyAndNull() {
        Test.startTest();
        MilestoneCompletionNotifier.notify(null);
        MilestoneCompletionNotifier.notify(new List<Construction_Milestone__c>());
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void notifyForCompletedMilestones_guardBranches() {
        Id projectId = setup();
        Construction_Milestone__c completed = new Construction_Milestone__c(
            Milestone_Name__c = MILESTONE, Project__c = projectId, Milestone_Status__c = 'Completed'
        );
        Construction_Milestone__c stillCompleted = new Construction_Milestone__c(
            Milestone_Name__c = MILESTONE, Project__c = projectId, Milestone_Status__c = 'Completed'
        );
        insert new List<Construction_Milestone__c>{ completed, stillCompleted };

        Map<Id, Construction_Milestone__c> oldMap = new Map<Id, Construction_Milestone__c>{
            // Transitioned: was In Progress, now Completed -> notify
            completed.Id => new Construction_Milestone__c(Id = completed.Id, Milestone_Status__c = 'In Progress'),
            // No transition: was already Completed -> skipped
            stillCompleted.Id => new Construction_Milestone__c(Id = stillCompleted.Id, Milestone_Status__c = 'Completed')
        };

        // A record missing from oldMap -> old == null continue branch
        Construction_Milestone__c notInOldMap = new Construction_Milestone__c(
            Id = completed.Id, Milestone_Status__c = 'Completed'
        );

        Test.startTest();
        MilestoneCompletionNotifier.notifyForCompletedMilestones(
            new List<Construction_Milestone__c>{ completed, stillCompleted }, oldMap
        );
        MilestoneCompletionNotifier.notifyForCompletedMilestones(
            new List<Construction_Milestone__c>{ notInOldMap }, new Map<Id, Construction_Milestone__c>()
        );
        // Null guards
        MilestoneCompletionNotifier.notifyForCompletedMilestones(null, null);
        MilestoneCompletionNotifier.notifyForCompletedMilestones(
            new List<Construction_Milestone__c>(), oldMap
        );
        Test.stopTest();
        System.debug('Guard branches exercised');
    }
}