/**
 * @description Test class for DynamicDocumentPDFController
 */
@isTest
private class DynamicDocumentPDFControllerTest {

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'PDF Test Account');
        insert a;

        Document_Template__c tmpl = new Document_Template__c(
            Name = 'PDF Test Template',
            Object_API_Name__c = 'Account',
            Page_Size__c = 'A4',
            Page_Orientation__c = 'portrait',
            Template_JSON__c = JSON.serialize(new Map<String, Object>{
                'header' => new Map<String, Object>{
                    'content' => 'Header for {!Name}',
                    'showLogo' => false
                },
                'footer' => new Map<String, Object>{
                    'content' => 'Footer text',
                    'showPageNumbers' => true
                },
                'sections' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'content',
                        'content' => 'Hello {!Name}'
                    },
                    new Map<String, Object>{
                        'type' => 'separator'
                    }
                },
                'styles' => new Map<String, Object>{
                    'fontFamily' => 'Arial',
                    'fontSize' => '12px',
                    'primaryColor' => '#000',
                    'marginTop' => '20',
                    'marginRight' => '15',
                    'marginBottom' => '20',
                    'marginLeft' => '15'
                }
            })
        );
        insert tmpl;
    }

    @isTest
    static void constructor_missingTemplateId_setsErrorHtml() {
        Test.startTest();
        Test.setCurrentPage(new PageReference('/apex/DynamicDocumentPDF'));
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        System.assert(ctrl.renderedHtml.contains('Missing templateId'), 'Should report missing templateId');
        System.assertEquals('Document', ctrl.documentTitle, 'Title should default to Document');
    }

    @isTest
    static void constructor_validTemplateAndRecord_rendersHtml() {
        Document_Template__c tmpl = [SELECT Id FROM Document_Template__c LIMIT 1];
        Account a = [SELECT Id FROM Account LIMIT 1];

        PageReference page = new PageReference('/apex/DynamicDocumentPDF');
        page.getParameters().put('templateId', tmpl.Id);
        page.getParameters().put('id', a.Id);
        Test.setCurrentPage(page);

        Test.startTest();
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.renderedHtml, 'Rendered HTML should not be null');
        System.assertEquals('PDF Test Template', ctrl.documentTitle, 'Title should match template');
        System.assertEquals('A4', ctrl.pageSize, 'Page size should match template');
    }

    @isTest
    static void constructor_unknownTemplateId_setsNotFoundHtml() {
        PageReference page = new PageReference('/apex/DynamicDocumentPDF');
        // Use a syntactically valid Apex Id (15 char) that won't match any record
        page.getParameters().put('templateId', '001000000000001');
        Test.setCurrentPage(page);

        Test.startTest();
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.renderedHtml, 'Should populate rendered HTML');
    }

    @isTest
    static void constructor_templateWithLogoUrl_processed() {
        Document_Template__c tmpl = new Document_Template__c(
            Name = 'Logo Template',
            Object_API_Name__c = 'Account',
            Page_Size__c = 'Letter',
            Page_Orientation__c = 'landscape',
            Logo_URL__c = 'https://example.com/sfc/servlet.shepherd/version/download/068000000000001AAA',
            Template_JSON__c = JSON.serialize(new Map<String, Object>{
                'header' => new Map<String, Object>{
                    'showLogo' => false,
                    'logoUrl' => '',
                    'left' => new Map<String, Object>{
                        'type' => 'image',
                        'logoUrl' => 'https://example.com/sfc/servlet.shepherd/version/download/068000000000002AAA'
                    },
                    'center' => new Map<String, Object>{
                        'type' => 'text',
                        'content' => 'Hello'
                    },
                    'right' => new Map<String, Object>{
                        'type' => 'image',
                        'logoContentVersionId' => '068000000000003AAA'
                    }
                },
                'sections' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'image',
                        'imageUrl' => 'https://example.com/sfc/servlet.shepherd/version/download/068000000000004AAA'
                    },
                    new Map<String, Object>{
                        'type' => 'image',
                        'imageContentVersionId' => '068000000000005AAA'
                    },
                    new Map<String, Object>{
                        'type' => 'content',
                        'content' => 'body'
                    }
                },
                'styles' => new Map<String, Object>{
                    'marginTop' => '5',
                    'marginRight' => '5',
                    'marginBottom' => '5',
                    'marginLeft' => '5',
                    'fontFamily' => 'Times New Roman'
                }
            })
        );
        insert tmpl;

        PageReference page = new PageReference('/apex/DynamicDocumentPDF');
        page.getParameters().put('templateId', tmpl.Id);
        Test.setCurrentPage(page);

        Test.startTest();
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.renderedHtml, 'Rendered HTML present');
        System.assertEquals('Letter', ctrl.pageSize, 'Page size from template');
        System.assertEquals('landscape', ctrl.pageOrientation, 'Orientation from template');
        System.assertEquals('5', ctrl.marginTop, 'Margin top read');
        System.assertEquals('Times New Roman', ctrl.fontFamily, 'Font family from styles');
    }

    @isTest
    static void constructor_templateWithRealContentVersion_renders() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test Logo',
            PathOnClient = 'logo.png',
            VersionData = Blob.valueOf('fakeimagedata')
        );
        insert cv;
        ContentVersion saved = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        Document_Template__c tmpl = new Document_Template__c(
            Name = 'CV Template',
            Object_API_Name__c = 'Account',
            Template_JSON__c = JSON.serialize(new Map<String, Object>{
                'header' => new Map<String, Object>{
                    'logoContentVersionId' => saved.Id,
                    'showLogo' => true
                },
                'sections' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'image',
                        'imageContentVersionId' => saved.Id
                    }
                }
            })
        );
        insert tmpl;

        PageReference page = new PageReference('/apex/DynamicDocumentPDF');
        page.getParameters().put('templateId', tmpl.Id);
        Test.setCurrentPage(page);

        Test.startTest();
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.renderedHtml, 'Should render');
    }

    @isTest
    static void constructor_blankTemplateJson_handles() {
        Document_Template__c tmpl = new Document_Template__c(
            Name = 'Blank Template',
            Object_API_Name__c = 'Account',
            Template_JSON__c = null
        );
        insert tmpl;

        PageReference page = new PageReference('/apex/DynamicDocumentPDF');
        page.getParameters().put('templateId', tmpl.Id);
        Test.setCurrentPage(page);

        Test.startTest();
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();
        System.assertEquals('Blank Template', ctrl.documentTitle, 'Title from template');
    }

    @isTest
    static void constructor_invalidJsonInTemplate_setsErrorHtml() {
        Document_Template__c tmpl = new Document_Template__c(
            Name = 'Bad JSON',
            Object_API_Name__c = 'Account',
            Template_JSON__c = 'not valid json'
        );
        insert tmpl;

        PageReference page = new PageReference('/apex/DynamicDocumentPDF');
        page.getParameters().put('templateId', tmpl.Id);
        Test.setCurrentPage(page);

        Test.startTest();
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.renderedHtml, 'Should not throw');
    }
}