@isTest
private class QuoteApprovalTriggerHandlerTest {

    // Tests handleBeforeInsert (covers mapManagerHierarchy — sets Manager__c / GrandManager__c)
    // Hierarchy: owner → manager → grandManager (3 levels required for GrandManager__c to populate)
    @isTest
    static void testHandleBeforeInsert() {
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User grandManager = new User(
            FirstName = 'Grand', LastName = 'Manager',
            Email = 'grandmgr@testex.com',
            Username = 'grandmgr' + System.currentTimeMillis() + '@testex.com',
            Alias = 'gmgr',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles',
            ProfileId = stdProfile.Id
        );
        insert grandManager;

        User manager = new User(
            FirstName = 'Mid', LastName = 'Manager',
            Email = 'midmgr@testex.com',
            Username = 'midmgr' + System.currentTimeMillis() + '@testex.com',
            Alias = 'mmgr',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles',
            ProfileId = stdProfile.Id,
            ManagerId = grandManager.Id
        );
        insert manager;

        User owner = new User(
            FirstName = 'Owner', LastName = 'User',
            Email = 'owneruser@testex.com',
            Username = 'owneruser' + System.currentTimeMillis() + '@testex.com',
            Alias = 'ownr',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles',
            ProfileId = stdProfile.Id,
            ManagerId = manager.Id
        );
        insert owner;

        // Build quotes in memory (before insert — no IDs yet)
        Quote__c q1 = new Quote__c(OwnerId = owner.Id);         // has full 3-level hierarchy
        Quote__c q2 = new Quote__c(OwnerId = grandManager.Id);  // top of hierarchy — no manager
        List<Quote__c> quotes = new List<Quote__c>{ q1, q2 };

        Test.startTest();
        // handleBeforeInsert calls mapManagerHierarchy which populates Manager__c / GrandManager__c
        QuoteApprovalTriggerHandler.handleBeforeInsert(quotes);

        // Cover the null / empty guard paths in mapManagerHierarchy
        QuoteApprovalTriggerHandler.handleBeforeInsert(null);
        QuoteApprovalTriggerHandler.handleBeforeInsert(new List<Quote__c>());
        Test.stopTest();

        // q1: Owner -> Manager (manager.Id) -> GrandManager (grandManager.Id)
        System.assertEquals(manager.Id, q1.Manager__c, 'Manager__c should be the owner\'s ManagerId');
        System.assertEquals(grandManager.Id, q1.GrandManager__c, 'GrandManager__c should be the manager\'s ManagerId');
    }

    // Tests handleAfterInsert (covers updateUnitStatus → 'Blocked')
    // submitForApproval returns early in test context — those inner lines are not reachable
    @isTest
    static void testHandleAfterInsert() {
        Project__c proj = new Project__c(Name = 'ProjAI', Project_Type__c = 'Residential');
        insert proj;

        Block__c blk = new Block__c(Name = 'BlkAI');
        insert blk;

        String statusVal = Plot__c.Status__c.getDescribe().getPicklistValues()[0].getValue();
        String bhkVal = Plot__c.BHK_Type__c.getDescribe().getPicklistValues()[0].getValue();

        Plot__c plot = new Plot__c(
            Name = 'UnitAI', Price_Per_Sq_Ft__c = 1000,
            Project__c = proj.Id, Status__c = statusVal,
            Block1__c = blk.Id, BHK_Type__c = bhkVal
        );
        insert plot;

        // Call directly with an in-memory quote that has Unit__c set
        // (not inserted to avoid trigger double-fire; submitForApproval returns early in tests)
        Quote__c q = new Quote__c(Unit__c = plot.Id);

        Test.startTest();
        QuoteApprovalTriggerHandler.handleAfterInsert(new List<Quote__c>{ q });
        Test.stopTest();

        // Unit status should now be 'Blocked'
        Plot__c updated = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Blocked', updated.Status__c, 'Plot should be Blocked after handleAfterInsert');
    }

