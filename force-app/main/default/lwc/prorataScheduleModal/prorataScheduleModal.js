// prorataScheduleModal.js
// Payment schedule Bank/Customer split editor. Runs as a Quick Action modal
// (lightning__RecordAction / ScreenAction) or as a record-page component.
//
// Editable fields: Bank Flat, Customer Flat, Bank GST, Customer GST — nothing else.
// Base, Percentage, GST, TDS and Total are read-only context; they are not sent to the
// server, so they cannot be changed from here.
//
// Rules (mirrored from ProrataInvariantService):
//   per milestone : Bank Flat + Customer Flat = Base ;  Bank GST + Customer GST = GST
//   per booking   : Σ (Bank Flat + Bank GST)  = Loan Sanctioned
//   per booking   : Σ (Cust Flat + Cust GST)  = Deficit − locked-unsplit total  (Prorata/Partial)
//
// TDS is customer-payable but sits OUTSIDE the split, because
// Deficit__c = Grand_Total__c − Loan_Sanctioned_Amount__c − TDS__c.
//
// Locked milestones (demand raised) are never given a split in the UI. Their Base + GST is
// treated as already settled by the customer and comes off the Deficit target instead.
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';
import getSchedulesForEditing from '@salesforce/apex/PaymentScheduleEditorController.getSchedulesForEditing';
import saveEditedSchedules from '@salesforce/apex/PaymentScheduleEditorController.saveEditedSchedules';

/** Currency tolerance. Matches ProrataInvariantService.TOLERANCE. */
const TOLERANCE = 1;

const FLAT = { bank: 'bankFlat', customer: 'customerFlat', target: 'baseAmount' };
const GST = { bank: 'bankGst', customer: 'customerGst', target: 'gstAmount' };

const num = (v) => (v === null || v === undefined || v === '' || isNaN(v) ? 0 : Number(v));
const r2 = (v) => Math.round((num(v) + Number.EPSILON) * 100) / 100;

export default class ProrataScheduleModal extends LightningElement {
    @api recordId;

    @track schedules = [];
    @track totals = {};
    @track issues = [];

    editingEnabled = false;
    isProrata = false;
    isStrictProrata = false;
    fundingType;

    isLoading = true;
    isSaving = false;
    hasError = false;
    errorMessage = '';
    showConfirmClose = false;

    wiredScheduleResult;
    original = new Map();
    live = {};

    // ─── load ────────────────────────────────────────────────────────────────────

    @wire(getSchedulesForEditing, { bookingId: '$recordId' })
    wiredSchedules(result) {
        this.wiredScheduleResult = result;
        if (result.data) {
            this.editingEnabled = result.data.editingEnabled;
            this.isProrata = result.data.isProrata;
            this.isStrictProrata = result.data.isStrictProrata;
            this.fundingType = result.data.fundingType;
            this.totals = result.data.totals || {};
            this.loadRows(result.data.schedules || [], result.data.editingEnabled);
            this.isLoading = false;
            this.hasError = false;
        } else if (result.error) {
            this.isLoading = false;
            this.hasError = true;
            this.errorMessage = this.extractError(result.error);
        }
    }

    loadRows(schedules, editingEnabled) {
        this.original = new Map();
        this.schedules = schedules.map((s) => {
            const canEdit = editingEnabled && s.isEditable;
            const base = num(s.baseAmount);
            const gst = num(s.gstAmount);

            // Never split before? Start the whole milestone on the customer side.
            // Apex omits null fields from the response, so these arrive as undefined rather
            // than null — a loose == null test is required here, not ===.
            const unsplit =
                s.bankFlat == null && s.customerFlat == null &&
                s.bankGst == null && s.customerGst == null;

            // Locked rows are shown exactly as stored — nothing is inferred onto them.
            const seed = canEdit && unsplit;

            const row = {
                ...s,
                baseAmount: base,
                gstAmount: gst,
                tdsAmount: num(s.tdsAmount),
                amount: num(s.amount),
                percentage: num(s.percentage),
                pendingAmount: num(s.pendingAmount),
                bankFlat: seed ? 0 : num(s.bankFlat),
                customerFlat: seed ? base : num(s.customerFlat),
                bankGst: seed ? 0 : num(s.bankGst),
                customerGst: seed ? gst : num(s.customerGst),
                hasSplit: !unsplit,
                canEdit,
                cannotEdit: !canEdit,
                flatAnchor: 'bank',
                gstAnchor: 'bank',
                serverErrors: []
            };
            this.original.set(row.id, {
                bankFlat: row.bankFlat,
                customerFlat: row.customerFlat,
                bankGst: row.bankGst,
                customerGst: row.customerGst
            });
            return row;
        });
        this.recompute();
    }

