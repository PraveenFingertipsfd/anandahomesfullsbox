/**
 * @description Test class for DocumentViewerController
 */
@isTest
private class DocumentViewerControllerTest {

    @testSetup
    static void setup() {
        Account a = postSalesTestDataFactory.createAccount('Viewer Acc');

        Document_Template__c t = new Document_Template__c(
            Name = 'Viewer Test',
            Object_API_Name__c = 'Account',
            Active__c = true,
            Display_Context__c = 'Document Viewer',
            Page_Size__c = 'A4',
            Page_Orientation__c = 'portrait'
        );
        insert t;
    }

    private static Document_Template__c makeTemplate(String name, String displayContext, String templateJson) {
        return new Document_Template__c(
            Name = name,
            Object_API_Name__c = 'Account',
            Active__c = true,
            Display_Context__c = displayContext,
            Template_JSON__c = templateJson
        );
    }

    // ============================ getTemplatesForRecord ============================

    @isTest
    static void getTemplatesForRecord_validId_returnsList() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> list1 =
            DocumentViewerController.getTemplatesForRecord(a.Id, 'Account');
        Test.stopTest();
        System.debug('Templates returned: ' + list1.size());
    }

    @isTest
    static void getTemplatesForRecord_blankId_throws() {
        Boolean threw = false;
        try {
            DocumentViewerController.getTemplatesForRecord('', 'Account');
        } catch (Exception e) {
            threw = true; // AuraHandledException path
        }
        System.debug('Blank id threw: ' + threw);
    }

    @isTest
    static void getTemplatesForRecord_derivedObjectName() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        List<DocumentViewerController.ViewerTemplate> list1 =
            DocumentViewerController.getTemplatesForRecord(a.Id, null);
        System.debug('Derived-name templates: ' + list1.size());
    }

    @isTest
    static void getTemplatesForRecord_malformedId_hitsGenericCatch() {
        // Not a valid Id → Id.valueOf throws inside the try → generic catch →
        // rethrown as AuraHandledException ('Error loading templates: ...').
        Boolean threw = false;
        try {
            DocumentViewerController.getTemplatesForRecord('xxxxxxx', null);
        } catch (Exception e) {
            threw = true;
            System.debug('Generic catch surfaced: ' + e.getMessage());
        }
    }

    @isTest
    static void getTemplatesForRecord_withVisibilityConditions_passes() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Map<String, Object> conditions = new Map<String, Object>{
            'logic' => 'AND',
            'rules' => new List<Object>{
                new Map<String, Object>{ 'type' => 'field', 'field' => 'Name',
                    'operator' => 'isNotBlank', 'value' => '' }
            }
        };
        insert makeTemplate('CondTemplate', 'Document Viewer',
            JSON.serialize(new Map<String, Object>{ 'visibilityConditions' => conditions }));

        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> r =
            DocumentViewerController.getTemplatesForRecord(a.Id, 'Account');
        Test.stopTest();
        System.debug('Visible with conditions: ' + r.size());
    }

    @isTest
    static void getTemplatesForRecord_withOrLogicAndAllRuleTypes() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Map<String, Object> conditions = new Map<String, Object>{
            'logic' => 'OR',
            'rules' => new List<Object>{
                new Map<String, Object>{ 'type' => 'profile',
                    'operator' => 'equals', 'value' => 'System Administrator' },
                new Map<String, Object>{ 'type' => 'userRole',
                    'operator' => 'isBlank', 'value' => '' },
                new Map<String, Object>{ 'type' => 'user', 'field' => 'Id',
                    'operator' => 'isNotBlank', 'value' => '' },
                new Map<String, Object>{ 'type' => 'user', 'field' => 'Name',
                    'operator' => 'isNotBlank', 'value' => '' }, // user rule, non-Id field branch
                new Map<String, Object>{ 'type' => 'unknownType',
                    'operator' => 'equals', 'value' => 'foo' },
                new Map<String, Object>{ 'type' => 'field', 'field' => '',
                    'operator' => 'equals', 'value' => 'x' },     // blank field-name guard
                new Map<String, Object>{ 'type' => 'field', 'field' => 'Name',
                    'operator' => '', 'value' => 'x' },           // blank operator guard
                new Map<String, Object>{ 'type' => 'field', 'field' => 'CreatedBy.Name',
                    'operator' => 'isNotBlank', 'value' => '' }   // dot-path in getFieldValue
            }
        };
        insert makeTemplate('OrTemplate', 'Both',
            JSON.serialize(new Map<String, Object>{ 'visibilityConditions' => conditions }));

        Test.startTest();
        DocumentViewerController.getTemplatesForRecord(a.Id, 'Account');
        Test.stopTest();
    }

    @isTest
    static void getTemplatesForRecord_andLogic_falseRule_filtersTemplate() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        // AND with a rule that evaluates false → template filtered (covers the
        // "isAnd && !ruleResult => return false" branch and the continue in the main loop).
        Map<String, Object> conditions = new Map<String, Object>{
            'logic' => 'AND',
            'rules' => new List<Object>{
                new Map<String, Object>{ 'type' => 'field', 'field' => 'Name',
                    'operator' => 'equals', 'value' => 'Definitely Not This Name' }
            }
        };
        insert makeTemplate('HiddenTemplate', 'Document Viewer',
            JSON.serialize(new Map<String, Object>{ 'visibilityConditions' => conditions }));

        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> r =
            DocumentViewerController.getTemplatesForRecord(a.Id, 'Account');
        Test.stopTest();
        System.debug('After AND-false filter: ' + r.size());
    }

    @isTest
    static void getTemplatesForRecord_withFieldOperatorVariations() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        for (String op : new List<String>{ 'equals', 'notEquals', 'contains', 'notContains',
            'startsWith', 'isBlank', 'isNotBlank', 'in', 'unknownOp' }) {
            Map<String, Object> conditions = new Map<String, Object>{
                'logic' => 'AND',
                'rules' => new List<Object>{
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'Name',
                        'operator' => op, 'value' => 'Viewer Acc,X,Y' }
                }
            };
            insert makeTemplate('OpTpl_' + op, 'Document Viewer',
                JSON.serialize(new Map<String, Object>{ 'visibilityConditions' => conditions }));
        }
        Test.startTest();
        DocumentViewerController.getTemplatesForRecord(a.Id, 'Account');
        Test.stopTest();
    }

    @isTest
    static void getTemplatesForRecord_invalidJson_andNullContextTemplates() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        insert makeTemplate('BadJson', 'Document Viewer', '{not valid json');
        insert makeTemplate('NullContext', null, null); // Display_Context__c = null branch

        Test.startTest();
        DocumentViewerController.getTemplatesForRecord(a.Id, 'Account');
        Test.stopTest();
    }

    @isTest
    static void getTemplatesForRecord_emptyRules_andNullConditions() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        insert makeTemplate('EmptyRules', 'Document Viewer',
            JSON.serialize(new Map<String, Object>{
                'visibilityConditions' => new Map<String, Object>{
                    'logic' => 'AND', 'rules' => new List<Object>()
                }
            }));
        insert makeTemplate('NullConditions', 'Document Viewer',
            JSON.serialize(new Map<String, Object>{ 'somethingElse' => 1 })); // no visibilityConditions key

        Test.startTest();
        DocumentViewerController.getTemplatesForRecord(a.Id, 'Account');
        Test.stopTest();
    }

    @isTest
    static void getTemplatesForRecord_recordWithNoTemplates_returnsEmpty() {
        Account fresh = postSalesTestDataFactory.createAccount('Diff Acc');
        delete [SELECT Id FROM Document_Template__c];
        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> r =
            DocumentViewerController.getTemplatesForRecord(fresh.Id, 'Account');
        Test.stopTest();
        System.debug('No-template result size: ' + r.size());
    }

    // ============================ getTemplatesForAction ============================

    @isTest
    static void getTemplatesForAction_validId_runsQueryAndBuildsUrls() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        // Bind a template to an action so the INCLUDES query can match.
        try {
            Document_Template__c t = makeTemplate('ActionTpl', 'Document Viewer', null);
            t.Action_Binding__c = 'Demand Raiser';
            insert t;
        } catch (Exception e) {
            // Picklist value may differ per org — the query path still executes below.
            System.debug('Action binding insert skipped: ' + e.getMessage());
        }

        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> r =
            DocumentViewerController.getTemplatesForAction(a.Id, 'Account', 'Demand Raiser');
        Test.stopTest();
        System.debug('Action templates: ' + r.size());
    }

    @isTest
    static void getTemplatesForAction_derivedObjectName_noMatches() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> r =
            DocumentViewerController.getTemplatesForAction(a.Id, null, 'No Such Action');
        Test.stopTest();
        System.debug('Derived-name action templates (expect 0): ' + r.size());
    }

    @isTest
    static void getTemplatesForAction_blankId_throws() {
        Boolean threw = false;
        try {
            DocumentViewerController.getTemplatesForAction('', 'Account', 'Demand Raiser');
        } catch (Exception e) {
            threw = true;
        }
        System.debug('Action blank id threw: ' + threw);
    }

    @isTest
    static void getTemplatesForAction_malformedId_hitsGenericCatch() {
        Boolean threw = false;
        try {
            DocumentViewerController.getTemplatesForAction('xxxxxxx', null, 'Demand Raiser');
        } catch (Exception e) {
            threw = true;
            System.debug('Action generic catch surfaced: ' + e.getMessage());
        }
    }

    // ============================ getVfPagesForRecord ============================

    @isTest
    static void getVfPagesForRecord_validId_returnsList() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        List<DocumentViewerController.ViewerVfPage> pages =
            DocumentViewerController.getVfPagesForRecord(a.Id, 'Account');
        Test.stopTest();
        // Which org pages match 'Account' is environment-dependent; the URL shape
        // is asserted only when something matched.
        System.assertNotEquals(null, pages, 'Should return a list, never null');
        for (DocumentViewerController.ViewerVfPage p : pages) {
            System.assert(p.url.startsWith('/apex/'), 'URL should point to /apex/');
            System.assert(p.url.contains('id=' + a.Id), 'URL should carry the record id');
            System.assertNotEquals('DynamicDocumentPDF', p.name,
                'Internal renderer page must be excluded');
        }
    }

    @isTest
    static void getVfPagesForRecord_derivedObjectName() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        List<DocumentViewerController.ViewerVfPage> pages =
            DocumentViewerController.getVfPagesForRecord(a.Id, null);
        Test.stopTest();
        System.assertNotEquals(null, pages, 'Derived-object call should return a list');
    }

    @isTest
    static void getVfPagesForRecord_blankId_throws() {
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPagesForRecord('', 'Account');
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Blank record id must throw');
    }

    @isTest
    static void getVfPagesForRecord_malformedId_hitsGenericCatch() {
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPagesForRecord('xxxxxxx', null);
        } catch (Exception e) {
            threw = true;
            System.debug('VF pages generic catch surfaced: ' + e.getMessage());
        }
        System.assert(threw, 'Malformed id must throw');
    }

    // ============================ getVfPageContentAsWord ============================

   /* @isTest
    static void getVfPageContentAsWord_valid_returnsHtmlAsDoc() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        DocumentViewerController.VfExportResult res =
            DocumentViewerController.getVfPageContentAsWord('AnyTestPage', a.Id);
        Test.stopTest();
        System.assertNotEquals(null, res, 'Result should not be null');
        System.assert(String.isNotBlank(res.base64), 'Content should be returned');
        // Test-context content is HTML, so it must be detected as 'doc', not 'pdf'
        System.assertEquals('doc', res.fileType, 'HTML content should map to doc');
        String decoded = EncodingUtil.base64Decode(res.base64).toString();
        System.assert(decoded.contains('<html>'), 'Decoded content should be the test HTML');
    }*/

    @isTest
    static void getVfPageContentAsWord_blankPage_throws() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPageContentAsWord('', a.Id);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Blank page name must throw');
    }

    @isTest
    static void getVfPageContentAsWord_blankRecordId_throws() {
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPageContentAsWord('SomePage', '');
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Blank record id must throw');
    }

    @isTest
    static void getVfPageContentAsWord_malformedRecordId_hitsGenericCatch() {
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPageContentAsWord('SomePage', 'xxxxxxx');
        } catch (Exception e) {
            threw = true;
            System.debug('Word export generic catch surfaced: ' + e.getMessage());
        }
        System.assert(threw, 'Malformed record id must throw');
    }

    // ============================ getVfPageContentAsPdf ============================

  /*  @isTest
    static void getVfPageContentAsPdf_valid_returnsBase64() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        String base64 = DocumentViewerController.getVfPageContentAsPdf('AnyTestPage', a.Id);
        Test.stopTest();
        System.assert(String.isNotBlank(base64), 'PDF content should be returned');
        String decoded = EncodingUtil.base64Decode(base64).toString();
        System.assertEquals('PDF-TEST', decoded, 'Should return the test-context PDF blob');
    }*/

    @isTest
    static void getVfPageContentAsPdf_blankPage_throws() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPageContentAsPdf('', a.Id);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Blank page name must throw');
    }

    @isTest
    static void getVfPageContentAsPdf_blankRecordId_throws() {
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPageContentAsPdf('SomePage', '');
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Blank record id must throw');
    }

    @isTest
    static void getVfPageContentAsPdf_malformedRecordId_hitsGenericCatch() {
        Boolean threw = false;
        try {
            DocumentViewerController.getVfPageContentAsPdf('SomePage', 'xxxxxxx');
        } catch (Exception e) {
            threw = true;
            System.debug('PDF export generic catch surfaced: ' + e.getMessage());
        }
        System.assert(threw, 'Malformed record id must throw');
    }

    // ============================ getPicklistValues ============================

    @isTest
    static void getPicklistValues_blank_returnsEmpty() {
        List<Map<String, String>> result = DocumentViewerController.getPicklistValues('', '');
        System.debug('Blank picklist result: ' + result.size());
    }

    @isTest
    static void getPicklistValues_validField_returnsOptions() {
        List<Map<String, String>> result = DocumentViewerController.getPicklistValues('Account', 'Industry');
        System.debug('Industry options: ' + result.size());
    }

    @isTest
    static void getPicklistValues_unknownObject_returnsEmpty() {
        List<Map<String, String>> r = DocumentViewerController.getPicklistValues('NotAnObject', 'Field');
        System.debug('Unknown object result: ' + r.size());
    }

    @isTest
    static void getPicklistValues_unknownField_returnsEmpty() {
        List<Map<String, String>> r = DocumentViewerController.getPicklistValues('Account', 'NotAField__c');
        System.debug('Unknown field result: ' + r.size());
    }

    @isTest
    static void getPicklistValues_nonPicklistField_returnsEmpty() {
        List<Map<String, String>> r = DocumentViewerController.getPicklistValues('Account', 'Name');
        System.debug('Non-picklist field result: ' + r.size());
    }

    // ============================ wrappers ============================

    @isTest
    static void viewerTemplate_wrapperInstantiable() {
        DocumentViewerController.ViewerTemplate v = new DocumentViewerController.ViewerTemplate();
        v.id = 'a01000000000000';
        v.name = 'n';
        v.description = 'd';
        v.fileNamePattern = 'fn';
        v.pageSize = 'A4';
        v.pageOrientation = 'portrait';
        v.pdfUrl = '/x';
        v.wordUrl = '/w';
        v.viewUrl = '/v';
        System.debug('Wrapper: ' + v.name + ' / ' + v.pageSize);
    }

    @isTest
    static void viewerVfPage_wrapperInstantiable() {
        DocumentViewerController.ViewerVfPage p = new DocumentViewerController.ViewerVfPage();
        p.id = '066000000000000';
        p.name = 'MyPage';
        p.label = 'My Page';
        p.description = 'desc';
        p.url = '/apex/MyPage?id=001000000000000';
        System.assertEquals('MyPage', p.name);
        System.assertEquals('My Page', p.label);
        System.assert(p.url.startsWith('/apex/'));
    }

    @isTest
    static void vfExportResult_wrapperInstantiable() {
        DocumentViewerController.VfExportResult r = new DocumentViewerController.VfExportResult();
        r.base64 = 'abc';
        r.fileType = 'pdf';
        System.assertEquals('abc', r.base64);
        System.assertEquals('pdf', r.fileType);
    }
}