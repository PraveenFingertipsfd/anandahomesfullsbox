public class AdditionalChargesMainController {
    
    @AuraEnabled
    public static List<Additional_Charges__c> getAdditionalCharges(Id bookingId) {
        // Query Additional_Charges__c records related to the given Booking__c ID
        List<Additional_Charges__c> additionalCharges = [
            SELECT Id,Name, Total_Additional_Charge__c,Pending_Amount__c,Total_Received_Amount__c, 
            Additional_Charge_Type__c, GST__c, Status__c, Booking__c,Approval_Status__c,Status_Dynamic__c,
            Booking__r.salutation_Applicant1__c,
            Booking__r.First_Applicant_Name__c,
            Booking__r.Second_Applicant_Name__c,
            Booking__r.salutation_Applicant2__c,
            Booking__r.Project1__r.Name,
            Booking__r.Project_Company__c
            FROM Additional_Charges__c
            WHERE Booking__c = :bookingId
            ORDER BY CreatedDate DESC
        ];
        
        return additionalCharges;
    }
    
    @AuraEnabled
    public static Additional_Charges__c getACRecord (Id recordId){
        return [
            SELECT Id,Name, Total_Additional_Charge__c,Pending_Amount__c,Total_Received_Amount__c, 
            Additional_Charge_Type__c, GST__c, Status__c, Booking__c,Approval_Status__c,Project_Company__c,Status_Dynamic__c
            FROM Additional_Charges__c
            WHERE Id = :recordId];
    }
    
    @AuraEnabled
    public static void RaiseManualACDemand(List<Id> recordIds) {
        if (recordIds != null && !recordIds.isEmpty()) {
            try {
                sendBulkEmails(recordIds);
            } catch (Exception e) {
                System.debug('Error in RaiseManualACDemand: ' + e.getMessage());
                throw new AuraHandledException('An error occurred while processing the demand emails: ' + e.getMessage());
            }
        } else {
            throw new AuraHandledException('No record IDs provided for raising demand.');
        }
    }

    @InvocableMethod
    public static void sendBulkEmails(List<Id> additionalChargeIds) {
      /*  
        Id groupId = [SELECT Id FROM Group WHERE DeveloperName = 'CRM_User_Group' LIMIT 1].Id;
        
        List<GroupMember> groupMembers = [
            SELECT UserOrGroupId 
            FROM GroupMember 
            WHERE GroupId = :groupId
        ];
        
        List<String> ccCRMAddresses = new List<String>();
        
        // Iterate over group members and add their emails to the CC list
        for (GroupMember gm : groupMembers) {
            User u = [SELECT Email FROM User WHERE Id = :gm.UserOrGroupId];
            if (u.Email != null) {
                ccCRMAddresses.add(u.Email);
            }
        }
        ccCRMAddresses.add('Crmlead@mahendrahomes.com');
        
        // Query required fields
        List<Additional_Charges__c> additionalCharges = [
            SELECT Name, Total_Additional_Charge__c, Pending_Amount__c, Total_Received_Amount__c,  
            Additional_Charge_Type__c, GST__c, Status__c, Booking__c,
            Booking__r.salutation_Applicant1__c, Booking__r.First_Applicant_Name__c,
            Booking__r.Second_Applicant_Name__c, Booking__r.salutation_Applicant2__c,
            Booking__r.Project1__r.Name, Booking__r.Project_Company__c,
            booking__r.Email1__c,booking__r.Email2__c,booking__r.Project__c,
            booking__r.Owner.Email,booking__r.CRM_Manager__r.Email,CreatedBy.Email,Status_Dynamic__c,
            (SELECT ContentDocumentId, ContentDocument.Title FROM ContentDocumentLinks)
            FROM Additional_Charges__c
            WHERE Id IN :additionalChargeIds
        ];
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        // Iterate over records and construct email content
        for (Additional_Charges__c additionalCharge : additionalCharges) {
            
            List<String> lstCCEmail = new List<String>();
            List<String> sendTo = new List<String>();
            
            sendTo.add(additionalCharge.booking__r.Email1__c);
            if (additionalCharge.booking__r.Email2__c != null) {
                sendTo.add(additionalCharge.booking__r.Email2__c);
            }
            
            // Include CRM Manager email in CC
            lstCCEmail.add(additionalCharge.booking__r.Owner.Email);
            if (additionalCharge.booking__r.CRM_Manager__r != null && additionalCharge.booking__r.CRM_Manager__r.Email != null) {
                lstCCEmail.add(additionalCharge.booking__r.CRM_Manager__r.Email);
            }
            
            String applicantNames = '';
            if (additionalCharge.Booking__r.salutation_Applicant1__c != null && 
                additionalCharge.Booking__r.First_Applicant_Name__c != null) {
                    applicantNames = additionalCharge.Booking__r.salutation_Applicant1__c + ' ' + additionalCharge.Booking__r.First_Applicant_Name__c;
                }
            
            String secondApplicantName = '';
            if (additionalCharge.Booking__r.Second_Applicant_Name__c != null && 
                additionalCharge.Booking__r.Second_Applicant_Name__c.trim() != '') {
                    secondApplicantName = additionalCharge.Booking__r.salutation_Applicant2__c + ' ' + additionalCharge.Booking__r.Second_Applicant_Name__c;
                }
            
            if (!String.isEmpty(secondApplicantName)) {
                applicantNames += ' and ' + secondApplicantName;
            }
            
            String projectName = '';
            if (additionalCharge.Booking__r.Project1__r.Name != null) {
                projectName = additionalCharge.Booking__r.Project1__r.Name;
            }
            
            String defaultEmailContent = '<div style="color: black;"><strong>Dear ' + applicantNames + ',</strong></div><br/>' +
                '<div><strong>Greetings from Mahendra Homes!!!</strong><br/><br/>' +
                'We would like to inform you about additional charges incurred for <strong>' + projectName + '</strong>. These charges are associated with <strong>' +
                additionalCharge.Additional_Charge_Type__c + '</strong> and are in accordance with the agreed terms and conditions. ' +
                'The total amount due is <strong>Rs.' + additionalCharge.Pending_Amount__c + '</strong>.<br/><br/>' +
                'If you have any questions or need further assistance, please do not hesitate to contact us.<br/><br/>' +
                'Thank you for choosing <strong>Mahendra Homes</strong>.<br/><br/>' +
                'Best regards,<br/>';
            
            if (additionalCharge.Booking__r.Project_Company__c == 'MAHENDRA HOMES PVT LTD') {
                defaultEmailContent += '<strong>Mahendra Homes Pvt Ltd</strong></div>';
            } else if (additionalCharge.Booking__r.Project_Company__c == 'MAHENDRA ARTO LLP') {
                defaultEmailContent += '<strong>Mahendra Arto LLP</strong></div>';
            }
            
            PageReference vfPage;
            if (additionalCharge.Booking__r.Project__c == 'Aarya') {
                vfPage = Page.DEMAND_LETTER_AC_AARYA;
            } else if (additionalCharge.Booking__r.Project__c == 'Arto Helix') {
                vfPage = Page.DEMAND_LETTER_AC_HELIX;
            }
            vfPage.getParameters().put('id', additionalCharge.Id);
            Blob pdfBlob = !Test.isRunningTest() ? vfPage.getContentAsPDF() : Blob.valueOf('testblob');
            
            List<String> validccEmails = new List<String>();
            List<String> combinedCCAddresses = new List<String>();
            
            combinedCCAddresses.addAll(ccCRMAddresses);
            combinedCCAddresses.addAll(lstCCEmail);
            validccEmails = GenerateDocumnetController.validateEmails(combinedCCAddresses);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            if (!validccEmails.isEmpty()) {
                email.setCcAddresses(validccEmails);
            }
            email.setToAddresses(sendTo);
            email.setSubject('Demand Note for '+additionalCharge.Additional_Charge_Type__c+' (Additional Charges)');
            email.setHtmlBody(defaultEmailContent);
            
            list<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
            for (ContentDocumentLink link : additionalCharge.ContentDocumentLinks) {
                ContentVersion version = [SELECT Title, FileExtension, VersionData 
                                          FROM ContentVersion 
                                          WHERE ContentDocumentId = :link.ContentDocumentId 
                                          ORDER BY CreatedDate DESC LIMIT 1];
                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                attachment.setFileName(version.Title + '.' + version.FileExtension);
                attachment.setBody(version.VersionData);
                attachments.add(attachment);
            }
            
            Messaging.EmailFileAttachment attachmentDoc = new Messaging.EmailFileAttachment();
            attachmentDoc.setFileName('Demand.pdf');
            attachmentDoc.setBody(pdfBlob);
            attachments.add(attachmentDoc);
            
            if (!attachments.isEmpty()) {
                email.setFileAttachments(attachments);
            }
            if(!Test.isRunningTest()){
                String CreatedEmail = additionalCharge.CreatedBy.Email;
                list<OrgWideEmailAddress> orgWideEmail = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :CreatedEmail LIMIT 1];
                if (orgWideEmail.size() > 0) {
                    email.setOrgWideEmailAddressId(orgWideEmail[0].Id);
                }
            }
            
            email.setSaveAsActivity(true);
            email.setWhatId(additionalCharge.Id);
            
            emails.add(email);
        }
        
        // Send emails
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }*/
    }
    @AuraEnabled
    public static void saveAdditionalChargeReceipts(List<Additional_Charge_Receipt__c> receiptRecords) {
        try {
            if (receiptRecords != null && !receiptRecords.isEmpty()) {
                insert receiptRecords;
            }
        } catch (Exception ex) {
            throw new AuraHandledException('Error saving records: ' + ex.getMessage());
        }
    }
    public static void sendNotificationsFromAdditionalChange(String title, List<Additional_Charges__c> adChargeRec) {
        
        for (Additional_Charges__c adc : adChargeRec) {
            String body = '';
            Set<String> userIds = new Set<String>();
            userIds.add(adc.CreatedById);
            if(title == 'Additional Charge Demand Raise Approved'){
                body = 'This is to notify that Booking ' + adc.Booking_Name__c + 
                    ', The additional charge demand raise request ' + adc.Name + ' is Approved by the Finance Team';
            }
            if(title == 'Additional Charge Demand Raise Rejected'){
                body = 'This is to notify that Booking ' + adc.Booking_Name__c + 
                    ', The additional charge demand raise request ' + adc.Name + ' is Rejected by the Finance Team';
            }
    //        ReceiptController.sendCustomNotification(userIds, title, body, adc.Id, 'Receipt_Notification');
        }
    }
}