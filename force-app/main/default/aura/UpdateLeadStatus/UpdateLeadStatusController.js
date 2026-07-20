({
    // Last modified: 2026-05-06T10:49:27Z
    doInit: function(component, event, helper){
        // Default Site Visit / Follow-up Date & Time to (now + 5 minutes) so the
        // picker opens with a valid future time instead of exactly "now".
        var defaultDt = new Date(new Date().getTime() + 5 * 60 * 1000);
        component.set("v.defaultDateTime", defaultDt.toISOString());
        helper.fetchInitData(component, event, helper);
    },
   
    handleSuccess: function(component, event, helper) {
       component.set("v.isSubmitting", false);
        
        var status = component.get("v.status");
        var recordId = component.get("v.recordId");
        var closedLostReason = component.get("v.closedLostReason");
        var unQualifiedReason = component.get("v.UnqualifiedReason");
        var unqualifiedClosedLostRemarks = component.get("v.unqualifiedClosedLostRemarks");
        // Mandatory reason checks
        if (status === 'Unqualified' && !unQualifiedReason) {
            helper.toastMsg('Error', 'Unqualified Reason is mandatory when status is Unqualified.', 'error');
            component.set("v.isSubmitting", false);
            return;
        }
        if (status === 'Closed Lost' && !closedLostReason) {
            helper.toastMsg('Error', 'Closed Lost Reason is mandatory when status is Closed Lost.', 'error');
            component.set("v.isSubmitting", false);
            return;
        }
        if ((status === 'Unqualified' || status === 'Closed Lost') && !unqualifiedClosedLostRemarks) {
            helper.toastMsg('Error', 'Remarks are mandatory for Unqualified or Closed Lost.', 'error');
            return;
        }
        
        // Get Follow-up input values safely
        var followupDateTime = component.find("followupDateTime") ? component.find("followupDateTime").get("v.value") : null;
        var followupSubject = component.find("followupSubject") ? component.find("followupSubject").get("v.value") : null;
        var followupRemark = component.find("followupRemark") ? component.find("followupRemark").get("v.value") : null;

        // Site Visit inputs
        var siteVisitScheduledDateTime = component.find("siteVisitDateTime") ? component.find("siteVisitDateTime").get("v.value") : null;
        //Addded by Pattu
        var ProjectName = component.get("v.leadProject");
        var siteVisitDescription = component.find("siteVisitDescription") ? component.find("siteVisitDescription").get("v.value") : null;
        var visitType = component.get("v.visitType");
        // Visit Source Type / Channel Partner hidden for now; retain logic for future use.
        // var visitSourceType = component.get("v.visitSourceType");
        // var channelPartnerId = component.get("v.channelPartnerId");
        
        var now = new Date();
        var followupExpected = (status !== 'Unqualified' && status !== 'Closed Lost' && status !== 'Booked');
        
        // Validation for Follow-up section
        if (followupExpected) {
            if (!followupDateTime || !followupSubject || !followupRemark) {
                helper.toastMsg('Error', 'Follow-up Date, Subject, and Remark are mandatory.', 'error');
                component.set("v.isSubmitting", false);
                return;
            }
            if (new Date(followupDateTime) <= now) {
                helper.toastMsg('Error', 'Follow-up Date & Time must be a future date and time.', 'error');
                component.set("v.isSubmitting", false);
                return;
            }
        }
        
        // Validation for Site Visit
        if (status === 'Site Visit Scheduled') {
            if (!siteVisitScheduledDateTime || !ProjectName) {
                helper.toastMsg('Error', 'Site Visit Date/Time and Project Name are mandatory.', 'error');
                component.set("v.isSubmitting", false);
                return;
            }
            if (new Date(siteVisitScheduledDateTime) <= now) {
                helper.toastMsg('Error', 'Site Visit Date & Time must be a future date and time.', 'error');
                component.set("v.isSubmitting", false);
                return;
            }
            if (!visitType) {
                helper.toastMsg('Error', 'Visit Type is mandatory.', 'error');
                component.set("v.isSubmitting", false);
                return;
            }
            // Visit Source Type / Channel Partner validations hidden for now; retain logic for future use.
            // if (visitType === 'Site Visit' && !visitSourceType) {
            //     helper.toastMsg('Error', 'Visit Source Type is mandatory when Visit Type is Site Visit.', 'error');
            //     component.set("v.isSubmitting", false);
            //     return;
            // }
            // if (visitSourceType === 'CP' && !channelPartnerId) {
            //     helper.toastMsg('Error', 'Channel Partner is mandatory when Visit Source Type is CP.', 'error');
            //     component.set("v.isSubmitting", false);
            //     return;
            // }
        }
        
        // Proceed — Lead update logic wrapped so it can run directly for terminal
        // statuses (Unqualified / Closed Lost / Booked) where the Lead trigger
        // cascades open Site Visits to Cancelled and open Follow-ups to Missed.
        var proceedWithUpdate = function() {
            var leadRecord = {
                sobjectType: 'Lead',
                Lead_Status__c: status,
                Unqualified_Reason__c: unQualifiedReason,
                Closed_Lost_Reason__c: closedLostReason,
                Unqualified_Closed_Lost_Remarks__c: unqualifiedClosedLostRemarks,
                Id: recordId
            };

            var action = component.get("c.LeadUpdation");
            action.setParams({ leadRecord: JSON.stringify(leadRecord) });

            action.setCallback(this, function(resp) {
                var st = resp.getState();
                if (st !== "SUCCESS") {
                    var errs = resp.getError();
                    helper.toastMsg('Error', (errs && errs[0] && errs[0].message) ? errs[0].message : 'Error updating Lead.', 'error');
                    component.set("v.isSubmitting", false);
                    return;
                }

                if (!followupExpected) {
                    helper.toastMsg('Success', 'Lead updated successfully.', 'success');
                    helper.navigateToRecord(recordId);
                    return;
                }

                // Create Follow-up
                var followUpRecord = {
                    sobjectType: 'Follow_up__c',
                    Scheduled_Date__c: followupDateTime,
                    Subject__c: followupSubject,
                    Comments__c: followupRemark
                };

                if (status === 'Site Visit Scheduled') {
                    var siteVisitRecord = {
                        sobjectType: 'Site_Visit__c',
                        Status__c: 'Scheduled',
                        Date__c: siteVisitScheduledDateTime,
                        Project__c: ProjectName,
                        Feedback__c: siteVisitDescription,
                        CLead__c: recordId,
                        Visit_Type__c: visitType
                        // Visit Source Type / Channel Partner hidden for now; retain mapping for future use.
                        // Visit_Source_Type__c: visitSourceType,
                        // Channel_Partner__c: channelPartnerId
                    };

                    //added by karthik 14-11-25
                    helper.checkExistingSV(component, recordId, ProjectName, function(svExists) {
                        if (svExists) {
                            helper.toastMsg(
                                'Error',
                                'A Site Visit is already scheduled for this project. You cannot create another one.',
                                'error'
                            );
                            component.set("v.isSubmitting", false);
                            return;
                        }

                    helper.createSiteVisit(component, siteVisitRecord, recordId, function(svRes) {
                        if (!svRes.success) {
                            helper.toastMsg('Error', 'There was an issue creating the Site Visit.', 'error');
                            component.set("v.isSubmitting", false);
                            return;
                        }

                        helper.createFollowUp(component, followUpRecord, recordId, function(fuRes) {
                            if (fuRes.success) {
                                helper.toastMsg('Success', 'Lead updated, Site Visit scheduled and Follow-up created.', 'success');
                                helper.navigateToRecord(recordId);
                            } else {
                                helper.toastMsg('Error', 'There was an issue creating the Follow-up.', 'error');
                                component.set("v.isSubmitting", false);
                            }
                        });
                    });
                    });
                } else {
                    helper.createFollowUp(component, followUpRecord, recordId, function(fuRes) {
                        if (fuRes.success) {
                            helper.toastMsg('Success', 'Lead updated and Follow-up created successfully.', 'success');
                            helper.navigateToRecord(recordId);
                        } else {
                            helper.toastMsg('Error', 'There was an issue creating the Follow-up.', 'error');
                            component.set("v.isSubmitting", false);
                        }
                    });
                }
            });
            $A.enqueueAction(action);
        };

        // Only block on an existing Scheduled Follow-up when we would be
        // creating a new one. For terminal statuses (Unqualified / Closed Lost /
        // Booked) the Lead trigger marks the open Follow-up as Missed, so skip
        // the block — mirrors how Site Visits are already handled.
        if (followupExpected) {
            helper.checkExistingFollowup(component, recordId, function(res) {
                if (res.exists) {
                    helper.toastMsg(
                        'Error',
                        'This Lead already has a Scheduled Follow-up. Please close it before adding a new Follow-up or Site Visit.',
                        'error'
                    );
                    component.set("v.isSubmitting", false);
                    $A.get("e.force:closeQuickAction").fire();
                    return;
                }
                proceedWithUpdate();
            });
        } else {
            proceedWithUpdate();
        }
    },

    handleError: function(component, event, helper) {
        component.set("v.isSubmitting", false); // Hide the spinner after an error
        const errors = event.getParam("error");
        //alert('hello');
        //alert(JSON.stringify(errors));
        helper.toastMsg('Error', errors.message, 'error'); // Show error message
    },

    closeModel: function(component, event, helper) {
        $A.get("e.force:closeQuickAction").fire(); // Close the modal after save or cancel
    },
    
    Status: function(component, event, helper){
        var status = event.getParam("value");
        if (!status) {
            status = event.getSource().get("v.value");
        }
        component.set("v.status", status);
    },

    // Visit Source Type handler hidden for now; retain logic for future use.
    // visitSourceTypeChange: function(component, event, helper){
    //     var visitSourceType = event.getSource().get("v.value");
    //     component.set("v.visitSourceType", visitSourceType);
    //     component.set("v.channelPartnerId", "");
    // },

})