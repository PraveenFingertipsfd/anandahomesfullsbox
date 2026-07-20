({
    doInit : function(component, event, helper) {
        // Default Site Visit and Follow-up Scheduled Date & Time to system.now + 5 minutes
        var defaultDateTime = new Date(Date.now() + 5 * 60 * 1000).toISOString();
        component.set("v.siteVisitDateTimeValue", defaultDateTime);
        component.set("v.followupDateTimeValue", defaultDateTime);

        var recordId = component.get("v.recordId");
        var action = component.get("c.fetchInitData");
        action.setParams({ recordId: recordId });

        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var data = response.getReturnValue();
                component.set("v.Subject", data.subjectList);
                component.set("v.projectList", data.projectList);
                component.set("v.visitTypeList", data.visitTypeList);
                component.set("v.leadProject", data.leadRecord.Allocated_Project__c);
                component.set("v.leadOwnerId", data.leadRecord.OwnerId);
            } else {
                helper.toastMsg("error", "Error", "Failed to load initial data.");
            }
        });

        $A.enqueueAction(action);
    },

    handleError: function(cmp, event, helper) {
        cmp.set("v.isSubmitting", false);
        var errorMessage = event.getParam("message");
        if (errorMessage === 'The requested resource does not exist') {
            history.back();
        }
    },

    handleSuccess : function(component, event, helper) {
        component.set("v.isSubmitting", true);
        var recordId = component.get("v.recordId");

        // Check for any existing scheduled Follow-up
        var checkAction = component.get("c.getFollowUpDetails");
        checkAction.setParams({ leadId: recordId });

        checkAction.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var existingFollowUps = response.getReturnValue();

                if (existingFollowUps && existingFollowUps.length > 0) {
                    helper.toastMsg("error", "Cannot create Site Visit", "A Scheduled Follow-up already exists for this Lead.");
                    component.set("v.isSubmitting", false);
                    return;
                }

                // Call the site visit creation method
                helper.processSiteVisitCreation(component, helper, recordId);

            } else {
                helper.toastMsg("error", "Check Failed", "Unable to verify existing Follow-ups. Try again later.");
                component.set("v.isSubmitting", false);
            }
        });

        $A.enqueueAction(checkAction);
    },

    visitTypeChange: function(component, event, helper) {
        var visitType = event.getSource().get("v.value");
        component.set("v.visitType", visitType);
        if (visitType !== 'Site Visit') {
            component.set("v.visitSourceType", "");
            component.set("v.channelPartnerId", "");
        }
    },

    visitSourceTypeChange: function(component, event, helper) {
        var sourceType = event.getSource().get("v.value");
        component.set("v.visitSourceType", sourceType);
        if (sourceType !== 'CP') {
            component.set("v.channelPartnerId", "");
        }
    },

    closeModel: function(component, event, helper) {
        $A.get("e.force:closeQuickAction").fire();
    }
})