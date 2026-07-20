trigger ProjectTrigger on Project__c (before insert,before update,after insert, after update, after delete, after undelete) {
    /*if(Trigger.isAfter && Trigger.isUpdate) {
        Set<Id> newset = new Set<Id>();
        list <Payment_schedule__c> updatelist = new list <Payment_schedule__c>();
        for (Project__c block : Trigger.new) {
            if(block.Interest_Percentage__c != null && block.Interest_Percentage__c != Trigger.oldmap.get(block.Id).Interest_Percentage__c)
                
            {
                newset.add(block.Id);
            }
        }
        List<Payment_schedule__c> lstpayment = [ SELECT Id, Pending_Amount__c,Name,Payment_Due_Date__c, Amount__c,Booking__c,Last_Payment_Date__c, Balance_Amount__c,Payment_percent__c,Booking__r.Project1__r.Interest_Percentage__c, Interest_Up_to_Date__c,Include_Interest__c,Interest_Amount__c,Interest_Percent__c  
                                                FROM Payment_Schedule__c
                                                WHERE Booking__r.Project1__c IN :newset];
        List<Interest_Amount_Line_Item__c> intAmtLiIts = new List<Interest_Amount_Line_Item__c>();
        for (Payment_Schedule__c extps : lstpayment) {
            Payment_schedule__c ps = new Payment_schedule__c();
            ps.id = extps.id;
            ps.Interest_Percent__c = extps.Booking__r.Project1__r.Interest_Percentage__c;
            ps.Interest_Change_Date__c = system.today();
            updatelist.add(ps);
            Interest_Amount_Line_Item__c interestItems = new Interest_Amount_Line_Item__c();
            interestItems.Interest_Amount__c = extps.Interest_Amount__c;
            if(extps.Last_Payment_Date__c == null){
                interestItems.Interest_Start_Date__c = extps.Payment_Due_Date__c;
            }
            else{
                interestItems.Interest_Start_Date__c = extps.Last_Payment_Date__c;
            }
            interestItems.Interest_End_Date__c = system.today();
            interestItems.Interest_Percent__c = extps.Interest_Percent__c;
            interestItems.Payment_Schedule__c = extps.id;
            interestItems.Booking__c = extps.Booking__c;
            interestItems.Principal_Amount__c = extps.Pending_Amount__c;
            intAmtLiIts.add(interestItems);
        }
        if(!updatelist.isEmpty()){
            update updatelist;
        }
        if(!intAmtLiIts.isEmpty()){
            insert intAmtLiIts;
        }
    }*/
}