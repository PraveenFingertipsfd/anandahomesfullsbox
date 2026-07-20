/**
 * @description Tests for MilestoneStatusRemarkService and ConstructionMilestoneTrigger.
 *              Verifies milestone status remark capture on creation and status change (pointer 2).
 */
@isTest
private class MilestoneStatusRemarkServiceTest {

    private static Construction_Milestone__c makeMilestone(String status, String remarks) {
        Project__c project = new Project__c(Name = 'P1', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Construction_Milestone__c m = new Construction_Milestone__c(
            Project__c = project.Id,
            Milestone_Name__c = 'Foundation',
            Milestone_Status__c = status,
            Status_Remarks__c = remarks,
            Sequence_Number__c = 1
        );
        insert m;
        return m;
    }

    @isTest
    static void captureOnInsert_createsInitialRemark() {
        Test.startTest();
        Construction_Milestone__c m = makeMilestone('Planned', 'Planned work');
        Test.stopTest();

        List<Milestone_Status_Remark__c> remarks = [
            SELECT Status__c, Previous_Status__c, Remarks__c, Captured_By__c
            FROM Milestone_Status_Remark__c WHERE Construction_Milestone__c = :m.Id
        ];
        System.assertEquals(1, remarks.size());
        System.assertEquals('Planned', remarks[0].Status__c);
        System.assertEquals(null, remarks[0].Previous_Status__c);
        System.assertEquals('Planned work', remarks[0].Remarks__c);
    }

    @isTest
    static void captureOnStatusChange_recordsPreviousAndNew() {
        Construction_Milestone__c m = makeMilestone('In Progress', 'started');

        Test.startTest();
        m.Status_Remarks__c = 'Completed on site';
        m.Milestone_Status__c = 'Completed';
        m.Actual_Completion_Date__c = Date.today();
        update m;
        Test.stopTest();

        List<Milestone_Status_Remark__c> remarks = [
            SELECT Status__c, Previous_Status__c, Remarks__c, Completion_Date__c
            FROM Milestone_Status_Remark__c WHERE Construction_Milestone__c = :m.Id
        ];
        System.assertEquals(2, remarks.size());

        Boolean foundCompleted = false;
        for (Milestone_Status_Remark__c r : remarks) {
            if (r.Status__c == 'Completed') {
                foundCompleted = true;
                System.assertEquals('In Progress', r.Previous_Status__c);
                System.assertEquals('Completed on site', r.Remarks__c);
                System.assertEquals(Date.today(), r.Completion_Date__c);
            }
        }
        System.assert(foundCompleted, 'Completed status change should be captured');
    }

    @isTest
    static void noStatusChange_doesNotCreateRemark() {
        Construction_Milestone__c m = makeMilestone('Planned', 'x');

        Test.startTest();
        m.Status_Remarks__c = 'edited only';
        update m;
        Test.stopTest();

        List<Milestone_Status_Remark__c> remarks = [SELECT Id FROM Milestone_Status_Remark__c WHERE Construction_Milestone__c = :m.Id];
        System.assertEquals(1, remarks.size());
    }

    @isTest
    static void serviceMethods_nullSafe() {
        Test.startTest();
        MilestoneStatusRemarkService.captureForNewMilestones(null);
        MilestoneStatusRemarkService.captureForStatusChanges(new List<Construction_Milestone__c>(), null);
        Test.stopTest();
        System.assert(true);
    }
}