/**
 * @description Invocable wrapper so a record-triggered Flow can (re)apply the Bank/Customer
 *              prorata split on a Prorata/Partial booking's payment schedules when the Loan
 *              Sanctioned Amount is set/changed. Delegates to
 *              {@link PaymentScheduleGeneratorService#applyProrataSplit}, which is a safe,
 *              non-destructive no-op unless the booking is Prorata/Partial, has a positive Loan
 *              Sanctioned Amount, and its schedules are not already split.
 * @author System
 */
public with sharing class ProrataSplitInvocable {

    public class Input {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
    }

    @InvocableMethod(label='Apply Prorata Split'
        description='Populates the Bank/Customer prorata split on a booking\'s payment schedules from Loan Sanctioned Amount and Deficit'
        category='Financial')
    public static void apply(List<Input> inputs) {
        if (inputs == null || inputs.isEmpty()) return;
        Set<Id> ids = new Set<Id>();
        for (Input inp : inputs) {
            if (inp != null && inp.bookingId != null) ids.add(inp.bookingId);
        }
        PaymentScheduleGeneratorService.applyProrataSplit(ids);
    }
}