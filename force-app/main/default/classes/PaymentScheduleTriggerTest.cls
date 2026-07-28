@IsTest
public class PaymentScheduleTriggerTest {

    @IsTest
    static void testPaymentScheduleTrigger_UpdateIncludeInterest() {
        Project__c project = new  Project__c();
        project.Name = 'Arto Helix';
        project.Project_Type__c='Residential';
        insert project;
        
        Block__c block = new Block__c();
        block.Name='A';
        block.Project__c=project.id;
        insert block;
        
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
        unit.Facing__c = 'East facing';
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
        //unit.Other_Charges__c = 20000;
        unit.Solar_Charges__c = 15000;
        unit.GST1__c = 18;
        unit.Floor__c = '30';
        
        insert unit;
        
        Booking__c book = new Booking__c();
        book.Followup_Date__c = system.today();
        book.Followup_Subject__c = 'test22';
        book.Last_Comment__c = 'test22';
        //book.Project__c = 'The Legacey';
        book.Payment_Type__c = 'Custom';
        book.Sale_Agreement_Completed__c = false;
        book.Demand_Number__c = '12345'; 
        book.Property_Type__c = 'Apartment';
        book.Project1__c = project.Id; 
        book.Date_of_Booking__c = System.today(); 
        book.Mode_Of_Payment__c = 'Credit Card';
        book.Funding_Type__c = 'Self-Funded';
		book.Plot__c = unit.Id;
        book.Loan_Sanction_Confirmed__c = true;
        book.Loan_Sanctioned_Amount__c = 10000;
        book.Maintenance_Charge__c = 350000;
        insert book;
        
        Master_payment_schedule__c mpy = new Master_payment_schedule__c ();
        mpy.Status__c = 'Completed';
        mpy.Project__c = project.id;
        mpy.Payment_Percent__c=5;
        insert mpy;
        
        Payment_schedule__c pay = new Payment_schedule__c();
        pay.Booking__c = book.id;
        pay.Amount__c = 10000;
        pay.S_No__c = 2;
     //   pay.name = 'Test';
      
        insert pay;
        
        pay.Payment_percent__c = 20;
        pay.Master_Payment_Schedule__c = mpy.Id;
        pay.Include_Interest__c = false;
        
        update pay;
    }

}