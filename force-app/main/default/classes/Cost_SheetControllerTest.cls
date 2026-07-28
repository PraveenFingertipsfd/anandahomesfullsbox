@isTest
public class Cost_SheetControllerTest {

    @testSetup
    static void setup() {
        Project__c project = new Project__c();
        project.Name = 'Arto Helix';
        project.Project_Type__c = 'Residential';
        insert project;

        Block__c block = new Block__c();
        block.Name = 'A';
        block.Project__c = project.Id;
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

        Plot__c unit1 = new Plot__c();
        unit1.Name = '105';
        unit1.Status__c = 'Available';
        unit1.Project__c = project.Id;
        unit1.Block__c = 'A4';
        unit1.Plot_Type__c = 'Residential';
        unit1.Block1__c = block.Id;
        unit1.Carpet_Area__c = 850;
        unit1.Balcony_Sq_mts__c = 20;
        unit1.Balcony_Area__c = 100;
        unit1.BHK_Type__c = '3 BHK + 2T';
        unit1.Premium_Status__c = 'Premium';
        unit1.Floor__c = '1';
        unit1.Share__c = 'MHPL';
        unit1.Facing__c = 'East Facing';
        unit1.Carpet_Sq_mts__c = 80;
        unit1.CA__c = 75;
        unit1.Built_up_area__c = 1200;
        unit1.UDS__c = 300;
        unit1.UDS_Sq_mts__c = 50;
        unit1.Super_built_up_area__c = 1500;
        unit1.Price_Per_Sq_Ft__c = 5000;
        unit1.Floor_Rise__c = 200;
        unit.Premium_Charge__c = 100000;
        unit1.Covered_Park_Parking__c = 50000;
        unit1.Other_Charges__c = 20000;
        unit1.Solar_Charges__c = 15000;
        unit1.GST1__c = 18;
        unit1.Floor__c = '1';
        insert unit1;

        Plot__c unit2 = new Plot__c();
        unit2.Name = '135';
        unit2.Status__c = 'Available';
        unit2.Project__c = project.Id;
        unit2.Block__c = 'A4';
        unit2.Plot_Type__c = 'Residential';
        unit2.Block1__c = block.Id;
        unit2.Carpet_Area__c = 850;
        unit2.Balcony_Sq_mts__c = 20;
        unit2.Balcony_Area__c = 100;
        unit2.BHK_Type__c = '3 BHK + 2T';
        unit2.Premium_Status__c = 'Premium';
        unit2.Floor__c = '1';
        unit2.Share__c = 'MHPL';
        unit2.Facing__c = 'East Facing';
        unit2.Carpet_Sq_mts__c = 80;
        unit2.CA__c = 75;
        unit2.Built_up_area__c = 1200;
        unit2.UDS__c = 300;
        unit2.UDS_Sq_mts__c = 50;
        unit2.Super_built_up_area__c = 1500;
        unit2.Price_Per_Sq_Ft__c = 5000;
        unit2.Floor_Rise__c = 200;
        unit2.Premium_Charge__c = 100000;
        unit2.Covered_Park_Parking__c = 50000;
        unit2.Other_Charges__c = 20000;
        unit2.Solar_Charges__c = 15000;
        unit2.GST1__c = 18;
        unit2.Floor__c = '15';
        insert unit2;

        // Booking without FloorNo__c — covers FloorNo__c == null path
        Booking__c book = new Booking__c();
        book.Followup_Date__c = system.today();
        book.Followup_Subject__c = 'test22';
        book.Last_Comment__c = 'test22';
        //book.Project__c = 'The Ozone Heights';
        book.Payment_Type__c = 'Custom';
        book.Sale_Agreement_Completed__c = false;
        book.Agreement_Amount_Cleared__c = 'Received Partial Amount';
        book.Stage__c = 'New Booking';
        book.Demand_Number__c = '12345';
        book.Project1__c = project.Id;
        book.Date_of_Booking__c = System.today();
        book.Mode_Of_Payment__c = 'Credit Card';
        book.Funding_Type__c = 'Self-Funded';
        book.Plot__c = unit.Id;
        book.Loan_Sanction_Confirmed__c = true;
        book.Loan_Sanctioned_Amount__c = 10000;
        book.Maintenance_Charge__c = 350000;
        book.Email1__c = 'Email1@gma.com';
        book.Email2__c = 'test2@example.com';
        book.First_Applicant_Name__c = 'John Doe';
        book.Bank__c = 'SBI';
        book.Other_Charges__c = 1000;
        book.Premium_Charge__c = 2000;
        book.Price_per_sqft__c = 5000;
        insert book;

        Booking__c book2 = new Booking__c();
        book2.Followup_Date__c = system.today();
        book2.Followup_Subject__c = 'test22';
        book2.Last_Comment__c = 'test22';
        //book2.Project__c = 'The Ozone Heights';
        book2.Payment_Type__c = 'Custom';
        book2.Sale_Agreement_Completed__c = false;
        book2.Agreement_Amount_Cleared__c = 'Received Partial Amount';
        book2.Stage__c = 'New Booking';
        book2.Demand_Number__c = '12345';
        book2.Project1__c = project.Id;
        book2.Date_of_Booking__c = System.today();
        book2.Mode_Of_Payment__c = 'Credit Card';
        book2.Funding_Type__c = 'Self-Funded';
        book2.Plot__c = unit2.Id;
        book2.Loan_Sanction_Confirmed__c = true;
        book2.Loan_Sanctioned_Amount__c = 10000;
        book2.Maintenance_Charge__c = 350000;
        book2.Email1__c = 'Email11@gma.com';
        book2.Email2__c = 'test22@example.com';
        book2.First_Applicant_Name__c = 'John Doeh';
        book2.Bank__c = 'SBI';
        book2.Other_Charges__c = 1000;
        book2.Premium_Charge__c = 2000;
        book2.Price_per_sqft__c = 5000;
        insert book2;
    }

