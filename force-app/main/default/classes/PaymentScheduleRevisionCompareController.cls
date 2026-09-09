/**
 * @description Controller for the Payment Schedule Revision Compare VF page. Reads the revision's
 *              Proposed_Changes_JSON__c (a PaymentScheduleRevisionService.RevisionPayload) and
 *              flattens it into old-vs-new rows with per-field "changed" flags, so the approver
 *              can see exactly what is being proposed before approving or rejecting.
 * @author System
 */
public without sharing class PaymentScheduleRevisionCompareController {

    public Payment_Schedule_Revision__c revision { get; private set; }
    public List<LineRow> lineRows { get; private set; }
    public PaymentScheduleRevisionService.RevisionTotals totals { get; private set; }

    public PaymentScheduleRevisionCompareController(ApexPages.StandardController stdController) {
        Id revId = stdController.getId();
        revision = [
            SELECT Id, Name, Booking__c, Booking__r.Name, Approval_Status__c, Revision_Reason__c,
                   Submitted_By__c, Submitted_By__r.Name, Submitted_Date__c,
                   Approved_By__c, Approved_By__r.Name, Approved_Date__c,
                   Applied__c, Applied_Date__c, Proposed_Changes_JSON__c
            FROM Payment_Schedule_Revision__c
            WHERE Id = :revId
        ];
        load();
    }

    private void load() {
        lineRows = new List<LineRow>();
        totals = new PaymentScheduleRevisionService.RevisionTotals();
        if (String.isBlank(revision.Proposed_Changes_JSON__c)) return;

        PaymentScheduleRevisionService.RevisionPayload payload;
        try {
            payload = (PaymentScheduleRevisionService.RevisionPayload) JSON.deserialize(
                revision.Proposed_Changes_JSON__c, PaymentScheduleRevisionService.RevisionPayload.class
            );
        } catch (Exception e) {
            // Likely a revision staged before the comparison payload existed; nothing to show.
            return;
        }
        if (payload == null) return;
        if (payload.totals != null) totals = payload.totals;
        if (payload.lines == null) return;

        // The milestone name stored in the revision payload is the schedule's own
        // Milestone_Name__c, which is blank on all but the first milestone. Backfill any blank
        // name from the live schedule's master template (Master_Payment_Schedule__r.Name), so the
        // Milestone column is populated for existing and future revisions alike.
        Set<Id> psIds = new Set<Id>();
        for (PaymentScheduleRevisionService.RevisionLineDiff d : payload.lines) {
            if (d.id != null && String.isBlank(d.milestoneName)) psIds.add(d.id);
        }
        Map<Id, String> nameById = new Map<Id, String>();
        if (!psIds.isEmpty()) {
            for (Payment_Schedule__c ps : [
                SELECT Id, Milestone_Name__c, Master_Payment_Schedule__r.Name
                FROM Payment_Schedule__c
                WHERE Id IN :psIds
            ]) {
                String nm = String.isNotBlank(ps.Milestone_Name__c)
                    ? ps.Milestone_Name__c
                    : (ps.Master_Payment_Schedule__c != null ? ps.Master_Payment_Schedule__r.Name : null);
                if (String.isNotBlank(nm)) nameById.put(ps.Id, nm);
            }
        }

        for (PaymentScheduleRevisionService.RevisionLineDiff d : payload.lines) {
            if (String.isBlank(d.milestoneName) && d.id != null && nameById.containsKey(d.id)) {
                d.milestoneName = nameById.get(d.id);
            }
            lineRows.add(new LineRow(d));
        }
    }

    /** Flattened, VF-friendly row with a "changed" flag per field for highlighting. */
    public class LineRow {
        public String milestoneName { get; private set; }

        public Decimal oldPercentage { get; private set; }
        public Decimal newPercentage { get; private set; }
        public Boolean percentageChanged { get; private set; }

        public Decimal oldBaseAmount { get; private set; }
        public Decimal newBaseAmount { get; private set; }
        public Boolean baseAmountChanged { get; private set; }

        public Decimal oldGstAmount { get; private set; }
        public Decimal newGstAmount { get; private set; }
        public Boolean gstAmountChanged { get; private set; }

        public Decimal oldTdsAmount { get; private set; }
        public Decimal newTdsAmount { get; private set; }
        public Boolean tdsAmountChanged { get; private set; }

        public Decimal oldAmount { get; private set; }
        public Decimal newAmount { get; private set; }
        public Boolean amountChanged { get; private set; }

        public Decimal oldBankFlat { get; private set; }
        public Decimal newBankFlat { get; private set; }
        public Boolean bankFlatChanged { get; private set; }

        public Decimal oldCustomerFlat { get; private set; }
        public Decimal newCustomerFlat { get; private set; }
        public Boolean customerFlatChanged { get; private set; }

        public Decimal oldBankGst { get; private set; }
        public Decimal newBankGst { get; private set; }
        public Boolean bankGstChanged { get; private set; }

        public Decimal oldCustomerGst { get; private set; }
        public Decimal newCustomerGst { get; private set; }
        public Boolean customerGstChanged { get; private set; }

        public LineRow(PaymentScheduleRevisionService.RevisionLineDiff d) {
            PaymentScheduleRevisionService.RevisionLine o = d.oldValues;
            PaymentScheduleRevisionService.RevisionLine n = d.newValues;
            milestoneName = d.milestoneName;

            oldPercentage = o != null ? o.percentage : null;
            newPercentage = n != null ? n.percentage : null;
            percentageChanged = differs(oldPercentage, newPercentage);

            oldBaseAmount = o != null ? o.baseAmount : null;
            newBaseAmount = n != null ? n.baseAmount : null;
            baseAmountChanged = differs(oldBaseAmount, newBaseAmount);

            oldGstAmount = o != null ? o.gstAmount : null;
            newGstAmount = n != null ? n.gstAmount : null;
            gstAmountChanged = differs(oldGstAmount, newGstAmount);

            oldTdsAmount = o != null ? o.tdsAmount : null;
            newTdsAmount = n != null ? n.tdsAmount : null;
            tdsAmountChanged = differs(oldTdsAmount, newTdsAmount);

            oldAmount = o != null ? o.amount : null;
            newAmount = n != null ? n.amount : null;
            amountChanged = differs(oldAmount, newAmount);

            oldBankFlat = o != null ? o.bankFlat : null;
            newBankFlat = n != null ? n.bankFlat : null;
            bankFlatChanged = differs(oldBankFlat, newBankFlat);

            oldCustomerFlat = o != null ? o.customerFlat : null;
            newCustomerFlat = n != null ? n.customerFlat : null;
            customerFlatChanged = differs(oldCustomerFlat, newCustomerFlat);

            oldBankGst = o != null ? o.bankGst : null;
            newBankGst = n != null ? n.bankGst : null;
            bankGstChanged = differs(oldBankGst, newBankGst);

            oldCustomerGst = o != null ? o.customerGst : null;
            newCustomerGst = n != null ? n.customerGst : null;
            customerGstChanged = differs(oldCustomerGst, newCustomerGst);
        }

        private Boolean differs(Decimal a, Decimal b) {
            Decimal av = a == null ? 0 : a;
            Decimal bv = b == null ? 0 : b;
            return av != bv;
        }
    }
}