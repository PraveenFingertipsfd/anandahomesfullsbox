/**
 * @description Utility class for creating test data for the Integration Orchestration Platform.
 *              All methods insert records and return the persisted instances.
 *              This is NOT a test class -- it is a helper used by @IsTest classes.
 * @author Integration Platform
 */
public class postSalesTestDataFactory {


    /**
     * @description Create and insert a basic Account record for post-sales tests.
     */
    public static Account createAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    /**
     * @description Create and insert a Project__c record.
     */
    public static Project__c createProject(String name) {
        Project__c p = new Project__c(
            Name = name,
            Project_Type__c = 'Residential',
            Interest_Rate__c = 12,
            Reminder_Days__c = 7
        );
        insert p;
        return p;
    }

    /**
     * @description Create and insert a Plot__c record under the given Project.
     */
    public static Plot__c createUnit(Id projectId) {
        Plot__c u = new Plot__c(
            Project__c = projectId,
            Unit_Type__c = 'Apartment',
            Status__c = 'Available'
        );
        insert u;
        return u;
    }

    /**
     * @description Create and insert a Booking__c record.
     */
    public static Quote__c createQuote(Id projectId) {
    Quote__c q = new Quote__c();
    insert q;
    return q;
}
    
    public static Booking__c createBooking(Id projectId, Id unitId) {
        Quote__c quote = createQuote(projectId);

    Booking__c b = new Booking__c(
        Project__c = projectId,
        Plot__c = unitId,
        Quote__c = quote.Id,
        Booking_Date__c = Date.today().addDays(-30),
        Mode_Of_Payment__c = 'UPI',
        Total_Flat_Cost__c = 1000000,
        GST_Amount__c = 50000,
        Total_Payable_Amount__c = 1050000,

        // Receipt Creation Flow
        Booking_Amount__c = 100000,

        Email__c = 'tester@example.com',
        Status__c = 'New'
    );

    insert b;
    return b;

    }

    /**
     * @description Convenience method that creates Project, Unit and Booking together.
     */
    public static Booking__c createFullBooking(String projectName) {
        Project__c project = createProject(projectName);
        Plot__c unit = createUnit(project.Id);
        return createBooking(project.Id, unit.Id);
    }
}