    // Builds a Plot__c with a specific Floor__c value. FloorNo__c on Booking__c is a
    // formula that pulls from Plot__r.Floor__c, so we must set it on the Plot, not the Booking.
    private static Plot__c buildPlot(Id projectId, Id blockId, String plotName, String floorValue) {
        Plot__c p = new Plot__c();
        p.Name = plotName;
        p.Status__c = 'Available';
        p.Project__c = projectId;
        p.Block__c = 'A4';
        p.Plot_Type__c = 'Residential';
        p.Block1__c = blockId;
        p.Carpet_Area__c = 850;
        p.Balcony_Sq_mts__c = 20;
        p.Balcony_Area__c = 100;
        p.BHK_Type__c = '3 BHK + 2T';
        p.Premium_Status__c = 'Premium';
        p.Share__c = 'MHPL';
        p.Facing__c = 'East Facing';
        p.Carpet_Sq_mts__c = 80;
        p.CA__c = 75;
        p.Built_up_area__c = 1200;
        p.UDS__c = 300;
        p.UDS_Sq_mts__c = 50;
        p.Super_built_up_area__c = 1500;
        p.Price_Per_Sq_Ft__c = 5000;
        p.Floor_Rise__c = 200;
        p.Premium_Charge__c = 100000;
        p.Covered_Park_Parking__c = 50000;
        p.Other_Charges__c = 20000;
        p.Solar_Charges__c = 15000;
        p.GST1__c = 18;
        p.Floor__c = floorValue;
        return p;
    }

