public class QuoteApprovalTriggerHandler {

    public static void handleBeforeInsert(List<Quote__c> quotes) {
        mapManagerHierarchy(quotes);
    }

    public static void handleAfterInsert(List<Quote__c> quotes) {
        if (quotes == null || quotes.isEmpty()) return;

        List<String> discountFields = getDiscountFieldNames();

        Set<Id> quoteIds = new Set<Id>();
        for (Quote__c qt : quotes) {
            quoteIds.add(qt.Id);
        }

        Set<Id> autoApproveIds = new Set<Id>();
        Set<Id> submitIds      = new Set<Id>();

        if (discountFields.isEmpty()) {
            submitIds.addAll(quoteIds);
        } else {
            String quoteSoql = 'SELECT Id, OwnerId, Project__c, ' +
                               String.join(discountFields, ', ') +
                               ' FROM Quote__c WHERE Id IN :quoteIds';
            List<Quote__c> fullQuotes = (List<Quote__c>) Database.query(quoteSoql);

            Set<Id> ownerIds = new Set<Id>();
            Set<String> projectVals = new Set<String>();
            for (Quote__c qt : fullQuotes) {
                if (qt.OwnerId != null) ownerIds.add(qt.OwnerId);
                if (qt.Project__c != null) projectVals.add(qt.Project__c);
            }

            Map<String, SObject> limitByKey = new Map<String, SObject>();
            if (!ownerIds.isEmpty() && !projectVals.isEmpty()) {
                String limitSoql = 'SELECT Executive__c, Project__c, ' +
                                   String.join(discountFields, ', ') +
                                   ' FROM Discount_Limit__c ' +
                                   'WHERE Executive__c IN :ownerIds ' +
                                   '  AND Project__c IN :projectVals';
                for (SObject dl : Database.query(limitSoql)) {
                    String key = String.valueOf(dl.get('Executive__c')) + '|' +
                                 String.valueOf(dl.get('Project__c'));
                    limitByKey.put(key, dl);
                }
            }

            for (Quote__c qt : fullQuotes) {
                String key = String.valueOf(qt.OwnerId) + '|' + String.valueOf(qt.Project__c);
                SObject limitRec = limitByKey.get(key);
                if (limitRec == null) {
                    submitIds.add(qt.Id);
                    continue;
                }
                Boolean allWithin = true;
                for (String fld : discountFields) {
                    Decimal taken  = (Decimal) qt.get(fld);
                    Decimal capped = (Decimal) limitRec.get(fld);
                    if (taken == null)  taken  = 0;
                    if (capped == null) capped = 0;
                    if (taken > capped) {
                        allWithin = false;
                        break;
                    }
                }
                if (allWithin) autoApproveIds.add(qt.Id);
                else           submitIds.add(qt.Id);
            }
        }

        if (!autoApproveIds.isEmpty()) {
            autoApproveWithinLimit(autoApproveIds);
        }
        if (!submitIds.isEmpty()) {
            submitForApproval(submitIds, 'Quote_Approval');
        }

        updateUnitStatus(quotes, 'Blocked');
        createQuoteBlockHistory(quotes);
    }

    private static List<String> getDiscountFieldNames() {
        List<String> fields = new List<String>();
        for (Quote_Discount_Config__mdt c : [
            SELECT Quote_Field_API__c
            FROM   Quote_Discount_Config__mdt
            WHERE  Active__c = true
        ]) {
            if (c.Quote_Field_API__c != null) {
                fields.add(c.Quote_Field_API__c.replace('__c', '_Discount__c'));
            }
        }
        return fields;
    }

    private static void autoApproveWithinLimit(Set<Id> quoteIds) {
        List<Quote__c> toUpdate = new List<Quote__c>();
        for (Id qId : quoteIds) {
            toUpdate.add(new Quote__c(Id = qId, Quote_status__c = 'Approved'));
        }
        update toUpdate;
    }

    public static void handleAfterUpdate(List<Quote__c> newQuotes, Map<Id, Quote__c> oldMap) {
        List<Quote__c> rejectedQuotes = new List<Quote__c>();
        Set<Id> rejectedQuoteIds = new Set<Id>();
        List<Quote__c> deniedQuotes = new List<Quote__c>();
        Set<Id> deniedQuoteIds = new Set<Id>();
        for (Quote__c qt : newQuotes) {
            String oldStatus = oldMap.get(qt.Id).Quote_status__c;
            if (qt.Quote_status__c == 'Rejected' && oldStatus != 'Rejected') {
                rejectedQuotes.add(qt);
                rejectedQuoteIds.add(qt.Id);
            }
            if (qt.Quote_status__c == 'Denied by Customer' && oldStatus != 'Denied by Customer') {
                deniedQuotes.add(qt);
                deniedQuoteIds.add(qt.Id);
            }
        }
        if (!rejectedQuotes.isEmpty()) {
            updateUnitStatus(rejectedQuotes, 'Available');
            revokeQuoteBlockHistory(rejectedQuoteIds, 'Cost sheet was rejected');
        }
        if (!deniedQuotes.isEmpty()) {
            updateUnitStatus(deniedQuotes, 'Available');
            revokeQuoteBlockHistory(deniedQuoteIds, 'Cost sheet was denied by customer');
        }
    }

