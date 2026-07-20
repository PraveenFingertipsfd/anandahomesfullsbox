// Last updated: 2026-04-22
public with sharing class UnitBlockingController {

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getProjectOptions() {
        try {
            List<PicklistOption> options = new List<PicklistOption>();
            Schema.DescribeFieldResult fieldResult =
                Unit_Block_History__c.Project__c.getDescribe();
            for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
                }
            }
            return options;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UnitWrapper> searchUnits(String projectValue, String searchTerm) {
        try {
            List<UnitWrapper> results = new List<UnitWrapper>();
            if (String.isBlank(projectValue)) {
                return results;
            }

            List<Plot__c> plots;
            if (String.isBlank(searchTerm)) {
                plots = [
                    SELECT Id, Name, Apartment_No__c, Unit_Number__c,
                           Plot_Number__c, Tower__c, Floor_Number__c, Status__c,
                           Project_Name__c
                    FROM Plot__c
                    WHERE Project_Name__c = :projectValue
                      AND Status__c = 'Available'
                    ORDER BY Apartment_No__c NULLS LAST
                    LIMIT 25
                ];
            } else {
                String likeStr = '%' + String.escapeSingleQuotes(searchTerm) + '%';
                plots = [
                    SELECT Id, Name, Apartment_No__c, Unit_Number__c,
                           Plot_Number__c, Tower__c, Floor_Number__c, Status__c,
                           Project_Name__c
                    FROM Plot__c
                    WHERE Project_Name__c = :projectValue
                      AND Status__c = 'Available'
                      AND (Name LIKE :likeStr
                           OR Apartment_No__c LIKE :likeStr
                           OR Unit_Number__c LIKE :likeStr
                           OR Plot_Number__c LIKE :likeStr)
                    ORDER BY Apartment_No__c NULLS LAST
                    LIMIT 25
                ];
            }

            for (Plot__c p : plots) {
                results.add(new UnitWrapper(p));
            }
            return results;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled
    public static Id saveUnitBlock(Id leadId, Id unitId, String projectValue,
                                   String blockReason, Decimal blockDuration) {
        try {
            if (leadId == null) {
                throw new AuraHandledException('Lead is required.');
            }
            if (unitId == null) {
                throw new AuraHandledException('Unit is required.');
            }
            if (String.isBlank(projectValue)) {
                throw new AuraHandledException('Project is required.');
            }
            if (String.isBlank(blockReason)) {
                throw new AuraHandledException('Block Reason is required.');
            }
            if (blockDuration == null || blockDuration <= 0) {
                throw new AuraHandledException('No of days to Block must be greater than zero.');
            }

            List<Project__c> projects = [
                SELECT Id, Max_Unit_Block_Days__c
                FROM Project__c
                WHERE Name = :projectValue
                LIMIT 1
            ];
            if (!projects.isEmpty()
                && projects[0].Max_Unit_Block_Days__c != null
                && blockDuration > projects[0].Max_Unit_Block_Days__c) {
                String msg = 'Days for blocking the unit exceeds the defined limit';
                AuraHandledException limitEx = new AuraHandledException(msg);
                limitEx.setMessage(msg);
                throw limitEx;
            }

            Datetime blockedTime = System.now();
            Unit_Block_History__c rec = new Unit_Block_History__c(
                CLead__c               = leadId,
                Unit__c                = unitId,
                Project__c             = projectValue,
                Block_Reason__c        = blockReason,
                Block_Duration__c      = blockDuration,
                Status__c              = 'Blocked',
                Blocked_Time__c        = blockedTime,
                Blocked_Expiry_Date__c = blockedTime.addDays(blockDuration.intValue()),
                Executive__c           = UserInfo.getUserId()
            );

            Savepoint sp = Database.setSavepoint();
            try {
                insert rec;
                update new Plot__c(Id = unitId, Status__c = 'Blocked');
            } catch (Exception dmlEx) {
                Database.rollback(sp);
                throw dmlEx;
            }
            return rec.Id;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class UnitWrapper {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String name;
        @AuraEnabled public String apartmentNo;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String plotNumber;
        @AuraEnabled public String tower;
        @AuraEnabled public String floorNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String projectName;

        public UnitWrapper(Plot__c p) {
            this.unitId      = p.Id;
            this.name        = p.Name;
            this.apartmentNo = p.Apartment_No__c;
            this.unitNumber  = p.Unit_Number__c;
            this.plotNumber  = p.Plot_Number__c;
            this.tower       = p.Tower__c;
            this.floorNumber = p.Floor_Number__c == null ? null : String.valueOf(p.Floor_Number__c);
            this.status      = p.Status__c;
            this.projectName = p.Project_Name__c;
        }
    }
}