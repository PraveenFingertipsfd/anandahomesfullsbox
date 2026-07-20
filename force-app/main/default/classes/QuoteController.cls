public class QuoteController {
    
    @AuraEnabled(cacheable=true)
    public static Quote__c getQuoteData(Id recordId) {
        // Fetch the booking record
        Quote__c Quote = [SELECT Id, Name, Lead_Email__c,Lead_Name__c,Project_Company__c,Discount_Approval_Status__c,Manager_Approval_Status__c,Apply_Discount__c,OwnerId,Owner.Name,Owner.Phone,Project1__r.Name,Unit__c,Unit__r.Name,Owner.Email,CLead__r.Email__c,CLead__r.Name__c,CLead__r.Salutation__c
                          FROM Quote__c WHERE Id = :recordId LIMIT 1];
        return Quote;
        
        
    }
    @AuraEnabled
    public static string sendEmailtoCustomer(String recordId, string emailContent,string contentIds)
    {
        Quote__c qt = [SELECT Id,payment_type__c,Quote_status__c,Approval_status__c,Project_Company__c, Project__c, Project1__r.Name, SLead__r.Email, SLead__r.Secondary_Email__c,SLead__c, CLead__r.Email__c, Owner.Email   FROM Quote__c WHERE Id=:recordId];
        if(qt.Quote_status__c == 'Approved' || qt.Quote_status__c == 'Drafted'){
            Messaging.SingleEmailMessage semail = new Messaging.SingleEmailMessage();
            Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
            PageReference pref;

            String projectName = (qt.Project1__r != null) ? qt.Project1__r.Name : null;

            if (projectName == 'The Legacey') {
                pref = Page.COST_SHEET_TL;
            } else {
                return 'Cost Sheet template is not configured for this project. Please contact admin.';
            }
            system.debug(qt.Project_Company__c);

            pref.getParameters().put('id', recordId);
            pref.setRedirect(true);
            system.debug(pref);
            Blob b;
            
            Boolean isTest = System.Test.isRunningTest();
            if(isTest){
                b = blob.valueOf('Unit.Test');
            }else{
                b = pref.getContent();
            }
            attach.setFileName('AnandaHomes_CostSheet.pdf');
            attach.setBody(b);
            semail.setSubject('Ananda Homes CostSheet');
            
            List<string> sendTo = new List<string>();
            if(qt.CLead__r != null && qt.CLead__r.Email__c != null){
                sendTo.add(qt.CLead__r.Email__c);
            }
            if(qt.SLead__r != null && qt.SLead__r.Email !=null){
                sendTo.add(qt.SLead__r.Email);
            }

            if(qt.SLead__r != null && qt.SLead__r.Secondary_Email__c !=null){
                sendTo.add(qt.SLead__r.Secondary_Email__c);
            }
            
            List<OrgWideEmailAddress> owea = [SELECT Id, Address, DisplayName FROM OrgWideEmailAddress WHERE Address = :System.Label.Org_Wide_Address LIMIT 1];
            if (owea.size() > 0) {
                semail.setOrgWideEmailAddressId(owea[0].Id);
            }
            semail.setToAddresses(sendTo);
            semail.setHtmlBody(emailContent);
           // semail.setHtmlBody('Dear Sir/Madam,<br/> <br/> Thank you very much for your interest in '+qt.Project__c +'.<br/>Please find the attached quote for your kind Perusal.<br/>Note: This is a sample quote purely for reference.<br/>Please feel free to talk us for clarification if any.,<br/>');
            semail.setFileAttachments(new Messaging.EmailFileAttachment[]{attach});
            if(sendTo.size()>0){
                Messaging.sendEmail(new Messaging.SingleEmailMessage[]{semail});
                return 'Quotation sent to customer';
            }else{
                return 'Please enter email address in lead';
            }
        }else{
            return 'Quote is not approved, you can not send Quote';
        }
    }
}