    // Tests handleAfterUpdate when a Quote transitions to 'Rejected' (covers updateUnitStatus → 'Available')
    @isTest
    static void testHandleAfterUpdate_Rejected() {
        Project__c proj = new Project__c(Name = 'ProjAU', Project_Type__c = 'Residential');
        insert proj;

        Block__c blk = new Block__c(Name = 'BlkAU');
        insert blk;

        String statusVal = Plot__c.Status__c.getDescribe().getPicklistValues()[0].getValue();
        String bhkVal = Plot__c.BHK_Type__c.getDescribe().getPicklistValues()[0].getValue();

        Plot__c plot = new Plot__c(
            Name = 'UnitAU', Price_Per_Sq_Ft__c = 1000,
            Project__c = proj.Id, Status__c = statusVal,
            Block1__c = blk.Id, BHK_Type__c = bhkVal
        );
        insert plot;

        // Insert quote without Unit__c to avoid trigger side-effects, then set it in memory
        Quote__c q = new Quote__c();
        insert q;

        // Simulate a Drafted → Rejected transition
        Map<Id, Quote__c> oldMap = new Map<Id, Quote__c>{
            q.Id => new Quote__c(Id = q.Id, Quote_status__c = 'Drafted')
        };
        q.Quote_status__c = 'Rejected';
        q.Unit__c = plot.Id;    // set in memory so updateUnitStatus can update it

        Test.startTest();
        QuoteApprovalTriggerHandler.handleAfterUpdate(new List<Quote__c>{ q }, oldMap);
        Test.stopTest();

        // Unit status should now be 'Available'
        Plot__c updated = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Available', updated.Status__c, 'Plot should be Available after rejection');
    }

    // Tests handleAfterUpdate when a Quote transitions to 'Denied by Customer'
    // (covers updateUnitStatus → 'Available' for the denial branch)
    @isTest
    static void testHandleAfterUpdate_DeniedByCustomer() {
        Project__c proj = new Project__c(Name = 'ProjDC', Project_Type__c = 'Residential');
        insert proj;

        Block__c blk = new Block__c(Name = 'BlkDC');
        insert blk;

        String statusVal = Plot__c.Status__c.getDescribe().getPicklistValues()[0].getValue();
        String bhkVal = Plot__c.BHK_Type__c.getDescribe().getPicklistValues()[0].getValue();

        Plot__c plot = new Plot__c(
            Name = 'UnitDC', Price_Per_Sq_Ft__c = 1000,
            Project__c = proj.Id, Status__c = statusVal,
            Block1__c = blk.Id, BHK_Type__c = bhkVal
        );
        insert plot;

        Quote__c q = new Quote__c();
        insert q;

        Map<Id, Quote__c> oldMap = new Map<Id, Quote__c>{
            q.Id => new Quote__c(Id = q.Id, Quote_status__c = 'Drafted')
        };
        q.Quote_status__c = 'Denied by Customer';
        q.Unit__c = plot.Id;

        Test.startTest();
        QuoteApprovalTriggerHandler.handleAfterUpdate(new List<Quote__c>{ q }, oldMap);
        Test.stopTest();

        Plot__c updated = [SELECT Status__c FROM Plot__c WHERE Id = :plot.Id];
        System.assertEquals('Available', updated.Status__c,
            'Plot should be Available after Denied by Customer');
    }

    // Tests handleAfterUpdate when no rejection occurs (empty rejectedQuotes path)
    @isTest
    static void testHandleAfterUpdate_NoRejection() {
        Quote__c q = new Quote__c();
        insert q;

        // Old and new both 'Drafted' — no rejection
        Map<Id, Quote__c> oldMap = new Map<Id, Quote__c>{
            q.Id => new Quote__c(Id = q.Id, Quote_status__c = 'Drafted')
        };
        q.Quote_status__c = 'Drafted';

        Test.startTest();
        QuoteApprovalTriggerHandler.handleAfterUpdate(new List<Quote__c>{ q }, oldMap);
        Test.stopTest();

        System.assert(true, 'No exception expected for non-rejected quote update');
    }

