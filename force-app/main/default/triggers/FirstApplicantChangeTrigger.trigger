/**
 * @description Trigger on First_Applicant_Change__c. Stamps the approval date and applies the
 *              approved change to the booking (BRD §12A).
 * @author System
 */
trigger FirstApplicantChangeTrigger on First_Applicant_Change__c (before update, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        FirstApplicantChangeService.stampApprovalDate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        FirstApplicantChangeService.applyApprovedChanges(Trigger.new, Trigger.oldMap);
    }
}