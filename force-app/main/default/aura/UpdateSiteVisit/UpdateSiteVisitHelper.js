({ // Updated: 2026-04-01 12:00
    toastMsg : function (type, title, msg) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": title,
            "type": type,
            "message": msg
        });
        toastEvent.fire();
    },
    /*showToast: function(title, message, variant) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": title,
            "message": message,
            "variant": variant
        });
        toastEvent.fire();
    },*/
    // Apex call to create the Follow-up record
    createFollowUp : function(component, followUpRecord,myRecordId, callback) {
        var action = component.get("c.createFollowUpApex");
        action.setParams({
            followUpRecord: JSON.stringify(followUpRecord),
            SiteVisitId: myRecordId,
            LeadId:''
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if(state === "SUCCESS") {
                callback({ success: true });
            } else {
                callback({ success: false });
            }
        });
        $A.enqueueAction(action);
    },
    fetchOriginalDate: function(component) {
        var action = component.get("c.fetchSiteVisitDetails");
        action.setParams({
            recordId: component.get("v.recordId")
        });
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var sv = response.getReturnValue();
                if (sv && sv.Date__c) {
                    component.set("v.originalDate", sv.Date__c);
                }
                if (sv && sv.CLead__c) {
                    component.set("v.leadId", sv.CLead__c);
                }
                if (sv && sv.OwnerId) {
                    component.set("v.ownerId", sv.OwnerId);
                }
            }
        });
        $A.enqueueAction(action);
    },
    setDefaultFollowupDateTime: function(component) {
        // Default Follow-up Scheduled Date & Time to system.now + 5 minutes
        var d = new Date(Date.now() + 5 * 60 * 1000);
        component.set("v.followupDateTimeValue", d.toISOString());
    },
    maybeAdvanceLeadStatus: function(component, callback) {
        var done = function() { if (typeof callback === 'function') { callback(); } };
        var leadId = component.get("v.leadId");
        if (!leadId) { done(); return; }

        var getStatus = component.get("c.getLeadStatus");
        getStatus.setParams({ leadId: leadId });
        getStatus.setCallback(this, function(response) {
            if (response.getState() !== "SUCCESS") {
                console.warn('getLeadStatus failed; skipping Lead status update.');
                done();
                return;
            }
            var currentStatus = response.getReturnValue();
            if (currentStatus !== 'Site Visit Scheduled') {
                done();
                return;
            }
            var updateStatus = component.get("c.updateLeadStatusOnly");
            updateStatus.setParams({ leadId: leadId, newStatus: 'Site Visit Completed' });
            updateStatus.setCallback(this, function(updResp) {
                if (updResp.getState() !== "SUCCESS") {
                    this.toastMsg('warning', 'Lead status not updated',
                        'Site Visit was saved, but the Lead status could not be updated.');
                }
                done();
            });
            $A.enqueueAction(updateStatus);
        });
        $A.enqueueAction(getStatus);
    },
    fetchSubject: function(component, event, helper){
        var action = component.get("c.fetchSubject");
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if(state === "SUCCESS") {
                var subjectList = response.getReturnValue();
                component.set("v.Subject",subjectList);
            } else {
                callback({ success: false });
            }
        });
        $A.enqueueAction(action);
    },
    
})