    // ─── editing: type one side, the other follows ───────────────────────────────

    handleFieldChange(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const raw = event.target.value;
        const value = raw === '' ? 0 : r2(parseFloat(raw));

        this.schedules = this.schedules.map((s) =>
            s.id === id ? this.applyEdit({ ...s }, field, value) : s
        );
        this.recompute();
    }

    /** Sets the edited field and derives its counterpart. Last edited field wins. */
    applyEdit(row, field, value) {
        const pair = field === FLAT.bank || field === FLAT.customer ? FLAT : GST;
        const anchorKey = pair === FLAT ? 'flatAnchor' : 'gstAnchor';
        const target = num(row[pair.target]);

        row[field] = value;
        if (field === pair.bank) {
            row[pair.customer] = r2(target - value);
            row[anchorKey] = 'bank';
        } else {
            row[pair.bank] = r2(target - value);
            row[anchorKey] = 'customer';
        }
        row.serverErrors = [];
        return row;
    }

    /** Moves the whole milestone back to the customer. */
    handleAllToCustomer(event) {
        const id = event.target.dataset.id;
        this.schedules = this.schedules.map((s) =>
            s.id === id && s.canEdit ? this.setBank(s, 0, 0) : s
        );
        this.recompute();
    }

    /** Puts the outstanding loan balance on this milestone, capped at what it can hold. */
    handleFillRemaining(event) {
        const id = event.target.dataset.id;
        const others = this.schedules.reduce(
            (a, s) => (s.id === id ? a : a + num(s.bankFlat) + num(s.bankGst)),
            0
        );
        const outstanding = num(this.totals.loanSanctioned) - others;

        this.schedules = this.schedules.map((s) => {
            if (s.id !== id || !s.canEdit) return s;
            const capacity = num(s.baseAmount) + num(s.gstAmount);
            const give = Math.max(0, Math.min(outstanding, capacity));
            const bankFlat = r2(Math.min(give, num(s.baseAmount)));
            return this.setBank(s, bankFlat, r2(give - bankFlat));
        });
        this.recompute();
    }

    /** Spreads the Loan Sanctioned across editable milestones, pro-rata to Base + GST. */
    handleDistribute() {
        const loan = num(this.totals.loanSanctioned);
        const editable = this.schedules.filter((s) => s.canEdit);
        if (!editable.length || loan <= 0) return;

        const weight = editable.reduce((a, s) => a + num(s.baseAmount) + num(s.gstAmount), 0);
        if (weight <= 0) return;

        const shares = new Map();
        let allocated = 0;
        editable.forEach((s, i) => {
            const capacity = num(s.baseAmount) + num(s.gstAmount);
            let share =
                i === editable.length - 1
                    ? r2(loan - allocated) // residue lands on the last editable milestone
                    : r2((loan * capacity) / weight);
            share = Math.max(0, Math.min(share, capacity));
            allocated = r2(allocated + share);
            shares.set(s.id, share);
        });

        this.schedules = this.schedules.map((s) => {
            if (!shares.has(s.id)) return s;
            const share = shares.get(s.id);
            const bankFlat = r2(Math.min(share, num(s.baseAmount)));
            return this.setBank(s, bankFlat, r2(share - bankFlat));
        });
        this.recompute();
    }

    handleClearAll() {
        this.schedules = this.schedules.map((s) => (s.canEdit ? this.setBank(s, 0, 0) : s));
        this.recompute();
    }

    handleDiscard() {
        this.schedules = this.schedules.map((s) => {
            const o = this.original.get(s.id);
            return o ? { ...s, ...o, flatAnchor: 'bank', gstAnchor: 'bank', serverErrors: [] } : s;
        });
        this.recompute();
    }

    setBank(row, bankFlat, bankGst) {
        return {
            ...row,
            bankFlat,
            bankGst,
            customerFlat: r2(num(row.baseAmount) - bankFlat),
            customerGst: r2(num(row.gstAmount) - bankGst),
            flatAnchor: 'bank',
            gstAnchor: 'bank',
            serverErrors: []
        };
    }

    // ─── derived state: one pass over every row on every change ──────────────────