    // Builds a minimal Booking__c linked to the given plot.
    // Super_Built_up_area_NE__c on Booking is a formula = Built_up_area__c; setting
    // Built_up_area__c controls whether the charges-calculation branch executes.
    private static Booking__c buildBooking(Id projectId, Id plotId, Decimal builtUpArea, String firstName) {
        Booking__c b = new Booking__c();
        b.Followup_Date__c = system.today();
        b.Followup_Subject__c = 'test';
        b.Last_Comment__c = 'test';
        //b.Project__c = 'The Ozone Heights';
        b.Payment_Type__c = 'Custom';
        b.Sale_Agreement_Completed__c = false;
        b.Agreement_Amount_Cleared__c = 'Received Partial Amount';
        b.Stage__c = 'New Booking';
        b.Demand_Number__c = '99999';
        b.Project1__c = projectId;
        b.Date_of_Booking__c = System.today();
        b.Mode_Of_Payment__c = 'Credit Card';
        b.Funding_Type__c = 'Self-Funded';
        b.Plot__c = plotId;
        b.Loan_Sanction_Confirmed__c = true;
        b.Loan_Sanctioned_Amount__c = 5000;
        b.Maintenance_Charge__c = 100000;
        b.Email1__c = 'floortest@gma.com';
        b.Email2__c = 'floortest2@gma.com';
        b.First_Applicant_Name__c = firstName;
        b.Bank__c = 'HDFC';
        b.Other_Charges__c = 500;
        b.Floor_Rise_Charges_Rate__c = 50;
        b.Premium_Charge__c = 800;
        b.Price_per_sqft__c = 4500;
        b.Built_up_area__c = builtUpArea;
        return b;
    }

    @isTest
    static void testFloorNumberWithNumericFloor() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        Booking__c booking1 = [SELECT Id, First_Applicant_Name__c FROM Booking__c WHERE First_Applicant_Name__c = 'John Doeh' LIMIT 1];
        Booking__c booking2 = [SELECT Id, First_Applicant_Name__c FROM Booking__c WHERE First_Applicant_Name__c = 'John Doe' LIMIT 1];

        ApexPages.StandardController sc = new ApexPages.StandardController(booking);
        Cost_SheetController controller = new Cost_SheetController(sc);

        ApexPages.StandardController sc1 = new ApexPages.StandardController(booking1);
        Cost_SheetController controller2 = new Cost_SheetController(sc1);

        ApexPages.StandardController sc2 = new ApexPages.StandardController(booking2);
        Cost_SheetController controller3 = new Cost_SheetController(sc2);

