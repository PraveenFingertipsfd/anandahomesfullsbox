import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';
import getContext from '@salesforce/apex/FirstApplicantChangeController.getContext';
import createChange from '@salesforce/apex/FirstApplicantChangeController.createChange';

export default class FirstApplicantChange extends LightningElement {
    @api recordId; // Booking__c

    @track ctx;
    @track newApplicant = '';
    @track newEmail = '';
    @track newMobile = '';
    @track reason = '';
    isLoading = false;
    wiredCtx;

    @wire(getContext, { bookingId: '$recordId' })
    wired(result) {
        this.wiredCtx = result;
        if (result.data) {
            this.ctx = result.data;
        } else if (result.error) {
            this.showError(result.error);
        }
    }

    get currentApplicant() {
        return this.ctx ? this.ctx.currentApplicant : '';
    }

    get changes() {
        return (this.ctx && this.ctx.changes) ? this.ctx.changes : [];
    }

    get hasChanges() {
        return this.changes.length > 0;
    }

    get submitDisabled() {
        return this.isLoading || !this.newApplicant;
    }

    handleNewApplicant(event) { this.newApplicant = event.detail.value; }
    handleNewEmail(event) { this.newEmail = event.detail.value; }
    handleNewMobile(event) { this.newMobile = event.detail.value; }
    handleReason(event) { this.reason = event.detail.value; }

    async handleSubmit() {
        this.isLoading = true;
        try {
            await createChange({
                bookingId: this.recordId,
                newApplicantName: this.newApplicant,
                newEmail: this.newEmail,
                newMobile: this.newMobile,
                reason: this.reason
            });
            this.showToast(
                'Request created',
                'First Applicant Change request created. It will be applied to the booking once approved.',
                'success'
            );
            this.newApplicant = '';
            this.newEmail = '';
            this.newMobile = '';
            this.reason = '';
            if (this.wiredCtx) await refreshApex(this.wiredCtx);
            // Close the Quick Action modal (no-op on a record page).
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message =
            (error && error.body && error.body.message) ||
            (error && error.message) ||
            'Unexpected error';
        this.showToast('Error', message, 'error');
    }
}