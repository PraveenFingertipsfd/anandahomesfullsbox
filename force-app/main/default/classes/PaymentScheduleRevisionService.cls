/**
 * @description Stages proposed Payment Schedule edits as a Payment_Schedule_Revision__c and
 *              applies them to the Payment Schedule only after the revision is APPROVED.
 *
 *              BRD 8.2: "For each Prorata revision, CRM manager approval is mandatory." This
 *              service generalises that rule to every payment-schedule edit: edits made in the
 *              schedule editors are no longer written directly — they are captured as a JSON
 *              snapshot on a revision record and submitted for approval through the existing
 *              config-driven engine (Approval_Configuration__c / DynamicApprovalService). When
 *              the revision's Approval_Status__c becomes Approved, PaymentScheduleRevisionTrigger
 *              calls applyApproved() to write the values onto Payment_Schedule__c (where the
 *              §8.3.1 prorata invariants are enforced by PaymentScheduleTrigger).
 *
 *              Proposed_Changes_JSON__c stores a RevisionPayload: for every edited milestone it
 *              captures both the pre-edit (oldValues) and resolved post-edit (newValues) line, plus
 *              booking-level before/after totals — so an approver (via the Payment Schedule
 *              Revision Compare VF page) can see exactly what is changing without cross-referencing
 *              the live records. No new custom fields are required; this is purely a change to the
 *              shape of the existing JSON field. applyApprovedFromTrigger() still accepts the older
 *              (pre-comparison-payload) JSON shape as a fallback for any revision already Pending
 *              before this change was deployed.
 * @author System
 */
