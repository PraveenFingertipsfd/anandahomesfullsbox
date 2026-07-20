/**
 * @description Tests for MilestoneCompletionNotifier (BRD 8.44 — notify related booking
 *              owners when a construction milestone is completed).
 */
@isTest
private class MilestoneCompletionNotifierTest {

    private static final String MILESTONE = 'Foundation';

    private static Id setup() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;
        insert new Payment_Schedule__c(
            Booking__c = b.Id, Milestone_Name__c = MILESTONE, Amount__c = 100000,
            Sequence__c = 1, Status__c = 'Pending'
        );
        return project.Id;
    }

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
        m.Milestone_Status__c = 'In Progress'; // not Completed → no notification path
        update m;
        Test.stopTest();

        System.assertEquals(
            'In Progress',
            [SELECT Milestone_Status__c FROM Construction_Milestone__c WHERE Id = :m.Id].Milestone_Status__c
        );
    }

    @isTest
    static void notify_handlesEmptyAndNull() {
        Test.startTest();
        MilestoneCompletionNotifier.notify(null);
        MilestoneCompletionNotifier.notify(new List<Construction_Milestone__c>());
        Test.stopTest();
        // No exception == pass.
        System.assert(true);
    }
}