    /** Covers handleAfterUpdate with rejected quote that has Unit__c == null —
     *  exercises the if(qt.Unit__c != null) false branch in updateUnitStatus,
     *  which leaves plotsToUpdate empty (no DML executed).
     */
    @isTest
    static void testHandleAfterUpdate_RejectedNoUnit() {
        Quote__c q = new Quote__c();
        insert q;

        Map<Id, Quote__c> oldMap = new Map<Id, Quote__c>{
            q.Id => new Quote__c(Id = q.Id, Quote_status__c = 'Drafted')
        };
        q.Quote_status__c = 'Rejected';
        // Unit__c stays null

        Test.startTest();
        QuoteApprovalTriggerHandler.handleAfterUpdate(new List<Quote__c>{ q }, oldMap);
        Test.stopTest();

        System.assert(true, 'Rejection with no Unit__c should not throw');
    }

    /** Covers mapManagerHierarchy when quotes have null OwnerId — ownerIds set stays empty, returns early. */
    @isTest
    static void testHandleBeforeInsert_NullOwnerId() {
        Quote__c q = new Quote__c();  // OwnerId not set (null)

        Test.startTest();
        QuoteApprovalTriggerHandler.handleBeforeInsert(new List<Quote__c>{ q });
        Test.stopTest();

        System.assertEquals(null, q.Manager__c, 'Manager should not be set when OwnerId is null');
    }

    /** Covers mapManagerHierarchy where the owner has no ManagerId — managerIds set is empty,
     *  the second SOQL for managers is skipped (line 57 false branch).
     */
    @isTest
    static void testHandleBeforeInsert_NoManager() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User soloOwner = new User(
            FirstName = 'Solo', LastName = 'Owner',
            Email = 'soloowner@testex.com',
            Username = 'soloowner' + System.currentTimeMillis() + '@testex.com',
            Alias = 'solow',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles',
            ProfileId = p.Id
            // ManagerId NOT set
        );
        insert soloOwner;

        Quote__c q = new Quote__c(OwnerId = soloOwner.Id);

        Test.startTest();
        QuoteApprovalTriggerHandler.handleBeforeInsert(new List<Quote__c>{ q });
        Test.stopTest();

