@isTest
public class LightningFileUploadHandlerTest {
    
    @isTest
    static void testGetFiles() {
        // Create a test Project__c record
        Project__c pr1 = new Project__c(Name = 'Arto Helix', Project_Type__c = 'Residential');
        insert pr1;

        // Create a test ContentVersion
        ContentVersion contentVersion = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.pdf',
            VersionData = Blob.valueOf('Test content'),
            IsMajorVersion = true
        );
        insert contentVersion;

        // Retrieve the ContentDocument using the ContentVersion's ContentDocumentId
       ContentDocument contentDocument = [SELECT Id, Title FROM ContentDocument limit 1];

        // Link ContentDocument to the test project
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink(
            ContentDocumentId = contentDocument.id,
            LinkedEntityId = pr1.Id,
            ShareType = 'I'  // 'I' means Inferred permission
        );
        insert contentDocumentLink;
        
        List<ContentDocument> files = LightningFileUploadHandler.getFiles(pr1.Id, new List<String>{contentDocument.Id});
        System.assertNotEquals(null, files, 'File list returned');
        System.assertEquals(1, files.size(), 'One linked file found');
        System.assertEquals(contentDocument.Id, files[0].Id, 'Returned the linked document');

        LightningFileUploadHandler.deleteFile(contentDocument.Id);

        Integer remaining = [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocument.Id];
        System.assertEquals(0, remaining, 'Document deleted via handler');
    }
}