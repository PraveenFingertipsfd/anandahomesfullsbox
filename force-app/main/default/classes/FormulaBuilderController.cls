/**
 * @description Controller for Formula Builder LWC
 */
public with sharing class FormulaBuilderController {
    
    /**
     * Get all projects for dropdown
     */
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects() {
        return [SELECT Id, Name FROM Project__c ORDER BY Name LIMIT 1000];
    }
    
    
}