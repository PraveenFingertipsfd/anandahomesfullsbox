import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getProjectOptions from '@salesforce/apex/UnitBlockingController.getProjectOptions';
import searchUnits from '@salesforce/apex/UnitBlockingController.searchUnits';
import saveUnitBlock from '@salesforce/apex/UnitBlockingController.saveUnitBlock';

export default class UnitBlocking extends LightningElement {
    @api recordId;

    isLoading = false;
    projectOptions = [];
    selectedProject = '';
    unitSearchTerm = '';
    unitResults = [];
    showUnitResults = false;
    selectedUnit = null;
    blockReason = '';
    blockDuration = null;
    _searchTimeout;

    connectedCallback() {
        this.loadProjectOptions();
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${
            this.showUnitDropdown ? 'slds-is-open' : ''
        }`;
    }

    loadProjectOptions() {
        this.isLoading = true;
        getProjectOptions()
            .then(result => {
                this.projectOptions = result || [];
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleProjectChange(event) {
        this.selectedProject = event.detail.value;
        this.selectedUnit = null;
        this.unitSearchTerm = '';
        this.unitResults = [];
        this.showUnitResults = false;
    }

    handleUnitSearchFocus() {
        if (!this.selectedProject || this.selectedUnit) {
            return;
        }
        this.performUnitSearch();
    }

    handleUnitSearchChange(event) {
        const newValue = event.target.value;
        this.unitSearchTerm = newValue;
        if (this.selectedUnit && this.selectedUnit.name !== newValue) {
            this.selectedUnit = null;
        }
        clearTimeout(this._searchTimeout);
        this._searchTimeout = setTimeout(() => {
            this.performUnitSearch();
        }, 300);
    }

    performUnitSearch() {
        if (!this.selectedProject) {
            return;
        }
        this.isLoading = true;
        searchUnits({ projectValue: this.selectedProject, searchTerm: this.unitSearchTerm })
            .then(result => {
                this.unitResults = result || [];
                this.showUnitResults = true;
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSelectUnit(event) {
        event.preventDefault();
        event.stopPropagation();
        const unitId = event.currentTarget.dataset.id;
        const match = this.unitResults.find(u => u.unitId === unitId);
        if (match) {
            this.selectedUnit = match;
            this.unitSearchTerm = match.name;
            this.showUnitResults = false;
        }
    }

    handleReasonChange(event) {
        this.blockReason = event.target.value;
    }

    handleDurationChange(event) {
        const raw = event.target.value;
        this.blockDuration = raw === '' ? null : Number(raw);
    }

    get hasUnitResults() {
        return this.unitResults && this.unitResults.length > 0;
    }

    get showUnitDropdown() {
        return this.showUnitResults && !this.selectedUnit && !!this.selectedProject;
    }

    get isUnitSearchDisabled() {
        return !this.selectedProject;
    }

    get isSaveDisabled() {
        return this.isLoading
            || !this.selectedProject
            || !this.selectedUnit
            || !this.blockReason || this.blockReason.trim().length === 0
            || !this.blockDuration || this.blockDuration <= 0;
    }

    handleSave() {
        this.isLoading = true;
        saveUnitBlock({
            leadId: this.recordId,
            unitId: this.selectedUnit ? this.selectedUnit.unitId : null,
            projectValue: this.selectedProject,
            blockReason: this.blockReason,
            blockDuration: this.blockDuration
        })
            .then(() => {
                this.showToast('Success', 'Unit Blocked Successfully', 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
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