import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInitData from '@salesforce/apex/BulkLeadReassignmentController.getInitData';
import getLeadsByOwner from '@salesforce/apex/BulkLeadReassignmentController.getLeadsByOwner';
import reassignLeads from '@salesforce/apex/BulkLeadReassignmentController.reassignLeads';
import getActiveTemporaryAssignments from '@salesforce/apex/BulkLeadReassignmentController.getActiveTemporaryAssignments';
import revokeTemporaryAccess from '@salesforce/apex/BulkLeadReassignmentController.revokeTemporaryAccess';

export default class BulkLeadReassignment extends LightningElement {

    // ─── Tab state ───
    activeTab = 'newReassignment';

    // ─── Loading ───
    isLoading = false;

    // ─── Init data ───
    userOptions = [];
    projectOptions = [];
    statusOptions = [];

    // ─── New Re-assignment form ───
    reassignmentType = 'Permanent';
    currentOwnerId = '';
    newOwnerId = '';
    tempExpiryDate = '';
    reason = '';

    // ─── Filters ───
    projectFilter = '';
    statusFilter = '';
    fromDate = '';
    toDate = '';
    mobileFilter = '';

    // ─── Leads ───
    @track leads = [];
    searchPerformed = false;

    // ─── Temp assignments ───
    @track tempAssignments = [];

    // ─── Getters ───
    get reassignmentTypeOptions() {
        return [
            { label: 'Permanent', value: 'Permanent' },
            { label: 'Temporary', value: 'Temporary' }
        ];
    }

    get isTemporary() {
        return this.reassignmentType === 'Temporary';
    }

    get minExpiryDate() {
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        return tomorrow.toISOString().split('T')[0];
    }

    get hasLeads() {
        return this.leads && this.leads.length > 0;
    }

    get leadCount() {
        return this.leads ? this.leads.length : 0;
    }

    get selectedLeads() {
        return this.leads ? this.leads.filter(l => l.isSelected) : [];
    }

    get selectedCount() {
        return this.selectedLeads.length;
    }

    get isReassignDisabled() {
        return this.selectedCount === 0 || !this.newOwnerId || !this.reason;
    }

    get showNoLeadsMessage() {
        return this.searchPerformed && (!this.leads || this.leads.length === 0);
    }

    get hasTempAssignments() {
        return this.tempAssignments && this.tempAssignments.length > 0;
    }

    get tempCount() {
        return this.tempAssignments ? this.tempAssignments.length : 0;
    }

    get selectedTempRecords() {
        return this.tempAssignments ? this.tempAssignments.filter(r => r.isSelected) : [];
    }

    get selectedTempCount() {
        return this.selectedTempRecords.length;
    }

    get isRevokeDisabled() {
        return this.selectedTempCount === 0;
    }

    // New Lead Owner options: filtered to the same profile as the selected current owner
    get newOwnerOptions() {
        if (!this.currentOwnerId) {
            return this.userOptions;
        }
        const current = this.userOptions.find(u => u.value === this.currentOwnerId);
        if (!current) {
            return this.userOptions;
        }
        return this.userOptions.filter(
            u => u.profileName === current.profileName && u.value !== this.currentOwnerId
        );
    }

    // ─── Wire init data ───
    @wire(getInitData)
    wiredInitData({ data, error }) {
        if (data) {
            this.userOptions = data.activeUsers.map(u => ({
                label: u.label + ' (' + u.profileName + ')',
                value: u.value,
                profileName: u.profileName
            }));
            // Add empty option at the beginning
            this.projectOptions = [
                { label: '-- All Projects --', value: '' },
                ...data.projectOptions
            ];
            this.statusOptions = [
                { label: '-- All Statuses --', value: '' },
                ...data.statusOptions
            ];
        }
        if (error) {
            this.showToast('Error', 'Failed to load init data: ' + this.reduceErrors(error), 'error');
        }
    }

    // ─── Tab change ───
    handleTabChange(event) {
        this.activeTab = event.target.activeTabValue;
        if (this.activeTab === 'tempAssignments') {
            this.loadTempAssignments();
        }
    }