public without sharing class PaymentScheduleRevisionService {

    /** Process type used to find the Approval_Configuration__c and stamp Approval_Name__c. */
    @TestVisible private static final String PROCESS_TYPE = 'PaymentScheduleRevision';
    private static final String OBJECT_API = 'Payment_Schedule_Revision__c';

    /** Re-entrancy guard for the apply-on-approval trigger. */
    private static Boolean applying = false;

    /** A single proposed line of changes (all fields optional — only non-null ones apply). */
    public class RevisionLine {
        public Id id;
        public Decimal amount;
        public Decimal baseAmount;
        public Decimal gstAmount;
        public Decimal tdsAmount;
        public Decimal percentage;
        public Decimal bankFlat;
        public Decimal customerFlat;
        public Decimal bankGst;
        public Decimal customerGst;
        public Boolean withGst;
    }

    /** Before/after pair for one milestone, for the approver comparison view. */
    public class RevisionLineDiff {
        public Id id;
        public String milestoneName;
        public RevisionLine oldValues;
        public RevisionLine newValues;
    }

    /** Booking-level before/after totals, computed across every milestone (not just edited ones).
     *  Uses explicit properties (not plain member variables) so Visualforce can resolve nested
     *  merge fields like {!totals.oldGrandTotal} on the compare page. */
    public class RevisionTotals {
        public Decimal oldGrandTotal { get; set; }
        public Decimal newGrandTotal { get; set; }
        public Decimal oldPercentageTotal { get; set; }
        public Decimal newPercentageTotal { get; set; }
    }

    /** The full JSON structure persisted to Proposed_Changes_JSON__c. */
    public class RevisionPayload {
        public List<RevisionLineDiff> lines;
        public RevisionTotals totals;
    }

    // ==================== STAGING (called from the editors) ====================

    /**
     * @description Validates the proposed edits against the live triggers/invariants (via a
     *              rolled-back trial update), then stores them (with an old-vs-new comparison) as
     *              a Pending revision and submits it for approval. Throws an AuraHandledException
     *              with the validation message if the proposed values are invalid.
     * @param bookingId The booking the schedules belong to
     * @param lines     The proposed per-schedule changes
     * @param reason    Optional reason for the revision
     * @return the new Payment_Schedule_Revision__c Id
     */
    public static Id stageAndSubmit(Id bookingId, List<RevisionLine> lines, String reason) {
        if (bookingId == null) {
            throw new AuraHandledException('Booking is required.');
        }
        List<RevisionLine> clean = dropEmpty(lines);
        if (clean.isEmpty()) {
            throw new AuraHandledException('There are no editable changes to submit.');
        }

        // Snapshot every schedule on the booking BEFORE any trial update, so the revision can
        // show a full old-vs-new comparison (and booking-level before/after totals) later.
        Map<Id, Payment_Schedule__c> oldRows = new Map<Id, Payment_Schedule__c>([
            SELECT Id, Milestone_Name__c, Master_Payment_Schedule__r.Name,
                   Percentage__c, Payment_Schedule_Amount__c, GST_Amount__c,
                   TDS_Amount__c, Amount__c, Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c, With_GST__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId
        ]);

        // 1. Trial-apply against the real records so all triggers/invariants run, then roll
        //    back so nothing is persisted yet. Surfaces invariant errors before approval.
        Savepoint sp = Database.setSavepoint();
        Boolean trialOk = false;
        try {
            update buildScheduleUpdates(clean);
            trialOk = true;
        } catch (DmlException de) {
            Database.rollback(sp);
            throw new AuraHandledException(
                de.getDmlMessage(0) != null ? de.getDmlMessage(0) : de.getMessage()
            );
        }
        if (trialOk) {
            Database.rollback(sp);
        }

        // 2. Build the old-vs-new comparison payload for the approver.
        RevisionPayload payload = buildComparisonPayload(oldRows, clean);

        // 3. Persist the revision as Pending.
        Payment_Schedule_Revision__c rev = new Payment_Schedule_Revision__c(
            Booking__c = bookingId,
            Approval_Status__c = 'Pending',
            Approval_Name__c = PROCESS_TYPE,
            Proposed_Changes_JSON__c = JSON.serialize(payload),
            Revision_Reason__c = reason,
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_Date__c = System.now(),
            Applied__c = false
        );
        insert rev;

        // 4. Best-effort: submit through the dynamic approval engine if it is configured.
        //    If no Approval_Configuration__c exists yet, the revision simply stays Pending and
        //    can be approved (Approval_Status__c -> Approved) by the approver, which still
        //    triggers the apply.
        trySubmitForApproval(rev.Id);

        return rev.Id;
    }

    private static void trySubmitForApproval(Id revisionId) {
        try {
            List<Approval_Configuration__c> cfgs = [
                SELECT Id FROM Approval_Configuration__c
                WHERE Object_API_Name__c = :OBJECT_API AND Is_Active__c = true
                ORDER BY Sequence_Order__c NULLS LAST
                LIMIT 1
            ];
            if (!cfgs.isEmpty()) {
                DynamicApprovalService.submitForApproval(revisionId, cfgs[0].Id, 'Payment schedule revision');
            }
        } catch (Exception e) {
            // Submission is best-effort; the revision remains Pending for manual approval.
            System.debug('PaymentScheduleRevisionService: approval submit deferred - ' + e.getMessage());
        }
    }

    // ==================== APPLY ON APPROVAL (called from the trigger) ====================

    /**
     * @description From a before-update trigger: for every revision that just moved to Approved
     *              and has not been applied, write the proposed values onto Payment_Schedule__c
     *              and stamp the revision as applied (on the in-memory record, no extra DML).
     */
    public static void applyApprovedFromTrigger(
        List<Payment_Schedule_Revision__c> newList, Map<Id, Payment_Schedule_Revision__c> oldMap
    ) {
        if (applying || newList == null || oldMap == null) return;

        List<Payment_Schedule_Revision__c> toApply = new List<Payment_Schedule_Revision__c>();
        for (Payment_Schedule_Revision__c r : newList) {
            Payment_Schedule_Revision__c old = oldMap.get(r.Id);
            if (old == null) continue;
            Boolean becameApproved = 'Approved'.equalsIgnoreCase(r.Approval_Status__c)
                && !'Approved'.equalsIgnoreCase(old.Approval_Status__c);
            if (becameApproved && r.Applied__c != true) {
                toApply.add(r);
            }
        }
        if (toApply.isEmpty()) return;

        applying = true;
        try {
            for (Payment_Schedule_Revision__c r : toApply) {
                List<RevisionLine> lines = parseNewValues(r.Proposed_Changes_JSON__c);
                List<Payment_Schedule__c> updates = buildScheduleUpdates(lines);
                if (!updates.isEmpty()) {
                    update updates; // PaymentScheduleTrigger enforces §8.3.1 invariants
                }
                // Stamp the revision on the in-memory record (before update → no extra DML).
                r.Applied__c = true;
                r.Applied_Date__c = System.now();
                if (r.Approved_Date__c == null) r.Approved_Date__c = System.now();
                if (r.Approved_By__c == null) r.Approved_By__c = UserInfo.getUserId();
            }
        } catch (DmlException de) {
            // Block the approval if the values can no longer be applied cleanly.
            String msg = de.getDmlMessage(0) != null ? de.getDmlMessage(0) : de.getMessage();
            for (Payment_Schedule_Revision__c r : toApply) {
                r.addError('Approved values could not be applied to the payment schedule: ' + msg);
            }
        } finally {
            applying = false;
        }
    }

    // ==================== HELPERS ====================

    /**
     * @description Builds the old-vs-new comparison payload: a diff for every edited milestone,
     *              plus booking-level before/after totals computed across ALL milestones (so the
     *              approver can confirm the grand total and percentage total are unaffected).
     */
    private static RevisionPayload buildComparisonPayload(
        Map<Id, Payment_Schedule__c> oldRows, List<RevisionLine> edited
    ) {
        Map<Id, RevisionLine> editedById = new Map<Id, RevisionLine>();
        for (RevisionLine l : edited) {
            if (l.id != null) editedById.put(l.id, l);
        }

        Decimal oldGrandTotal = 0, newGrandTotal = 0, oldPctTotal = 0, newPctTotal = 0;
        List<RevisionLineDiff> diffs = new List<RevisionLineDiff>();

        for (Payment_Schedule__c row : oldRows.values()) {
            RevisionLine oldL = toRevisionLine(row);
            oldGrandTotal += nz(oldL.amount);
            oldPctTotal += nz(oldL.percentage);

            RevisionLine editedL = editedById.get(row.Id);
            RevisionLine newL = editedL != null ? resolveNew(oldL, editedL) : oldL;
            newGrandTotal += nz(newL.amount);
            newPctTotal += nz(newL.percentage);

            if (editedL != null) {
                RevisionLineDiff diff = new RevisionLineDiff();
                diff.id = row.Id;
                // Milestone label must never be blank: use the schedule's own Milestone Name, and
                // when that is empty fall back to the linked Master Payment Schedule's Name.
                diff.milestoneName = String.isNotBlank(row.Milestone_Name__c)
                    ? row.Milestone_Name__c
                    : (row.Master_Payment_Schedule__r != null ? row.Master_Payment_Schedule__r.Name : '');
                diff.oldValues = oldL;
                diff.newValues = newL;
                diffs.add(diff);
            }
        }

        RevisionTotals totals = new RevisionTotals();
        totals.oldGrandTotal = oldGrandTotal;
        totals.newGrandTotal = newGrandTotal;
        totals.oldPercentageTotal = oldPctTotal;
        totals.newPercentageTotal = newPctTotal;

        RevisionPayload payload = new RevisionPayload();
        payload.lines = diffs;
        payload.totals = totals;
        return payload;
    }

    private static RevisionLine toRevisionLine(Payment_Schedule__c ps) {
        RevisionLine l = new RevisionLine();
        l.id = ps.Id;
        l.percentage = ps.Percentage__c;
        l.baseAmount = ps.Payment_Schedule_Amount__c;
        l.gstAmount = ps.GST_Amount__c;
        l.tdsAmount = ps.TDS_Amount__c;
        l.amount = ps.Amount__c;
        l.bankFlat = ps.Bank_Flat_Amount__c;
        l.customerFlat = ps.Customer_Flat_Prorata__c;
        l.bankGst = ps.Bank_GST_Amount__c;
        l.customerGst = ps.Customer_GST_Prorata__c;
        l.withGst = ps.With_GST__c;
        return l;
    }

    /** Merges the edited (partial) line onto the old line, recomputing the total the same way
     *  buildScheduleUpdates() does, so newValues reflects the fully resolved post-edit state. */
    private static RevisionLine resolveNew(RevisionLine oldL, RevisionLine edited) {
        RevisionLine n = new RevisionLine();
        n.id = oldL.id;
        n.percentage = edited.percentage != null ? edited.percentage : oldL.percentage;
        n.baseAmount = edited.baseAmount != null ? edited.baseAmount : oldL.baseAmount;
        n.gstAmount = edited.gstAmount != null ? edited.gstAmount : oldL.gstAmount;
        n.tdsAmount = edited.tdsAmount != null ? edited.tdsAmount : oldL.tdsAmount;
        n.bankFlat = edited.bankFlat != null ? edited.bankFlat : oldL.bankFlat;
        n.customerFlat = edited.customerFlat != null ? edited.customerFlat : oldL.customerFlat;
        n.bankGst = edited.bankGst != null ? edited.bankGst : oldL.bankGst;
        n.customerGst = edited.customerGst != null ? edited.customerGst : oldL.customerGst;
        n.withGst = edited.withGst != null ? edited.withGst : oldL.withGst;
        if (n.baseAmount != null && n.gstAmount != null && n.tdsAmount != null) {
            n.amount = n.baseAmount + n.gstAmount + n.tdsAmount;
        } else if (edited.amount != null) {
            n.amount = edited.amount;
        } else {
            n.amount = oldL.amount;
        }
        return n;
    }

    /**
     * @description Extracts the resolved "new" line for every edited milestone from a revision's
     *              JSON, for applying on approval. Supports the current comparison-payload shape,
     *              with a fallback to the older (pre-comparison-payload) plain-array shape for any
     *              revision staged before this change.
     */
    private static List<RevisionLine> parseNewValues(String jsonText) {
        if (String.isBlank(jsonText)) return new List<RevisionLine>();
        try {
            RevisionPayload payload = (RevisionPayload) JSON.deserialize(jsonText, RevisionPayload.class);
            if (payload != null && payload.lines != null && !payload.lines.isEmpty()) {
                List<RevisionLine> result = new List<RevisionLine>();
                for (RevisionLineDiff d : payload.lines) {
                    if (d.newValues != null) {
                        if (d.newValues.id == null) d.newValues.id = d.id;
                        result.add(d.newValues);
                    }
                }
                return result;
            }
        } catch (Exception e) {
            // Fall through to the legacy format below.
        }
        // Legacy format: a plain List<RevisionLine> (no old/new comparison).
        try {
            return (List<RevisionLine>) JSON.deserialize(jsonText, List<RevisionLine>.class);
        } catch (Exception e2) {
            return new List<RevisionLine>();
        }
    }

    private static List<RevisionLine> dropEmpty(List<RevisionLine> lines) {
        List<RevisionLine> result = new List<RevisionLine>();
        if (lines == null) return result;
        for (RevisionLine l : lines) {
            if (l != null && l.id != null && hasAnyValue(l)) result.add(l);
        }
        return result;
    }

    private static Boolean hasAnyValue(RevisionLine l) {
        return l.amount != null || l.baseAmount != null || l.gstAmount != null
            || l.tdsAmount != null || l.percentage != null || l.bankFlat != null
            || l.customerFlat != null || l.bankGst != null || l.customerGst != null
            || l.withGst != null;
    }

    /** Builds Payment_Schedule__c updates, setting only the fields supplied on each line. */
    private static List<Payment_Schedule__c> buildScheduleUpdates(List<RevisionLine> lines) {
        List<Payment_Schedule__c> updates = new List<Payment_Schedule__c>();
        for (RevisionLine l : lines) {
            if (l.id == null) continue;
            Payment_Schedule__c ps = new Payment_Schedule__c(Id = l.id);
            if (l.baseAmount != null) ps.Payment_Schedule_Amount__c = l.baseAmount;
            if (l.gstAmount != null) ps.GST_Amount__c = l.gstAmount;
            // TDS is a single per-milestone value; preserve it as supplied (a prorata split edit
            // changes the Bank/Customer split of the Flat, not the TDS).
            if (l.tdsAmount != null) ps.TDS_Amount__c = l.tdsAmount;
            // Total Payable = Flat + GST + TDS. Recompute when all three components are supplied so
            // the total stays consistent with the breakup; otherwise fall back to the supplied total.
            if (l.baseAmount != null && l.gstAmount != null && l.tdsAmount != null) {
                ps.Amount__c = l.baseAmount + l.gstAmount + l.tdsAmount;
            } else if (l.amount != null) {
                ps.Amount__c = l.amount;
            }
            if (l.percentage != null) ps.Percentage__c = l.percentage;
            if (l.bankFlat != null) ps.Bank_Flat_Amount__c = l.bankFlat;
            if (l.customerFlat != null) ps.Customer_Flat_Prorata__c = l.customerFlat;
            if (l.bankGst != null) ps.Bank_GST_Amount__c = l.bankGst;
            if (l.customerGst != null) ps.Customer_GST_Prorata__c = l.customerGst;
            if (l.withGst != null) ps.With_GST__c = l.withGst;
            updates.add(ps);
        }
        return updates;
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}