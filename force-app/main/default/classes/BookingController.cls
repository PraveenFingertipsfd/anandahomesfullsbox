public without sharing class BookingController {

    // Updated 2026-04-10: Fetch Quote directly with charge fields + Unit__r relationship
    @AuraEnabled
    public static Quote__c convertUnit(Id recId){
        Quote__c qt = [SELECT Id, Unit__c, Unit__r.Name, Unit__r.Block1__r.Name, Unit__r.Floor__c,
                       Unit__r.Block1__c, Unit__r.Block__c, Unit__r.GST1__c, Unit__r.Project__c,
                       Unit__r.Project__r.Booking_Advance_Amount__c,
                       Tower__c, Saleable_Area_Sft__c, Price_Per_Sq_Ft__c,
                       East_Facing_Charges__c, Corner_Charges__c, Hi_Rise_Charges__c,
                       Central_Court_Yard_Premium__c, Meadow_Premium__c, Roadside_Premium__c,
                       Court_Yard_Premium__c, Outer_Premium__c, Amenities_Car_Parking__c,
                       Infrastructure_Charges__c, GST_Amount__c, Sub_total__c, Total__c
                       FROM Quote__c WHERE Id = :recId LIMIT 1];
        return qt;
    }

    @AuraEnabled
    public static List<String> getModeofPayment() {
        List<String> paymentTypeValues = new List<String>();
        Schema.DescribeFieldResult fieldResult = Booking__c.Mode_Of_Payment__c.getDescribe();
        for (Schema.PicklistEntry picklistEntry : fieldResult.getPicklistValues()) {
            paymentTypeValues.add(picklistEntry.getLabel());
        }
        return paymentTypeValues;
    }
    @AuraEnabled
    public static List<String> getFundingType() {
        List<String> paymentTypeValues = new List<String>();
        Schema.DescribeFieldResult fieldResult = Booking__c.Funding_Type__c.getDescribe();
        for (Schema.PicklistEntry picklistEntry : fieldResult.getPicklistValues()) {
            paymentTypeValues.add(picklistEntry.getLabel());
        }
        return paymentTypeValues;
    }
    @auraEnabled
    public static String createBook(Booking__c bk, String recId, List<Co_Applicant__c> applicantList) {
        // ✅ CHANGED: SLead__c to CLead
        Quote__c quoteRecord = [SELECT Id, Unit__c,CLead__c,CLead__r.Lead_source__c,CLead__r.OwnerId FROM Quote__c WHERE Id = :recId LIMIT 1];
        List<Co_Applicant__c> applicantListToInsert = new List<Co_Applicant__c>();
        List<Plot__c> qt = [SELECT Id, Name, Status__c, Project__c, Super_built_up_area__c, Price_Per_Sq_Ft__c, Floor_Rise__c, Premium_Charge__c,
                            Other_Charges__c, Covered_Park_Parking__c, TAXES__c,Block1__c,Block__c FROM Plot__c WHERE Id = :quoteRecord.Unit__c];
        if (qt.isEmpty()) {
            System.debug('Plot record not found.'); 
            return 'Plot record not found.';
        }
        list<Block__c> block =[select id,Name from Block__c where Id =:bk.Block__c];
        List<Project__c> projectList = [SELECT Id, CRM_Manager__c, Legal_User__c, Finance_User__c, Reservation_User__c,
                                        Demands_Collection_User__c, Possession_User__c, Agreement_User__c,
                                        Registration_User__c, Maintenance_User__c,Project__c,
                                        Director__c,Sales_Manager__c,VP__c,CFO__c,Loan_Stage_User__c,Handover_User__c FROM Project__c WHERE Id= :bk.Project1__c];
        
        if (projectList.isEmpty()) {
            return 'Project record not found for the given Booking Project.';
        }
        bk.Quote__c = recId;
        if (qt[0].Status__c == 'Blocked') {
            System.debug('oppPlot: ' + bk);
            //map project level managers to booking fileds
            bk.CRM_Manager__c = projectList[0].CRM_Manager__c;
            //bk.Legal_Team__c = projectList[0].Legal_User__c;
            //bk.Director__c = projectList[0].Director__c;
            //bk.Finance_User__c = projectList[0].Finance_User__c;
            //bk.Sales_Manager1__c = projectList[0].Sales_Manager__c;
            //stage-wise users map
            /*bk.Reservation_User__c = projectList[0].Reservation_User__c;
            bk.Agreement_User__c = projectList[0].Agreement_User__c;
            bk.Maintenance_User__c = projectList[0].Maintenance_User__c;
            bk.Possession_User__c = projectList[0].Possession_User__c;
            bk.Registration_User__c = projectList[0].Registration_User__c;
            bk.Demand_Collection_Users__c = projectList[0].Demands_Collection_User__c;*/
            bk.CFO__c = projectList[0].CFO__c;
            bk.VP__c = projectList[0].VP__c;
            //bk.Loan_User__c = projectList[0].Loan_Stage_User__c;
            //bk.Handover_User__c = projectList[0].Handover_User__c; 
            //remaining fileds
            //bk.Project__c=projectList[0].Project__c;
            // ✅ CHANGED: SLead__c to CLead__c
            bk.CLead__c = quoteRecord.CLead__c;
            bk.Leads_source__c = quoteRecord.CLead__r.Lead_source__c;
            //bk.Relationship_Manager__c = quoteRecord.CLead__r.OwnerId;
            System.debug('Booking to upsert: ' + bk);
            upsert bk;
            
            qt[0].Status__c = 'Booked';
            update qt[0];
            
            // ✅ CHANGED: Lead to Lead__c (Custom Object)
            Lead__c ld = new Lead__c();
            ld.Id = quoteRecord.CLead__c;
            ld.Lead_Status__c='Booked';
            update ld;
            
            System.debug('applicantList: ' + applicantList);
            for (Co_Applicant__c coA : applicantList) {
                System.debug('Co-Applicant Name: ' + coA.Name);
                if (coA.Name != null && coA.Name != '') {
                    System.debug('Adding Co-Applicant to insert list.');
                    coA.Booking__c = bk.Id;
                    applicantListToInsert.add(coA);
                }
            }
            if (!applicantListToInsert.isEmpty()) {
                System.debug('Co-Applicants to insert: ' + applicantListToInsert);
                try {
                    insert applicantListToInsert;
                    System.debug('Co-Applicants inserted successfully.');
                } catch (Exception e) {
                    System.debug('Error during insert of Co-Applicants: ' + e.getMessage());
                    return 'Error during insert of Co-Applicants: ' + e.getMessage();
                }
            }
            system.debug('Booking Id '+bk.ID);
            return bk.ID;
        } else {
            return 'Plot is not available.';
        }
    }
    
    public static void bookingAmountReceipt(Booking__c booking){ 
        List<Payment_Schedule__c> existingPaymentSchedules = [
            SELECT Id, Name,Booking__c,Payment_percent__c,status__c,S_No__c,Master_Payment_Schedule__c  
            FROM Payment_Schedule__c
            WHERE Booking__c =: booking.id
        ];
        
        Receipt__c recp = new Receipt__c();
        recp.Booking__c = booking.Id;
        recp.Receipt_Name__c = 'Booking Amount Receipt';
        recp.Remarks__c = 'Receipt for the Booking Amount. Auto Generated by system';
        insert recp;
        
       if(recp.Id != null){
            Receipt_Line_Item__c rli = new Receipt_Line_Item__c();
            rli.Receipt_Line_Item_Name__c = 'Booking Amount';
            rli.Cheque_no_Transaction_Number__c = booking.Cheque_DD_NEFT_RTGS_No__c;
            //rli.Mode_of_Payment__c = booking.Mode_Of_Payment__c;
            rli.Receipt__c = recp.Id;
            rli.Booking__c = booking.Id;
            rli.Amount__c = booking.Booking_Amount1__c;
            //rli.Payment_schedule__c = existingPaymentSchedules[0].Id;
            insert rli;
        }
    }
    
   public static void cloneBookingWithUnitChangeDetails(Booking__c currentBooking, String newStage, String previousBookingStage) {
        try {
            // List to store all sObjects that need to be updated
            List<sObject> allToUpdate = new List<sObject>();
            List<Plot__c> plotsToUpdate = new List<Plot__c>();
            
            // Fetch the plots associated with Swap_Unit__c and current Plot__c
            List<Plot__c> swapUnitPlotList = [SELECT Id, Name, Status__c FROM Plot__c WHERE Id = :currentBooking.Swap_Unit__c];
            List<Plot__c> currentPlotList = [SELECT Id, Name, Status__c FROM Plot__c WHERE Id = :currentBooking.Plot__c];
            
            // Mark the current plot as 'Available' and clear its booking reference
            for (Plot__c currentPlot : currentPlotList) {
                currentPlot.Status__c = 'Available';
                currentPlot.Booking__c = null;
                plotsToUpdate.add(currentPlot);
            }
            
            // Clone the current booking and update its details
            Booking__c clonedBooking = currentBooking.clone(false, true, false, false);
            clonedBooking.Stage__c = previousBookingStage;
            clonedBooking.Plot__c = currentBooking.Swap_Unit__c;
            clonedBooking.Swap_Unit__c = null;
            clonedBooking.Swap_unit_status__c = '';
            clonedBooking.Extra_Covered_Parking_Charges__c = currentBooking.Swap_Extra_Covered_Parking_Charges__c;
            clonedBooking.Funding_Type__c = currentBooking.Swap_Funding_Type__c;
            clonedBooking.Extra_Covered_Parking_Slots__c = currentBooking.Swap_Extra_Covered_Parking_Slots__c;
            clonedBooking.Mode_Of_Payment__c = currentBooking.Swap_Mode_of_Payment__c;
            clonedBooking.Solar_Charges__c = currentBooking.Swap_Solar_Charges__c;
            clonedBooking.Is_Swap__c = true;
            clonedBooking.Swapped_Booking__c = currentBooking.Id;
            insert clonedBooking;
            
            // Mark the swap unit plot as 'Booked' with the new booking reference
            for (Plot__c swapUnitPlot : swapUnitPlotList) {
                swapUnitPlot.Status__c = 'Booked';
                swapUnitPlot.Booking__c = clonedBooking.Id;
                plotsToUpdate.add(swapUnitPlot);
            }
            
            // Update plot statuses
            if (!plotsToUpdate.isEmpty()) {
                update plotsToUpdate;
            }
            
            // Clone payment schedules and map them to the new booking
            List<Payment_Schedule__c> paymentSchedules = [SELECT Id,Name, S_No__c, Payment_Percent__c, Amount__c, Completed_Date__c, Payment_Due_Date__c, Status__c
                                                          FROM Payment_Schedule__c WHERE Booking__c = :currentBooking.Id ORDER BY S_No__c ASC];
            List<Payment_Schedule__c> clonedSchedules = new List<Payment_Schedule__c>();
            Map<Decimal, Id> scheduleNumberToIdMap = new Map<Decimal, Id>();
            
            for (Payment_Schedule__c schedule : paymentSchedules) {
                Payment_Schedule__c clonedSchedule = schedule.clone(false, true, false, false);
                clonedSchedule.Booking__c = clonedBooking.Id;
                clonedSchedules.add(clonedSchedule);
            }
            
            if (!clonedSchedules.isEmpty()) {
                upsert clonedSchedules;
                for (Payment_Schedule__c clonedSchedule : clonedSchedules) {
                    scheduleNumberToIdMap.put(clonedSchedule.S_No__c, clonedSchedule.Id);
                }
            }
            
            // Clone co-applicants and assign them to the new booking
            List<Co_Applicant__c> coApplicants = [SELECT Id, Name, Booking__c FROM Co_Applicant__c WHERE Booking__c = :currentBooking.Id];
            for (Co_Applicant__c coApplicant : coApplicants) {
                Co_Applicant__c clonedCoApplicant = coApplicant.clone(false, true, false, false);
                clonedCoApplicant.Booking__c = clonedBooking.Id;
                allToUpdate.add(clonedCoApplicant);
            }
            
            // Clone receipts and their line items
            List<Receipt__c> receipts = [SELECT Id, Name, Booking__c FROM Receipt__c WHERE Booking__c = :currentBooking.Id];
            //List<Receipt_Line_Item__c> receiptLineItems = [SELECT Id, S_No__c, Payment_Schedule__c, Booking__c, Amount__c, Approval_Status1__c, Received_Amount__c, Mode_of_Payment__c, Cheque_no_Transaction_Number__c FROM Receipt_Line_Item__c WHERE Booking__c = :currentBooking.Id];
            
            Receipt__c newReceipt;
            if (!receipts.isEmpty()) {
                newReceipt = new Receipt__c(Booking__c = clonedBooking.Id);
                allToUpdate.add(newReceipt);
            }
            
            upsert allToUpdate; // Save all updated records
            
            if (newReceipt != null) {
                newReceipt = [SELECT Id FROM Receipt__c WHERE Booking__c = :clonedBooking.Id LIMIT 1];
            }
            
           /* if (!receiptLineItems.isEmpty() && newReceipt != null) {
                List<Receipt_Line_Item__c> clonedReceiptLineItems = new List<Receipt_Line_Item__c>();
                
                for (Receipt_Line_Item__c lineItem : receiptLineItems) {
                    Receipt_Line_Item__c clonedLineItem = lineItem.clone(false, true, false, false);
                    clonedLineItem.Booking__c = clonedBooking.Id;
                    clonedLineItem.Receipt__c = newReceipt.Id;
                    //clonedLineItem.Payment_Schedule__c = scheduleNumberToIdMap.get(lineItem.S_No__c);
                    clonedReceiptLineItems.add(clonedLineItem);
                }
                
                insert clonedReceiptLineItems;
            }*/
         /*   Booking__c book = new Booking__c();
           book.id = currentbooking.Id;
            book.Swapped_Booking__c = clonedBooking.Id;
            update book;*/
        } catch (Exception e) {
            System.debug('Error in cloneBookingWithUnitChangeDetails: ' + e.getMessage());
        }
    }
    
    public static void createPaymentSchedules(List<Booking__c> newBookings) {
        Set<Id> projectIds = new Set<Id>();
        // Collect Project__c IDs from the Booking__c records
        for (Booking__c booking : newBookings) {
            if (booking.Project1__c != null) {
                projectIds.add(booking.Tower__c);
            }
        }
        List<Master_Payment_Schedule__c> relatedMasterPaymentSchedules = new List<Master_Payment_Schedule__c>();
        // Query Master_Payment_Schedule__c records related to the Project__c IDs
        if (!projectIds.isEmpty()) {
            relatedMasterPaymentSchedules = [
                SELECT Id, Name, Amount__c, Payment_percent__c, Status__c, S_No__c, Project__c,Include_interest__c,Tower__c
                FROM Master_Payment_Schedule__c
                WHERE Tower__c IN :projectIds  
            ];
        }
        List<Payment_Schedule__c> newPaymentSchedules = new List<Payment_Schedule__c>();
        // Create new Payment_Schedule__c records for Booking__c
        for (Booking__c booking : newBookings) {
            for (Master_Payment_Schedule__c masterPaymentSchedule : relatedMasterPaymentSchedules) {
                if (masterPaymentSchedule.Tower__c == booking.Tower__c) {
                    // Create a new Payment_Schedule__c record with data copied from the Master_Payment_Schedule__c record
                    Payment_Schedule__c newPaymentSchedule = new Payment_Schedule__c(
                        Booking__c = booking.Id,
                        // Copy fields from Master_Payment_Schedule__c
                        Payment_percent__c = masterPaymentSchedule.Payment_percent__c,
                        //Status__c = masterPaymentSchedule.Status__c,
                        Interest_Percent__c = booking.Interest_Percent__c,
                        Include_interest__c = masterPaymentSchedule.Include_interest__c,
                        S_No__c = masterPaymentSchedule.S_No__c,
                        Amount__c = masterPaymentSchedule.Amount__c,
                        Master_Payment_Schedule__c = masterPaymentSchedule.Id,
                        Payment_Schedule_Name__c = masterPaymentSchedule.Name
                    );
                    newPaymentSchedules.add(newPaymentSchedule);
                }
            }
        }
        if (!newPaymentSchedules.isEmpty()) {
            insert newPaymentSchedules;
        }
    }
    
    
    public static void stageWiseOwnerUpdate(List<Booking__c> newBookings, Map<Id, Booking__c> oldBookingMap) {
        Set<Id> projectIds = new Set<Id>();
        for (Booking__c newBooking : newBookings) {
            if (newBooking.Project1__c != null) {
                projectIds.add(newBooking.Project1__c);
            }
        }
        Map<Id, Project__c> projectMap = new Map<Id, Project__c>([
            SELECT Id, Reservation_User__c, Demands_Collection_User__c, Possession_User__c,
            Agreement_User__c, Registration_User__c, Maintenance_User__c
            FROM Project__c WHERE Id IN :projectIds
        ]);
        
        for (Booking__c newBooking : newBookings) {
            if (oldBookingMap != null) {
                Booking__c oldBooking = oldBookingMap.get(newBooking.Id);
                
                if (oldBooking.Stage__c != newBooking.Stage__c) {
                    Project__c project = projectMap.get(newBooking.Project1__c);
                    if (newBooking.Stage__c == 'Agreement' && project.Agreement_User__c != null) {
                        newBooking.OwnerId = project.Agreement_User__c;
                    } else if (newBooking.Stage__c == 'Demands & Collection' && project.Demands_Collection_User__c != null) {
                        newBooking.OwnerId = project.Demands_Collection_User__c;
                    } else if (newBooking.Stage__c == 'Registration' && project.Registration_User__c != null) {
                        newBooking.OwnerId = project.Registration_User__c;
                    } else if (newBooking.Stage__c == 'Possession' && project.Possession_User__c != null) {
                        newBooking.OwnerId = project.Possession_User__c;
                    } else if (newBooking.Stage__c == 'Maintenance' && project.Maintenance_User__c != null) {
                        newBooking.OwnerId = project.Maintenance_User__c;
                    }
                }
            }
        }
    }
    
    public static void sendCustomNotification(Set<String> recepientIds, String Title, String Body, String recId, String notificationName){
        CustomNotificationType closedWonNotification = [SELECT Id,DeveloperName FROM CustomNotificationType WHERE DeveloperName =: notificationName LIMIT 1]; 
        Messaging.CustomNotification Notification = new Messaging.CustomNotification(); 
        Notification.setNotificationTypeId(closedWonNotification.id); 
        Notification.setSenderId(Userinfo.getUserId()); 
        Notification.setBody(Body); 
        Notification.setTitle(Title); 
        Notification.setTargetId(recId); 
        Notification.send(recepientIds);
    }
    
   /* @AuraEnabled
    public static void documentVerificationApproval(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Document Verification Approval');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Documents_Check_Approval');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }
    
    @AuraEnabled
    public static void receiptApprovalforFinanceTeam(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Receipt Approval');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Receipt_Approval_To_Finance_Team	');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }
    
    @AuraEnabled
    public static void bookingCancellationApproval(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Booking Cancellation');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Cancellation_Approval_For_Booking');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }
    
    @AuraEnabled
    public static void requestSaleAgreement(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Sale Agreement');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Request_for_Sale_Agreement');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }
    
    @AuraEnabled
    public static void partialAmountAgreementAmountApproval(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Sale Agreement');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Agreement_Partial_Amount_Paid_Approval');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }
    
    @AuraEnabled
    public static void requestForSaleDeed(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Sale Agreement');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Agreement_Partial_Amount_Paid_Approval');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }
    
    @AuraEnabled
    public static void requestForRegistrationApproval(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Sale Agreement');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Registration_Approval');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }
    
    @AuraEnabled
    public static void requestTransferApproval(Id recId){
        Approval.ProcessSubmitRequest req1 = new Approval.ProcessSubmitRequest();
        req1.setComments('Sale Agreement');
        req1.setObjectId(recId);
        req1.setSubmitterId(userInfo.getUserId()); 
        req1.setProcessDefinitionNameOrId('Transfer_Assignment_Approval');
        req1.setSkipEntryCriteria(true);
        Approval.ProcessResult result = Approval.process(req1);
    }*/
    
    public class BookingUserWrapper {
        @AuraEnabled
        public Booking__c booking;
        
        @AuraEnabled
        public User loggedInUser;
        
        public BookingUserWrapper(Booking__c booking, User loggedInUser) {
            this.booking = booking;
            this.loggedInUser = loggedInUser;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static BookingUserWrapper getRecordData(Id recordId) {
        // Fetch the booking record
        Booking__c booking = [SELECT Id, Name, First_Applicant_Name__c,Tower__c,Tower_Name__c, salutation_Applicant1__c, salutation_Applicant2__c, 
                              Second_Applicant_Name__c, Swap_Unit_Status__c, Booking_Amount1__c, 
                              Unit_NumberFor__c, Email1__c 
                              FROM Booking__c WHERE Id = :recordId LIMIT 1];
        
        // Fetch the logged-in user details
        User loggedInUser = [SELECT Name,Email, Phone FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        
        // Return both booking and logged-in user details in a wrapper
        return new BookingUserWrapper(booking, loggedInUser);
    }
    
    
    @AuraEnabled
    public static void sendWelcomeEmail(Id recordId, String emailContent, List<String> toAddresses, List<String> contentIds) {
        system.debug('Content IDs: ' + contentIds);
        Booking__c leadRecord = [SELECT Id,Plot__r.Name,salutation_Applicant2__c,salutation_Applicant1__c,Block__r.Name, Name, CRM_Manager__c,Email2__c,Project1__r.Name,CRM_Manager__r.Email, First_Applicant_Name__c,Second_Applicant_Name__c, Booking_Amount1__c, Unit_NumberFor__c, Email1__c,Project1__r.Project__c, 
                                 (SELECT ContentDocumentId, ContentDocument.Title FROM ContentDocumentLinks WHERE ContentDocumentId IN :contentIds) 
                                 FROM Booking__c 
                                 WHERE Id = :recordId 
                                 LIMIT 1];
        Id groupId = [SELECT Id FROM Group WHERE DeveloperName = 'CRM_User_Group' LIMIT 1].Id;
     /*   List<GroupMember> groupMembers = [
            SELECT UserOrGroupId 
            FROM GroupMember 
            WHERE GroupId = :groupId
        ];
        
        List<String> ccAddresses = new List<String>();
        
        // Iterate over group members and add their emails to the CC list
        for (GroupMember gm : groupMembers) {
            User u = [SELECT Email FROM User WHERE Id = :gm.UserOrGroupId];
            if (u.Email != null) {
                ccAddresses.add(u.Email);
            }
        }*/
        
         List<String> ccAddresses = new List<String>();
           Set<Id> userIds = new Set<Id>();
            
            for (GroupMember gm : [
                SELECT UserOrGroupId
                FROM GroupMember
                WHERE GroupId = :groupId
            ]) {
                if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
                    userIds.add(gm.UserOrGroupId);
                }
            }
            
            List<User> users = [
                SELECT Id, Name, Email
                FROM User
                WHERE Id IN :userIds
            ];
            
            for (User u : users) {
                 if (u.Email != null) {
                    ccAddresses.add(u.Email);
                }
            }
        
        // Adding Sales Manager in CC address according to Project on 21-01-2025
        if(leadRecord.Project1__r.Project__c=='Aarya'){
        ccAddresses.add('prashanth.kumar@mahendrahomes.com');
        }
        if(leadRecord.Project1__r.Project__c=='Arto Helix'){
        ccAddresses.add('mahesh.ds@mahendraarto.com');   
        }
        
        // Adding Sales Manager in CC address on 17-01-2025
        
        // Adding Sales Manager profile users to the CC list
      /*  List<User> salesManagers = [SELECT Email FROM User WHERE Profile.Name = 'Sales Manager'];
        for (User sm : salesManagers) {
            if (sm.Email != null) {
                ccAddresses.add(sm.Email);
            }
        }*/
        //ccAddresses.add('Crmlead@mahendrahomes.com');
        if (leadRecord != null && leadRecord.Email1__c != null) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            List<Messaging.EmailFileAttachment> emailAttachments = new List<Messaging.EmailFileAttachment>();
            Set<Id> contentDocumentIds = new Set<Id>();
            for (ContentDocumentLink docLink : leadRecord.ContentDocumentLinks) {
                contentDocumentIds.add(docLink.ContentDocumentId);
            }
            if (!contentDocumentIds.isEmpty()) {
                List<ContentVersion> contentVersions = [SELECT Title,FileExtension, VersionData FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds];
                for (ContentVersion cv : contentVersions) {
                    Messaging.EmailFileAttachment contentAttach = new Messaging.EmailFileAttachment();
                    String fileNameWithExtension = cv.Title + '.' + cv.FileExtension;
                    contentAttach.setFileName(fileNameWithExtension);
                    //contentAttach.setFileName(cv.Title);
                    contentAttach.setBody(cv.VersionData);
                    emailAttachments.add(contentAttach);
                }
            }
            toAddresses.add(leadRecord.Email1__c);
            if (leadRecord.Email2__c != null) {
                toAddresses.add(leadRecord.Email2__c);
            }
            List<PageReference> vfPages = new List<PageReference>();
            
        /*    if(leadRecord.Project1__r.Project__c == 'Aarya'){
                vfPages.add(Page.SALE_AGREEMENT_AARYA);
                vfPages.add(Page.COST_SHEET_AARYA);
                for (PageReference pref : vfPages) {
                    system.debug(pref);
                    pref.getParameters().put('id', recordId);
                    Blob pdfBlob = !Test.isRunningTest() ? pref.getContentAsPDF(): Blob.valueOf('testblob');
                    Messaging.EmailFileAttachment vfAttachment = new Messaging.EmailFileAttachment();
                    // Set a custom name for each PDF attachment based on the PageReference
                    String attachmentName;
                    
                    if (pref.getUrl().contains('sale_agreement_aarya')) {
                        attachmentName = 'Sale_Agreement.pdf'; // Custom name for Sale Agreement
                    } else if (pref.getUrl().contains('cost_sheet_aarya')) {
                        attachmentName = 'Cost_Sheet.pdf'; // Custom name for Cost Sheet
                    } else {
                        attachmentName = 'Document.pdf'; // Default name for any other case
                    }
                    
                    vfAttachment.setFileName(attachmentName);
                    vfAttachment.setBody(pdfBlob);
                    emailAttachments.add(vfAttachment);
                }
            }
            else if(leadRecord.Project1__r.Project__c == 'Arto Helix'){
                vfPages.add(Page.SALE_AGREEMENT_HELIX);
                vfPages.add(Page.COST_SHEET_HELIX);
                for (PageReference pref : vfPages) {
                    pref.getParameters().put('id', recordId);
                    Blob pdfBlob = !Test.isRunningTest() ? pref.getContentAsPDF(): Blob.valueOf('testblob');
                    Messaging.EmailFileAttachment vfAttachment = new Messaging.EmailFileAttachment();
                    // Set a custom name for each PDF attachment based on the PageReference
                    String attachmentName;
                    
                    if (pref.getUrl().contains('sale_agreement_helix')) {
                        attachmentName = 'Sale_Agreement.pdf'; // Custom name for Sale Agreement
                    } else if (pref.getUrl().contains('cost_sheet_helix')) {
                        attachmentName = 'Cost_Sheet.pdf'; // Custom name for Cost Sheet
                    } else {
                        attachmentName = 'Document.pdf'; // Default name for any other case
                    }
                    
                    vfAttachment.setFileName(attachmentName);
                    vfAttachment.setBody(pdfBlob);
                    emailAttachments.add(vfAttachment);
                }
            }
          */  
            if (!emailAttachments.isEmpty()) {
                mail.setFileAttachments(emailAttachments);
            }
            mail.setCcAddresses(ccAddresses);
            mail.setToAddresses(toAddresses);
            // Build the subject line
            String applicantNames = 'Welcome ';
            
            if (leadRecord.First_Applicant_Name__c != null) {
                if (leadRecord.salutation_Applicant1__c != null) {
                    applicantNames +=leadRecord.salutation_Applicant1__c + '. ';
                }
                applicantNames += leadRecord.First_Applicant_Name__c + ' ';
            }
            if (leadRecord.Second_Applicant_Name__c != null) {
                applicantNames += '& ';
                if (leadRecord.salutation_Applicant2__c != null) {
                    applicantNames += leadRecord.salutation_Applicant2__c + '. ';
                }
                applicantNames += leadRecord.Second_Applicant_Name__c + ',';
            }
            
            String projectDetails = applicantNames +' ' + leadRecord.Project1__r.Name + ' ' + leadRecord.Block__r.Name + ' ' + leadRecord.Plot__r.Name;
            
            // Set the subject line
            mail.setSubject(projectDetails);
            
            mail.setHtmlBody(emailContent);
            
            mail.setSaveAsActivity(true);
            mail.setWhatId(leadRecord.Id);
            
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
            leadRecord.Welcome_Mail_Sent_Time__c = system.now();
            leadRecord.Welcome_Email_Sent_to_Customer__c = true;
            update leadRecord;
        }
    }
    
    @AuraEnabled
    public static Transfer__c getTransferRecordDetails(Id recId){
        Transfer__c trnas = [select id,name,Customer_Name__c,Email__c,PAN_Number__c,Phone__c,Transfer_Amount__c from Transfer__c where Booking__c =:recId LIMIT 1 ];
        return trnas;
    }
    
    @AuraEnabled
    public static void saveTransfer(Booking__c booking, Id recordId, Boolean isSecondaryApplicantSame) {
        try {
            // Set the Booking Id to the recordId passed from the front end
            booking.Id = recordId;
            system.debug('booking'+booking);
            system.debug('recordId'+recordId);
            system.debug('isSecondaryApplicantSame'+isSecondaryApplicantSame);
            // Check if the secondary applicant fields should be cleared
            if (!isSecondaryApplicantSame) {
                if (String.isEmpty(booking.Second_Applicant_Name__c)) {
                    // Clear the secondary applicant fields if the checkbox is unchecked
                    booking.salutation_Applicant2__c = null;
                    booking.Second_Applicant_Name__c = null;
                    booking.Date_of_birth_Applicant2__c = null;
                    booking.Mobile_Primary1__c = null;
                    booking.Email2__c = null;
                    booking.Nationality_Applicant2__c = null;
                    booking.Relation_Details_Applicant2__c = null;
                    booking.Son_Daughter_Wife_of1__c = null;
                    booking.Passport_Aadhar_1__c = null;
                    booking.Aadhaar_Number1__c = null;
                    booking.Pan_Number_Applicant2__c = null;
                    booking.Occupation1__c = null;
                    booking.Name_of_Company1__c = null;
                    booking.Designation1__c = null;
                    booking.Anniverssary_Date1__c = null;
                    booking.Communication_address1__c = null;
                    booking.Permanent_Address1__c = null;
                }
            }
            
            // Perform the update
            update booking;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save the record: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Booking__c getSecondaryApplicantDetails(Id bookingId) {
        // Query the Booking__c object for secondary applicant details
        Booking__c booking = [SELECT salutation_Applicant2__c, Second_Applicant_Name__c, Date_of_birth_Applicant2__c, 
                              Mobile_Primary1__c, Email2__c, Nationality_Applicant2__c, Relation_Details_Applicant2__c,
                              Son_Daughter_Wife_of1__c, Passport_Aadhar_1__c, Aadhaar_Number1__c, Pan_Number_Applicant2__c, 
                              Occupation1__c, Name_of_Company1__c, Designation1__c, Anniverssary_Date1__c, 
                              Communication_address1__c, Permanent_Address1__c 
                              FROM Booking__c WHERE Id = :bookingId LIMIT 1];
        
        // Return the secondary applicant details
        return booking;
    }
    @AuraEnabled
    public static Quote__c fetchQuoteDetail(string QuoteId) {
        if (QuoteId != null && QuoteId != '') {
            try {
                // ✅ CHANGED: SLead__c to CLead__c
                // Query the Quote__c record
                Quote__c quote = [SELECT Id, Name, CLead__c,Pre_Sale_User_Name__c,Relationship_Manager__c, CLead__r.Lead_source__c, CLead__r.OwnerId , CLead__r.Owner.Name,CLead__r.Old_Owner_Name__r.Name
                                  FROM Quote__c 
                                  WHERE Id = :QuoteId 
                                  LIMIT 1];
                return quote;
            } catch (Exception e) {
                // Handle the error case where the query fails
                System.debug('Error: ' + e.getMessage());
                return null;
            }
        } else {
            // If the QuoteId is null or empty, return null or handle as necessary
            return null;
        }
    }
    
}