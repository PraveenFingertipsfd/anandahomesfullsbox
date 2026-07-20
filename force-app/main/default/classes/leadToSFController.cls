public class leadToSFController {
    public string status{get;set;}
    public void captureLead(){
        system.debug('hi');
        string firstName =   apexpages.currentpage().getparameters().get('firstName');
        string lastName =   apexpages.currentpage().getparameters().get('lastName'); 
        string mobile = apexpages.currentpage().getparameters().get('mobile'); 
        string email = apexpages.currentpage().getparameters().get('email'); 
        string project = apexpages.currentpage().getparameters().get('project');
        string unitPreference = apexpages.currentpage().getparameters().get('unitPreference');
        string source = apexpages.currentpage().getparameters().get('source');
        string subSource = apexpages.currentpage().getparameters().get('subSource');
        string campaign = apexpages.currentpage().getparameters().get('campaign');
        string description = apexpages.currentpage().getparameters().get('description');
        string residencelocation = apexpages.currentpage().getparameters().get('residencelocation');
        string worklocation = apexpages.currentpage().getparameters().get('worklocation');
        string hearaboutus = apexpages.currentpage().getparameters().get('hearaboutus');
        
        // Enqueue the Queueable job
        //    LeadCaptureQueueable job = new LeadCaptureQueueable(firstName, lastName, mobile, email,project, unitPreference, source, subSource,     campaign, description);
        //ID jobID  = System.enqueueJob(job);
        // system.debug(jobID);
        // status = 'Lead creation process has been initiated. Check status later.';
        
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c ='leadToSFController.captureLead';
        log.Request__c =ApexPages.currentPage().getUrl();
        
        lead ld = new lead();
        ld.LastName = lastName;
        ld.Lead_source__c = source;
        ld.Sub_Source__c = subSource;
        ld.Phone__c = mobile;
        ld.Email = email;
        ld.Allocated_project__c = project;
        ld.Campaign__c = campaign;
        // ld.RecordTypeId = Schema.SObjectType.lead__c.getRecordTypeInfosByName().get('Pre Sales').getRecordTypeId();
        
        try{
            insert ld;  
            log.response__c = string.valueof(ld);
            log.Status__c ='SUCCESS';
            insert log;
            
            status = 'SUCCESS '+ld.id;
        }catch(exception e){
            log.response__c = e.getStackTraceString();
            log.Status__c ='FAIL';
            log.Error_Message__c = e.getMessage();
            insert log;
            
            status = 'FAIL '+e.getMessage();
        }   
        
    }
}