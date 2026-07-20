@isTest
public class CoApplicantsControllerTest {
    
    @isTest
    public static void getData(){
        // Create a Booking record (replace with actual Booking__c if it's a custom object)
       User owner = new User(
            Email = 'owner112@example.com',
            Alias = 'owner',
            LastName='andy',
            ProfileId = UserInfo.getProfileId(),
            Username = 'owner43221163@example.com',
            EmailEncodingKey = 'UTF-8',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert owner;
        
        
        Project__c project = new  Project__c();
        project.Name = 'MAHENDRA AARYA';
        project.Project_Type__c='Residential';
        //project.Company__c='MAHENDRA HOMES PVT LTD';
        project.Finance_User__c = owner.Id;
        insert project;
        
        Block__c block = new Block__c();
        block.Name='Tower A';
        block.Project__c=project.id;
        insert block;
        
        list<Master_payment_schedule__c> mp = new list<Master_payment_schedule__c>();
        
        Master_payment_schedule__c mpy = new Master_payment_schedule__c ();
        mpy.Status__c = 'Completed';
        mpy.Project__c = project.id;
        mpy.Tower__c = block.Id;
        mpy.Name = 'On Regestration';
        mpy.S_No__c = 1;
        mpy.Payment_Percent__c = 0;
        mp.add(mpy);
        
        Master_payment_schedule__c mpy1 = new Master_payment_schedule__c ();
        mpy1.Status__c = 'Completed';
        mpy1.Project__c = project.id;
        mpy1.Tower__c = block.Id;
        mpy1.Name = 'On Agreement';
        mpy1.S_No__c = 2;
        mpy1.Payment_Percent__c = 0;
        mp.add(mpy1);
        
        Master_payment_schedule__c mpy2 = new Master_payment_schedule__c ();
        mpy2.Status__c = 'Not Started';
        mpy2.Project__c = project.id;
        mpy2.Tower__c = block.Id;
        mpy2.Name = 'On Completion of basement';
        mpy2.S_No__c = 3;
        mpy2.Payment_Percent__c = 0;
        mp.add(mpy2);
        
        insert mp;
        
        Plot__c unit = new Plot__c();
        unit.Name = '101';
        unit.Status__c = 'Available';
        unit.Project__c = project.Id;
        unit.Block__c = 'A4';
        unit.Plot_Type__c = 'Residential';
        unit.Block1__c = block.Id;
        unit.Carpet_Area__c = 850;
        unit.Balcony_Sq_mts__c = 20;
        unit.Balcony_Area__c = 100;
        unit.BHK_Type__c = '3 BHK + 2T';
        unit.Premium_Status__c = 'Premium';
        unit.Floor__c = '1';
        unit.Share__c = 'MHPL';
        unit.Facing__c = 'East Facing';
        unit.Carpet_Sq_mts__c = 80;
        unit.CA__c = 75;
        unit.Built_up_area__c = 1200;
        unit.UDS__c = 300;
        unit.UDS_Sq_mts__c = 50;
        unit.Super_built_up_area__c = 1500;
        unit.Price_Per_Sq_Ft__c = 5000;
        unit.Floor_Rise__c = 200;
        unit.Premium_Charge__c = 100000;
        unit.Covered_Park_Parking__c = 50000;
        unit.Other_Charges__c = 20000;
        unit.Solar_Charges__c = 15000;
        unit.GST1__c = 18;
        unit.Floor__c = '30';
        insert unit;
        
        Booking__c book = new Booking__c();
        book.Followup_Date__c = system.today();
        book.Followup_Subject__c = 'test22';
        book.Last_Comment__c = 'test22';
        //book.Project__c = 'The Ozone Heights';
        book.Payment_Type__c = 'Custom';
        book.Sale_Agreement_Completed__c = false;
        book.Agreement_Amount_Cleared__c ='Received Partial Amount';
        book.Stage__c ='New Booking';
        
        book.Demand_Number__c = '12345'; 
        book.Project1__c = project.Id; 
        book.Date_of_Booking__c = System.today(); 
        book.Mode_Of_Payment__c = 'Credit Card';
        book.Funding_Type__c = 'Self';
        book.Plot__c = unit.Id;
        book.Loan_Sanction_Confirmed__c = true;
        book.Loan_Sanctioned_Amount__c = 10000;
        book.Maintenance_Charge__c = 350000;
        //book.Finance_User__c = owner.Id;
        insert book;

        // Create Co-Applicant records linked to the Booking. Co_Applicant__c.Name is autonumber.
        Co_Applicant__c coApp1 = new Co_Applicant__c(
            Booking__c = book.Id,
            Salutation__c = 'Mr',
            Relalation_Details__c = 'W/o',
            W_o_S_o_C_o_c__c = 'Mr. Smith'
        );
        Co_Applicant__c coApp2 = new Co_Applicant__c(
            Booking__c = book.Id,
            Salutation__c = 'Ms',
            Relalation_Details__c = 'W/o',
            W_o_S_o_C_o_c__c = 'Mrs. Smith'
        );
        insert new List<Co_Applicant__c>{coApp1, coApp2};

        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(book);
        CoApplicantsController controller = new CoApplicantsController(stdCtrl);

        System.assertEquals(book.Id, controller.BookingId, 'Booking id wired from std controller');
        System.assertEquals(2, controller.coApplicants.size(), 'Both co-applicants loaded');
        Set<String> salutations = new Set<String>();
        for (Co_Applicant__c c : controller.coApplicants) {
            salutations.add(c.Salutation__c);
        }
        System.assert(salutations.contains('Mr') && salutations.contains('Ms'), 'Both salutations returned');
    }

    @isTest
    public static void controllerWithNoCoApplicantsReturnsEmpty() {
        Project__c project = new Project__c(Name='Empty Co App', Project_Type__c='Residential');
        insert project;

        Block__c block = new Block__c(Name='A', Project__c=project.Id);
        insert block;

        Plot__c plot = new Plot__c(
            Name='1', Status__c='Available', Project__c=project.Id,
            Block__c='A4', Plot_Type__c='Residential',
            Block1__c=block.Id, BHK_Type__c='3 BHK + 2T'
        );
        insert plot;

        Booking__c book = new Booking__c(
            //Project__c='The Ozone Heights', 
            Project1__c=project.Id,
            Property_Type__c='Apartment',
            Payment_Type__c='Custom', Date_of_Booking__c=System.today(),
            Mode_Of_Payment__c='Cheque', Funding_Type__c='Self', Plot__c=plot.Id,
            Sale_Agreement_Completed__c=false,
            Agreement_Amount_Cleared__c='Received Partial Amount',
            Stage__c='New Booking', Demand_Number__c='9',
            Maintenance_Charge__c=10000
        );
        insert book;

        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(book);
        CoApplicantsController controller = new CoApplicantsController(stdCtrl);

        System.assertEquals(book.Id, controller.BookingId);
        System.assertEquals(0, controller.coApplicants.size(), 'No co-applicants → empty');
    }
}