        System.assertEquals(null, q.Manager__c, 'Manager should be null when owner has no ManagerId');
    }

    /** Covers handleAfterInsert with empty quote list — submitForApproval not called, updateUnitStatus called with empty list. */
    @isTest
    static void testHandleAfterInsert_EmptyList() {
        Test.startTest();
        QuoteApprovalTriggerHandler.handleAfterInsert(new List<Quote__c>());
        Test.stopTest();
        System.assert(true, 'Empty list should not throw');
    }

    // NOTE: QuoteApprovalTriggerHandler.submitForApproval lines 92-99 are unreachable in test
    // context due to the `if (Test.isRunningTest()) return;` guard at line 91.

    // ---------- Helpers for within-limit auto-approve tests ----------

    private static User createExecutiveUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Disc', LastName = 'Exec' + tag,
            Email = 'discexec' + tag + '@testex.com',
            Username = 'discexec' + tag + System.currentTimeMillis() + '@testex.com',
            Alias = ('de' + tag).left(8),
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static String pickProjectValue() {
        List<Schema.PicklistEntry> entries = Quote__c.Project__c.getDescribe().getPicklistValues();
        return entries.isEmpty() ? null : entries[0].getValue();
    }

    private static List<String> discountFieldsFromMdt() {
        List<String> fields = new List<String>();
        for (Quote_Discount_Config__mdt c : [
            SELECT Quote_Field_API__c FROM Quote_Discount_Config__mdt WHERE Active__c = true
        ]) {
            if (c.Quote_Field_API__c != null) {
                fields.add(c.Quote_Field_API__c.replace('__c', '_Discount__c'));
            }
        }
        return fields;
    }

    private static Discount_Limit__c makeLimit(Id execId, String projectVal, Decimal cap) {
        Discount_Limit__c dl = new Discount_Limit__c(
            Executive__c = execId,
            Project__c = projectVal
        );
        for (String fld : discountFieldsFromMdt()) {
            dl.put(fld, cap);
        }
        return dl;
    }

    private static Quote__c makeQuote(String projectVal, Decimal discountVal) {
        Quote__c q = new Quote__c(Project__c = projectVal);
        for (String fld : discountFieldsFromMdt()) {
            q.put(fld, discountVal);
        }
        return q;
    }

    /** All 9 discounts within the executive's caps -> Quote_status__c flips to Approved on insert. */
    @isTest
    static void testAutoApprove_AllWithinLimit() {
        User exec = createExecutiveUser('A');
        String projVal = pickProjectValue();
        System.assertNotEquals(null, projVal, 'Project picklist must have at least one value');

        System.runAs(exec) {
            insert makeLimit(exec.Id, projVal, 100);
            Quote__c q = makeQuote(projVal, 50);

            Test.startTest();
            insert q;
            Test.stopTest();

            Quote__c result = [SELECT Quote_status__c FROM Quote__c WHERE Id = :q.Id];
            System.assertEquals('Approved', result.Quote_status__c,
                'Within-limit quote should auto-approve');
        }
    }

    /** One discount exceeds the cap -> stays in normal approval path (status not Approved in tests). */
    @isTest
    static void testRouteToApproval_OneExceeds() {
        User exec = createExecutiveUser('B');
        String projVal = pickProjectValue();

        System.runAs(exec) {
            insert makeLimit(exec.Id, projVal, 100);
            Quote__c q = makeQuote(projVal, 50);
            q.Price_Per_Sq_Ft_Discount__c = 200;

            Test.startTest();
            insert q;
            Test.stopTest();

            Quote__c result = [SELECT Quote_status__c FROM Quote__c WHERE Id = :q.Id];
            System.assertNotEquals('Approved', result.Quote_status__c,
                'Quote with a discount above the cap should not auto-approve');
        }
    }

    /** No Discount_Limit__c record for this (executive, project) pair -> route to approval. */
    @isTest
    static void testRouteToApproval_NoLimitRecord() {
        User exec = createExecutiveUser('C');
        String projVal = pickProjectValue();

        System.runAs(exec) {
            // Intentionally no Discount_Limit__c inserted.
            Quote__c q = makeQuote(projVal, 50);

            Test.startTest();
            insert q;
            Test.stopTest();

            Quote__c result = [SELECT Quote_status__c FROM Quote__c WHERE Id = :q.Id];
            System.assertNotEquals('Approved', result.Quote_status__c,
                'Quote without a Discount_Limit record should not auto-approve');
        }
    }

    /** Guard: every active MDT row must have a matching '<base>_Discount__c' field on
     *  both Quote__c and Discount_Limit__c. Fails the deploy if an admin adds an MDT
     *  row without creating the matching Discount_Limit__c field (or vice-versa).
     */
    @isTest
    static void testSchemaDriftGuard() {
        Map<String, Schema.SObjectField> quoteFields =
            Schema.SObjectType.Quote__c.fields.getMap();
        Map<String, Schema.SObjectField> limitFields =
            Schema.SObjectType.Discount_Limit__c.fields.getMap();

        for (Quote_Discount_Config__mdt c : [
            SELECT MasterLabel, Quote_Field_API__c
            FROM   Quote_Discount_Config__mdt
            WHERE  Active__c = true
        ]) {
            System.assertNotEquals(null, c.Quote_Field_API__c,
                'MDT row ' + c.MasterLabel + ' has null Quote_Field_API__c');
            String discField = c.Quote_Field_API__c.replace('__c', '_Discount__c').toLowerCase();
            System.assert(quoteFields.containsKey(discField),
                'Quote__c is missing derived discount field ' + discField +
                ' for MDT row ' + c.MasterLabel);
            System.assert(limitFields.containsKey(discField),
                'Discount_Limit__c is missing matching field ' + discField +
                ' for MDT row ' + c.MasterLabel);
        }
    }
}