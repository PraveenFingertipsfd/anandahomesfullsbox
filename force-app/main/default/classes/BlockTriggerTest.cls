@IsTest
private class BlockTriggerTest {
    
	@IsTest
    static void setupData() {
        // Create a Project, Block, Booking, Payment Schedule hierarchy
        Project__c proj = new Project__c(  Name = 'Test Project', 
            Project_Type__c = 'Residential');
        insert proj;
        
        Block__c block = new Block__c(
            Name = 'Block A',
            Project__c = proj.Id,
            Intrest_Percentage__c = 5
        );
        insert block;
         block.Name = 'Block Aq';                      
        block.Intrest_Percentage__c =10;
          update block;
        
        Booking__c booking = new Booking__c(
           
            Block__c = block.Id
        );
        insert booking;
        
   /*     Payment_Schedule__c ps = new Payment_Schedule__c(
            Name = 'PS1',
            Booking__c = booking.Id,
            Interest_Percent__c = 5
        );
        insert ps;*/
    }
    
/*    @isTest
    static void testNoChangeUpdate() {
        Block__c b = [SELECT Id, Intrest_Percentage__c FROM Block__c LIMIT 1];
        b.Name = 'Updated Block'; // Change irrelevant field
        Test.startTest();
        update b;
        Test.stopTest();
        
        // Assert no changes made in Payment_Schedule
        Payment_Schedule__c ps = [SELECT Interest_Percent__c FROM Payment_Schedule__c LIMIT 1];
    
    }
    
    @isTest
    static void testWithChangeUpdate() {
        Block__c b = [SELECT Id, Intrest_Percentage__c FROM Block__c LIMIT 1];
        b.Intrest_Percentage__c = 10; // Change to trigger logic
        Test.startTest();
        update b;
        Test.stopTest();
        
        // Payment schedule should be updated
        Payment_Schedule__c ps = [SELECT Interest_Percent__c FROM Payment_Schedule__c LIMIT 1];
       
    }
    
    @isTest
    static void testInsertAndUndelete() {
        // Insert new block (covers before/after insert)
        Block__c b = new Block__c(
            Name = 'Block B',
            Project__c = [SELECT Id FROM Project__c LIMIT 1].Id,
            Intrest_Percentage__c = 15
        );
        insert b;
        
        // Delete and undelete to cover those events
        delete b;
        undelete b;
        
    
    } */
}