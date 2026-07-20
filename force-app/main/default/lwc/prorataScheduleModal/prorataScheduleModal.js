// prorataScheduleModal.js
// Editor for payment schedules with Prorata / Partial split columns. Works both as a
// record-page component and as a Quick Action modal (lightning__RecordAction / ScreenAction).
// Backed by PaymentScheduleEditorController, which locks any milestone that is
// demand-raised, paid, or closed, and validates the §8.3.1 prorata invariants on save.
//
// Locked milestones (read-only) are NEVER given a Bank/Customer split in the UI, even if
// they were never split before — their Bank Payable / Customer Payable boxes stay exactly
// as stored (usually blank). Instead, when the reconciliation totals are computed, a locked
// milestone that has no split on record has its Base + GST amount treated as already
// settled by the customer and subtracted from the Deficit target, so only the editable
// (and already-split) milestones need to sum up to the reduced figure. This mirrors
// ProrataInvariantService.isLocked() / the Deficit-minus-lockedUnsplitTotal logic on save.
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';
import getSchedulesForEditing from '@salesforce/apex/PaymentScheduleEditorController.getSchedulesForEditing';
import saveEditedSchedules from '@salesforce/apex/PaymentScheduleEditorController.saveEditedSchedules';

const NUMERIC_FIELDS = new Set([
    'percentage', 'baseAmount', 'gstAmount', 'tdsAmount', 'amount',
    'bankFlat', 'customerFlat', 'bankGst', 'customerGst'
]);

const num = (v) => (v === null || v === undefined || v === '' ? 0 : parseFloat(v));

export default class ProrataScheduleModal extends LightningElement {
    @api recordId;

    @track schedules = [];
    @track totals = {};
    @track editingEnabled = false;
    @track isProrata = false;        // bank-funded → show Bank/Customer split columns
    @track isStrictProrata = false;  // Prorata/Partial → enforce Customer Flat total = Deficit
    fundingType;
    originalTotal = 0;
    @track isLoading = true;
    @track isSaving = false;
    @track hasError = false;
    @track errorMessage = '';

    wiredScheduleResult;

    @wire(getSchedulesForEditing, { bookingId: '$recordId' })
    wiredSchedules(result) {
        this.wiredScheduleResult = result;
        if (result.data) {
            this.editingEnabled = result.data.editingEnabled;
            this.isProrata = result.data.isProrata;
            this.isStrictProrata = result.data.isStrictProrata;
            this.fundingType = result.data.fundingType;
            this.totals = result.data.totals || {};
            this.schedules = (result.data.schedules || []).map((s) => this.decorate(s));
            // Capture the grand total to preserve (sum of Base + GST at load time).
            this.originalTotal = this.schedules.reduce(
                (a, s) => a + num(s.baseAmount) + num(s.gstAmount), 0
            );
            this.isLoading = false;
            this.hasError = false;
        } else if (result.error) {
            this.isLoading = false;
            this.hasError = true;
            this.errorMessage = this.extractError(result.error);
        }
    }

    decorate(s) {
        const canEdit = this.editingEnabled && s.isEditable;
        // Was any split ever recorded for this milestone? Locked rows with no split on
        // record predate the split feature (or were never split) — we never write to
        // them, and we don't display an assumed value either. Their amount is only used,
        // later, to reduce the Deficit target (see lockedUnsplitTotal / effectiveDeficit).
        const hasSplit = s.bankFlat != null || s.bankGst != null
            || s.customerFlat != null || s.customerGst != null;
        const liveTotal = num(s.baseAmount) + num(s.gstAmount);
        const deficitAlloc = num(s.customerFlat);
        const st = (s.status || '').toLowerCase();
        let statusClass = 'psm-badge psm-badge-pending';
        if (st.indexOf('paid') > -1 && st.indexOf('partial') === -1) statusClass = 'psm-badge psm-badge-paid';
        else if (st.indexOf('complete') > -1) statusClass = 'psm-badge psm-badge-completed';
        const withGstText = s.withGst === true ? 'Yes' : 'No';
        return { ...s, canEdit, cannotEdit: !canEdit, hasSplit, liveTotal, deficitAlloc, statusClass, withGstText };
    }

    // ─── live running totals ────────────────────────────────────────────────────

    sumOf(field) {
        return this.schedules.reduce((a, s) => a + num(s[field]), 0);
    }
    get sumPercentage() { return this.sumOf('percentage'); }
    // Bank/Customer Payable = Flat + GST.
    get sumBankFlat() { return this.sumOf('bankFlat') + this.sumOf('bankGst'); }
    get sumCustomerFlat() { return this.sumOf('customerFlat') + this.sumOf('customerGst'); }
    get sumTotal() {
        return this.schedules.reduce((a, s) => a + num(s.baseAmount) + num(s.gstAmount), 0);
    }
    get loanSanctioned() { return this.totals && this.totals.loanSanctioned != null ? num(this.totals.loanSanctioned) : null; }
    get deficit() { return this.totals && this.totals.deficit != null ? num(this.totals.deficit) : null; }
    get tolerance() { return Math.max(1, this.originalTotal * 0.0001); }

