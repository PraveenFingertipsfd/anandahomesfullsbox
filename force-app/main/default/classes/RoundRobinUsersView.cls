public without sharing class  RoundRobinUsersView {
     @AuraEnabled(cacheable=true)
    public static List<Round_Robin_Member__c> fetchRoundRobinMembers(string recordId) {
        return [SELECT Id, Name, Active__c,User__r.Name,User_Type__c FROM Round_Robin_Member__c where Round_Robin__c=:recordId ];
    }
    

    @AuraEnabled
    public static List<Round_Robin_Member__c> toggleMemberStatus(Id memId,string recId) {
        Round_Robin_Member__c member = [SELECT Id, Active__c,User__r.Name,User_Type__c FROM Round_Robin_Member__c WHERE Id = :memId LIMIT 1];
        member.Active__c = !member.Active__c; 
        update member;

		return [SELECT Id, Name, Active__c,User__r.Name,User_Type__c FROM Round_Robin_Member__c where Round_Robin__c=:recId];
    }

}