    // ─── Form Handlers ───
    handleTypeChange(event) {
        this.reassignmentType = event.detail.value;
        if (this.reassignmentType === 'Permanent') {
            this.tempExpiryDate = '';
        }
    }

    handleCurrentOwnerChange(event) {
        this.currentOwnerId = event.detail.value;
        // Reset new owner so a stale selection from a different profile cannot remain
        this.newOwnerId = '';
        this.leads = [];
        this.searchPerformed = false;
    }

    handleNewOwnerChange(event) {
        this.newOwnerId = event.detail.value;
    }

    handleExpiryDateChange(event) {
        this.tempExpiryDate = event.detail.value;
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    // ─── Filter Handlers ───
    handleProjectFilterChange(event) {
        this.projectFilter = event.detail.value;
    }

    handleStatusFilterChange(event) {
        this.statusFilter = event.detail.value;
    }

    handleFromDateChange(event) {
        this.fromDate = event.detail.value;
    }

    handleToDateChange(event) {
        this.toDate = event.detail.value;
    }

    handleMobileFilterChange(event) {
        this.mobileFilter = event.detail.value;
    }

    handleClearFilters() {
        this.projectFilter = '';
        this.statusFilter = '';
        this.fromDate = '';
        this.toDate = '';
        this.mobileFilter = '';
    }

    // ─── Search Leads ───
    handleSearchLeads() {
        if (!this.currentOwnerId) {
            this.showToast('Warning', 'Please select a Current Lead Owner.', 'warning');
            return;
        }

        this.isLoading = true;
        this.searchPerformed = true;

        getLeadsByOwner({
            ownerId: this.currentOwnerId,
            projectFilter: this.projectFilter || null,
            statusFilter: this.statusFilter || null,
            fromDate: this.fromDate || null,
            toDate: this.toDate || null,
            mobileFilter: this.mobileFilter || null
        })
        .then(result => {
            this.leads = result.map(lead => ({
                ...lead,
                isSelected: false,
                formattedDate: lead.Created_Dates__c
                    ? new Date(lead.Created_Dates__c).toLocaleDateString('en-IN')
                    : ''
            }));
        })
        .catch(error => {
            this.showToast('Error', 'Failed to fetch leads: ' + this.reduceErrors(error), 'error');
            this.leads = [];
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    // ─── Lead Selection ───
    handleLeadSelection(event) {
        const leadId = event.target.dataset.id;
        const isChecked = event.target.checked;
        this.leads = this.leads.map(lead => {
            if (lead.Id === leadId) {
                return { ...lead, isSelected: isChecked };
            }
            return lead;
        });
    }

    handleSelectAll() {
        this.leads = this.leads.map(lead => ({ ...lead, isSelected: true }));
    }

    handleDeselectAll() {
        this.leads = this.leads.map(lead => ({ ...lead, isSelected: false }));
    }

    // ─── Reassign ───
    handleReassign() {
        // Validations
        if (!this.newOwnerId) {
            this.showToast('Warning', 'Please select a New Lead Owner.', 'warning');
            return;
        }
        if (this.currentOwnerId === this.newOwnerId && this.reassignmentType === 'Permanent') {
            this.showToast('Warning', 'Current and New owner cannot be the same for Permanent re-assignment.', 'warning');
            return;
        }
        if (!this.reason) {
            this.showToast('Warning', 'Please enter a reason for re-assignment.', 'warning');
            return;
        }
        if (this.isTemporary && !this.tempExpiryDate) {
            this.showToast('Warning', 'Please select an Expiry Date for Temporary assignment.', 'warning');
            return;
        }

        const selectedIds = this.selectedLeads.map(l => l.Id);
        if (selectedIds.length === 0) {
            this.showToast('Warning', 'Please select at least one lead.', 'warning');
            return;
        }

        this.isLoading = true;

        reassignLeads({
            leadIds: selectedIds,
            currentOwnerId: this.currentOwnerId,
            newOwnerId: this.newOwnerId,
            reassignmentType: this.reassignmentType,
            reason: this.reason,
            tempExpiryDate: this.isTemporary ? this.tempExpiryDate : null
        })
        .then(result => {
            this.showToast('Success', result, 'success');
            // Reset Re-assignment Setup
            this.reassignmentType = 'Permanent';
            this.currentOwnerId = '';
            this.newOwnerId = '';
            this.reason = '';
            this.tempExpiryDate = '';
            // Reset Filters
            this.projectFilter = '';
            this.statusFilter = '';
            this.fromDate = '';
            this.toDate = '';
            this.mobileFilter = '';
            // Hide Filter Leads block and lead table
            this.leads = [];
            this.searchPerformed = false;
        })
        .catch(error => {
            this.showToast('Error', 'Re-assignment failed: ' + this.reduceErrors(error), 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    // ─── Temp Assignments ───
    loadTempAssignments() {
        this.isLoading = true;

        getActiveTemporaryAssignments()
        .then(result => {
            const today = new Date();
            today.setHours(0, 0, 0, 0);

            this.tempAssignments = result.map(rec => {
                const expiryDate = rec.Temp_Expiry__c ? new Date(rec.Temp_Expiry__c) : null;
                const isExpiringSoon = expiryDate && ((expiryDate - today) / (1000 * 60 * 60 * 24)) <= 2;

                return {
                    ...rec,
                    isSelected: false,
                    leadName:       (rec.Lead__r && rec.Lead__r.Name) ? rec.Lead__r.Name : (rec.Lead__c || ''),
                    leadUrl:        rec.Lead__c ? ('/lightning/r/Lead__c/' + rec.Lead__c + '/view') : '',
                    oldOwnerName:   rec.Old_Owner__r   ? rec.Old_Owner__r.Name   : '',
                    newOwnerName:   rec.New_Owner__r   ? rec.New_Owner__r.Name   : '',
                    assignedByName: rec.Assigned_By__r ? rec.Assigned_By__r.Name : '',
                    formattedAssignedDate: rec.Reassigned_Date__c
                        ? new Date(rec.Reassigned_Date__c).toLocaleDateString('en-IN')
                        : '',
                    formattedExpiryDate: rec.Temp_Expiry__c
                        ? new Date(rec.Temp_Expiry__c).toLocaleDateString('en-IN')
                        : '',
                    statusClass: 'slds-badge_' + (rec.Status__c === 'Active' ? 'inverse' : 'lightest'),
                    rowClass: isExpiringSoon ? 'slds-hint-parent expiring-soon' : 'slds-hint-parent'
                };
            });
        })
        .catch(error => {
            this.showToast('Error', 'Failed to load temp assignments: ' + this.reduceErrors(error), 'error');
            this.tempAssignments = [];
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    handleTempTabActive() {
        this.loadTempAssignments();
    }

    handleRefreshTemp() {
        this.loadTempAssignments();
    }

    // ─── Temp Selection ───
    handleTempSelection(event) {
        const recId = event.target.dataset.id;
        const isChecked = event.target.checked;
        this.tempAssignments = this.tempAssignments.map(rec => {
            if (rec.Id === recId) {
                return { ...rec, isSelected: isChecked };
            }
            return rec;
        });
    }

    handleSelectAllTemp() {
        this.tempAssignments = this.tempAssignments.map(rec => ({ ...rec, isSelected: true }));
    }

    handleDeselectAllTemp() {
        this.tempAssignments = this.tempAssignments.map(rec => ({ ...rec, isSelected: false }));
    }

    // ─── Revoke Access ───
    handleRevokeAccess() {
        const selectedIds = this.selectedTempRecords.map(r => r.Id);
        if (selectedIds.length === 0) {
            this.showToast('Warning', 'Please select records to revoke.', 'warning');
            return;
        }

        this.isLoading = true;

        revokeTemporaryAccess({ historyIds: selectedIds })
        .then(result => {
            this.showToast('Success', result, 'success');
            this.loadTempAssignments();
        })
        .catch(error => {
            this.showToast('Error', 'Revoke failed: ' + this.reduceErrors(error), 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    // ─── Utilities ───
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        return 'Unknown error';
    }
}