    // Sum of Flat+GST for locked milestones that were never split — excluded from the UI
    // split boxes and from sumCustomerFlat/sumBankFlat entirely (their fields stay null),
    // but their amount is treated as already settled by the customer, so it comes off the
    // Deficit target instead of ever being required from an editable row.
    get lockedUnsplitTotal() {
        return this.schedules.reduce((a, s) => {
            if (s.cannotEdit && !s.hasSplit) {
                return a + num(s.baseAmount) + num(s.gstAmount);
            }
            return a;
        }, 0);
    }

    // Deficit target reduced by whatever's already settled by locked/unsplit milestones.
    get effectiveDeficit() {
        if (this.deficit === null) return null;
        return this.deficit - this.lockedUnsplitTotal;
    }

    // ─── validity flags (mirror the server-side §8.3.1 + total/percentage rules) ──

    get pctValid() { return Math.abs(this.sumPercentage - 100) <= 0.5; }
    get totalValid() { return Math.abs(this.sumTotal - this.originalTotal) <= this.tolerance; }
    get bankFlatValid() {
        return !this.isProrata || this.loanSanctioned === null
            || Math.abs(this.sumBankFlat - this.loanSanctioned) <= this.tolerance;
    }
    get custFlatValid() {
        // Customer Flat total = Deficit only applies to Prorata/Partial (§8.3.1), and only
        // needs to match after subtracting whatever's already settled by locked milestones.
        return !this.isStrictProrata || this.effectiveDeficit === null
            || Math.abs(this.sumCustomerFlat - this.effectiveDeficit) <= this.tolerance;
    }
    get balanced() {
        return this.pctValid && this.totalValid && this.bankFlatValid && this.custFlatValid;
    }

    // ─── display helpers ─────────────────────────────────────────────────────────

    fmt(v) {
        if (v === null || v === undefined) return '-';
        return Number(v).toLocaleString('en-IN', { maximumFractionDigits: 2 });
    }
    get totalPayableText() { return this.fmt(this.totals ? this.totals.totalPayableAmount : null); }
    get loanSanctionedText() { return this.fmt(this.loanSanctioned); }
    get deficitText() { return this.fmt(this.deficit); }
    get effectiveDeficitText() { return this.fmt(this.effectiveDeficit); }
    get lockedUnsplitTotalText() { return this.fmt(this.lockedUnsplitTotal); }
    get originalTotalText() { return this.fmt(this.originalTotal); }
    get sumTotalText() { return this.fmt(this.sumTotal); }
    get sumPercentageText() { return this.fmt(this.sumPercentage); }
    get sumBankFlatText() { return this.fmt(this.sumBankFlat); }
    get sumCustomerFlatText() { return this.fmt(this.sumCustomerFlat); }
    get hasLockedUnsplit() { return this.lockedUnsplitTotal > 0; }

    cls(ok) { return 'slds-text-body_regular ' + (ok ? 'slds-text-color_success' : 'slds-text-color_error'); }
    get pctClass() { return this.cls(this.pctValid); }
    get totalClass() { return this.cls(this.totalValid); }
    get bankFlatClass() { return this.cls(this.bankFlatValid); }
    get custFlatClass() { return this.cls(this.custFlatValid); }

    get hasSchedules() {
        return this.schedules && this.schedules.length > 0;
    }
    get saveDisabled() {
        return this.isSaving || !this.editingEnabled || !this.balanced;
    }
    get showBalanceHint() {
        return this.editingEnabled && this.hasSchedules && !this.balanced;
    }

    // ─── editing ─────────────────────────────────────────────────────────────────

    handleFieldChange(event) {
        const scheduleId = event.target.dataset.id;
        const field = event.target.dataset.field;
        let value;

        if (field === 'withGst') {
            value = event.target.checked;
        } else if (field === 'forecastDate') {
            value = event.target.value || null;
        } else if (NUMERIC_FIELDS.has(field)) {
            value = event.target.value === '' ? null : parseFloat(event.target.value);
        } else {
            value = event.target.value;
        }

        this.schedules = this.schedules.map((s) => {
            if (s.id !== scheduleId) return s;
            const updated = { ...s, [field]: value };
            updated.liveTotal = num(updated.baseAmount) + num(updated.gstAmount);
            updated.deficitAlloc = num(updated.customerFlat);
            return updated;
        });
    }

    async handleSave() {
        this.isSaving = true;
        try {
            await saveEditedSchedules({
                bookingId: this.recordId,
                schedulesJson: JSON.stringify(this.schedules)
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Submitted for approval',
                    message:
                        'Your changes were submitted for approval. They will be applied to the ' +
                        'payment schedule once approved.',
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredScheduleResult);
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.extractError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    extractError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred.';
    }
}