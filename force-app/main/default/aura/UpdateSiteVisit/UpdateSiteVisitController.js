({ // Updated: 2026-04-01 12:00
    doInit: function(component, event, helper){
        helper.fetchSubject(component, event, helper);
        helper.fetchOriginalDate(component);
        helper.setDefaultFollowupDateTime(component);
    },
    handleSubmit: function(component, event, helper) {
        // Always prevent the default save first so nothing slips through on any early return
        event.preventDefault();
        component.set("v.isSubmitting", true);

        var status = component.get('v.SVStatus');

        // Follow-up Date & Time is only captured for Rescheduled
        if (status === 'Rescheduled') {
            var followupDateTime = component.find("followupDateTime").get("v.value");
            var followupDate = new Date(followupDateTime);
            if (!followupDateTime || followupDate <= new Date()) {
                helper.toastMsg('error', 'Error', 'Follow-up Date & Time must be a future date and time.');
                component.set("v.isSubmitting", false);
                return;
            }
        }

        // Completed-specific validations
        if (status === 'Completed') {
            var visitNotes = component.find("visitNotesField").get("v.value");
            var svCompletedDt = component.find("svCompletedDateTimeField").get("v.value");
            var checkOut = component.find("checkOutField").get("v.value");
            var visitSourceType = component.get("v.visitSourceType");
            var channelPartnerId = component.get("v.svChannelPartnerId");

            if (!visitNotes) {
                helper.toastMsg('error', 'Error', 'Please enter Visit Notes.');
                component.set("v.isSubmitting", false);
                return;
            }
            if (!svCompletedDt) {
                helper.toastMsg('error', 'Error', 'Please enter Site Visit Completed Time.');
                component.set("v.isSubmitting", false);
                return;
            }
            if (!checkOut) {
                helper.toastMsg('error', 'Error', 'Please enter Check Out time.');
                component.set("v.isSubmitting", false);
                return;
            }
            if (!visitSourceType) {
                helper.toastMsg('error', 'Error', 'Please select Visit Source Type.');
                component.set("v.isSubmitting", false);
                return;
            }
            if (visitSourceType === 'CP' && !channelPartnerId) {
                helper.toastMsg('error', 'Error', 'Please select a Channel Partner.');
                component.set("v.isSubmitting", false);
                return;
            }
        }

        var leadId = component.get("v.leadId");
        if (!leadId) {
            helper.toastMsg('error', 'Error', 'Lead information is still loading. Please try again in a moment.');
            component.set("v.isSubmitting", false);
            return;
        }

        var eventFields = event.getParam("fields");

        // Check for existing scheduled follow-up before proceeding
        var checkAction = component.get("c.getFollowUpDetails");
        checkAction.setParams({ leadId: leadId });
        checkAction.setCallback(this, function(response) {
            if (response.getState() !== "SUCCESS") {
                helper.toastMsg('error', 'Error', 'Unable to verify existing Follow-ups. Try again later.');
                component.set("v.isSubmitting", false);
                return;
            }
            var existingFollowUps = response.getReturnValue();
            if (existingFollowUps && existingFollowUps.length > 0) {
                helper.toastMsg('error', 'Scheduled Follow-up Exists',
                    'Please close the existing scheduled Follow-up before updating the Site Visit.');
                component.set("v.isSubmitting", false);
                return; // Site Visit is NOT submitted — status stays unchanged
            }
            // No scheduled follow-ups — proceed with submission
            if (status) {
                eventFields["Status__c"] = status;
            }
            if (status === 'Rescheduled') {
                var originalDate = component.get("v.originalDate");
                if (originalDate) {
                    eventFields["Rescheduled_From_Date__c"] = originalDate;
                }
            }
            if (status === 'Completed') {
                var completedDt = component.find("svCompletedDateTimeField").get("v.value");
                // Copy Site Visit Completed Time into Check_In__c on save
                if (completedDt) {
                    eventFields["Check_In__c"] = completedDt;
                }
                var cpId = component.get("v.svChannelPartnerId");
                var srcType = component.get("v.visitSourceType");
                if (srcType === 'CP' && cpId) {
                    eventFields["Channel_Partner__c"] = cpId;
                }
                var ownerId = component.get("v.ownerId");
                if (ownerId) {
                    eventFields["Handled_By__c"] = ownerId;
                }
            }
            component.find('myform').submit(eventFields);
        });
        $A.enqueueAction(checkAction);
    },

    handleSuccess: function(component, event, helper) {
        component.set("v.isSubmitting", false); // Hide the spinner after successful submission
        const recordId = component.get("v.recordId");

        // Determine selected status (support both attributes in case UI set one)
        var status = component.get("v.status") || component.get("v.SVStatus");

        // Map statuses to toast messages per requirement
        var messages = {
            'Scheduled': 'Site Visit has been successfully scheduled.',
            'Cancelled': 'Site Visit has been cancelled.',
            'Rescheduled': 'Site Visit has been rescheduled successfully.',
            'Completed': 'Site Visit has been marked as Completed.'
        };

        if (status && messages[status]) {
            // helper.toastMsg(type, title, message)
            helper.toastMsg('success', 'Success', messages[status]);
        } else {
            // fallback generic success (optional)
            helper.toastMsg('success', 'Success', 'Site Visit saved successfully.');
        }

        // For Cancelled, no Reminder Details were captured — skip follow-up creation
        if (status === 'Cancelled') {
            var navEvtCancel = $A.get("e.force:navigateToSObject");
            navEvtCancel.setParams({
                "recordId": recordId,
                "slideDevName": "detail"
            });
            navEvtCancel.fire();
            $A.get("e.force:closeQuickAction").fire();
            return;
        }

        // For Completed, no Follow-up is created — close after navigation
        if (status === 'Completed') {
            helper.maybeAdvanceLeadStatus(component, function() {
                var navEvtCompleted = $A.get("e.force:navigateToSObject");
                navEvtCompleted.setParams({
                    "recordId": recordId,
                    "slideDevName": "detail"
                });
                navEvtCompleted.fire();
                $A.get("e.force:closeQuickAction").fire();
            });
            return;
        }

        // Retrieve Follow-up details
        var followupDateTime = component.find("followupDateTime").get("v.value");
        var followupSubject = component.find("followupSubject").get("v.value");
        var followupRemark = component.find("followupRemark").get("v.value");
        var followupDescription = component.find("followupDescription").get("v.value");
         // Check if Follow-up Scheduled Date & Time is in the future
        var currentDate = new Date();
        var followupDate = new Date(followupDateTime);
        
        if (followupDate <= currentDate) {
            //alert('Follow-up Date & Time must be a future date and time.');
            helper.toastMsg('Error', 'error','Follow-up Date & Time must be a future date and time.');
            return; // Exit if validation fails
        }
        // Create Follow-up record
        var followUpRecord = {
            'sobjectType': 'Follow_up__c',
            'Scheduled_Date__c': followupDateTime,
            'Subject__c': followupSubject,
            'Comments__c': followupRemark,
            'Description__c': followupDescription,
            //'SLead__c': leadId
            //'Site_Visit__c': recordId // Link Follow-up to Site Visit record
        };
         // Insert Follow-up record via Apex (helper function or controller method)
        helper.createFollowUp(component, followUpRecord,recordId, function(response) {
            if(response.success) {
                // Navigate to the record page
                var navEvt = $A.get("e.force:navigateToSObject");
                navEvt.setParams({
                    "recordId": recordId,
                    "slideDevName": "detail"
                });
                navEvt.fire();
                $A.get("e.force:closeQuickAction").fire();
            } else {
                // On failure, show an error message
                component.set("v.isSubmitting", false);
               // component.set("v.spinner", false);
                helper.toastMsg('Error', 'There was an issue creating the follow-up', 'error');
            }
        });
        //helper.showToast('Success', 'Record saved successfully', 'success'); // Show success message
    },

    handleError: function(component, event, helper) {
        component.set("v.isSubmitting", false); // Hide the spinner after an error
        const errors = event.getParam("error");
        //alert('hello');
        //alert(JSON.stringify(errors));
        helper.toastMsg('Error', errors.message, 'Site Visit cannot be marked as Completed unless it has first been GRE Verified.'); // Show error message
    },

    closeModel: function(component, event, helper) {
        $A.get("e.force:closeQuickAction").fire(); // Close the modal after save or cancel
    },
    Status: function(component, event, helper){
        var status = event.getSource().get("v.value");
        // Keep both attributes in sync so other logic can read either
        component.set("v.status", status);
        component.set("v.SVStatus", status);
        if (status === 'Rescheduled') {
            helper.setDefaultFollowupDateTime(component);
        }
        if (status !== 'Completed') {
            // Reset Completed-only state when leaving Completed
            component.set("v.visitSourceType", "");
            component.set("v.svChannelPartnerId", "");
        }
    },
    handleVisitSourceTypeChange: function(component, event, helper){
        var src = component.find("visitSourceTypeField").get("v.value");
        component.set("v.visitSourceType", src);
        if (src !== 'CP') {
            component.set("v.svChannelPartnerId", "");
        }
    }
})