/**
 * @description Tests for EmailSenderInvocable.applyFieldUpdatesOnSend — the "update fields on
 *              send" capability added to the email template config.
 */
@isTest
private class EmailFieldUpdatesTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;
        return b;
    }

    @isTest
    static void appliesDateTimeCheckboxAndText() {
        Booking__c b = makeBooking();
        String json = '['
            + '{"field":"Welcome_Mail_Sent_DateTime__c","type":"DateTime","value":"NOW"},'
            + '{"field":"Disable_Demand_Reminders__c","type":"Checkbox","value":"true"},'
            + '{"field":"Stage_Remarks__c","type":"Text","value":"Welcome sent"}'
            + ']';

        Test.startTest();
        EmailSenderInvocable.applyFieldUpdatesOnSend(json, 'Booking__c', new Set<Id>{ b.Id });
        Test.stopTest();

        Booking__c updated = [
            SELECT Welcome_Mail_Sent_DateTime__c, Disable_Demand_Reminders__c, Stage_Remarks__c
            FROM Booking__c WHERE Id = :b.Id
        ];
        System.assertNotEquals(null, updated.Welcome_Mail_Sent_DateTime__c, 'DateTime NOW should be set');
        System.assertEquals(true, updated.Disable_Demand_Reminders__c, 'Checkbox should be true');
        System.assertEquals('Welcome sent', updated.Stage_Remarks__c, 'Text should be set');
    }

    @isTest
    static void ignoresUnknownFieldAndBlankConfig() {
        Booking__c b = makeBooking();

        Test.startTest();
        // Unknown field — must not throw.
        EmailSenderInvocable.applyFieldUpdatesOnSend(
            '[{"field":"Not_A_Real_Field__c","type":"Text","value":"x"}]', 'Booking__c', new Set<Id>{ b.Id }
        );
        // Blank / empty inputs — must not throw.
        EmailSenderInvocable.applyFieldUpdatesOnSend(null, 'Booking__c', new Set<Id>{ b.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend('[]', 'Booking__c', new Set<Id>{ b.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend('[{"field":"Stage_Remarks__c"}]', 'Booking__c', null);
        Test.stopTest();

        System.assert(true, 'No exception means the guards work');
    }
}