    recompute() {
        const issues = [];
        let sumBank = 0;
        let sumCust = 0;

        this.schedules = this.schedules.map((row) => {
            const base = num(row.baseAmount);
            const gst = num(row.gstAmount);
            const bf = num(row.bankFlat);
            const cf = num(row.customerFlat);
            const bg = num(row.bankGst);
            const cg = num(row.customerGst);

            const flatBalance = r2(base - bf - cf);
            const gstBalance = r2(gst - bg - cg);
            const bankPayable = r2(bf + bg);
            const customerPayable = r2(cf + cg);
            const label = row.milestoneName || `Milestone ${row.sequence}`;

            const rowIssues = [];
            if (row.canEdit) {
                if (bf < 0 || cf < 0 || bg < 0 || cg < 0) {
                    rowIssues.push({
                        field: bf < 0 ? 'bankFlat' : cf < 0 ? 'customerFlat' : bg < 0 ? 'bankGst' : 'customerGst',
                        message: 'This amount is below zero. Lower the other side of the split.'
                    });
                }
                if (base > 0 && Math.abs(flatBalance) > TOLERANCE) {
                    rowIssues.push({
                        field: row.flatAnchor === 'bank' ? 'customerFlat' : 'bankFlat',
                        message:
                            flatBalance > 0
                                ? `${this.money(flatBalance)} of the ${this.money(base)} base is not assigned to anyone.`
                                : `Flat split is ${this.money(-flatBalance)} more than the ${this.money(base)} base.`
                    });
                }
                if (gst > 0 && Math.abs(gstBalance) > TOLERANCE) {
                    rowIssues.push({
                        field: row.gstAnchor === 'bank' ? 'customerGst' : 'bankGst',
                        message:
                            gstBalance > 0
                                ? `${this.money(gstBalance)} of the ${this.money(gst)} GST is not assigned to anyone.`
                                : `GST split is ${this.money(-gstBalance)} more than the ${this.money(gst)} GST.`
                    });
                }
            }

            const all = [
                ...rowIssues,
                ...(row.serverErrors || []).map((m) => ({ field: null, message: m }))
            ];
            all.forEach((i, n) =>
                issues.push({ ...i, rowId: row.id, label, key: `${row.id}-${i.field || 'row'}-${n}` })
            );

            // Locked, never-split milestones are excluded from the split totals entirely —
            // their amount reduces the Deficit target instead (see effectiveDeficit).
            if (row.canEdit || row.hasSplit) {
                sumBank += bankPayable;
                sumCust += customerPayable;
            }

            const dirty = this.isDirtyRow(row);
            const hasIssue = all.length > 0;
            const balanced = Math.abs(flatBalance) <= TOLERANCE && Math.abs(gstBalance) <= TOLERANCE;

            return {
                ...row,
                flatBalance,
                gstBalance,
                bankPayable,
                customerPayable,
                bankPayableText: this.money(bankPayable),
                customerPayableText: this.money(customerPayable),
                bankFlatText: row.hasSplit || row.canEdit ? this.money(bf) : '—',
                customerFlatText: row.hasSplit || row.canEdit ? this.money(cf) : '—',
                bankGstText: row.hasSplit || row.canEdit ? this.money(bg) : '—',
                customerGstText: row.hasSplit || row.canEdit ? this.money(cg) : '—',
                baseText: this.money(base),
                gstText: this.money(gst),
                tdsText: this.money(row.tdsAmount),
                amountText: this.money(row.amount),
                pendingText: this.money(row.pendingAmount),
                percentageText: `${num(row.percentage)}%`,
                balanced,
                // Locked milestones carry no split by design — their amount comes off the
                // Deficit target instead, so flagging them as "unassigned" is noise.
                showBalance: row.canEdit || row.hasSplit,
                balanceText: this.balanceText(balanced, r2(flatBalance + gstBalance)),
                dirty,
                hasIssue,
                issueText: all.map((i) => i.message).join(' '),
                showAuto: row.canEdit,
                flatAutoOnCustomer: row.flatAnchor === 'bank',
                flatAutoOnBank: row.flatAnchor === 'customer',
                gstAutoOnCustomer: row.gstAnchor === 'bank',
                gstAutoOnBank: row.gstAnchor === 'customer',
                cardClass: this.cardClass(row, hasIssue, dirty),
                balanceClass: balanced ? 'ms-balance ms-balance-ok' : 'ms-balance ms-balance-off',
                statusClass: this.statusClass(row.status),
                bankFlatClass: this.inputClass(all, 'bankFlat', row.flatAnchor === 'customer'),
                customerFlatClass: this.inputClass(all, 'customerFlat', row.flatAnchor === 'bank'),
                bankGstClass: this.inputClass(all, 'bankGst', row.gstAnchor === 'customer'),
                customerGstClass: this.inputClass(all, 'customerGst', row.gstAnchor === 'bank')
            };
        });

        const loan = this.loanSanctioned;
        const bankVariance = loan === null ? 0 : r2(sumBank - loan);
        if (this.isProrata && loan !== null && loan !== 0 && Math.abs(bankVariance) > TOLERANCE) {
            issues.push({
                rowId: null,
                key: 'booking-bank',
                label: 'Loan Sanctioned',
                message:
                    bankVariance < 0
                        ? `${this.money(Math.abs(bankVariance))} of the loan is still unallocated.`
                        : `Bank Payable is over the loan by ${this.money(bankVariance)}.`
            });
        }

        const target = this.effectiveDeficit;
        const custVariance = target === null ? 0 : r2(sumCust - target);
        if (this.isStrictProrata && target !== null && Math.abs(custVariance) > TOLERANCE) {
            issues.push({
                rowId: null,
                key: 'booking-cust',
                label: 'Deficit',
                message: `Customer Payable is ${this.signed(custVariance)} against a target of ${this.money(target)}.`
            });
        }

        this.issues = issues;
        this.live = { sumBank, sumCust, bankVariance, custVariance, remaining: loan === null ? 0 : r2(loan - sumBank) };
    }