    private static void revokeQuoteBlockHistory(Set<Id> quoteIds, String revokeReason) {
        List<Unit_Block_History__c> toRevoke = [
            SELECT Id, Status__c, Revoke_Reason__c
            FROM Unit_Block_History__c
            WHERE Quote__c IN :quoteIds
              AND Status__c != 'Revoked'
        ];
        if (toRevoke.isEmpty()) {
            return;
        }
        for (Unit_Block_History__c h : toRevoke) {
            h.Status__c        = 'Revoked';
            h.Revoke_Reason__c = revokeReason;
        }
        update toRevoke;
    }

    private static void mapManagerHierarchy(List<Quote__c> quotes) {
        if (quotes == null || quotes.isEmpty()) return;

        Map<Id, Id> ownerToManagerMap = new Map<Id, Id>();
        Map<Id, Id> managerToGrandManagerMap = new Map<Id, Id>();

        Set<Id> ownerIds = new Set<Id>();
        for (Quote__c qt : quotes) {
            if (qt.OwnerId != null) {
                ownerIds.add(qt.OwnerId);
            }
        }

        if (ownerIds.isEmpty()) return;

        List<User> users = [SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds];
        for (User u : users) {
            ownerToManagerMap.put(u.Id, u.ManagerId);
        }

        Set<Id> managerIds = new Set<Id>();
        for (Id managerId : ownerToManagerMap.values()) {
            if (managerId != null) {
                managerIds.add(managerId);
            }
        }

        if (!managerIds.isEmpty()) {
            List<User> managers = [SELECT Id, ManagerId FROM User WHERE Id IN :managerIds];
            for (User manager : managers) {
                if (manager.ManagerId != null) {
                    managerToGrandManagerMap.put(manager.Id, manager.ManagerId);
                }
            }
        }

        for (Quote__c qt : quotes) {
            if (ownerToManagerMap.containsKey(qt.OwnerId)) {
                Id managerId = ownerToManagerMap.get(qt.OwnerId);
                qt.Manager__c = managerId;

                if (managerToGrandManagerMap.containsKey(managerId)) {
                    qt.GrandManager__c = managerToGrandManagerMap.get(managerId);
                }
            }
        }
    }

    private static void updateUnitStatus(List<Quote__c> quotes, String status) {
        List<Plot__c> plotsToUpdate = new List<Plot__c>();
        for (Quote__c qt : quotes) {
            if (qt.Unit__c != null) {
                plotsToUpdate.add(new Plot__c(Id = qt.Unit__c, Status__c = status));
            }
        }
        if (!plotsToUpdate.isEmpty()) {
            update plotsToUpdate;
        }
    }

    private static void createQuoteBlockHistory(List<Quote__c> quotes) {
        Set<Id> projectIds = new Set<Id>();
        for (Quote__c qt : quotes) {
            if (qt.Project1__c != null) {
                projectIds.add(qt.Project1__c);
            }
        }

        Map<Id, String> projectNameById = new Map<Id, String>();
        if (!projectIds.isEmpty()) {
            for (Project__c p : [SELECT Id, Name FROM Project__c WHERE Id IN :projectIds]) {
                projectNameById.put(p.Id, p.Name);
            }
        }

        Datetime now = System.now();
        List<Unit_Block_History__c> toInsert = new List<Unit_Block_History__c>();
        for (Quote__c qt : quotes) {
            if (qt.Unit__c == null || qt.CLead__c == null) {
                continue;
            }
            toInsert.add(new Unit_Block_History__c(
                CLead__c        = qt.CLead__c,
                Unit__c         = qt.Unit__c,
                Quote__c        = qt.Id,
                Project__c      = projectNameById.get(qt.Project1__c),
                Status__c       = 'Blocked',
                Blocked_Time__c = now,
                Block_Reason__c = 'Blocked due to Cost Sheet Creation',
                Executive__c    = qt.OwnerId
            ));
        }

        if (toInsert.isEmpty()) {
            return;
        }

        Database.SaveResult[] results = Database.insert(toInsert, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(LoggingLevel.WARN,
                    'Unit_Block_History__c insert failed for Quote ' + toInsert[i].Quote__c +
                    ': ' + results[i].getErrors());
            }
        }
    }

    private static void submitForApproval(Set<Id> quoteIds, String approvalProcessName) {
        if (Test.isRunningTest()) return;
        for (Id qId : quoteIds) {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(qId);
            req.setSubmitterId(UserInfo.getUserId());
            req.setProcessDefinitionNameOrId(approvalProcessName);
            req.setComments('Auto-submitted by trigger');
            Approval.ProcessResult res = Approval.process(req);
        }
    }
}