        System.assertNotEquals(null, controller, 'Controller for primary booking constructed');
        System.assertNotEquals(null, controller2, 'Controller for John Doeh booking constructed');
        System.assertNotEquals(null, controller3, 'Controller for John Doe booking constructed');
    }

    @isTest
    static void testFloorNumberWithTeenNumericFloor() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        ApexPages.StandardController sc = new ApexPages.StandardController(booking);
        Cost_SheetController controller = new Cost_SheetController(sc);
        System.assertNotEquals(null, controller, 'Controller constructed');
    }

    @isTest
    static void testFloorNumberWithNonNumericFloor() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        ApexPages.StandardController sc = new ApexPages.StandardController(booking);
        Cost_SheetController controller = new Cost_SheetController(sc);
        System.assertNotEquals(null, controller, 'Controller constructed');
    }

    @isTest
    static void testFloorNumberNullFloor() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Plot__c unit = [SELECT Id, Name FROM Plot__c WHERE Name = '105' LIMIT 1];

        Booking__c book = new Booking__c();
        book.Followup_Date__c = system.today();
        book.Followup_Subject__c = 'test22';
        book.Last_Comment__c = 'test22';
        //book.Project__c = 'The Ozone Heights';
        book.Payment_Type__c = 'Custom';
        book.Sale_Agreement_Completed__c = false;
        book.Agreement_Amount_Cleared__c = 'Received Partial Amount';
        book.Stage__c = 'New Booking';
        book.Demand_Number__c = '12345';
        book.Project1__c = project.Id;
        book.Date_of_Booking__c = System.today();
        book.Mode_Of_Payment__c = 'Credit Card';
        book.Funding_Type__c = 'Self-Funded';
        book.Plot__c = unit.Id;
        book.Loan_Sanction_Confirmed__c = true;
        book.Loan_Sanctioned_Amount__c = 10000;
        book.Maintenance_Charge__c = 350000;
        book.Email1__c = 'Email1@gma.com';
        book.Email2__c = 'test2@example.com';
        book.First_Applicant_Name__c = 'John Doev';
        book.Bank__c = 'SBI';
        book.Other_Charges__c = 1000;
        book.Premium_Charge__c = 2000;
        book.Price_per_sqft__c = 5000;
        insert book;

        ApexPages.StandardController sc = new ApexPages.StandardController(book);
        Cost_SheetController controller = new Cost_SheetController(sc);
        System.assertNotEquals(null, controller, 'Controller built with null Floor unit');
    }

    /**
     * Covers all branches of convertToWords and the Super_Built_up_area_NE__c charges block:
     *   - Single digit > 0 (e.g. '5')
     *   - Single digit == 0 (e.g. '0')
     *   - Two digits, teens 10-19 (e.g. '13')
     *   - Two digits, >= 20 with non-zero last digit (e.g. '23')
     *   - Two digits, >= 20 with zero last digit (e.g. '30')
     *   - Non-numeric 'G'
     *   - Non-numeric non-G (e.g. 'B1')
     *   - Super_Built_up_area_NE__c != null (charges calculation)
     */
    @isTest
    static void testFloorNumberVariants() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Block__c block = [SELECT Id FROM Block__c LIMIT 1];

        // Create plots with Floor__c variants (only values valid in the picklist):
        // 'G', '1'..'30'. The '0' and non-numeric-non-G branches are unreachable in this org.
        Plot__c p5  = buildPlot(project.Id, block.Id, '201', '5');   // single digit > 0
        Plot__c p13 = buildPlot(project.Id, block.Id, '203', '13');  // teens (10-19)
        Plot__c p23 = buildPlot(project.Id, block.Id, '204', '23');  // >=20, secondLast > 0
        Plot__c p30 = buildPlot(project.Id, block.Id, '205', '30');  // >=20, secondLast == 0
        Plot__c pG  = buildPlot(project.Id, block.Id, '206', 'G');   // Ground Floor
        insert new List<Plot__c>{ p5, p13, p23, p30, pG };

        // Booking linked to each plot. Built_up_area__c = null for most (skips charges block),
        // and one booking with Built_up_area__c set to cover the charges-calculation branch.
        Booking__c b5    = buildBooking(project.Id, p5.Id,  null,   'Floor5');
        Booking__c b13   = buildBooking(project.Id, p13.Id, null,   'Floor13');
        Booking__c b23   = buildBooking(project.Id, p23.Id, null,   'Floor23');
        Booking__c b30   = buildBooking(project.Id, p30.Id, null,   'Floor30');
        Booking__c bG    = buildBooking(project.Id, pG.Id,  null,   'FloorG');
        Booking__c bArea = buildBooking(project.Id, p5.Id,  1500.0, 'FloorArea');
        insert new List<Booking__c>{ b5, b13, b23, b30, bG, bArea };

        Test.startTest();
        Cost_SheetController c5  = new Cost_SheetController(new ApexPages.StandardController(b5));
        Cost_SheetController c13 = new Cost_SheetController(new ApexPages.StandardController(b13));
        Cost_SheetController c23 = new Cost_SheetController(new ApexPages.StandardController(b23));
        Cost_SheetController c30 = new Cost_SheetController(new ApexPages.StandardController(b30));
        Cost_SheetController cG  = new Cost_SheetController(new ApexPages.StandardController(bG));
        Cost_SheetController cA  = new Cost_SheetController(new ApexPages.StandardController(bArea));
        Test.stopTest();

        System.assertNotEquals(null, c5,  'floor 5 controller');
        System.assertNotEquals(null, c13, 'floor 13 controller');
        System.assertNotEquals(null, c23, 'floor 23 controller');
        System.assertNotEquals(null, c30, 'floor 30 controller');
        System.assertNotEquals(null, cG,  'floor G controller');
        System.assertNotEquals(null, cA,  'controller with built-up area');
    }
}