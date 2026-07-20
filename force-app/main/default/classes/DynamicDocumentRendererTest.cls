/**
 * @description Test class for DynamicDocumentRenderer
 */
@isTest
private class DynamicDocumentRendererTest {

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'Renderer Test Account');
        insert a;
    }

    @isTest
    static void renderDocument_blankTemplate_returnsEmpty() {
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument('', null, null);
        Test.stopTest();
        System.assertEquals('', html, 'Blank template should produce empty string');
    }

    @isTest
    static void renderDocument_simpleTemplate_rendersSections() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'content' => 'Header for {!Name}',
                'showLogo' => false
            },
            'footer' => new Map<String, Object>{
                'content' => 'Footer',
                'showPageNumbers' => true,
                'pageNumberPosition' => 'right'
            },
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content',  'content' => 'Hello {!Name}' },
                new Map<String, Object>{ 'type' => 'heading',  'content' => 'My Heading', 'level' => '2' },
                new Map<String, Object>{ 'type' => 'separator' },
                new Map<String, Object>{ 'type' => 'pageBreak' },
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'gridColumns' => 2,
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'Name' }
                    }
                }
            },
            'styles' => new Map<String, Object>{
                'fontFamily' => 'Arial',
                'fontSize' => '12px'
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();

        System.assert(html.contains('Hello'), 'Content should be rendered');
        System.assert(html.contains('My Heading'), 'Heading should be rendered');
    }

    @isTest
    static void renderDocument_threeColumnHeader_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'left'   => new Map<String, Object>{ 'type' => 'text',  'content' => 'Left' },
                'center' => new Map<String, Object>{ 'type' => 'text',  'content' => 'Center' },
                'right'  => new Map<String, Object>{ 'type' => 'image', 'logoUrl' => 'http://example.com/logo.png' }
            },
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'image',
                    'imageUrl' => 'http://example.com/section.png',
                    'imageCaption' => 'Caption'
                }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();

        System.assert(html.contains('Left'), 'Left col should render');
        System.assert(html.contains('Center'), 'Center col should render');
    }

    @isTest
    static void renderDocument_tableSection_missingConfig_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'table' }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();

        System.assert(html.contains('missing configuration'), 'Should warn on missing config');
    }

    @isTest
    static void renderDocument_legacyHeaderWithLogo_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'content' => 'Hi',
                'showLogo' => true,
                'logoUrl' => 'http://example.com/x.png',
                'logoPosition' => 'right',
                'fontSize' => '14px',
                'bold' => true,
                'textColor' => '#000'
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('img'), 'Should include image tag');
    }

    @isTest
    static void renderDocument_legacyHeaderWithLogoCenter_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'showLogo' => true,
                'logoUrl' => 'http://example.com/x.png',
                'logoPosition' => 'center'
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('center'), 'Should center logo');
    }

    @isTest
    static void renderDocument_tableSection_withRows_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        // Create child contacts
        Contact c1 = new Contact(LastName = 'C1', AccountId = a.Id);
        Contact c2 = new Contact(LastName = 'C2', AccountId = a.Id);
        insert new List<Contact>{c1, c2};

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'table',
                    'title' => 'Contacts',
                    'childObject' => 'Contact',
                    'relationshipField' => 'AccountId',
                    'columns' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'LastName' }
                    },
                    'orderBy' => 'LastName',
                    'maxRows' => 50,
                    'showRowNumbers' => true,
                    'alternateRowColors' => true,
                    'alternateRowBackground' => '#eee'
                }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('Contacts'), 'Title should be rendered');
        System.assert(html.contains('C1') || html.contains('C2'), 'Children should render');
    }

    @isTest
    static void renderDocument_tableSection_noRecords_rendersEmpty() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'table',
                    'childObject' => 'Contact',
                    'relationshipField' => 'AccountId',
                    'columns' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'LastName' }
                    }
                }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('No records found'), 'Should render no records msg');
    }

    @isTest
    static void renderDocument_imageSectionWithCaption_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'image',
                    'imageUrl' => 'http://x.com/img.png',
                    'imageCaption' => 'My {!Name}'
                }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('img'), 'Should render image');
        System.assert(html.contains('font-style:italic'), 'Caption styled italic');
    }

    @isTest
    static void renderDocument_imageSection_blankUrl_skips() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'image', 'imageUrl' => '' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assertNotEquals(null, html);
    }

    @isTest
    static void renderDocument_fieldGridOddCount_closesRow() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'columns' => 2,
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'Name' },
                        new Map<String, Object>{ 'label' => 'Id', 'field' => 'Id' },
                        new Map<String, Object>{ 'label' => 'X', 'field' => 'Name' }
                    }
                }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('colspan'), 'Should close odd row with colspan');
    }

    @isTest
    static void renderDocument_unknownSectionType_returnsEmpty() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'unknownType' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assertNotEquals(null, html, 'Unknown type should not break');
    }

    @isTest
    static void renderDocument_mergeFieldsResolveTodayNow() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'Today: {!TODAY} Now: {!NOW}' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(!html.contains('{!TODAY}'), 'TODAY token replaced');
        System.assert(!html.contains('{!NOW}'), 'NOW token replaced');
    }

    @isTest
    static void renderDocument_blankRecordId_renders() {
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'Static text' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, null, 'Account');
        Test.stopTest();
        System.assert(html.contains('Static text'), 'Should render static');
    }

    @isTest
    static void renderDocument_withObjectPrefixInMergeField() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'Name: {!Account.Name}' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(!html.contains('{!Account.Name}'), 'Object-prefixed merge should resolve');
    }

    @isTest
    static void renderDocument_separatorWithStyle() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'separator', 'style' => 'dashed' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('dashed'), 'Should use dashed style');
    }

    @isTest
    static void renderDocument_contentSectionWithStyles() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => 'styled',
                    'backgroundColor' => '#eee',
                    'textAlign' => 'right',
                    'fontSize' => '20px',
                    'bold' => true,
                    'textColor' => '#f00'
                }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('font-weight:bold'), 'Should be bold');
    }

    @isTest
    static void renderDocument_headerColumnTextOnly() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'left' => new Map<String, Object>{ 'type' => 'none' },
                'center' => null,
                'right' => new Map<String, Object>{ 'type' => 'text', 'content' => 'Right Side' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('Right Side'));
    }

    @isTest
    static void numberToWords_indianFormat() {
        System.assertEquals('Zero', DynamicDocumentRenderer.numberToWordsIndian(0));
        System.assertEquals('Five Hundred', DynamicDocumentRenderer.numberToWordsIndian(500));
        System.assertEquals('One Thousand', DynamicDocumentRenderer.numberToWordsIndian(1000));
        System.assertEquals('One Lakh Twenty Three Thousand Four Hundred Fifty Six',
            DynamicDocumentRenderer.numberToWordsIndian(123456));
        System.assertEquals('One Crore', DynamicDocumentRenderer.numberToWordsIndian(10000000));
        System.assertEquals('One Hundred and Fifty Paise',
            DynamicDocumentRenderer.numberToWordsIndian(100.50));
    }
}