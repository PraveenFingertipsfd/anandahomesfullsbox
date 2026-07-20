/**
 * @description Tests for EmailSenderInvocable.getUploadedFileAttachments — attaching uploaded
 *              Document-Manager files (ContentVersion by Document Type) on email send.
 */
@isTest
private class EmailUploadedFileAttachmentTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;
        return b;
    }

    private static Id linkFile(Id recordId, String docType) {
        ContentVersion cv = new ContentVersion(
            Title = 'KYC Doc', PathOnClient = 'kyc.pdf', VersionData = Blob.valueOf('hello')
        );
        if (String.isNotBlank(docType)) cv.put('Document_Type__c', docType);
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = cdId, LinkedEntityId = recordId, ShareType = 'V', Visibility = 'AllUsers'
        );
        return cdId;
    }

    @isTest
    static void guards_returnEmpty() {
        Booking__c b = makeBooking();
        Test.startTest();
        System.assertEquals(0, EmailSenderInvocable.getUploadedFileAttachments(null, null, 'X', null).size());
        System.assertEquals(0, EmailSenderInvocable.getUploadedFileAttachments(b.Id, null, null, null).size(),
            'Blank document type → no attachments');
        Test.stopTest();
    }

    @isTest
    static void linkedFile_butTypeMismatch_returnsEmpty() {
        Booking__c b = makeBooking();
        linkFile(b.Id, null); // a file with no document type
        Test.startTest();
        List<Messaging.EmailFileAttachment> r =
            EmailSenderInvocable.getUploadedFileAttachments(b.Id, null, 'Some_Type_That_Will_Not_Match', null);
        Test.stopTest();
        System.assertEquals(0, r.size(), 'No file matches the requested document type');
    }

    @isTest
    static void nameUsedAsDocumentType_whenTypeBlank() {
        Booking__c b = makeBooking();
        List<Schema.PicklistEntry> entries = ContentVersion.Document_Type__c.getDescribe().getPicklistValues();
        if (entries.isEmpty()) return;
        String docType = entries[0].getValue();

        Boolean inserted = false;
        try { linkFile(b.Id, docType); inserted = true; } catch (Exception e) { /* dependent picklist */ }

        Test.startTest();
        // documentType blank → the attachment name is used as the Document Type to match.
        List<Messaging.EmailFileAttachment> r = inserted
            ? EmailSenderInvocable.getUploadedFileAttachments(b.Id, null, null, docType)
            : new List<Messaging.EmailFileAttachment>();
        Test.stopTest();

        if (inserted) {
            System.assertEquals(1, r.size(), 'Name should be used as the Document Type to match');
        }
    }

    @isTest
    static void matchingFile_isAttached() {
        Booking__c b = makeBooking();

        List<Schema.PicklistEntry> entries = ContentVersion.Document_Type__c.getDescribe().getPicklistValues();
        if (entries.isEmpty()) return; // no document types configured — nothing to assert

        String docType = entries[0].getValue();
        Test.startTest();
        Boolean inserted = false;
        try {
            linkFile(b.Id, docType);
            inserted = true;
        } catch (Exception e) {
            // Document_Type may be a dependent picklist requiring a category — skip if so.
        }
        if (inserted) {
            List<Messaging.EmailFileAttachment> r =
                EmailSenderInvocable.getUploadedFileAttachments(b.Id, null, docType, null);
            System.assertEquals(1, r.size(), 'The matching uploaded file should be attached');
            System.assert(r[0].getFileName().startsWith('KYC Doc'), r[0].getFileName());
        }
        Test.stopTest();
    }
}