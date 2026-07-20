@isTest
public class MasterPaymentScheduleTriggerTest {

    @isTest
    static void testTrigger() {
        
        
        Project__c pr = new  Project__c();
        pr.Name = 'Aarya';
        pr.Project__c = 'The Legacey';
        pr.Project_Type__c='Residential';
        insert pr;

        
        Block__c blk = new Block__c();
        blk.Name='A3';
        blk.Project__c=pr.id;
        insert blk;
        
        Plot__c pl = new Plot__c();
        pl.Name = '101';
        pl.Status__c = 'Available';
        pl.Project__c = pr.Id;
        pl.Block__c = 'A4';
        pl.Plot_Type__c = 'Residential';
        pl.Block1__c = blk.Id;
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
        pl.Other_Charges__c = 20000;
        pl.Solar_Charges__c = 15000;
        pl.GST1__c = 18;
        
        insert pl;
        
        Booking__c ld1 = new Booking__c();
        ld1.Followup_Date__c = system.today();
        ld1.Followup_Subject__c = 'test22';
        ld1.Last_Comment__c = 'test22';
        //ld1.Project__c = 'The Legacey';
        ld1.Payment_Type__c = 'Custom';
        ld1.Sale_Agreement_Completed__c = false;
        ld1.Sub_Stages__c = 'Submitted For Approval';
        ld1.Demand_Number__c = '12345'; 
        ld1.Project1__c = pr.Id; 
        ld1.Date_of_Booking__c = System.today(); 
        ld1.Mode_Of_Payment__c = 'Credit Card';
        ld1.Funding_Type__c = 'Self';
        ld1.Plot__c = pl.Id;
        insert ld1;
        
        Booking__c ld = new Booking__c();
        ld.Followup_Date__c = system.today();
        ld.Followup_Subject__c = 'test22';
        ld.Last_Comment__c = 'test22';
        //ld.Project__c = 'The Legacey';
        ld.Payment_Type__c = 'Custom';
        ld.Sale_Agreement_Completed__c = false;
        ld.Sub_Stages__c = 'Submitted For Approval';
        ld.Demand_Number__c = '12345'; 
        ld.Project1__c = pr.Id; 
        ld.Date_of_Booking__c = System.today(); 
        ld.Mode_Of_Payment__c = 'Credit Card';
        ld.Funding_Type__c = 'Self';
        ld.Plot__c = pl.Id;
        insert ld;
        
        Master_payment_schedule__c mpy = new Master_payment_schedule__c ();
        mpy.Status__c = 'Not Started';
        mpy.Project__c = pr.id;
  mpy.Payment_Percent__c=10;
        mpy.Due_Date__c = system.today();
        insert mpy;
        
        Payment_schedule__c pys = new Payment_schedule__c();
        pys.Payment_Percent__c=10;
        pys.Payment_Due_Date__c = system.today()+3;
        pys.Booking__c = ld1.id;
        pys.Master_Payment_Schedule__c = mpy.Id;
        insert pys;

        Test.startTest();
        mpy.Status__c = 'Completed';
        update mpy;
        Test.stopTest();

        Master_Payment_Schedule__c afterMpy = [SELECT Status__c FROM Master_Payment_Schedule__c WHERE Id = :mpy.Id];
        System.assertEquals('Completed', afterMpy.Status__c, 'Master schedule status persisted');

        Payment_Schedule__c updatedPaymentSchedule = [SELECT Payment_Due_Date__c, Booking__c FROM Payment_Schedule__c WHERE Id = :pys.Id LIMIT 1];
        System.assertEquals(ld1.Id, updatedPaymentSchedule.Booking__c, 'Payment schedule still linked to booking');
        System.assertNotEquals(null, updatedPaymentSchedule.Payment_Due_Date__c, 'Due date present');
    }
}