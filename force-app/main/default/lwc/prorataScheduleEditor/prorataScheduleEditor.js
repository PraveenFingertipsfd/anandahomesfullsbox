// prorataScheduleEditor.js
// Editor for payment schedules with Prorata / Partial split columns. Works both as a
// record-page component and as a Quick Action modal (lightning__RecordAction / ScreenAction).
// Backed by PaymentScheduleEditorController, which locks any milestone that is
// demand-raised, paid, or closed, and validates the §8.3.1 prorata invariants on save.
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

export default class ProrataScheduleEditor extends LightningElement {
    @api recordId;

    @track schedules = [];
    @track totals = {};
    @track editingEnabled = false;
    @track isProrata = false;
    fundingType;
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
            this.fundingType = result.data.fundingType;
            this.totals = result.data.totals || {};
            this.schedules = result.data.schedules.map((s) => this.decorate(s));
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
        return { ...s, canEdit, cannotEdit: !canEdit };
    }

    get hasSchedules() {
        return this.schedules && this.schedules.length > 0;
    }

    get saveDisabled() {
        return this.isSaving || !this.editingEnabled;
    }

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

        this.schedules = this.schedules.map((s) =>
            s.id === scheduleId ? { ...s, [field]: value } : s
        );
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
            // When launched as a Quick Action the modal should close after a successful
            // save; on a record page this event is simply ignored.
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
        // Dismiss the Quick Action modal (no-op when used as a record-page component).
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