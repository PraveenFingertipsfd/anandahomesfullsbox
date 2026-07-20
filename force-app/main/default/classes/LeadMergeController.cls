public with sharing class LeadMergeController {

    @AuraEnabled(cacheable=true)
    public static List<LeadWrapper> searchLeads(String searchTerm, Id excludeLeadId) {
        try {
            List<LeadWrapper> results = new List<LeadWrapper>();
            if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
                return results;
            }

            String likeStr = '%' + String.escapeSingleQuotes(searchTerm) + '%';

            List<Lead__c> leads = [
                SELECT Id, Name, Name__c, Phone__c, Secondary_Phone__c,
                       Allocated_Project__c, Lead_Status__c, Owner.Name
                FROM Lead__c
                WHERE Id != :excludeLeadId
                  AND (Name LIKE :likeStr
                       OR Name__c LIKE :likeStr
                       OR Phone__c LIKE :likeStr
                       OR Secondary_Phone__c LIKE :likeStr)
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];

            for (Lead__c ld : leads) {
                results.add(new LeadWrapper(ld));
            }
            return results;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled
    public static LeadDetailWrapper getLeadDetails(Id leadId) {
        try {
            List<Lead__c> leads = [
                SELECT Id, Name, Name__c, Phone__c, Secondary_Phone__c,
                       Allocated_Project__c, Lead_Status__c, Owner.Name
                FROM Lead__c
                WHERE Id = :leadId
                LIMIT 1
            ];
            if (leads.isEmpty()) {
                throw new AuraHandledException('Lead not found. It may have been deleted or you may not have access.');
            }
            Lead__c ld = leads[0];

            Integer enquiryCount = [SELECT COUNT() FROM Enquiry_Source__c WHERE Lead__c = :leadId];
            Integer followUpCount = [SELECT COUNT() FROM Follow_up__c WHERE CLead__c = :leadId];
            Integer siteVisitCount = [SELECT COUNT() FROM Site_Visit__c WHERE CLead__c = :leadId];
            Integer relatedSourceCount = [SELECT COUNT() FROM Related_Source__c WHERE CLead__c = :leadId];

            return new LeadDetailWrapper(ld, enquiryCount, followUpCount, siteVisitCount, relatedSourceCount);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled
    public static String mergeLeads(Id duplicateLeadId, Id actualLeadId) {
        try {
            if (duplicateLeadId == actualLeadId) {
                throw new AuraHandledException('Cannot merge a lead with itself.');
            }
            return new MergeExecutor().execute(duplicateLeadId, actualLeadId);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            String msg = 'Error merging leads: ' + e.getMessage();
            AuraHandledException ex = new AuraHandledException(msg);
            ex.setMessage(msg);
            throw ex;
        }
    }

    // Runs without sharing so it can reassign records owned by other users
    private without sharing class MergeExecutor {
        public String execute(Id duplicateLeadId, Id actualLeadId) {
            List<Lead__c> actualLeads = [
                SELECT Id, OwnerId
                FROM Lead__c
                WHERE Id = :actualLeadId
                LIMIT 1
            ];
            if (actualLeads.isEmpty()) {
                throw new AuraHandledException('Actual lead not found. It may have been deleted.');
            }
            Lead__c actualLead = actualLeads[0];

            // Transfer Enquiry Sources
            List<Enquiry_Source__c> enquirySources = [
                SELECT Id, Lead__c
                FROM Enquiry_Source__c
                WHERE Lead__c = :duplicateLeadId
            ];
            for (Enquiry_Source__c es : enquirySources) {
                es.Lead__c = actualLeadId;
            }
            if (!enquirySources.isEmpty()) {
                update enquirySources;
            }

            // Transfer Follow-ups (change owner to actual lead owner)
            List<Follow_up__c> followUps = [
                SELECT Id, CLead__c, OwnerId
                FROM Follow_up__c
                WHERE CLead__c = :duplicateLeadId
            ];
            for (Follow_up__c fu : followUps) {
                fu.CLead__c = actualLeadId;
                fu.OwnerId = actualLead.OwnerId;
            }
            if (!followUps.isEmpty()) {
                update followUps;
            }

            // Transfer Site Visits (change owner to actual lead owner)
            List<Site_Visit__c> siteVisits = [
                SELECT Id, CLead__c, OwnerId
                FROM Site_Visit__c
                WHERE CLead__c = :duplicateLeadId
            ];
            for (Site_Visit__c sv : siteVisits) {
                sv.CLead__c = actualLeadId;
                sv.OwnerId = actualLead.OwnerId;
            }
            if (!siteVisits.isEmpty()) {
                update siteVisits;
            }

            // Transfer Related Sources (change owner to actual lead owner)
            List<Related_Source__c> relatedSources = [
                SELECT Id, CLead__c, OwnerId
                FROM Related_Source__c
                WHERE CLead__c = :duplicateLeadId
            ];
            for (Related_Source__c rs : relatedSources) {
                rs.CLead__c = actualLeadId;
                rs.OwnerId = actualLead.OwnerId;
            }
            if (!relatedSources.isEmpty()) {
                update relatedSources;
            }

            // Delete the duplicate lead
            List<Lead__c> duplicateLeads = [SELECT Id FROM Lead__c WHERE Id = :duplicateLeadId LIMIT 1];
            if (!duplicateLeads.isEmpty()) {
                delete duplicateLeads[0];
            }

            return 'Lead merged successfully. Transferred '
                + relatedSources.size() + ' Related Source(s), '
                + enquirySources.size() + ' Enquiry Source(s), '
                + followUps.size() + ' Follow-up(s), '
                + siteVisits.size() + ' Site Visit(s).';
        }
    }

    public class LeadWrapper {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String phone;
        @AuraEnabled public String project;
        @AuraEnabled public String status;
        @AuraEnabled public String ownerName;

        public LeadWrapper(Lead__c ld) {
            this.leadId = ld.Id;
            this.leadName = ld.Name;
            this.customerName = ld.Name__c;
            this.phone = ld.Phone__c;
            this.project = ld.Allocated_Project__c;
            this.status = ld.Lead_Status__c;
            this.ownerName = ld.Owner.Name;
        }
    }

    public class LeadDetailWrapper {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String phone;
        @AuraEnabled public String secondaryPhone;
        @AuraEnabled public String project;
        @AuraEnabled public String status;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Integer enquirySourceCount;
        @AuraEnabled public Integer followUpCount;
        @AuraEnabled public Integer siteVisitCount;
        @AuraEnabled public Integer relatedSourceCount;

        public LeadDetailWrapper(Lead__c ld, Integer esCount, Integer fuCount, Integer svCount, Integer rsCount) {
            this.leadId = ld.Id;
            this.leadName = ld.Name;
            this.customerName = ld.Name__c;
            this.phone = ld.Phone__c;
            this.secondaryPhone = ld.Secondary_Phone__c;
            this.project = ld.Allocated_Project__c;
            this.status = ld.Lead_Status__c;
            this.ownerName = ld.Owner.Name;
            this.enquirySourceCount = esCount;
            this.followUpCount = fuCount;
            this.siteVisitCount = svCount;
            this.relatedSourceCount = rsCount;
        }
    }
}