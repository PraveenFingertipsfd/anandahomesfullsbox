import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getNOCContext from '@salesforce/apex/NOCController.getNOCContext';
import createNOC from '@salesforce/apex/NOCController.createNOC';
import sendNOC from '@salesforce/apex/NOCController.sendNOC';

const NOC_TYPE_OPTIONS = [
    { label: 'Capri NOC', value: 'Capri NOC' },
    { label: 'Bank NOC', value: 'Bank NOC' },
    { label: 'Society NOC', value: 'Society NOC' }
];

export default class NocGenerator extends LightningElement {
    @api recordId; // Booking__c Id

    @track ctx;
    @track nocType = 'Capri NOC';
    @track mailBody = '';
    @track selectedCancellations = [];
    @track selectedSwaps = [];
    isLoading = false;

    nocTypeOptions = NOC_TYPE_OPTIONS;
    wiredCtx;

    @wire(getNOCContext, { bookingId: '$recordId' })
    wiredContext(result) {
        this.wiredCtx = result;
        if (result.data) {
            this.ctx = result.data;
            if (!this.mailBody) {
                this.mailBody = result.data.defaultMailBody;
            }
        } else if (result.error) {
            this.showError(result.error);
        }
    }

    get cancellationOptions() {
        return (this.ctx && this.ctx.cancellations)
            ? this.ctx.cancellations.map((c) => ({ label: `${c.name} — ${c.detail}`, value: c.recordId }))
            : [];
    }

    get swapOptions() {
        return (this.ctx && this.ctx.swaps)
            ? this.ctx.swaps.map((s) => ({ label: `${s.name} — ${s.detail}`, value: s.recordId }))
            : [];
    }

    get hasCancellations() {
        return this.cancellationOptions.length > 0;
    }

    get hasSwaps() {
        return this.swapOptions.length > 0;
    }

    get existingNOCs() {
        const list = (this.ctx && this.ctx.existingNOCs) ? this.ctx.existingNOCs : [];
        // A NOC can only be sent once it is Approved and not already sent. Compute a flag so the
        // UI only shows the Send button when it will actually work.
        return list.map((n) => {
            const approved = (n.approvalStatus || '').toLowerCase() === 'approved';
            return {
                ...n,
                _canSend: approved && !n.sent,
                _pending: !approved && !n.sent
            };
        });
    }

    get hasExistingNOCs() {
        return this.existingNOCs.length > 0;
    }

    handleTypeChange(event) {
        this.nocType = event.detail.value;
    }

    handleBodyChange(event) {
        this.mailBody = event.detail.value;
    }

    handleCancellationChange(event) {
        this.selectedCancellations = event.detail.value;
    }

    handleSwapChange(event) {
        this.selectedSwaps = event.detail.value;
    }

    async handleGenerate() {
        this.isLoading = true;
        try {
            await createNOC({
                bookingId: this.recordId,
                nocType: this.nocType,
                mailBody: this.mailBody,
                cancellationIds: this.selectedCancellations,
                swapIds: this.selectedSwaps
            });
            this.showToast('Success', 'NOC created and submitted for CRM Manager approval.', 'success');
            await refreshApex(this.wiredCtx);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleSend(event) {
        const nocId = event.target.dataset.id;
        this.isLoading = true;
        try {
            await sendNOC({ nocId });
            this.showToast('Sent', 'NOC emailed to the applicant.', 'success');
            await refreshApex(this.wiredCtx);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
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