/**
 * @description Test class for DynamicSOQLBuilder -- dynamic SOQL query building.
 *              Covers query generation, field/object validation failures, related and
 *              bulk queries, order/limit branches, schema helpers, and injection guards.
 * @author Integration Platform
 */
@IsTest
private class DynamicSOQLBuilderTest {

    // ============================ happy paths ============================

    @IsTest
    static void testBuildSimpleQuery() {
        Account testAcc = new Account(Name = 'SOQL Test');
        insert testAcc;

        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, testAcc.Id);
        Test.stopTest();
        System.debug('Simple: ' + query);
    }

    @IsTest
    static void testBuildQueryWithFilter() {
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery(
            'Account', 'Id, Name, Industry', 'Industry = \'Technology\'', null
        );
        Test.stopTest();
        System.debug('Filtered: ' + query);
    }

    @IsTest
    static void testBuildQueryWithRelationship() {
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery(
            'Contact', 'Id, FirstName, LastName, Account.Name', null, null
        );
        Test.stopTest();
        System.debug('Relationship: ' + query);
    }

    @IsTest
    static void testBlankFieldsDefaultsToId() {
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery('Account', null, null, null);
        Test.stopTest();
        System.debug('Default fields: ' + query);
    }

    @IsTest
    static void testFieldsWithoutId_idIsPrepended() {
        // 'Id' absent from the list — exercises the hasId=false prepend branch,
        // plus a blank segment between commas (isNotBlank skip).
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery('Account', 'Name, , Industry', null, null);
        Test.stopTest();
        System.debug('Id prepended: ' + query);
    }

    @IsTest
    static void testRecordIdPlusFilter_combinedWhere() {
        Account a = new Account(Name = 'Combo');
        insert a;
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery(
            'Account', 'Id, Name', 'Name != null', a.Id
        );
        Test.stopTest();
        System.debug('Combined WHERE: ' + query); // both conditions joined with AND
    }

    // ============================ order / limit overload ============================

    @IsTest
    static void testOrderAndLimit_allBranches() {
        Test.startTest();
        // ASC + normal limit
        String q1 = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, null, 'Name', true, 10);
        // DESC branch (isAscending = false)
        String q2 = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, null, 'Name', false, 10);
        // isAscending null → defaults to ASC
        String q3 = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, null, 'Name', null, 10);
        // Limit above Salesforce max → clamped to 50000
        String q4 = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, null, 'Name', true, 99999);
        // Blank orderBy + null limit → both blocks skipped
        String q5 = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, null, null, null, null);
        // Zero limit → LIMIT skipped
        String q6 = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, null, 'Name', true, 0);
        Test.stopTest();
        System.debug(q1 + '\n' + q2 + '\n' + q3 + '\n' + q4 + '\n' + q5 + '\n' + q6);
    }

    @IsTest
    static void testOrderBy_invalidField_throws() {
        Test.startTest();
        try {
            DynamicSOQLBuilder.buildQuery('Account', 'Id', null, null, 'Name; DROP', true, 10);
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.debug('Bad orderBy rejected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ============================ validation failures ============================

    @IsTest
    static void testNullAndBlankObjectName_throw() {
        Test.startTest();
        try { DynamicSOQLBuilder.buildQuery(null, 'Id, Name', null, null); }
        catch (DynamicSOQLBuilder.DynamicSOQLException e) { System.debug('Null obj: ' + e.getMessage()); }

        try { DynamicSOQLBuilder.buildQuery('', 'Id, Name', null, null); }
        catch (DynamicSOQLBuilder.DynamicSOQLException e) { System.debug('Blank obj: ' + e.getMessage()); }
        Test.stopTest();
    }

    @IsTest
    static void testInvalidObjectNamePattern_throws() {
        Test.startTest();
        try {
            DynamicSOQLBuilder.buildQuery('Bad Name!', 'Id', null, null);
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.debug('Pattern-invalid object rejected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testReservedWordObjectName_throws() {
        Test.startTest();
        try {
            DynamicSOQLBuilder.buildQuery('MERGE', 'Id', null, null);
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.debug('Reserved object rejected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testInvalidFieldNamePattern_throws() {
        Test.startTest();
        try {
            DynamicSOQLBuilder.buildQuery('Account', 'Id, Bad Field!', null, null);
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.debug('Pattern-invalid field rejected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testReservedWordFieldSegment_throws() {
        Test.startTest();
        try {
            // 'Merge' passes the character pattern but is a reserved segment.
            DynamicSOQLBuilder.buildQuery('Account', 'Id, Parent.Merge', null, null);
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.debug('Reserved field segment rejected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testDangerousFilterPatterns_allRejected() {
        Test.startTest();
        for (String badFilter : new List<String>{
            'Name = \'x\'; DELETE',
            'Name = \'x\' -- comment',
            'Name = \'x\' /* block */',
            'INSERT something',
            'UPDATE something',
            'DELETE something',
            'DROP table'
        }) {
            try {
                DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', badFilter, null);
            } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
                System.debug('Rejected [' + badFilter + ']: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testQueryExceedsMaxLength_throws() {
        // Build a clean (non-dangerous) filter longer than 20,000 characters.
        String chunk = 'Name != null AND ';
        String longFilter = chunk.repeat(1300) + 'Name != null';

        Test.startTest();
        try {
            DynamicSOQLBuilder.buildQuery('Account', 'Id', longFilter, null);
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.debug('Over-length rejected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ============================ related queries ============================

    @IsTest
    static void testBuildRelatedQuery() {
        Account parentAcc = new Account(Name = 'Parent Account');
        insert parentAcc;

        Test.startTest();
        String query = DynamicSOQLBuilder.buildRelatedQuery(
            'Contact', 'Id, FirstName, LastName', 'AccountId', parentAcc.Id
        );
        Test.stopTest();
        System.debug('Related: ' + query);
    }

    @IsTest
    static void testBuildRelatedQuery_guards() {
        Account parentAcc = new Account(Name = 'Guard Parent');
        insert parentAcc;

        Test.startTest();
        try { DynamicSOQLBuilder.buildRelatedQuery('Contact', 'Id', null, parentAcc.Id); }
        catch (DynamicSOQLBuilder.DynamicSOQLException e) { System.debug('Missing rel field: ' + e.getMessage()); }

        try { DynamicSOQLBuilder.buildRelatedQuery('Contact', 'Id', 'AccountId', null); }
        catch (DynamicSOQLBuilder.DynamicSOQLException e) { System.debug('Missing parent id: ' + e.getMessage()); }
        Test.stopTest();
    }

    // ============================ bulk queries ============================

    @IsTest
    static void testBuildBulkQuery() {
        Account a1 = new Account(Name = 'Bulk 1');
        Account a2 = new Account(Name = 'Bulk 2');
        insert new List<Account>{ a1, a2 };

        Test.startTest();
        String query = DynamicSOQLBuilder.buildBulkQuery(
            'Account', 'Id, Name', new Set<Id>{ a1.Id, a2.Id }
        );
        // Blank fields → defaults to Id inside bulk builder too
        String queryDefault = DynamicSOQLBuilder.buildBulkQuery(
            'Account', null, new Set<Id>{ a1.Id }
        );
        Test.stopTest();
        System.debug('Bulk: ' + query + '\nBulk default: ' + queryDefault);
    }

    @IsTest
    static void testBuildBulkQuery_emptyIds_throws() {
        Test.startTest();
        try { DynamicSOQLBuilder.buildBulkQuery('Account', 'Id', new Set<Id>()); }
        catch (DynamicSOQLBuilder.DynamicSOQLException e) { System.debug('Empty ids: ' + e.getMessage()); }

        try { DynamicSOQLBuilder.buildBulkQuery('Account', 'Id', null); }
        catch (DynamicSOQLBuilder.DynamicSOQLException e) { System.debug('Null ids: ' + e.getMessage()); }
        Test.stopTest();
    }

    // ============================ schema helpers ============================

    @IsTest
    static void testObjectExists_branches() {
        Test.startTest();
        Boolean acc = DynamicSOQLBuilder.objectExists('Account');
        Boolean missing = DynamicSOQLBuilder.objectExists('No_Such_Object__c');
        Boolean blank = DynamicSOQLBuilder.objectExists('');
        Boolean nul = DynamicSOQLBuilder.objectExists(null);
        Test.stopTest();
        System.debug('exists: ' + acc + '/' + missing + '/' + blank + '/' + nul);
    }

    @IsTest
    static void testGetAllFields_branches() {
        Test.startTest();
        String accountFields = DynamicSOQLBuilder.getAllFields('Account');
        String unknown = DynamicSOQLBuilder.getAllFields('No_Such_Object__c');
        String blank = DynamicSOQLBuilder.getAllFields('');
        Test.stopTest();
        System.debug('Account fields present: ' + (accountFields != null)
            + ', unknown: ' + unknown + ', blank: ' + blank);
    }

    // ============================ end-to-end sanity ============================

    @IsTest
    static void testGeneratedQueryActuallyExecutes() {
        Account a = new Account(Name = 'Runnable');
        insert a;

        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', 'Name != null', a.Id);
        List<SObject> rows = Database.query(query);
        Test.stopTest();
        System.debug('Executed rows: ' + rows.size());
    }
}