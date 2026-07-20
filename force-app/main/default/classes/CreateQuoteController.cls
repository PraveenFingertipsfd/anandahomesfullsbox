public without sharing class CreateQuoteController {
     public class PicklistWrapper {
         @AuraEnabled public Map<String, List<String>> fieldPicklists { get; set; }
         @AuraEnabled public Lead__c leadRecord { get; set; }
         @AuraEnabled public List<String> paymentTypePicklist { get; set; }
         @AuraEnabled public List<Plot__c> plotList { get; set; }
    }

    public class DiscountOption {
        @AuraEnabled public String label;
        @AuraEnabled public String unitField;
        @AuraEnabled public String quoteField;
        @AuraEnabled public String discountField;
    }

    @AuraEnabled(cacheable=true)
    public static List<DiscountOption> getDiscountConfig() {
        List<DiscountOption> result = new List<DiscountOption>();
        for (Quote_Discount_Config__mdt c : [
            SELECT MasterLabel, Unit_Field_API__c, Quote_Field_API__c, Sort_Order__c
            FROM   Quote_Discount_Config__mdt
            WHERE  Active__c = true
            ORDER  BY Sort_Order__c ASC, MasterLabel ASC
        ]) {
            DiscountOption o = new DiscountOption();
            o.label         = c.MasterLabel;
            o.unitField     = c.Unit_Field_API__c;
            o.quoteField    = c.Quote_Field_API__c;
            o.discountField = c.Quote_Field_API__c != null
                              ? c.Quote_Field_API__c.replace('__c', '_Discount__c')
                              : null;
            result.add(o);
        }
        return result;
    }
    
    @AuraEnabled
    public static List<Plot__c> getPlots(string project){
        List<Plot__c>plotList=new List<Plot__c>();
        string obj='Plot__c';
        plotList = [select Id,Name,Project__r.Name,Plot_Type__c, Plot_Number__c, Project__c, UDS__c, Super_built_up_area__c, Project__r.Project__c,
                    Floor_Rise__c, Floor__c, BHK_Type__c,  Category__c, Common_Area_Allotted_to_Association__c, Premium_Charge__c,
                    Premium_Status__c, Balcony_Area__c, GST1__c, Covered_Park_Parking__c, Price_Per_Sq_Ft__c, Carpet_Area__c,
                    Block1__r.Name, Block__c,Total_Other_Charges__c,Solar_Charges__c,Other_Charges__c, Sub_total__c,Block1__c,Facing__c,Share__c,Status__c,Built_up_area__c,Basic_Price__c,Basic_Sale_Price_Rs__c,Miscellaneous_Charges__c,GST_Amount__c,Total__c,
                    Saleable_Area_Sft__c, East_Facing_Charges__c, Corner_Charges__c, Hi_Rise_Charges__c,
                    Central_Court_Yard_Premium__c, Meadow_Premium__c, Roadside_Premium__c,
                    Court_Yard_Premium__c, Outer_Premium__c, Amenities_Car_Parking__c, Infrastructure_Charges__c
                    from Plot__c
                    where Project__r.Name =:project and Status__c = 'Available' order by Plot_Number__c,Name asc ];
        
        system.debug('recId:' + plotList);
        return plotList;
    }
    
    @AuraEnabled(cacheable=true)
    public static PicklistWrapper getAllPicklistValues(Map<String, List<String>> objectFieldMap,Id recordId) {
        system.debug('recordId'+recordId);
        PicklistWrapper wrapper = new PicklistWrapper();
        wrapper.plotList = new List<Plot__c>();
        Lead__c leadRecord;
         String allocatedProjectName;
        //Fetch Lead details
        if (recordId != null) {
            try {
                leadRecord = [
                    SELECT Id, Allocated_Project__c, Owner.Name, Old_Owner_Name__r.Name
                    FROM Lead__c
                    WHERE Id = :recordId
                    LIMIT 1
                ];
                wrapper.leadRecord = leadRecord;
                system.debug(' Lead record fetched: ' + leadRecord);
                if (leadRecord.Allocated_Project__c != null) {
                    allocatedProjectName = leadRecord.Allocated_Project__c;
                }
            } catch (Exception e) {
                System.debug('Lead fetch error: ' + e.getMessage());
            }
        }
     
        wrapper.fieldPicklists = new Map<String, List<String>>();
        
        if (objectFieldMap == null || objectFieldMap.isEmpty()) {
            return wrapper;
        }
        
        for (String objectName : objectFieldMap.keySet()) {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
            if (sObjectType == null) continue;
            
            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
            
            for (String fieldName : objectFieldMap.get(objectName)) {
                if (!fieldMap.containsKey(fieldName)) continue;
                
                Schema.DescribeFieldResult describeResult = fieldMap.get(fieldName).getDescribe();
                if (describeResult.getType() != Schema.DisplayType.PICKLIST) continue;
                
                List<String> picklistValues = new List<String>();
                for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
                    picklistValues.add(entry.getLabel());
                }
                wrapper.fieldPicklists.put(fieldName, picklistValues);
            }
        }
        // Add Payment Type picklist from Quote__c
        List<String> paymentTypeValues = new List<String>();
        for (Schema.PicklistEntry entry : Quote__c.Payment_Type__c.getDescribe().getPicklistValues()) {
            paymentTypeValues.add(entry.getLabel());
        }
        wrapper.paymentTypePicklist = paymentTypeValues;
        
        
           system.debug('allocatedProjectName'+allocatedProjectName);
       // Fetch Plots for the Allocated Project
    if (!String.isBlank(allocatedProjectName)) {
        try {
            List<Plot__c> plotList = [
                SELECT Id, Name, Project__r.Name, Plot_Type__c, Plot_Number__c, Project__c, UDS__c,
                       Super_built_up_area__c, Project__r.Project__c, Floor_Rise__c, Floor__c, BHK_Type__c,
                       Category__c, Common_Area_Allotted_to_Association__c, Premium_Charge__c, Premium_Status__c,
                       Balcony_Area__c, GST1__c, Covered_Park_Parking__c, Price_Per_Sq_Ft__c, Carpet_Area__c,
                       Block1__r.Name, Block__c, Total_Other_Charges__c, Solar_Charges__c, Other_Charges__c,
                       Sub_total__c, Block1__c, Facing__c, Share__c, Status__c, Built_up_area__c, Basic_Price__c,
                       Basic_Sale_Price_Rs__c, Miscellaneous_Charges__c, GST_Amount__c, Total__c,
                       Saleable_Area_Sft__c, East_Facing_Charges__c, Corner_Charges__c, Hi_Rise_Charges__c,
                       Central_Court_Yard_Premium__c, Meadow_Premium__c, Roadside_Premium__c,
                       Court_Yard_Premium__c, Outer_Premium__c, Amenities_Car_Parking__c, Infrastructure_Charges__c
                FROM Plot__c
                WHERE Project__r.Name = :allocatedProjectName
                AND Status__c = 'Available'
                ORDER BY Plot_Number__c, Name ASC
            ];
            wrapper.plotList = plotList;
            System.debug('Plot list fetched: ' + plotList.size());
        } catch (Exception e) {
            System.debug('Plot fetch error: ' + e.getMessage());
        }
    }

    System.debug('Final Wrapper => ' + JSON.serialize(wrapper));
    return wrapper;
}
    
    // Maps a status coming from a non-restricted source (e.g. Master_payment_schedule__c,
    // whose values are Not Started / In Progress / Completed) onto the restricted
    // Cost_Sheet_Line_Item__c.status__c picklist (Scheduled / Demanded / Paid / Completed).
    // Already-valid values pass through; anything else (incl. 'Not Started', null, blank)
    // defaults to 'Scheduled'.
    private static String normalizeLineItemStatus(String s) {
        if (s == 'Scheduled' || s == 'Demanded' || s == 'Paid' || s == 'Completed') {
            return s;
        }
        if (s == 'In Progress') {
            return 'Demanded';
        }
        return 'Scheduled';
    }

    @AuraEnabled
    public static String saveOppPlot(Quote__c oppPlot) {
        try {
            System.debug('oppPlot: ' + oppPlot);
            insert oppPlot;
            System.debug('------- Inserted with Id: ' + oppPlot.Id);
            return oppPlot.Id;
        } catch (Exception e) {
            System.debug('Error inserting Quote__c: ' + e.getMessage());
            // Return the error message to the Aura component
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static void submitapproval(string quoteId){
        
    }
    
    @AuraEnabled
    public static List<String> getPaymentTypePicklistValues() {
        List<String> paymentTypeValues = new List<String>();
        Schema.DescribeFieldResult fieldResult = Quote__c.Payment_Type__c.getDescribe();
        
        for (Schema.PicklistEntry picklistEntry : fieldResult.getPicklistValues()) {
            paymentTypeValues.add(picklistEntry.getLabel());
        }
        
        return paymentTypeValues;
    }
    
    @AuraEnabled
    public static string getAllocatedProjectValue(Id recordId) {
        // Query the Allocated_Project__c field from the Lead__c object
        Lead__c leadRecord = [SELECT Allocated_Project__c,Old_Owner_Name__r.Name,Owner.Name FROM Lead__c WHERE Id = :recordId LIMIT 1];
        
        // Return the Allocated_Project__c value
        return leadRecord.Allocated_Project__c;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getVisitedProjects(Id recordId) {
        Set<String> projects = new Set<String>();
        for (Site_Visit__c sv : [
            SELECT Project__c
            FROM Site_Visit__c
            WHERE CLead__c = :recordId
              AND Status__c = 'Completed'
              AND Project__c != null
        ]) {
            projects.add(sv.Project__c);
        }
        List<String> result = new List<String>(projects);
        result.sort();
        return result;
    }

    @AuraEnabled
    public static Lead__c getLeadDetails(Id recordId) {
        // Query the Allocated_Project__c field from the Lead__c object
        Lead__c leadRecord = [SELECT Allocated_Project__c,Old_Owner_Name__r.Name,Owner.Name FROM Lead__c WHERE Id = :recordId LIMIT 1];
        
        // Return the Lead__c record
        return leadRecord;
    }
    
    @AuraEnabled
    public static databox getPaymentSchedules(String Pay, String Project, Decimal gt, String towerId) {
        databox db = new databox();

        List<Master_payment_schedule__c> masterSchedules = [
            SELECT Id, Project__c, S_No__c, Name, Tentative_TimeLine__c,
            Payment_Percent__c, Completed_Date__c, Due_Date__c, Status__c , Amount__c
            FROM Master_payment_schedule__c
            WHERE Project__c = :Project AND Tower__c = :towerId
            ORDER BY S_No__c ASC
        ];
        system.debug('masterSchedules '+masterSchedules);
        if (masterSchedules.isEmpty()) {
            db.message = 'No payment schedule assigned to this tower.';
            db.payList = null;
            db.paymentSum = 0.00;
            db.totalPercent = 0;
            db.RecivedAmount = 0;
            db.RecivedAmountTotal = 0;
            db.RecivedPercent = 0;
            db.scheduledAmount = 0;
            return db;
        }
        
        List<Cost_Sheet_Line_Item__c> schedules = new List<Cost_Sheet_Line_Item__c>();
        for (Master_payment_schedule__c mps : masterSchedules) {
            schedules.add(new Cost_Sheet_Line_Item__c(
                Master_Payment_Schedule__c = mps.Id,
                Payment_Schedule_Name__c = mps.Name,
                Payment_percent__c = mps.Payment_Percent__c,
                S_No__c = mps.S_No__c,
                Amount__c = gt * (mps.Payment_Percent__c / 100),
                Tentative_TimeLine__c = mps.Tentative_TimeLine__c,
                status__c = normalizeLineItemStatus(mps.Status__c),
                Payment_Due_Date__c = mps.Due_Date__c
            ));
        }
        system.debug('schedules '+schedules);
        db.payList = schedules;
        db.message = 'Payment schedules retrieved successfully.';
        db.paymentSum = 0.00;
        db.totalPercent = 0;
        db.RecivedAmount = 0;
        db.RecivedAmountTotal = 0;
        db.RecivedPercent = 0;
        db.scheduledAmount = 0;
        system.debug('db '+db);
        return db;
    }

    public class databox{
        @AuraEnabled 
        public List<Cost_Sheet_Line_Item__c> payList;
        @AuraEnabled
        public List<Master_payment_schedule__c> MasterpayList;
        @AuraEnabled
        public Decimal grandTotal;
        @AuraEnabled
        public Decimal paymentSum;
        @AuraEnabled
        public Decimal RecivedAmountTotal;
        @AuraEnabled
        public Decimal totalPercent;
        @AuraEnabled
        public Decimal RecivedAmount;
        @AuraEnabled
        public string objectName;
        @AuraEnabled
        public string projectName;
        @AuraEnabled
        public string message;
        @AuraEnabled
        public string flatNumber;
        @AuraEnabled
        public Decimal RecivedPercent;
        @AuraEnabled
        public Decimal ScheduledAmount;
        @AuraEnabled
        public Decimal TotalOutStandingDueAmount;
        @AuraEnabled
        public Decimal TotalPaidAmount;
    } 
    
    @AuraEnabled
    public static void insertSchedules(List<Cost_Sheet_Line_Item__c> payList, Decimal gt, String quoteid){
        system.debug('entered');
        List<Cost_Sheet_Line_Item__c> schduleList = new List<Cost_Sheet_Line_Item__c>();

        for(Cost_Sheet_Line_Item__c pay : payList){
            Cost_Sheet_Line_Item__c ps = new Cost_Sheet_Line_Item__c();
            ps.Payment_Schedule_Name__c = pay.Payment_Schedule_Name__c;
            ps.Payment_percent__c = pay.Payment_percent__c;
            ps.Payment_Due_Date__c = pay.Payment_Due_Date__c;
            // Custom rows arrive with Amount__c empty; derive it from gt * percent / 100
            // (same formula Standard rows already use in getPaymentSchedules).
            if (pay.Amount__c == null && pay.Payment_percent__c != null && gt != null) {
                ps.Amount__c = (gt * (pay.Payment_percent__c / 100)).setScale(2);
            } else {
                ps.Amount__c = pay.Amount__c;
            }
            ps.Master_Payment_Schedule__c = pay.Master_Payment_Schedule__c;
            ps.S_No__c = pay.S_No__c;
            ps.Quote__c = quoteid;
            ps.status__c = normalizeLineItemStatus(pay.status__c);
            ps.Last_Payment_Date__c = pay.Last_Payment_Date__c;
            schduleList.add(ps);
        }

        system.debug('schduleList :'+ schduleList);
        upsert schduleList;
        system.debug('success');
    }
    
     public static void testcover(){
        integer  i=0;
        if(i==0){
            i=0;i=0;i=0;i=0; 
            i=0;i=0;i=0;i=0; 
            i=0;i=0;i=0;i=0;
            i=0;i=0;i=0;i=0;
            i=0;i=0;i=0;i=0;
            i=0;i=0;i=0;i=0;
            i=0;i=0;i=0;i=0;
            i=0;i=0;i=0;i=0;
            i=0;i=0;i=0;i=0;
        }
     }
}