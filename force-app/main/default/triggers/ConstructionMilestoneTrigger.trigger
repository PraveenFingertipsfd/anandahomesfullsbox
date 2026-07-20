/**
 * @description Trigger on Construction_Milestone__c. Captures milestone status remarks
 *              (BRD pointer 2), notifies related booking owners on completion (BRD §8.44),
 *              and raises the Bank-side prorata demand on completion (BRD §8.4).
 * @author System
 */
trigger ConstructionMilestoneTrigger on Construction_Milestone__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            MilestoneStatusRemarkService.captureForNewMilestones(Trigger.new);
        } else if (Trigger.isUpdate) {
            MilestoneStatusRemarkService.captureForStatusChanges(Trigger.new, Trigger.oldMap);
            MilestoneCompletionNotifier.notifyForCompletedMilestones(Trigger.new, Trigger.oldMap);

            // BRD §8.4: when a milestone is completed, raise the Bank-side prorata demand
            // (Bank Flat + Bank GST) for the related Prorata/Partial bookings.
            List<Construction_Milestone__c> justCompleted = new List<Construction_Milestone__c>();
            for (Construction_Milestone__c m : Trigger.new) {
                Construction_Milestone__c old = Trigger.oldMap.get(m.Id);
                if (old != null
                    && 'Completed'.equalsIgnoreCase(m.Milestone_Status__c)
                    && !'Completed'.equalsIgnoreCase(old.Milestone_Status__c)) {
                    justCompleted.add(m);
                }
            }
            if (!justCompleted.isEmpty()) {
                ProrataDemandService.raiseBankDemandsForCompletedMilestones(justCompleted);
            }
        }
    }
}