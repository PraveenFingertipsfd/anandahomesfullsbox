/**
 * @description Test class for EmailPdfGenerator
 */
@isTest
private class EmailPdfGeneratorTest {

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'Pdf Gen Test');
        insert a;

        ContentVersion cv = new ContentVersion(
            Title = 'TestDoc',
            PathOnClient = 'TestDoc.pdf',
            VersionData = Blob.valueOf('Hello PDF')
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ContentDocumentLink link = new ContentDocumentLink(
            LinkedEntityId = a.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V'
        );
        insert link;
    }

    @isTest
    static void generatePdfFromVfPage_returnsBlob() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Blob b = EmailPdfGenerator.generatePdfFromVfPage('SomePage', a.Id, 'id');
        Test.stopTest();

        System.assertNotEquals(null, b, 'Should return a blob in test context');
    }

    @isTest
    static void generatePdfFromVfPage_blankInputs_throws() {
        Boolean threw = false;
        try {
            EmailPdfGenerator.generatePdfFromVfPage('', null, null);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Blank inputs should throw');
    }

    @isTest
    static void generatePdfAttachment_returnsAttachment() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Messaging.EmailFileAttachment att = EmailPdfGenerator.generatePdfAttachment(
            'SomePage', a.Id, 'doc.pdf', 'id'
        );
        Test.stopTest();

        System.assertNotEquals(null, att, 'Attachment should be created');
        System.assertEquals('doc.pdf', att.getFileName(), 'Filename should be set');
    }

    @isTest
    static void generatePdfAttachment_withExtraParams_returnsAttachment() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Messaging.EmailFileAttachment att = EmailPdfGenerator.generatePdfAttachment(
            'SomePage', a.Id, 'doc.pdf', 'id',
            new Map<String, String>{ 'templateId' => '001000000000001' }
        );
        Test.stopTest();

        System.assertNotEquals(null, att, 'Attachment should be created');
    }

    @isTest
    static void getStaticDocumentAttachment_contentDocument_returnsAttachment() {
        ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion LIMIT 1];

        Test.startTest();
        Messaging.EmailFileAttachment att = EmailPdfGenerator.getStaticDocumentAttachment(cv.ContentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, att, 'Should produce a content document attachment');
    }

    @isTest
    static void getRelatedFilesAttachments_returnsList() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<Messaging.EmailFileAttachment> atts = EmailPdfGenerator.getRelatedFilesAttachments(a.Id);
        Test.stopTest();

        System.assertNotEquals(null, atts, 'Should return non-null list');
    }

    @isTest
    static void getAttachmentInfoList_parsesConfig() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        String configJson = JSON.serialize(new Map<String, Object>{
            'attachments' => new List<Object>{
                new Map<String, Object>{
                    'id' => '1',
                    'name' => 'Test',
                    'type' => 'VFPage',
                    'isRequired' => true,
                    'isDefaultChecked' => true,
                    'vfPageName' => 'MyPage',
                    'vfPageParam' => 'id',
                    'fileNamePattern' => 'File_{!Name}.pdf'
                },
                new Map<String, Object>{
                    'id' => '2',
                    'name' => 'StaticTest',
                    'type' => 'StaticDocument',
                    'documentId' => '069000000000001'
                }
            }
        });

        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> infos =
            EmailPdfGenerator.getAttachmentInfoList(configJson, a.Id, 'Account');
        Test.stopTest();

        System.assertEquals(2, infos.size(), 'Should parse two attachments');
    }
}