    balanceText(balanced, remainder) {
        if (balanced) return 'Balanced';
        return remainder > 0
            ? `${this.money(remainder)} unassigned`
            : `${this.money(-remainder)} over`;
    }

    isDirtyRow(row) {
        const o = this.original.get(row.id);
        if (!o) return false;
        return (
            num(o.bankFlat) !== num(row.bankFlat) ||
            num(o.customerFlat) !== num(row.customerFlat) ||
            num(o.bankGst) !== num(row.bankGst) ||
            num(o.customerGst) !== num(row.customerGst)
        );
    }

    cardClass(row, hasIssue, dirty) {
        let c = 'ms-card';
        if (!row.canEdit) c += ' ms-card-locked';
        if (hasIssue) c += ' ms-card-error';
        else if (dirty) c += ' ms-card-dirty';
        return c;
    }

    inputClass(issues, field, derived) {
        let c = 'ms-input';
        if (derived) c += ' ms-derived';
        if (issues.some((i) => i.field === field)) c += ' ms-invalid';
        return c;
    }

    statusClass(status) {
        const st = (status || '').toLowerCase();
        if (st.indexOf('paid') > -1 && st.indexOf('partial') === -1) return 'psm-badge psm-badge-paid';
        if (st.indexOf('complete') > -1) return 'psm-badge psm-badge-completed';
        return 'psm-badge psm-badge-pending';
    }

    // ─── totals ──────────────────────────────────────────────────────────────────

    get loanSanctioned() {
        return this.totals && this.totals.loanSanctioned != null ? num(this.totals.loanSanctioned) : null;
    }
    get deficit() {
        return this.totals && this.totals.deficit != null ? num(this.totals.deficit) : null;
    }
    get lockedUnsplitTotal() {
        return num(this.totals ? this.totals.lockedUnsplitTotal : 0);
    }
    get effectiveDeficit() {
        if (this.totals && this.totals.deficitTarget != null) return num(this.totals.deficitTarget);
        return this.deficit === null ? null : this.deficit - this.lockedUnsplitTotal;
    }
    get hasLockedUnsplit() {
        return this.lockedUnsplitTotal > 0;
    }

    get grandTotalText() { return this.money(this.totals ? this.totals.grandTotal : 0); }
    get loanSanctionedText() { return this.money(this.loanSanctioned); }
    get deficitText() { return this.money(this.deficit); }
    get effectiveDeficitText() { return this.money(this.effectiveDeficit); }
    get lockedUnsplitTotalText() { return this.money(this.lockedUnsplitTotal); }
    get totalTdsText() { return this.money(this.totals ? this.totals.totalTds : 0); }
    get sumBankText() { return this.money(this.live.sumBank); }
    get sumCustText() { return this.money(this.live.sumCust); }

    get bankClass() {
        return Math.abs(this.live.bankVariance || 0) <= TOLERANCE
            ? 'recon-value recon-ok'
            : 'recon-value recon-off';
    }
    get custClass() {
        return Math.abs(this.live.custVariance || 0) <= TOLERANCE
            ? 'recon-value recon-ok'
            : 'recon-value recon-off';
    }

    // ─── allocation meter ────────────────────────────────────────────────────────

    get remainingText() {
        const r = this.live.remaining || 0;
        if (this.loanSanctioned === null) return 'No loan sanctioned on this booking';
        if (Math.abs(r) <= TOLERANCE) return 'Loan fully allocated';
        return r > 0
            ? `${this.money(r)} left to allocate`
            : `${this.money(Math.abs(r))} over-allocated`;
    }

