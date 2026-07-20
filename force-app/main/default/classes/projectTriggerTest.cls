@isTest
public class projectTriggerTest {
 @TestSetup
    static void setupTestData() {
        // Create a Booking record
        Project__c pr = new  Project__c();
        pr.Name = 'Aarya';
        pr.Project_Type__c='Residential';
        insert pr;
        Booking__c ld1 = new Booking__c();
        ld1.Followup_Date__c = system.today();
        ld1.Followup_Subject__c = 'test22';
        ld1.Last_Comment__c = 'test22';
        //ld1.Project__c = 'The Legacey';
        ld1.Payment_Type__c = 'Custom';
        ld1.Sale_Agreement_Completed__c = false;
        ld1.Sub_Stages__c = 'Submitted For Approval';
        ld1.Demand_Number__c = '12345'; 
        ld1.Property_Type__c = 'Apartment';
        ld1.Project1__c = pr.Id; 
        ld1.Date_of_Booking__c = System.today(); 
        ld1.Mode_Of_Payment__c = 'Credit Card';
        ld1.Funding_Type__c = 'Self';

        
        insert ld1;
        
             Payment_Schedule__c paymentSchedule1 = new Payment_Schedule__c(
           // Name = 'Payment Schedule 1',
            Amount__c = 1000.0,
            Booking__c = ld1.Id,
            Interest_Percent__c = 0.0
        );
        insert paymentSchedule1;
        
        pr.Interest_Percentage__c=5;
        update pr;
        

        Project__c pr1 = new  Project__c();
        pr1.Name = 'The Legacey';
        pr1.Project_Type__c='Residential';
        insert pr1;
        
        Block__c blk = new Block__c();
        blk.Name='A';
        blk.Project__c=pr.id;
        insert blk;
        
        Block__c blk1 = new Block__c();
        blk1.Name='B';
        blk1.Project__c=pr.id;
        insert blk1;
        
        Block__c blk2 = new Block__c();
        blk2.Name='A';
        blk2.Project__c=pr1.id;
        insert blk2;
        
        Block__c blk3 = new Block__c();
        blk3.Name='B';
        blk3.Project__c=pr1.id;
        insert blk3;
        
        Block__c blk4 = new Block__c();
        blk4.Name='C';
        blk4.Project__c=pr1.id;
        insert blk4;
        
         Plot__c pl = new Plot__c();
        pl.Name = '101';
        pl.Status__c = 'Available';
        pl.Project__c = pr.Id;
        pl.Block__c = 'A4';
        pl.Plot_Type__c = 'Residential';
        pl.Block1__c = blk1.Id;
        pl.Carpet_Area__c = 850;
        pl.Balcony_Sq_mts__c = 20;
        pl.Balcony_Area__c = 100;
        pl.BHK_Type__c = '3 BHK + 2T';
        pl.Premium_Status__c = 'Premium';
        pl.Floor__c = '1';
        pl.Share__c = 'MHPL';
        pl.Facing__c = 'East facing';
        pl.Carpet_Sq_mts__c = 80;
        pl.CA__c = 75;
        pl.Built_up_area__c = 1200;
        pl.UDS__c = 300;
        pl.UDS_Sq_mts__c = 50;
        pl.Super_built_up_area__c = 1500;
        pl.Price_Per_Sq_Ft__c = 5000;
        pl.Floor_Rise__c = 200;
        pl.Premium_Charge__c = 100000;
        pl.Covered_Park_Parking__c = 50000;
        //pl.Other_Charges__c = 20000;
        pl.Solar_Charges__c = 15000;
        pl.GST1__c = 18;
        
        insert pl;

        
        Booking__c ld2 = new Booking__c();
        ld2.Followup_Date__c = system.today().addDays(7);
        ld2.Followup_Subject__c = 'test33';
        ld2.Last_Comment__c = 'test33';
        //ld2.Project__c = 'The Legacey';
        ld2.Payment_Type__c = 'Standard';
        ld2.Sale_Agreement_Completed__c = true;
        ld2.Sub_Stages__c = 'Approved by Sales Manager';
        ld2.Demand_Number__c = '54321';
        ld2.Property_Type__c = 'Apartment';
        ld2.Project1__c = pr1.Id; 
        ld2.Date_of_Booking__c = Date.newInstance(2024, 8, 15);
        ld2.Mode_Of_Payment__c = 'Cheque';
        ld2.Funding_Type__c = 'Loan';
        insert ld2;
        
        // Create a ContentVersion (which automatically creates a ContentDocument)
        ContentVersion contentVersion = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.txt',
            VersionData = Blob.valueOf('Test content'),
            IsMajorVersion = true
        );
        insert contentVersion;

        
        // Get the ContentDocumentId from the ContentVersion
        id contentDoc = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1].ContentDocumentId;
        
        // Create a ContentDocumentLink
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = ld2.Id,
            ContentDocumentId = contentDoc,
            ShareType = 'V'
        );
        insert cdl;
    }
    @isTest
    static void testGetFiles() {
        ContentDocument cd = [select id from ContentDocument limit 1];
        booking__c bk = [select id from booking__c limit 1];
        SimplyfyFilesCntrl.getFiles(bk.Id);
        SimplyfyFilesCntrl.UpdateFiles(cd.id, 'Title', bk.id);
    }
}