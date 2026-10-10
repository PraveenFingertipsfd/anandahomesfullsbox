/**
 * Payment Schedule Split Editor.
 *
 * Only the four split fields are editable: Bank Flat, Customer Flat, Bank GST, Customer GST.
 * Entering one side of a pair derives the other (last-edited-wins), so the user allocates the
 * bank's share and the customer's share follows.
 *
 * Rules mirrored from ProrataInvariantService:
 *   row   : Bank Flat + Customer Flat = Base ;  Bank GST + Customer GST = GST
 *   bank  : Σ (Bank Flat + Bank GST)   = Loan Sanctioned
 *   cust  : Σ (Cust Flat + Cust GST)   = Deficit − locked-unsplit total   (Prorata/Partial only)
 * TDS is customer-payable but sits outside the split, because
 * Deficit__c = Grand_Total__c − Loan_Sanctioned_Amount__c − TDS__c.
 */
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';
import getSchedulesForEditing from '@salesforce/apex/PaymentScheduleEditorController.getSchedulesForEditing';
import saveEditedSchedules from '@salesforce/apex/PaymentScheduleEditorController.saveEditedSchedules';

/** Currency tolerance. Matches ProrataInvariantService.TOLERANCE. */
const TOLERANCE = 1;

const FLAT_PAIR = { bank: 'bankFlat', customer: 'customerFlat', target: 'baseAmount' };
const GST_PAIR = { bank: 'bankGst', customer: 'customerGst', target: 'gstAmount' };

const num = (v) => (v === null || v === undefined || v === '' || isNaN(v) ? 0 : Number(v));
const round2 = (v) => Math.round((num(v) + Number.EPSILON) * 100) / 100;

export default class ProrataScheduleEditor extends LightningElement {
    @api recordId;

    @track rows = [];
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

    wiredResult;
    original = new Map();

    // ─── Data ────────────────────────────────────────────────────────────────