    get meterClass() {
        const r = this.live.remaining || 0;
        if (this.loanSanctioned === null) return 'alloc-meter alloc-none';
        if (Math.abs(r) <= TOLERANCE) return 'alloc-meter alloc-ok';
        return r > 0 ? 'alloc-meter alloc-under' : 'alloc-meter alloc-over';
    }

    // ─── flags ───────────────────────────────────────────────────────────────────

    get hasSchedules() {
        return this.schedules && this.schedules.length > 0;
    }
    get isDirty() {
        return this.schedules.some((s) => s.dirty);
    }
    get hasIssues() {
        return this.issues.length > 0;
    }
    get issueHeading() {
        return this.issues.length === 1
            ? '1 issue to fix before you can send this'
            : `${this.issues.length} issues to fix before you can send this`;
    }
    get saveDisabled() {
        return this.isSaving || !this.editingEnabled || !this.isDirty;
    }
    get footerNote() {
        if (this.isSaving) return 'Sending…';
        if (!this.editingEnabled) return 'This booking is read-only.';
        if (!this.isDirty) return 'Change a split to send it for approval.';
        if (this.hasIssues) return this.issueHeading;
        return 'Ready to send for approval.';
    }

    // ─── submit ──────────────────────────────────────────────────────────────────

    handleSave() {
        if (this.hasIssues) {
            this.focusIssue(this.issues[0]);
            return;
        }
        this.submit();
    }

    async submit() {
        this.isSaving = true;
        try {
            const payload = this.schedules
                .filter((s) => s.canEdit && s.dirty)
                .map((s) => ({
                    id: s.id,
                    sequence: s.sequence,
                    milestoneName: s.milestoneName,
                    baseAmount: s.baseAmount,
                    gstAmount: s.gstAmount,
                    bankFlat: s.bankFlat,
                    customerFlat: s.customerFlat,
                    bankGst: s.bankGst,
                    customerGst: s.customerGst
                }));

            await saveEditedSchedules({
                bookingId: this.recordId,
                schedulesJson: JSON.stringify(payload),
                reason: null
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Sent for approval',
                    message: 'The split will be applied to the payment schedule once it is approved.',
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredScheduleResult);
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.mapServerError(this.extractError(error));
        } finally {
            this.isSaving = false;
        }
    }

    /** Attaches each server message to the milestone it names, so it lands on the right card. */
    mapServerError(message) {
        const lines = String(message)
            .split('\n')
            .map((l) => l.replace(/^[•\s]+/, '').trim())
            .filter(Boolean);
        let matched = false;

        this.schedules = this.schedules.map((s) => {
            const own = s.milestoneName
                ? lines.filter((l) => l.toLowerCase().includes(s.milestoneName.toLowerCase()))
                : [];
            if (own.length) matched = true;
            return { ...s, serverErrors: own };
        });
        this.recompute();

        if (!matched) {
            this.hasError = true;
            this.errorMessage = message;
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Not sent',
                message: matched ? 'Fix the milestones marked below, then send again.' : message,
                variant: 'error'
            })
        );
    }

    handleIssueClick(event) {
        const key = event.currentTarget.dataset.key;
        this.focusIssue(this.issues.find((i) => i.key === key));
    }

    focusIssue(issue) {
        if (!issue) return;
        if (!issue.rowId) {
            const panel = this.template.querySelector('.issue-panel');
            if (panel) panel.scrollIntoView({ behavior: 'smooth', block: 'center' });
            return;
        }
        const card = this.template.querySelector(`[data-card="${issue.rowId}"]`);
        if (card) {
            card.scrollIntoView({ behavior: 'smooth', block: 'center' });
            card.classList.add('ms-flash');
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => card.classList.remove('ms-flash'), 1200);
        }
        if (issue.field) {
            const input = this.template.querySelector(
                `[data-id="${issue.rowId}"][data-field="${issue.field}"]`
            );
            if (input) input.focus();
        }
    }

    // ─── close ───────────────────────────────────────────────────────────────────

    handleClose() {
        if (this.isDirty) {
            this.showConfirmClose = true;
            return;
        }
        this.close();
    }
    handleConfirmClose() {
        this.showConfirmClose = false;
        this.close();
    }
    handleCancelClose() {
        this.showConfirmClose = false;
    }
    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ─── formatting ──────────────────────────────────────────────────────────────

    money(v) {
        if (v === null || v === undefined) return '—';
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 2
        }).format(num(v));
    }

    signed(v) {
        const n = r2(v);
        return `${n > 0 ? '+' : ''}${this.money(n)}`;
    }

    extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.body && Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join('\n');
        }
        if (error && error.message) return error.message;
        return 'Something went wrong. Try again.';
    }
}