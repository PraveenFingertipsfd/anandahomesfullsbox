import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import searchLeads from '@salesforce/apex/LeadMergeController.searchLeads';
import getLeadDetails from '@salesforce/apex/LeadMergeController.getLeadDetails';
import mergeLeads from '@salesforce/apex/LeadMergeController.mergeLeads';

export default class LeadMerge extends NavigationMixin(LightningElement) {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            this.loadDuplicateLeadDetails();
        }
    }

    isLoading = false;
    searchTerm = '';
    searchResults = [];
    showSearchResults = false;
    duplicateDetail = null;
    actualDetail = null;
    selectedActualLeadId = null;
    _searchTimeout;

    loadDuplicateLeadDetails() {
        this.isLoading = true;
        getLeadDetails({ leadId: this.recordId })
            .then(result => {
                this.duplicateDetail = result;
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasSearchResults() {
        return this.searchResults && this.searchResults.length > 0;
    }

    get duplicateRecordSummary() {
        if (!this.duplicateDetail) return '';
        return `Records to transfer: ${this.duplicateDetail.relatedSourceCount} Related Source(s), ${this.duplicateDetail.followUpCount} Follow-up(s), ${this.duplicateDetail.siteVisitCount} Site Visit(s)`;
    }

    get actualRecordSummary() {
        if (!this.actualDetail) return '';
        return `Existing records: ${this.actualDetail.relatedSourceCount} Related Source(s), ${this.actualDetail.followUpCount} Follow-up(s), ${this.actualDetail.siteVisitCount} Site Visit(s)`;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._searchTimeout);

        if (this.searchTerm.length < 2) {
            this.searchResults = [];
            this.showSearchResults = false;
            return;
        }

        this._searchTimeout = setTimeout(() => {
            this.performSearch();
        }, 300);
    }

    performSearch() {
        this.isLoading = true;
        searchLeads({ searchTerm: this.searchTerm, excludeLeadId: this.recordId })
            .then(result => {
                this.searchResults = result;
                this.showSearchResults = true;
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSelectLead(event) {
        event.stopPropagation();
        const leadId = event.currentTarget.dataset.id;
        this.selectedActualLeadId = leadId;
        this.showSearchResults = false;
        this.searchTerm = '';

        this.isLoading = true;
        getLeadDetails({ leadId: leadId })
            .then(result => {
                this.actualDetail = result;
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleClearSelection() {
        this.actualDetail = null;
        this.selectedActualLeadId = null;
        this.searchTerm = '';
        this.searchResults = [];
        this.showSearchResults = false;
    }

    get isMergeDisabled() {
        return !this.selectedActualLeadId || this.isLoading;
    }

    handleMerge() {
        this.isLoading = true;
        mergeLeads({ duplicateLeadId: this.recordId, actualLeadId: this.selectedActualLeadId })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.selectedActualLeadId,
                        objectApiName: 'Lead__c',
                        actionName: 'view'
                    }
                });
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred.';
    }
}