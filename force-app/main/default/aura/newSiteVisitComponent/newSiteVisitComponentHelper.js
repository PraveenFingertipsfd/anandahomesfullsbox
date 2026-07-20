({
    toastMsg : function (type, title, msg) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": title,
            "type": type,
            "message": msg
        });
        toastEvent.fire();
    },

    // Translate a raw platform access error into a friendly message.
    // Returns the friendly text when the error is an access error, otherwise null.
    mapLeadAccessError : function (msg) {
        if (msg && /INSUFFICIENT_ACCESS_OR_READONLY|insufficient access/i.test(msg)) {
            return "You don't have edit access to this lead. Please contact your administrator.";
        }
        return null;
    },

    // Pull the first error message out of an Aura server response.
    getResponseError : function (response) {
        var errors = response.getError();
        return (errors && errors[0] && errors[0].message) ? errors[0].message : '';
    },

    createFollowUp : function(component, followUpRecord, recordId, callback) {
        var action = component.get("c.createFollowUpApex");
        action.setParams({
            followUpRecord: JSON.stringify(followUpRecord),
            SiteVisitId: '',
            LeadId: recordId
        });

        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                callback({ success: true });
            } else {
                callback({ success: false, error: this.getResponseError(response) });
            }
        });
        $A.enqueueAction(action);
    },

    createSiteVisit: function(component, siteVisitRecord, myRecordId, leadOwnerId, callback) {
        var action = component.get("c.createSiteVisitApex");
        action.setParams({
            siteVisitRecord: JSON.stringify(siteVisitRecord),
            leadOwnerId: leadOwnerId
        });

        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                callback({ success: true });
            } else {
                callback({ success: false, error: this.getResponseError(response) });
            }
        });
        $A.enqueueAction(action);
    },

    processSiteVisitCreation : function(component, helper, recordId) {

        var siteVisitScheduledDateTime = component.find("siteVisitDateTime").get("v.value");
        var ProjectName = component.get("v.leadProject");
        var visitType = component.find("visitType").get("v.value");
        var leadOwnerId = component.get("v.leadOwnerId");
        var siteVisitDescription = component.find("siteVisitDescription").get("v.value");
        var currentDate = new Date();
        var siteVisitDate = new Date(siteVisitScheduledDateTime);

        if (siteVisitDate <= currentDate) {
            helper.toastMsg("error", "Invalid Date", "Site Visit Date & Time must be in the future.");
            component.set("v.isSubmitting", false);
            return;
        }
        if (!siteVisitScheduledDateTime || !ProjectName || !visitType) {
            helper.toastMsg("error", "Missing Fields", "Site Visit Date/Time, Project and Visit Type are required.");
            component.set("v.isSubmitting", false);
            return;
        }
        component.set("v.visitType", visitType);

        // Visit Type / Source / Channel Partner validations - hidden, kept for future use
        // var visitType = component.get("v.visitType");
        // var visitSourceType = component.get("v.visitSourceType");
        // var channelPartnerId = component.get("v.channelPartnerId");
        //
        // if (!visitType) {
        //     helper.toastMsg("error", "Missing Fields", "Visit Type is required.");
        //     component.set("v.isSubmitting", false);
        //     return;
        // }
        // if (visitType === 'Site Visit' && !visitSourceType) {
        //     helper.toastMsg("error", "Missing Fields", "Visit Source Type is required when Visit Type is Site Visit.");
        //     component.set("v.isSubmitting", false);
        //     return;
        // }
        // if (visitSourceType === 'CP' && !channelPartnerId) {
        //     helper.toastMsg("error", "Missing Fields", "Channel Partner is required when Visit Source Type is CP.");
        //     component.set("v.isSubmitting", false);
        //     return;
        // }

        // Prevent Duplicate Scheduled SV for same Project
        var svAction = component.get("c.hasScheduledSV");
        svAction.setParams({ leadId: recordId, projectName: ProjectName });

        svAction.setCallback(this, function(svRes) {
            if (svRes.getState() === "SUCCESS" && svRes.getReturnValue()) {
                helper.toastMsg("error", "Duplicate Site Visit",
                                "A Scheduled Site Visit already exists for this Project.");
                component.set("v.isSubmitting", false);
                return;
            }

            // Auto-update Lead Status
            var statusAction = component.get("c.getLeadStatus");
            statusAction.setParams({ leadId: recordId });

            statusAction.setCallback(this, function(stRes) {
                var leadStatus = stRes.getReturnValue();

                if (leadStatus === "New Sales Enquiry" || leadStatus === "Sales Follow up") {
                    var updAct = component.get("c.updateLeadStatusOnly");
                    updAct.setParams({
                        leadId: recordId,
                        newStatus: "Site Visit Scheduled"
                    });
                    updAct.setCallback(this, function(updRes) {
                        if (updRes.getState() !== "SUCCESS") {
                            var accessMsg = helper.mapLeadAccessError(helper.getResponseError(updRes));
                            if (accessMsg) {
                                helper.toastMsg("error", "Error", accessMsg);
                            }
                        }
                    });
                    $A.enqueueAction(updAct);
                }

                var siteVisitRecord = {
                    sobjectType: "Site_Visit__c",
                    Status__c: "Scheduled",
                    Date__c: siteVisitScheduledDateTime,
                    Project__c: ProjectName,
                    Visit_Type__c: visitType,
                    Feedback__c: siteVisitDescription,
                    CLead__c: recordId
                };
                // if (visitSourceType === 'CP' && channelPartnerId) {
                //     siteVisitRecord.Channel_Partner__c = channelPartnerId;
                // }

                // Follow-up details
                var followupDateTime = component.find("followupDateTime").get("v.value");
                var followupSubject = component.find("followupSubject").get("v.value");
                var followupRemark = component.find("followupRemark").get("v.value");
                var followupDate = new Date(followupDateTime);

                if (followupDate <= currentDate) {
                    helper.toastMsg("error", "Invalid Date", "Follow-up Date & Time must be in the future.");
                    component.set("v.isSubmitting", false);
                    return;
                }
                if (!followupDateTime || !followupSubject || !followupRemark) {
                    helper.toastMsg("error", "Missing Fields", "Follow-up Date, Subject, and Remark are required.");
                    component.set("v.isSubmitting", false);
                    return;
                }

                var followUpRecord = {
                    sobjectType: "Follow_up__c",
                    Scheduled_Date__c: followupDateTime,
                    Subject__c: followupSubject,
                    Comments__c: followupRemark
                };

                // Create Site Visit first
                helper.createSiteVisit(component, siteVisitRecord, recordId, leadOwnerId, function(response) {
                    if (response.success) {
                        // Then create Follow-up
                        helper.createFollowUp(component, followUpRecord, recordId, function(res) {
                            if (res.success) {
                                helper.toastMsg("success", "Success", "Site Visit & Follow-up created successfully");
                                component.set("v.isModalOpen", false);
                                component.set("v.isSubmitting", false);
                                $A.get("e.force:closeQuickAction").fire();
                                $A.get('e.force:refreshView').fire();
                            } else {
                                component.set("v.isSubmitting", false);
                                var fuAccessMsg = helper.mapLeadAccessError(res.error);
                                if (fuAccessMsg) {
                                    helper.toastMsg("error", "Error", fuAccessMsg);
                                } else {
                                    helper.toastMsg("error", "Follow-up Creation Failed", "Please try again.");
                                }
                            }
                        });
                    } else {
                        component.set("v.isSubmitting", false);
                        var svAccessMsg = helper.mapLeadAccessError(response.error);
                        if (svAccessMsg) {
                            helper.toastMsg("error", "Error", svAccessMsg);
                        } else {
                            helper.toastMsg("error", "Site Visit Creation Failed", "Please try again.");
                        }
                    }
                });

            });

            $A.enqueueAction(statusAction);

        });

        $A.enqueueAction(svAction);
    }

})