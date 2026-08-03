/**
 * @description Controller for the Document Viewer LWC.
 * Fetches active templates for a given object/record, evaluates visibility
 * conditions (field values, profile, user), and generates PDF URLs.
 * Also discovers Visualforce pages related to the record's object
 * (e.g. pages with standardController="Booking__c") for a second section.
 */
public with sharing class DocumentViewerController {

    // ============================== WRAPPERS ==============================

    public class ViewerTemplate {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String fileNamePattern { get; set; }
        @AuraEnabled public String pageSize { get; set; }
        @AuraEnabled public String pageOrientation { get; set; }
        @AuraEnabled public String pdfUrl { get; set; }
        @AuraEnabled public String wordUrl { get; set; }
        @AuraEnabled public String viewUrl { get; set; }
    }

    /** Wrapper for a related Visualforce page shown in the "VF Pages" section */
    public class ViewerVfPage {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }        // API name (with namespace if any)
        @AuraEnabled public String label { get; set; }       // MasterLabel for display
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String url { get; set; }         // /apex/PageName?id=recordId
    }

    // ============================== MAIN METHOD ==============================

    /**
     * @description Get active templates visible for the given record.
     *              Evaluates visibility conditions stored in Template_JSON__c.
     */
    @AuraEnabled
    public static List<ViewerTemplate> getTemplatesForRecord(String recordId, String objectApiName) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            if (String.isBlank(objectApiName)) {
                objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
            }

            List<Document_Template__c> templates = [
                SELECT Id, Name, Description__c, Template_JSON__c,
                       Template_Content_Document_Id__c,
                       File_Name_Pattern__c, Page_Size__c, Page_Orientation__c,
                       Matching_Criteria__c
                FROM Document_Template__c
                WHERE Object_API_Name__c = :objectApiName
                  AND Active__c = true
                  AND (Display_Context__c = 'Document Viewer' OR Display_Context__c = 'Both' OR Display_Context__c = null)
                ORDER BY Name ASC
            ];

            if (templates.isEmpty()) {
                return new List<ViewerTemplate>();
            }

            SObject record = queryRecordForConditions(recordId, objectApiName, templates);

            User currentUser = [
                SELECT Id, ProfileId, Profile.Name, UserRoleId, UserRole.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            String baseUrl = '/apex/DynamicDocumentPDF';

            List<ViewerTemplate> result = new List<ViewerTemplate>();
            for (Document_Template__c tmpl : templates) {
                if (!isTemplateVisible(tmpl, record, currentUser)) {
                    continue;
                }

                if (String.isNotBlank(tmpl.Matching_Criteria__c)) {
                    Boolean criteriaMatch = ConfigMatchingService.evaluateCriteria(
                        tmpl.Matching_Criteria__c, Id.valueOf(recordId), objectApiName
                    );
                    if (!criteriaMatch) {
                        continue;
                    }
                }

                ViewerTemplate vt = new ViewerTemplate();
                vt.id = tmpl.Id;
                vt.name = tmpl.Name;
                vt.description = tmpl.Description__c;
                vt.fileNamePattern = tmpl.File_Name_Pattern__c;
                vt.pageSize = tmpl.Page_Size__c;
                vt.pageOrientation = tmpl.Page_Orientation__c;
                vt.pdfUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId;
                vt.wordUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId + '&format=word';
                vt.viewUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId + '&format=html';
                result.add(vt);
            }

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading templates: ' + e.getMessage());
        }
    }

    // ============================== VF PAGES SECTION ==============================

    /**
     * @description Get Visualforce pages related to the record's object.
     *              A page is considered "related" when its markup uses the object as
     *              its standardController (e.g. standardController="Booking__c").
     *              NOTE: ApexPage.Markup is a long text area and cannot be filtered
     *              in SOQL, so matching is done in Apex after querying.
     * @param recordId       The record whose object drives the match (used for ?id= in URLs)
     * @param objectApiName  Optional - derived from recordId if blank
     */
    @AuraEnabled
    public static List<ViewerVfPage> getVfPagesForRecord(String recordId, String objectApiName) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            if (String.isBlank(objectApiName)) {
                objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
            }

            List<ApexPage> pages = [
                SELECT Id, Name, MasterLabel, Description, Markup, NamespacePrefix
                FROM ApexPage
                ORDER BY MasterLabel ASC
                LIMIT 1000
            ];

            String objLower = objectApiName.toLowerCase();          // booking__c
            String baseNameLower = objLower.removeEnd('__c');       // booking

            // Matches controller="SomeBookingController" / standardController=... with any spacing/quotes
            Pattern controllerAttr = Pattern.compile('(?i)controller\\s*=\\s*["\']([^"\']+)["\']');

            List<ViewerVfPage> result = new List<ViewerVfPage>();
            for (ApexPage pg : pages) {
                // Skip the internal renderer page used for the document templates
                if (pg.Name == 'DynamicDocumentPDF') continue;

                String nameLower = pg.Name.toLowerCase();
                String labelLower = pg.MasterLabel != null ? pg.MasterLabel.toLowerCase() : '';
                String markupLower = pg.Markup != null ? pg.Markup.toLowerCase() : '';

                Boolean isRelated = false;

                // 1. Markup mentions the object anywhere:
                //    standardController="Booking__c", SOQL in components, merge fields, etc.
                if (markupLower.contains(objLower)) {
                    isRelated = true;
                }

                // 2. Page name or label contains the base object name (e.g. "Booking")
                if (!isRelated && (nameLower.contains(baseNameLower) || labelLower.contains(baseNameLower))) {
                    isRelated = true;
                }

                // 3. Custom controller class name contains the base name
                //    e.g. controller="BookingAllotmentController"
                if (!isRelated && String.isNotBlank(markupLower)) {
                    Matcher m = controllerAttr.matcher(markupLower);
                    while (m.find()) {
                        if (m.group(1) != null && m.group(1).contains(baseNameLower)) {
                            isRelated = true;
                            break;
                        }
                    }
                }

                if (!isRelated) continue;

                String pageName = String.isNotBlank(pg.NamespacePrefix)
                    ? pg.NamespacePrefix + '__' + pg.Name
                    : pg.Name;

                ViewerVfPage vp = new ViewerVfPage();
                vp.id = pg.Id;
                vp.name = pageName;
                vp.label = String.isNotBlank(pg.MasterLabel) ? pg.MasterLabel : pg.Name;
                vp.description = pg.Description;
                vp.url = '/apex/' + pageName + '?id=' + recordId;
                result.add(vp);
            }

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading Visualforce pages: ' + e.getMessage());
        }
    }

    /**
     * @description Result of a VF page export: the content plus the detected
     *              file type, so the client saves it with the right extension.
     */
    public class VfExportResult {
        @AuraEnabled public String base64 { get; set; }
        @AuraEnabled public String fileType { get; set; } // 'doc' (HTML content) or 'pdf'
    }

    /**
     * @description Render a Visualforce page for the given record and return
     *              its content base64-encoded. Pages that render as HTML are
     *              downloaded as .doc (Word opens HTML-based .doc natively).
     *              Pages defined with renderAs="pdf" return PDF bytes from
     *              getContent(), which cannot be converted to Word in Apex —
     *              those are flagged as 'pdf' so the client saves a valid .pdf.
     *              A format=word parameter is passed so pages with a dynamic
     *              renderAs can opt into returning HTML for Word export.
     * @param pageName The VF page API name (including namespace prefix if any)
     * @param recordId The record id passed to the page as ?id=
     * @return VfExportResult with base64 content and detected file type
     */
    /** Shared guard: only pages the viewer lists for this record can be exported */
    private static void assertPageAllowed(String pageName, String recordId) {
        String objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
        for (ViewerVfPage vp : getVfPagesForRecord(recordId, objectApiName)) {
            if (vp.name == pageName) {
                return;
            }
        }
        throw new AuraHandledException('This page is not available for export');
    }

    /**
     * @description Render a Visualforce page as PDF for the given record and
     *              return the bytes base64-encoded. Works for every VF page:
     *              getContentAsPDF() forces PDF rendering even for pages that
     *              normally render as HTML.
     */
    @AuraEnabled
    public static String getVfPageContentAsPdf(String pageName, String recordId) {
        try {
            if (String.isBlank(pageName) || String.isBlank(recordId)) {
                throw new AuraHandledException('Page name and record ID are required');
            }
            assertPageAllowed(pageName, recordId);

            PageReference pr = new PageReference('/apex/' + pageName);
            pr.getParameters().put('id', recordId);

            Blob content;
            if (Test.isRunningTest()) {
                content = Blob.valueOf('PDF-TEST');
            } else {
                content = pr.getContentAsPDF();
            }
            return EncodingUtil.base64Encode(content);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating PDF: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static VfExportResult getVfPageContentAsWord(String pageName, String recordId) {
        try {
            if (String.isBlank(pageName) || String.isBlank(recordId)) {
                throw new AuraHandledException('Page name and record ID are required');
            }
            assertPageAllowed(pageName, recordId);

            PageReference pr = new PageReference('/apex/' + pageName);
            pr.getParameters().put('id', recordId);
            // Honored only if the page uses a dynamic renderAs that reads this
            // parameter — lets PDF pages return HTML for true Word export.
            pr.getParameters().put('format', 'word');

            Blob content;
            if (Test.isRunningTest()) {
                content = Blob.valueOf('<html><body>Test</body></html>');
            } else {
                content = pr.getContent(); // rendered output of the page
            }

            VfExportResult res = new VfExportResult();
            res.base64 = EncodingUtil.base64Encode(content);
            // '%PDF' in base64 starts with 'JVBERi' — detect renderAs="pdf" pages
            res.fileType = res.base64.startsWith('JVBERi') ? 'pdf' : 'doc';
            return res;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating file: ' + e.getMessage());
        }
    }

    /**
     * Get templates filtered by Action Binding (e.g., 'Demand Raiser').
     */
    @AuraEnabled
    public static List<ViewerTemplate> getTemplatesForAction(String recordId, String objectApiName, String actionName) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            if (String.isBlank(objectApiName)) {
                objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
            }

            List<Document_Template__c> templates = [
                SELECT Id, Name, Description__c, Template_JSON__c,
                       Template_Content_Document_Id__c,
                       File_Name_Pattern__c, Page_Size__c, Page_Orientation__c,
                       Matching_Criteria__c
                FROM Document_Template__c
                WHERE Object_API_Name__c = :objectApiName
                  AND Active__c = true
                  AND Action_Binding__c INCLUDES (:actionName)
                ORDER BY Name ASC
            ];

            if (templates.isEmpty()) {
                return new List<ViewerTemplate>();
            }

            String baseUrl = '/apex/DynamicDocumentPDF';
            List<ViewerTemplate> result = new List<ViewerTemplate>();

            for (Document_Template__c tmpl : templates) {
                if (String.isNotBlank(tmpl.Matching_Criteria__c)) {
                    Boolean criteriaMatch = ConfigMatchingService.evaluateCriteria(
                        tmpl.Matching_Criteria__c, Id.valueOf(recordId), objectApiName
                    );
                    if (!criteriaMatch) continue;
                }

                ViewerTemplate vt = new ViewerTemplate();
                vt.id = tmpl.Id;
                vt.name = tmpl.Name;
                vt.description = tmpl.Description__c;
                vt.fileNamePattern = tmpl.File_Name_Pattern__c;
                vt.pageSize = tmpl.Page_Size__c;
                vt.pageOrientation = tmpl.Page_Orientation__c;
                vt.pdfUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId;
                vt.wordUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId + '&format=word';
                vt.viewUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId + '&format=html';
                result.add(vt);
            }

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading action templates: ' + e.getMessage());
        }
    }

    // ============================== CONDITION EVALUATION ==============================

    private static Boolean isTemplateVisible(Document_Template__c tmpl, SObject record, User currentUser) {
        String jsonStr = TemplateJsonStorageService.loadTemplateJson(tmpl);
        if (String.isBlank(jsonStr)) return true;

        try {
            Map<String, Object> templateJson = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
            if (!templateJson.containsKey('visibilityConditions')) return true;

            Map<String, Object> conditions = (Map<String, Object>) templateJson.get('visibilityConditions');
            if (conditions == null) return true;

            List<Object> rules = (List<Object>) conditions.get('rules');
            if (rules == null || rules.isEmpty()) return true;

            String logic = (String) conditions.get('logic');
            if (String.isBlank(logic)) logic = 'AND';

            Boolean isAnd = logic.equalsIgnoreCase('AND');

            for (Object ruleObj : rules) {
                Map<String, Object> rule = (Map<String, Object>) ruleObj;
                Boolean ruleResult = evaluateRule(rule, record, currentUser);

                if (isAnd && !ruleResult) return false;
                if (!isAnd && ruleResult) return true;
            }

            return isAnd;
        } catch (Exception e) {
            return true;
        }
    }

    private static Boolean evaluateRule(Map<String, Object> rule, SObject record, User currentUser) {
        String ruleType = (String) rule.get('type');
        String operator = (String) rule.get('operator');
        String expectedValue = (String) rule.get('value');

        if (String.isBlank(ruleType) || String.isBlank(operator)) return true;

        String actualValue = '';

        if (ruleType == 'field') {
            String fieldName = (String) rule.get('field');
            if (String.isBlank(fieldName) || record == null) return true;
            try {
                Object val = getFieldValue(record, fieldName);
                actualValue = val != null ? String.valueOf(val) : '';
            } catch (Exception e) {
                return true;
            }
        } else if (ruleType == 'profile') {
            actualValue = currentUser.Profile?.Name != null ? currentUser.Profile.Name : '';
        } else if (ruleType == 'userRole') {
            actualValue = currentUser.UserRole?.Name != null ? currentUser.UserRole.Name : '';
        } else if (ruleType == 'user') {
            String fieldName = (String) rule.get('field');
            if (fieldName == 'Id') {
                actualValue = currentUser.Id;
            } else {
                actualValue = currentUser.Id;
            }
        } else {
            return true;
        }

        return evaluateOperator(actualValue, operator, expectedValue);
    }

    private static Boolean evaluateOperator(String actualValue, String operator, String expectedValue) {
        if (actualValue == null) actualValue = '';
        if (expectedValue == null) expectedValue = '';

        if (operator == 'equals') {
            return actualValue.equalsIgnoreCase(expectedValue);
        } else if (operator == 'notEquals') {
            return !actualValue.equalsIgnoreCase(expectedValue);
        } else if (operator == 'contains') {
            return actualValue.containsIgnoreCase(expectedValue);
        } else if (operator == 'notContains') {
            return !actualValue.containsIgnoreCase(expectedValue);
        } else if (operator == 'startsWith') {
            return actualValue.startsWithIgnoreCase(expectedValue);
        } else if (operator == 'isBlank') {
            return String.isBlank(actualValue);
        } else if (operator == 'isNotBlank') {
            return String.isNotBlank(actualValue);
        } else if (operator == 'in') {
            for (String v : expectedValue.split(',')) {
                if (actualValue.equalsIgnoreCase(v.trim())) return true;
            }
            return false;
        }

        return true;
    }

    // ============================== HELPERS ==============================

    private static SObject queryRecordForConditions(String recordId, String objectApiName,
                                                      List<Document_Template__c> templates) {
        Set<String> fieldNames = new Set<String>{'Id'};

        for (Document_Template__c tmpl : templates) {
            String jsonStr = TemplateJsonStorageService.loadTemplateJson(tmpl);
            if (String.isNotBlank(jsonStr)) {
                try {
                    Map<String, Object> templateJson = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
                    if (templateJson.containsKey('visibilityConditions')) {
                        Map<String, Object> conditions = (Map<String, Object>) templateJson.get('visibilityConditions');
                        List<Object> rules = (List<Object>) conditions.get('rules');
                        if (rules != null) {
                            for (Object ruleObj : rules) {
                                Map<String, Object> rule = (Map<String, Object>) ruleObj;
                                if (rule.get('type') == 'field') {
                                    String fieldName = (String) rule.get('field');
                                    if (String.isNotBlank(fieldName)) {
                                        fieldNames.add(String.escapeSingleQuotes(fieldName));
                                    }
                                }
                            }
                        }
                    }
                } catch (Exception e) {
                    // Skip invalid JSON
                }
            }
        }

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return null;
        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();

        Set<String> validFields = new Set<String>();
        for (String f : fieldNames) {
            String fLower = f.toLowerCase();
            if (fieldMap.containsKey(fLower) && fieldMap.get(fLower).getDescribe().isAccessible()) {
                validFields.add(f);
            }
        }

        if (validFields.isEmpty()) {
            validFields.add('Id');
        }

        String query = 'SELECT ' + String.join(new List<String>(validFields), ', ') +
                        ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                        ' WHERE Id = :recordId LIMIT 1';

        try {
            List<SObject> records = Database.query(query);
            return records.isEmpty() ? null : records[0];
        } catch (Exception e) {
            return null;
        }
    }

    private static Object getFieldValue(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) return null;
        try {
            if (fieldPath.contains('.')) {
                String relName = fieldPath.substringBefore('.');
                String remaining = fieldPath.substringAfter('.');
                SObject parent = record.getSObject(relName);
                return parent != null ? getFieldValue(parent, remaining) : null;
            }
            return record.get(fieldPath);
        } catch (Exception e) {
            return null;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(String objectApiName, String fieldApiName) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return result;

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return result;

        Schema.SObjectField field = sType.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
        if (field == null) return result;

        Schema.DescribeFieldResult dfr = field.getDescribe();
        if (dfr.getType() != Schema.DisplayType.PICKLIST && dfr.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return result;
        }

        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                result.add(new Map<String, String>{
                    'label' => pe.getLabel(),
                    'value' => pe.getValue()
                });
            }
        }
        return result;
    }
}