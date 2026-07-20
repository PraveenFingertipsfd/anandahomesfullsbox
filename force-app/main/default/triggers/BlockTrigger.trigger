trigger BlockTrigger on Block__c (before insert, before update, after insert, after update, after delete, after undelete) {

    if(Trigger.isAfter && Trigger.isUpdate) {
        Set<Id> updatedBlockIds = new Set<Id>();
        List<Payment_Schedule__c> updateList = new List<Payment_Schedule__c>();
        
        for (Block__c block : Trigger.new) { 
            if(block.Intrest_Percentage__c != null &&
               block.Intrest_Percentage__c != Trigger.oldMap.get(block.Id).Intrest_Percentage__c) {
                updatedBlockIds.add(block.Id);
            }
        }
        
        if(!updatedBlockIds.isEmpty()) {
            List<Payment_Schedule__c> lstPayments = [
                SELECT Id, Booking__r.Block__r.Intrest_Percentage__c
                FROM Payment_Schedule__c
                WHERE Booking__r.Block__c IN :updatedBlockIds
            ];
            
            for (Payment_Schedule__c ps : lstPayments) {
                ps.Interest_Percent__c = ps.Booking__r.Block__r.Intrest_Percentage__c;
                updateList.add(ps);
            }
            
            if(!updateList.isEmpty()){
                update updateList;
            }
        }
    }
}