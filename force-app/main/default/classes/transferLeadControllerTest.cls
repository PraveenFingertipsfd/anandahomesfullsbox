@isTest
public class transferLeadControllerTest
{
    @isTest
    public static void TestMech()
    {
              // Create a Lead record
       Lead__c testLead = new Lead__c(
            Name__c = 'Test Transfer Lead',
            Email__c = 'leadtest@test.com',
            Secondary_Email__c = 'leadtest2@test.com',
           Phone__c = '9088777766'
        );
        insert testLead;
        
        Profile profile = [SELECT Id FROM Profile WHERE Name='System Administrator'];
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@fingertip.com',
            Username = 'testuser@fingertip.com',
            ProfileId = profile.Id,
            Alias = 'tuser',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        
        );
        insert testUser;
        
        transferLeadController.getRecordAccess(testLead.id);
        transferLeadController.getUserType();
        transferLeadController.getPickListValues();
        transferLeadController.getAllUsers(testLead.id);
        transferLeadController.getCountryAndCode();
        transferLeadController.getProjectNames(testLead.id);
        transferLeadController.getSalesUsers();
        //.moveToSales(testLead.id,'ATMOS Silverwoods','tReason',false,testUser.id);

    }
}