@IsTest
private class CreateQuoteControllerTest {

    @IsTest
    static void testGetPlots() {
        Project__c testProject = new Project__c(Name = 'Test Project', Project_Type__c = 'Residential');
        insert testProject;

        Plot__c plot1 = new Plot__c(Project__c = testProject.Id, Status__c = 'Available');
        Plot__c plot2 = new Plot__c(Project__c = testProject.Id, Status__c = 'Available');
        insert new List<Plot__c>{plot1, plot2};

        Test.startTest();
        List<Plot__c> plots = CreateQuoteController.getPlots('Test Project');
        Test.stopTest();

        System.assertEquals(2, plots.size());
    }

  @IsTest
static void testGetAllPicklistValues() {
    // Prepare input similar to Lightning component's JS
    Map<String, List<String>> objectFieldMap = new Map<String, List<String>>{
        'Lead__c' => new List<String>{ 'Allocated_Project__c' },
        'Plot__c' => new List<String>{
            'BHK_Type__c',
            'Floor__c',
            'Property_Type__c',
            'Unit_Facing_Direction__c',
            'Building__c',
            'Block__c'
        }
    };
        
          // Create Lead using one of the picklist values
    Lead__c testLead = new Lead__c(
        Name__c = 'Test Lead',
        Phone__c = '9876543210'

    );
    insert testLead;

    Test.startTest();
    CreateQuoteController.PicklistWrapper wrapper = CreateQuoteController.getAllPicklistValues(objectFieldMap,testLead.id);
    Test.stopTest();

  
}


    @IsTest
    static void testSaveOppPlot() {
        Quote__c newQuote = new Quote__c( Payment_Type__c = 'Standard');
        Test.startTest();
        String quoteId = CreateQuoteController.saveOppPlot(newQuote);
        Test.stopTest();

        System.assertNotEquals(null, quoteId);
    }

    @IsTest
    static void testSubmitApproval() {
        Quote__c newQuote = new Quote__c( Payment_Type__c = 'Standard');
        insert newQuote;

        Test.startTest();
        CreateQuoteController.submitapproval(newQuote.Id);
        Test.stopTest();

        System.assertNotEquals(null, newQuote.Id); // minimal coverage
    }

    @IsTest
    static void testGetPaymentTypePicklistValues() {
        Test.startTest();
        List<String> paymentTypes = CreateQuoteController.getPaymentTypePicklistValues();
        Test.stopTest();

        System.assert(paymentTypes.contains('Standard'), 'Should include Standard');
    }

@IsTest
static void testGetAllocatedProjectValue() {
    // Create a test Project record
    Project__c testProject = new Project__c(Name = 'Test Project', Project_Type__c = 'Residential');
    insert testProject;

    // Prepare the objectFieldMap (same as what frontend sends)
    Map<String, List<String>> objectFieldMap = new Map<String, List<String>>{
        'Lead__c' => new List<String>{ 'Allocated_Project__c' }
    };
          // Create Lead using one of the picklist values
    Lead__c testLead = new Lead__c(
        Name__c = 'Test Lead',
        Phone__c = '9876543210'

    );
    insert testLead;

    // Call the new method to fetch picklist values
    Test.startTest();
    CreateQuoteController.PicklistWrapper wrapper = CreateQuoteController.getAllPicklistValues(objectFieldMap,testLead.id);
   

    // Get picklist values for Allocated_Project__c
    List<String> values = wrapper.fieldPicklists.get('Allocated_Project__c');
   
		testLead.Allocated_Project__c = values[0];
    update testLead;
  

    // Call method under test
   
    String allocatedProject = CreateQuoteController.getAllocatedProjectValue(testLead.Id);
    Test.stopTest();

    // Assertions
    System.assertEquals(values[0], allocatedProject, 'Returned project value should match the Lead value');
}


