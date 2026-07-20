public class getQuoteData {
    public List<Master_Payment_Schedule__c> masterPayments { get; set; }
    public Id recid { get; set; }
    public string currencySymbol {get; set;}
    public getQuoteData(ApexPages.StandardController controller) {
        this.recid = ApexPages.currentPage().getParameters().get('id');
        
        if (recid != null) {
            Quote__c quotes = [select Id, Name, Unit__c,	Project1__c from Quote__c where id=:recid limit 1];
            List<Master_Payment_Schedule__c> master = [select Id, Name,Payment_Percent__c,S_No__c from Master_Payment_Schedule__c where Unit__c=:quotes.Unit__c and Project__c=:quotes.Project1__c Order By S_No__c asc];
            //List<Quote__c> quotes = [SELECT Id,  (SELECT Id, Name, Payment_percent__c, S_No__c FROM Payment_Schedules__r ORDER BY S_No__c ASC) FROM Quote__c WHERE Id = :recid LIMIT 1];
            
            if (!master.isEmpty()) {
                masterPayments = master;
            }
            currencySymbol = '₹';
        }
    }
}