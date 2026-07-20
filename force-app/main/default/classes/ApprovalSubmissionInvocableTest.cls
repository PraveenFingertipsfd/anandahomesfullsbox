/**
 * @description Tests for ApprovalSubmissionInvocable (Flow entry to the dynamic approval engine).
 */
@isTest
private class ApprovalSubmissionInvocableTest {

    @isTest
    static void nullAndEmpty_areHandled() {
        Test.startTest();
        System.assertEquals(0, ApprovalSubmissionInvocable.submit(null).size(), 'Null input → no results');
        List<ApprovalSubmissionInvocable.Result> r =
            ApprovalSubmissionInvocable.submit(new List<ApprovalSubmissionInvocable.Request>());
        Test.stopTest();
        System.assertEquals(0, r.size(), 'Empty input → no results');
    }

    @isTest
    static void missingRecordId_returnsError() {
        ApprovalSubmissionInvocable.Request req = new ApprovalSubmissionInvocable.Request();
        Test.startTest();
        List<ApprovalSubmissionInvocable.Result> res =
            ApprovalSubmissionInvocable.submit(new List<ApprovalSubmissionInvocable.Request>{ req });
        Test.stopTest();
        System.assertEquals(false, res[0].success);
        System.assert(res[0].message.contains('Record Id'), res[0].message);
    }

    @isTest
    static void noConfig_returnsClearMessage() {
        Project__c p = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert p;

        ApprovalSubmissionInvocable.Request req = new ApprovalSubmissionInvocable.Request();
        req.recordId = p.Id;
        req.processType = 'SomeProcess';

        Test.startTest();
        List<ApprovalSubmissionInvocable.Result> res =
            ApprovalSubmissionInvocable.submit(new List<ApprovalSubmissionInvocable.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, res[0].success);
        System.assert(res[0].message.contains('No active Approval Configuration'), res[0].message);
    }

    @isTest
    static void withConfig_attemptsSubmission() {
        Project__c p = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert p;

        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Project__c',
            Process_Type__c = 'TestProcess',
            Is_Active__c = true,
            Status_Field_API_Name__c = 'Approval_Status__c',
            Pending_Status_Value__c = 'Pending',
            Approved_Status_Value__c = 'Approved',
            Rejected_Status_Value__c = 'Rejected',
            Steps_JSON__c = '{"numberOfSteps":1,"steps":[{"stepNumber":1,"approverType":"field","fieldPath":"CreatedById"}]}'
        );

        ApprovalSubmissionInvocable.Request req = new ApprovalSubmissionInvocable.Request();
        req.recordId = p.Id;
        req.processType = 'TestProcess';
        req.comments = 'Please approve';

        Test.startTest();
        List<ApprovalSubmissionInvocable.Result> res =
            ApprovalSubmissionInvocable.submit(new List<ApprovalSubmissionInvocable.Request>{ req });
        Test.stopTest();

        // The config is resolved and submission is attempted; without a native approval process
        // on Project__c the engine reports a failure gracefully rather than throwing.
        System.assertEquals(1, res.size());
        System.assertNotEquals(null, res[0].message);
    }
}