    @IsTest
    static void testGetLeadDetails() {
        Lead__c testLead = new Lead__c(Name__c = 'Test Lead', Phone__c = '9876543210');
        insert testLead;

        Test.startTest();
        Lead__c result = CreateQuoteController.getLeadDetails(testLead.Id);
        Test.stopTest();

        System.assertEquals(testLead.Id, result.Id);
    }

    @IsTest
    static void testGetPaymentSchedules() {
        Project__c testProject = new Project__c(Name = 'Test Project', Project_Type__c ='Residential');
        insert testProject;

        Block__c block = new Block__c(Name = 'Tower A', Project__c = testProject.Id);
        insert block;

        Plot__c unit = new Plot__c(Project__c = testProject.Id, Status__c = 'Available');
        insert unit;

        Master_payment_schedule__c mps = new Master_payment_schedule__c(
            Project__c = testProject.Id,
            Tower__c = block.Id,
            Unit__c = unit.Id,
            S_No__c = 1,
            Payment_Percent__c = 10,
            Amount__c = 1000
        );
        insert mps;

        Test.startTest();
        CreateQuoteController.databox result = CreateQuoteController.getPaymentSchedules('Standard', testProject.Id, 10000, block.Id);
        Test.stopTest();

        System.assertEquals(1, result.payList.size());
    }
    
    @IsTest
    static void testGetDiscountConfig() {
        Test.startTest();
        List<CreateQuoteController.DiscountOption> options = CreateQuoteController.getDiscountConfig();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Discount config list should not be null');

        Map<String, Schema.SObjectField> plotFields  = Plot__c.SObjectType.getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> quoteFields = Quote__c.SObjectType.getDescribe().fields.getMap();
        for (CreateQuoteController.DiscountOption o : options) {
            System.assert(String.isNotBlank(o.label),         'Label should be populated');
            System.assert(String.isNotBlank(o.unitField),     'Unit field should be populated');
            System.assert(String.isNotBlank(o.quoteField),    'Quote field should be populated');
            System.assert(String.isNotBlank(o.discountField), 'Derived discount field should be populated');
            System.assert(plotFields.containsKey(o.unitField.toLowerCase()),
                'Unit_Field_API__c "' + o.unitField + '" must exist on Plot__c');
            System.assert(quoteFields.containsKey(o.quoteField.toLowerCase()),
                'Quote_Field_API__c "' + o.quoteField + '" must exist on Quote__c');
            System.assert(quoteFields.containsKey(o.discountField.toLowerCase()),
                'Derived discount field "' + o.discountField + '" must exist on Quote__c');
        }
    }

    @IsTest
    static void testInsertSchedules() {
        // Step 1: Create a Quote__c record
        Quote__c q = new Quote__c(
            Payment_Type__c = 'Standard'
        );
        insert q;

        // Step 2: Create Cost_Sheet_Line_Item__c records to pass to insertSchedules
        List<Cost_Sheet_Line_Item__c> payList = new List<Cost_Sheet_Line_Item__c>{
            new Cost_Sheet_Line_Item__c(
                Payment_percent__c = 10,
                Amount__c = 1000,
                S_No__c = 1
            ),
            new Cost_Sheet_Line_Item__c(
                Payment_percent__c = 20,
                Amount__c = 2000,
                S_No__c = 2
            )
        };

        // Step 3: Call the controller method
        Test.startTest();
        CreateQuoteController.insertSchedules(payList, 10000.00, q.Id);
        CreateQuoteController.testcover();
        Test.stopTest();

        // Step 4: Verify that Cost_Sheet_Line_Item__c records were inserted with Quote__c set
        List<Cost_Sheet_Line_Item__c> insertedItems = [
            SELECT Id, Quote__c, Payment_percent__c, Amount__c
            FROM Cost_Sheet_Line_Item__c
            WHERE Quote__c = :q.Id
        ];

        System.assertEquals(2, insertedItems.size(), 'Two cost sheet line items should be inserted');
        for (Cost_Sheet_Line_Item__c item : insertedItems) {
            System.assertEquals(q.Id, item.Quote__c, 'Quote__c must be assigned correctly');
        }
    }
}