    @wire(getSchedulesForEditing, { bookingId: '$recordId' })
    wiredSchedules(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.editingEnabled = data.editingEnabled;
            this.isProrata = data.isProrata;
            this.isStrictProrata = data.isStrictProrata;
            this.fundingType = data.fundingType;
            this.totals = data.totals || {};
            this.loadRows(data.schedules || [], data.editingEnabled);
            this.isLoading = false;
            this.hasError = false;
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            this.errorMessage = this.extractError(error);
        }
    }

    loadRows(schedules, editingEnabled) {
        this.original = new Map();
        this.rows = schedules.map((s) => {
            const canEdit = editingEnabled && s.isEditable;
            const base = num(s.baseAmount);
            const gst = num(s.gstAmount);

            // A row with no split recorded starts fully with the customer.
            const seeded = s.bankFlat === null && s.customerFlat === null
                && s.bankGst === null && s.customerGst === null;

            const row = {
                ...s,
                baseAmount: base,
                gstAmount: gst,
                tdsAmount: num(s.tdsAmount),
                amount: num(s.amount),
                bankFlat: seeded ? 0 : num(s.bankFlat),
                customerFlat: seeded ? base : num(s.customerFlat),
                bankGst: seeded ? 0 : num(s.bankGst),
                customerGst: seeded ? gst : num(s.customerGst),
                canEdit,
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

    // ─── Editing ─────────────────────────────────────────────────────────────

    handleFieldChange(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const raw = event.target.value;
        const value = raw === '' ? 0 : round2(parseFloat(raw));

        this.rows = this.rows.map((row) => {
            if (row.id !== id) return row;
            return this.applyEdit({ ...row }, field, value);
        });
        this.recompute();
    }

    /** Sets the edited field and derives its counterpart. Last edited field wins. */
    applyEdit(row, field, value) {
        const pair = field === FLAT_PAIR.bank || field === FLAT_PAIR.customer ? FLAT_PAIR : GST_PAIR;
        const target = num(row[pair.target]);
        const anchorKey = pair === FLAT_PAIR ? 'flatAnchor' : 'gstAnchor';

        row[field] = value;
        if (field === pair.bank) {
            row[pair.customer] = round2(target - value);
            row[anchorKey] = 'bank';
        } else {
            row[pair.bank] = round2(target - value);
            row[anchorKey] = 'customer';
        }
        row.serverErrors = [];
        return row;
    }

    handleResetRow(event) {
        const id = event.target.dataset.id;
        this.rows = this.rows.map((row) => {
            if (row.id !== id || !row.canEdit) return row;
            return {
                ...row,
                bankFlat: 0,
                customerFlat: num(row.baseAmount),
                bankGst: 0,
                customerGst: num(row.gstAmount),
                flatAnchor: 'bank',
                gstAnchor: 'bank',
                serverErrors: []
            };
        });
        this.recompute();
    }

    /** Puts the whole outstanding bank balance on this row, capped at what the row can hold. */
    handleFillRemaining(event) {
        const id = event.target.dataset.id;
        const outstanding = num(this.totals.loanSanctioned) - this.sumBankPayable(id);

        this.rows = this.rows.map((row) => {
            if (row.id !== id || !row.canEdit) return row;
            const capacity = num(row.baseAmount) + num(row.gstAmount);
            const give = Math.max(0, Math.min(outstanding, capacity));
            const bankFlat = round2(Math.min(give, num(row.baseAmount)));
            const bankGst = round2(give - bankFlat);
            return {
                ...row,
                bankFlat,
                customerFlat: round2(num(row.baseAmount) - bankFlat),
                bankGst,
                customerGst: round2(num(row.gstAmount) - bankGst),
                flatAnchor: 'bank',
                gstAnchor: 'bank',
                serverErrors: []
            };
        });
        this.recompute();
    }

    /** Sum of bank payable across every row except the one being filled. */
    sumBankPayable(excludeId) {
        return this.rows.reduce(
            (acc, r) => (r.id === excludeId ? acc : acc + num(r.bankFlat) + num(r.bankGst)),
            0
        );
    }

    handleDistribute() {
        const loan = num(this.totals.loanSanctioned);
        const editable = this.rows.filter((r) => r.canEdit);
        if (!editable.length || loan <= 0) return;

        const weight = editable.reduce((a, r) => a + num(r.baseAmount) + num(r.gstAmount), 0);
        if (weight <= 0) return;

        const shares = new Map();
        let allocated = 0;
        editable.forEach((r, i) => {
            const capacity = num(r.baseAmount) + num(r.gstAmount);
            let share;
            if (i === editable.length - 1) {
                share = round2(loan - allocated); // residue lands on the last editable row
            } else {
                share = round2((loan * capacity) / weight);
            }
            share = Math.max(0, Math.min(share, capacity));
            allocated = round2(allocated + share);
            shares.set(r.id, share);
        });

        this.rows = this.rows.map((row) => {
            if (!shares.has(row.id)) return row;
            const share = shares.get(row.id);
            const bankFlat = round2(Math.min(share, num(row.baseAmount)));
            const bankGst = round2(share - bankFlat);
            return {
                ...row,
                bankFlat,
                customerFlat: round2(num(row.baseAmount) - bankFlat),
                bankGst,
                customerGst: round2(num(row.gstAmount) - bankGst),
                flatAnchor: 'bank',
                gstAnchor: 'bank',
                serverErrors: []
            };
        });
        this.recompute();
    }

    handleClearAll() {
        this.rows = this.rows.map((row) =>
            row.canEdit
                ? {
                      ...row,
                      bankFlat: 0,
                      customerFlat: num(row.baseAmount),
                      bankGst: 0,
                      customerGst: num(row.gstAmount),
                      flatAnchor: 'bank',
                      gstAnchor: 'bank',
                      serverErrors: []
                  }
                : row
        );
        this.recompute();
    }

    handleDiscard() {
        this.rows = this.rows.map((row) => {
            const o = this.original.get(row.id);
            return o ? { ...row, ...o, flatAnchor: 'bank', gstAnchor: 'bank', serverErrors: [] } : row;
        });
        this.recompute();
    }

    // ─── Derived state ───────────────────────────────────────────────────────

    /** Recomputes per-row figures, validation and booking totals. Single pass, called on
     *  every change so the user watches the variances converge as they type. */
    recompute() {
        const issues = [];
        let sumBank = 0;
        let sumCust = 0;
        let sumBase = 0;
        let sumGst = 0;
        let sumTds = 0;
        let sumAmount = 0;

        this.rows = this.rows.map((row) => {
            const base = num(row.baseAmount);
            const gst = num(row.gstAmount);
            const bf = num(row.bankFlat);
            const cf = num(row.customerFlat);
            const bg = num(row.bankGst);
            const cg = num(row.customerGst);

            const flatBalance = round2(base - bf - cf);
            const gstBalance = round2(gst - bg - cg);
            const bankPayable = round2(bf + bg);
            const customerPayable = round2(cf + cg);

            const label = row.milestoneName || `Milestone ${row.sequence}`;
            const rowIssues = [];

            if (bf < 0 || cf < 0 || bg < 0 || cg < 0) {
                rowIssues.push({
                    field: bf < 0 ? 'bankFlat' : cf < 0 ? 'customerFlat' : bg < 0 ? 'bankGst' : 'customerGst',
                    message: 'This amount is below zero. Reduce the other side of the split.'
                });
            }
            if (base > 0 && Math.abs(flatBalance) > TOLERANCE) {
                rowIssues.push({
                    field: row.flatAnchor === 'bank' ? 'customerFlat' : 'bankFlat',
                    message: `Flat split is ${this.signed(flatBalance)} against a base of ${this.money(base)}.`
                });
            }
            if (gst > 0 && Math.abs(gstBalance) > TOLERANCE) {
                rowIssues.push({
                    field: row.gstAnchor === 'bank' ? 'customerGst' : 'bankGst',
                    message: `GST split is ${this.signed(gstBalance)} against GST of ${this.money(gst)}.`
                });
            }

            const allIssues = [
                ...rowIssues,
                ...(row.serverErrors || []).map((m) => ({ field: null, message: m }))
            ];
            allIssues.forEach((i) => issues.push({ ...i, rowId: row.id, label, key: `${row.id}-${i.field || 'row'}-${issues.length}` }));

            sumBank += bankPayable;
            sumCust += customerPayable;
            sumBase += base;
            sumGst += gst;
            sumTds += num(row.tdsAmount);
            sumAmount += num(row.amount);

            const dirty = this.isRowDirty(row);
            const hasIssue = allIssues.length > 0;

            return {
                ...row,
                flatBalance,
                gstBalance,
                bankPayable,
                customerPayable,
                rowBalanced: Math.abs(flatBalance) <= TOLERANCE && Math.abs(gstBalance) <= TOLERANCE,
                balanceLabel: this.signed(round2(flatBalance + gstBalance)),
                dirty,
                hasIssue,
                issueText: allIssues.map((i) => i.message).join(' '),
                bankFlatInvalid: allIssues.some((i) => i.field === 'bankFlat'),
                customerFlatInvalid: allIssues.some((i) => i.field === 'customerFlat'),
                bankGstInvalid: allIssues.some((i) => i.field === 'bankGst'),
                customerGstInvalid: allIssues.some((i) => i.field === 'customerGst'),
                flatDerivedIsCustomer: row.flatAnchor === 'bank',
                gstDerivedIsCustomer: row.gstAnchor === 'bank',
                rowClass: this.rowClass(row, hasIssue, dirty),
                bankFlatClass: this.cellClass(allIssues, 'bankFlat', row.flatAnchor !== 'bank'),
                customerFlatClass: this.cellClass(allIssues, 'customerFlat', row.flatAnchor === 'bank'),
                bankGstClass: this.cellClass(allIssues, 'bankGst', row.gstAnchor !== 'bank'),
                customerGstClass: this.cellClass(allIssues, 'customerGst', row.gstAnchor === 'bank'),
                balanceClass: Math.abs(flatBalance + gstBalance) <= TOLERANCE
                    ? 'psp-balance psp-ok'
                    : 'psp-balance psp-off'
            };
        });

        // Booking-level checks.
        const loan = num(this.totals.loanSanctioned);
        const bankVariance = round2(sumBank - loan);
        if (loan > 0 && Math.abs(bankVariance) > TOLERANCE) {
            issues.push({
                rowId: null,
                key: 'booking-bank',
                label: 'Loan Sanctioned',
                message:
                    bankVariance < 0
                        ? `${this.money(Math.abs(bankVariance))} of the loan is still unallocated.`
                        : `Bank Payable exceeds the loan by ${this.money(bankVariance)}.`
            });
        }

        const deficitTarget = this.totals.deficitTarget === null || this.totals.deficitTarget === undefined
            ? null
            : num(this.totals.deficitTarget);
        const custVariance = deficitTarget === null ? 0 : round2(sumCust - deficitTarget);
        if (this.isStrictProrata && deficitTarget !== null && Math.abs(custVariance) > TOLERANCE) {
            issues.push({
                rowId: null,
                key: 'booking-cust',
                label: 'Deficit',
                message: `Customer Payable is ${this.signed(custVariance)} against a target of ${this.money(deficitTarget)}. Submission will be rejected.`
            });
        }

        this.issues = issues;
        this.live = {
            sumBank,
            sumCust,
            sumBase,
            sumGst,
            sumTds,
            sumAmount,
            bankVariance,
            custVariance,
            remaining: round2(loan - sumBank),
            deficitTarget
        };
    }

    isRowDirty(row) {
        const o = this.original.get(row.id);
        if (!o) return false;
        return (
            num(o.bankFlat) !== num(row.bankFlat) ||
            num(o.customerFlat) !== num(row.customerFlat) ||
            num(o.bankGst) !== num(row.bankGst) ||
            num(o.customerGst) !== num(row.customerGst)
        );
    }

    rowClass(row, hasIssue, dirty) {
        let c = 'psp-row';
        if (!row.canEdit) c += ' psp-locked';
        if (hasIssue) c += ' psp-row-error';
        else if (dirty) c += ' psp-row-dirty';
        return c;
    }

    cellClass(issues, field, derived) {
        let c = 'psp-input';
        if (derived) c += ' psp-derived';
        if (issues.some((i) => i.field === field)) c += ' psp-invalid';
        return c;
    }

    // ─── Getters for the template ────────────────────────────────────────────

    get hasRows() {
        return this.rows && this.rows.length > 0;
    }

    get isDirty() {
        return this.rows.some((r) => r.dirty);
    }

    get blockingIssues() {
        return this.issues;
    }

    get hasIssues() {
        return this.issues.length > 0;
    }

    get issueCount() {
        return this.issues.length;
    }

    get issueHeading() {
        return this.issues.length === 1
            ? '1 issue to fix before you can submit'
            : `${this.issues.length} issues to fix before you can submit`;
    }

    get remainingLabel() {
        const r = this.live ? this.live.remaining : 0;
        if (Math.abs(r) <= TOLERANCE) return 'Fully allocated';
        return r > 0 ? `${this.money(r)} left to allocate` : `${this.money(Math.abs(r))} over-allocated`;
    }

    get remainingClass() {
        const r = this.live ? this.live.remaining : 0;
        if (Math.abs(r) <= TOLERANCE) return 'psp-meter psp-meter-ok';
        return r > 0 ? 'psp-meter psp-meter-under' : 'psp-meter psp-meter-over';
    }

    get bankVarianceClass() {
        return Math.abs(this.live ? this.live.bankVariance : 0) <= TOLERANCE
            ? 'psp-total psp-ok'
            : 'psp-total psp-off';
    }

    get custVarianceClass() {
        return Math.abs(this.live ? this.live.custVariance : 0) <= TOLERANCE
            ? 'psp-total psp-ok'
            : 'psp-total psp-off';
    }

    get sumBank() { return this.live ? this.live.sumBank : 0; }
    get sumCust() { return this.live ? this.live.sumCust : 0; }
    get sumBase() { return this.live ? this.live.sumBase : 0; }
    get sumGst() { return this.live ? this.live.sumGst : 0; }
    get sumTds() { return this.live ? this.live.sumTds : 0; }
    get sumAmount() { return this.live ? this.live.sumAmount : 0; }
    get bankVariance() { return this.live ? this.live.bankVariance : 0; }
    get custVariance() { return this.live ? this.live.custVariance : 0; }
    get deficitTarget() { return this.live ? this.live.deficitTarget : null; }

    get showDeficitRow() {
        return this.isStrictProrata && this.deficitTarget !== null;
    }

    get lockedUnsplitTotal() {
        return num(this.totals.lockedUnsplitTotal);
    }

    get hasLockedUnsplit() {
        return this.lockedUnsplitTotal > 0;
    }

    get submitDisabled() {
        return this.isSaving || !this.editingEnabled || !this.isDirty;
    }

    get submitReason() {
        if (this.isSaving) return 'Submitting…';
        if (!this.editingEnabled) return 'Editing is switched off for this booking.';
        if (!this.isDirty) return 'Change a split to submit.';
        if (this.hasIssues) return this.issueHeading;
        return '';
    }

    get showSubmitReason() {
        return this.submitReason !== '';
    }

    // ─── Submit ──────────────────────────────────────────────────────────────

    handleSubmitClick() {
        if (this.hasIssues) {
            this.focusIssue(this.issues[0]);
            return;
        }
        this.submit();
    }

    async submit() {
        this.isSaving = true;
        try {
            const payload = this.rows
                .filter((r) => r.canEdit && r.dirty)
                .map((r) => ({
                    id: r.id,
                    sequence: r.sequence,
                    milestoneName: r.milestoneName,
                    baseAmount: r.baseAmount,
                    gstAmount: r.gstAmount,
                    bankFlat: r.bankFlat,
                    customerFlat: r.customerFlat,
                    bankGst: r.bankGst,
                    customerGst: r.customerGst
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
            await refreshApex(this.wiredResult);
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.mapServerError(this.extractError(error));
        } finally {
            this.isSaving = false;
        }
    }

    /** Attaches a server message to the milestone it names, so it lands on the right row. */
    mapServerError(message) {
        const lines = String(message).split('\n').map((l) => l.replace(/^[•\s]+/, '').trim()).filter(Boolean);
        let matched = false;

        this.rows = this.rows.map((row) => {
            const own = lines.filter(
                (l) => row.milestoneName && l.toLowerCase().includes(row.milestoneName.toLowerCase())
            );
            if (own.length) matched = true;
            return own.length ? { ...row, serverErrors: own } : { ...row, serverErrors: [] };
        });

        this.recompute();

        if (!matched) {
            this.hasError = true;
            this.errorMessage = message;
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Not submitted',
                message: matched ? 'Fix the milestones marked below and submit again.' : message,
                variant: 'error'
            })
        );
    }

    focusIssue(issue) {
        if (!issue || !issue.rowId) {
            const panel = this.template.querySelector('.psp-issues');
            if (panel) panel.scrollIntoView({ behavior: 'smooth', block: 'center' });
            return;
        }
        const el = this.template.querySelector(`tr[data-row="${issue.rowId}"]`);
        if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            el.classList.add('psp-flash');
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => el.classList.remove('psp-flash'), 1200);
        }
        const input = this.template.querySelector(
            `[data-id="${issue.rowId}"][data-field="${issue.field}"]`
        );
        if (input) input.focus();
    }

    handleIssueClick(event) {
        const key = event.currentTarget.dataset.key;
        this.focusIssue(this.issues.find((i) => i.key === key));
    }

    // ─── Close ───────────────────────────────────────────────────────────────

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

    // ─── Formatting ──────────────────────────────────────────────────────────

    money(v) {
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 2
        }).format(num(v));
    }

    signed(v) {
        const n = round2(v);
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