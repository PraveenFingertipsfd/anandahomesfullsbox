// Last Modified: 2026-03-27
public without sharing class SLeadTriggerHandler {

    public static void pushToCustomLead(List<Lead> newLeads) {
        List<Lead__c> customLeads = new List<Lead__c>();

        for (Lead sLead : newLeads) {
            Lead__c ld = new Lead__c();

            // Name mapping
            ld.Lead_First_Name__c = sLead.FirstName;
            ld.Lead_Last_Name__c = sLead.LastName;
            String fullName = '';
            if (String.isNotBlank(sLead.FirstName)) {
                fullName = sLead.FirstName;
            }
            if (String.isNotBlank(sLead.LastName)) {
                fullName = String.isNotBlank(fullName) ? fullName + ' ' + sLead.LastName : sLead.LastName;
            }
            if (String.isBlank(fullName)) {
                fullName = sLead.Phone__c;
            }
            ld.Name__c = fullName;

            // Contact fields
            ld.Phone__c = sLead.Phone__c;
            ld.Secondary_Phone__c = sLead.Secondary_Phone__c;
            ld.Email__c = sLead.Email;
            ld.Secondary_Email__c = sLead.Secondary_Email__c;

            // Source & Project
            ld.Lead_source__c = sLead.Lead_source__c;
            ld.Allocated_Project__c = sLead.Allocated_Project__c;

            // Campaign — store text; LeadTrigger mapCampaignLookup resolves the lookup
            ld.Campaign__c = sLead.Campaign__c;

            customLeads.add(ld);
        }

        if (!customLeads.isEmpty()) {
            insert customLeads;
            // LeadTrigger on Lead__c handles: phone normalization, campaign lookup resolution,
            // duplicate check, round-robin assignment, record type mapping

            // Delete standard Leads asynchronously (cannot delete in same after-insert transaction)
            Set<Id> standardLeadIds = new Set<Id>();
            for (Lead sLead : newLeads) {
                standardLeadIds.add(sLead.Id);
            }
            deleteStandardLeads(standardLeadIds);
        }
    }

    @future
    public static void deleteStandardLeads(Set<Id> leadIds) {
        List<Lead> toDelete = [SELECT Id FROM Lead WHERE Id IN :leadIds];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }
}