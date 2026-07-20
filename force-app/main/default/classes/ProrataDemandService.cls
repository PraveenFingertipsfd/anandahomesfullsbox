/**
 * @description Raises the split Prorata / Partial demands described in BRD §8.4.
 *
 *              For a Prorata / Partial booking each eligible milestone produces TWO demands
 *              instead of one:
 *                • Bank demand     — Bank Flat + Bank GST, raised when the milestone is
 *                                    completed, delivered to the banker contact.
 *                • Customer demand — Customer Flat + Customer GST, raised on the milestone's
 *                                    demand date (after the forecast-date reminder).
 *
 *              Standard (Self / Loan) bookings are untouched — they keep using the normal
 *              single-demand flow (BulkDemandController / individual demand).
 *
 *              Each side is tracked independently on the Payment Schedule
 *              (Bank_Demand_Raised__c / Customer_Demand_Raised__c) so the same milestone is
 *              never double-demanded on the same side, and raising a demand locks the split
 *              (Demand_Raised__c) per §8.3.1.
 * @author System
 */
public with sharing class ProrataDemandService {

    /** Escape hatch for trusted bulk / migration processes. */
    public static Boolean bypass = false;

    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };
    // Bank-funded types that carry a per-milestone Bank/Customer split (BRD §8.1).
    private static final Set<String> FUNDING_SPLIT = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };
    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Paid', 'Completed', 'Waived', 'Cancelled' };
    @TestVisible private static final String TYPE_BANK = 'Bank Demand';
    @TestVisible private static final String TYPE_CUSTOMER = 'Customer Prorata Demand';

    // ==================== PUBLIC ENTRY POINTS ====================

    /** Raises Bank demands (Bank Flat + Bank GST) for the given payment-schedule milestones. */
    public static Integer raiseBankDemands(Set<Id> scheduleIds) {
        return raise(scheduleIds, true);
    }

    /** Raises Customer demands (Customer Flat + Customer GST) for the given milestones. */
    public static Integer raiseCustomerDemands(Set<Id> scheduleIds) {
        return raise(scheduleIds, false);
    }

    /**
     * @description On milestone completion, raise the Bank demand for the Prorata/Partial
     *              bookings whose payment schedule includes that milestone (matched by Project +
     *              Milestone Name, the correlation used elsewhere). Called from
     *              ConstructionMilestoneTrigger.
     */
    public static Integer raiseBankDemandsForCompletedMilestones(List<Construction_Milestone__c> milestones) {
        if (bypass || milestones == null || milestones.isEmpty()) return 0;

        Set<Id> projectIds = new Set<Id>();
        Set<String> names = new Set<String>();
        for (Construction_Milestone__c m : milestones) {
            if (m.Project__c != null) projectIds.add(m.Project__c);
            if (String.isNotBlank(m.Milestone_Name__c)) names.add(m.Milestone_Name__c);
        }
        if (projectIds.isEmpty() || names.isEmpty()) return 0;

        Set<Id> scheduleIds = new Set<Id>();
        for (Payment_Schedule__c ps : [
            SELECT Id
            FROM Payment_Schedule__c
            WHERE Milestone_Name__c IN :names
            AND Booking__r.Project__c IN :projectIds
            AND Booking__r.Funding_Type__c IN :FUNDING_SPLIT
            AND Bank_Demand_Raised__c = false
            AND Bank_Flat_Amount__c > 0
        ]) {
            scheduleIds.add(ps.Id);
        }
        return raiseBankDemands(scheduleIds);
    }

    /**
     * @description Daily job hook: raise the Customer demand for Prorata/Partial milestones whose
     *              demand date has arrived (Due Date today or earlier), the forecast reminder has
     *              gone out, and the customer side has not been demanded yet. Called from
     *              DemandReminderSchedulable.
     */
    public static Integer raiseDueCustomerDemands() {
        if (bypass) return 0;
        Date today = Date.today();
        Set<Id> scheduleIds = new Set<Id>();
        for (Payment_Schedule__c ps : [
            SELECT Id
            FROM Payment_Schedule__c
            WHERE Booking__r.Funding_Type__c IN :FUNDING_PRORATA
            AND Customer_Demand_Raised__c = false
            AND Customer_Flat_Prorata__c > 0
            AND Due_Date__c <= :today
            AND Status__c NOT IN :CLOSED_STATUSES
            LIMIT 200
        ]) {
            scheduleIds.add(ps.Id);
        }
        return raiseCustomerDemands(scheduleIds);
    }

    // ==================== CORE ====================

    private static Integer raise(Set<Id> scheduleIds, Boolean bankSide) {
        if (bypass || scheduleIds == null || scheduleIds.isEmpty()) return 0;

        List<Payment_Schedule__c> rows = [
            SELECT Id, Booking__c, Milestone_Name__c, Due_Date__c, Status__c,
                   Bank_Flat_Amount__c, Bank_GST_Amount__c, Customer_Flat_Prorata__c,
                   Customer_GST_Prorata__c, TDS_Amount__c, With_GST__c,
                   Bank_Demand_Raised__c, Customer_Demand_Raised__c,
                   Booking__r.Funding_Type__c
            FROM Payment_Schedule__c
            WHERE Id IN :scheduleIds
            AND Booking__r.Funding_Type__c IN :FUNDING_SPLIT
        ];
        if (rows.isEmpty()) return 0;

        List<Demands__c> demands = new List<Demands__c>();
        List<Payment_Schedule__c> flags = new List<Payment_Schedule__c>();

        for (Payment_Schedule__c ps : rows) {
            if (CLOSED_STATUSES.contains(ps.Status__c)) continue;

            Boolean already = bankSide ? ps.Bank_Demand_Raised__c == true
                                       : ps.Customer_Demand_Raised__c == true;
            if (already) continue;

            Decimal flat = bankSide ? nz(ps.Bank_Flat_Amount__c) : nz(ps.Customer_Flat_Prorata__c);
            Decimal gst  = bankSide ? nz(ps.Bank_GST_Amount__c)  : nz(ps.Customer_GST_Prorata__c);
            Decimal total = flat + gst;
            if (total <= 0) continue;

            demands.add(new Demands__c(
                Booking__c = ps.Booking__c,
                Payment_Schedule__c = ps.Id,
                Demand_Type__c = bankSide ? TYPE_BANK : TYPE_CUSTOMER,
                Funding_Type__c = ps.Booking__r.Funding_Type__c,
                Base_Amount__c = flat,
                GST_Amount__c = gst,
                TDS_Amount__c = bankSide ? 0 : nz(ps.TDS_Amount__c),
                Demand_Amount__c = total,
                Status__c = PostSalesConstants.DEMAND_STATUS_RAISED,
                Demand_Date__c = Date.today(),
                Due_Date__c = ps.Due_Date__c != null
                    ? ps.Due_Date__c
                    : Date.today().addDays(PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS)
            ));

            Payment_Schedule__c flag = new Payment_Schedule__c(Id = ps.Id);
            if (bankSide) flag.Bank_Demand_Raised__c = true;
            else flag.Customer_Demand_Raised__c = true;
            // Raising either side locks the split (BRD §8.3.1).
            flag.Demand_Raised__c = true;
            flags.add(flag);
        }

        if (demands.isEmpty()) return 0;
        insert demands;
        if (!flags.isEmpty()) {
            // Only demand-raised flags change here (not the split), so suspend the §8.3.1
            // invariant re-validation while stamping them.
            Boolean prior = ProrataInvariantService.bypass;
            ProrataInvariantService.bypass = true;
            try {
                update flags;
            } finally {
                ProrataInvariantService.bypass = prior;
            }
        }
        return demands.size();
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }

    // ==================== INVOCABLE (Flow / buttons) ====================

    public class Request {
        @InvocableVariable(required=true label='Payment Schedule Id') public Id scheduleId;
        @InvocableVariable(label='Bank Side? (true = Bank demand, false = Customer demand)')
        public Boolean bankSide;
    }

    @InvocableMethod(label='Raise Prorata Split Demand'
        description='Raises the Bank or Customer prorata demand for a payment-schedule milestone (BRD 8.4)')
    public static void raiseFromFlow(List<Request> requests) {
        if (requests == null || requests.isEmpty()) return;
        Set<Id> bankIds = new Set<Id>();
        Set<Id> customerIds = new Set<Id>();
        for (Request r : requests) {
            if (r == null || r.scheduleId == null) continue;
            if (r.bankSide == true) bankIds.add(r.scheduleId);
            else customerIds.add(r.scheduleId);
        }
        if (!bankIds.isEmpty()) raiseBankDemands(bankIds);
        if (!customerIds.isEmpty()) raiseCustomerDemands(customerIds);
    }
}