global class TempAssignmentExpiryScheduler implements Schedulable {
//test
    // Schedule daily at 6 AM:
    // System.schedule('Temp Assignment Expiry Daily', '0 0 6 * * ?', new TempAssignmentExpiryScheduler());

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new TempAssignmentExpiryBatch(), 200);
    }
}