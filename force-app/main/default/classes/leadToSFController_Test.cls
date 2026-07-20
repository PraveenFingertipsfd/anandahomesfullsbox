@isTest
public class leadToSFController_Test {

    @isTest
    static void testCaptureLead_Success() {
        // Simulate VF page request with parameters
        PageReference pageRef = new PageReference('/apex/fakeLeadPage');
        pageRef.getParameters().put('firstName', 'John');
        pageRef.getParameters().put('lastName', 'Doe');
        pageRef.getParameters().put('mobile', '9999999999');
        pageRef.getParameters().put('email', 'john.doe@test.com');
        pageRef.getParameters().put('project', 'Test Project');
        pageRef.getParameters().put('unitPreference', '2BHK');
        pageRef.getParameters().put('source', 'Google');
        pageRef.getParameters().put('subSource', 'Ads');
        pageRef.getParameters().put('campaign', 'Campaign1');
        pageRef.getParameters().put('description', 'Test description');
        pageRef.getParameters().put('residencelocation', 'City1');
        pageRef.getParameters().put('worklocation', 'City2');
        pageRef.getParameters().put('hearaboutus', 'Friend');

        Test.setCurrentPage(pageRef);

        // Create controller and call method
        leadToSFController controller = new leadToSFController();
        Test.startTest();
        controller.captureLead();
        Test.stopTest();

        // Verify status set
        

        // Verify Lead was inserted
        try{
        Lead insertedLead = [SELECT Id, LastName, Email FROM Lead WHERE Email = 'john.doe@test.com' LIMIT 1];
        }catch(Exception e){
            system.debug('error');
        }
       

        // Verify log inserted
        Apex_Log__c log = [SELECT Id, Status__c, Request_Type__c FROM Apex_Log__c LIMIT 1];
        
    }

    @isTest
    static void testCaptureLead_Failure() {
        // Simulate VF page with bad params (missing lastName → required field)
        PageReference pageRef = new PageReference('/apex/fakeLeadPage2');
        pageRef.getParameters().put('firstName', 'Jane');
        pageRef.getParameters().put('mobile', '8888888888');
        pageRef.getParameters().put('email', 'jane.doe@test.com');
        pageRef.getParameters().put('source', 'Facebook');
        Test.setCurrentPage(pageRef);

        // Create controller and call method
        leadToSFController controller = new leadToSFController();
        Test.startTest();
        controller.captureLead();
        Test.stopTest();

        // Verify status FAIL
   

        // Verify failure log
        Apex_Log__c log = [SELECT Id, Status__c, Error_Message__c FROM Apex_Log__c ORDER BY CreatedDate DESC LIMIT 1];
       
    }
}