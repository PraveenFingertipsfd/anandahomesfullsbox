/**
 * @description Captures milestone status remarks for Construction Milestones into the
 *              Milestone_Status_Remark__c history object. A snapshot is taken every time
 *              Milestone_Status__c changes, reading the remark text from
 *              Construction_Milestone__c.Status_Remarks__c.
 *
 *              BRD pointer 2: "Milestone status remarks to be captured."
 * @author System
 */
public with sharing class MilestoneStatusRemarkService {

    /**
     * @description Captures a status remark for newly created milestones (initial status).
     * @param newMilestones Trigger.new list (already committed)
     */
    public static void captureForNewMilestones(List<Construction_Milestone__c> newMilestones) {
        if (newMilestones == null || newMilestones.isEmpty()) return;

        List<Milestone_Status_Remark__c> toInsert = new List<Milestone_Status_Remark__c>();
        for (Construction_Milestone__c m : newMilestones) {
            toInsert.add(buildRemark(m, null, m.Milestone_Status__c));
        }
        insertRemarks(toInsert);
    }

    /**
     * @description Captures a status remark for every milestone whose status changed.
     * @param newMilestones Trigger.new list
     * @param oldMap Trigger.oldMap
     */
    public static void captureForStatusChanges(List<Construction_Milestone__c> newMilestones, Map<Id, Construction_Milestone__c> oldMap) {
        if (newMilestones == null || newMilestones.isEmpty() || oldMap == null) return;

        List<Milestone_Status_Remark__c> toInsert = new List<Milestone_Status_Remark__c>();
        for (Construction_Milestone__c m : newMilestones) {
            Construction_Milestone__c oldM = oldMap.get(m.Id);
            if (oldM == null) continue;
            if (m.Milestone_Status__c == oldM.Milestone_Status__c) continue;

            toInsert.add(buildRemark(m, oldM.Milestone_Status__c, m.Milestone_Status__c));
        }
        insertRemarks(toInsert);
    }

    // ==================== HELPERS ====================

    private static Milestone_Status_Remark__c buildRemark(
        Construction_Milestone__c m, String previousStatus, String status
    ) {
        return new Milestone_Status_Remark__c(
            Construction_Milestone__c = m.Id,
            Previous_Status__c = previousStatus,
            Status__c = status,
            Remarks__c = m.Status_Remarks__c,
            Completion_Date__c = m.Actual_Completion_Date__c,
            Captured_By__c = UserInfo.getUserId(),
            Captured_Date__c = System.now()
        );
    }

    private static void insertRemarks(List<Milestone_Status_Remark__c> remarks) {
        if (remarks == null || remarks.isEmpty()) return;
        Database.insert(remarks, false);
    }
}