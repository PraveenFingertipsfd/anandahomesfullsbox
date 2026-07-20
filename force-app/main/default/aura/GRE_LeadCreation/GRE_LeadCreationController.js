({
    doInit: function(component, event, helper) {
        
        // IMPORTANT: Ensure isSelectedLead is false on init to prevent layout issues..
        component.set('v.isSelectedLead', false);
        
        // Pre-fetch user details
        var userId = $A.get("$SObjectType.CurrentUser.Id");
        component.set('v.userId', userId);

        var userAction = component.get("c.getCurrentUserDetails");
        userAction.setCallback(this, function(resp) {
            if (resp.getState() === "SUCCESS") {
                var u = resp.getReturnValue();
                component.set("v.currentUserProfile", u.profileName);
                component.set("v.currentUserProject", u.projectPicklistValue);
                component.set("v.isGREUser", u.profileName === "GRE");
            }
        });
        $A.enqueueAction(userAction);

        // Pre-fetch country codes
        var countryAction = component.get("c.getCountryAndCode");
        countryAction.setCallback(this, function(response) {
            if (response.getState() === "SUCCESS") {
                component.set("v.sectionLabels", response.getReturnValue());
            }
        });
        $A.enqueueAction(countryAction);

        // Pre-fetch record type ID
        helper.getRecordTypeId(component, event);
    },
    toggleNewLead: function(component, event, helper) {
        var visible = component.get('v.newLeadForm');
        visible = !visible;
        /* commented out for later use - Reset CP-related state when closing the modal (Source Type WALKIN - CP)
        if (!visible) {
            component.set('v.isWalkinCP', false);
            component.set('v.selectedCPId', null);
        }
        */
        component.set('v.newLeadForm', visible);
    },
    handleCountryChange: function(component, event, helper) {
        var selectedUnitId = component.find("CountryLookupField").get("v.value");
        var countryMap = component.get("v.sectionLabels");
        console.log(JSON.stringify(countryMap));
        var selectedCountryCode = countryMap[selectedUnitId];
        component.set("v.selectedCountryCode", selectedCountryCode);
        
    },
    handleError: function (cmp, event, helper) {
        cmp.set("v.isSubmitting", false);
        cmp.set('v.spinner', false);

        // Get the error message
        var errorMessage = event.getParam("message");
        if(errorMessage=='The requested resource does not exist'){
            helper.toastMsg('error','Duplicate','Lead already exist in the system');
            cmp.set('v.selectedLead',[]);
            cmp.set('v.isSelectedLead',false);
            cmp.set('v.newLeadForm', false);
            return;
        }

        // Show any other server validation/DML error as a proper toast (no inline banner)
        helper.toastMsg('error', 'Error', helper.extractFormError(event));
    },
    handleSubmit : function(component, event, helper) {
        component.set("v.isSubmitting", true);
        component.set('v.spinner', true);
        event.preventDefault(); // Stop the form submission to handle it manually
        var recordTypeId = component.find("v.recordTypeId");
        // Get the field values
        let phoneField = component.find("PhoneNumber");
        let secondaryPhoneField = component.find("secondaryPhoneNumber");
        
        // Get actual values
        let phoneValue = phoneField.get("v.value");
        let secondaryPhoneValue = secondaryPhoneField.get("v.value");

        // Validate phone numbers client-side (mirrors Lead__c Mobile_Number_Validation rule)
        var TEN_DIGITS = /^[0-9]{10}$/;
        var badPhone = phoneValue && !TEN_DIGITS.test(String(phoneValue));
        var badSecondary = secondaryPhoneValue && !TEN_DIGITS.test(String(secondaryPhoneValue));
        if (badPhone || badSecondary) {
            component.set("v.isSubmitting", false);
            component.set('v.spinner', false);
            helper.toastMsg('error', 'Invalid Phone Number',
                'Phone Number and Secondary Phone Number must contain exactly 10 digits and only numbers.');
            return;
        }

        // Get the event fields and add additional values
        var eventFields = event.getParam("fields");

        var subSourceValue = eventFields["Primary_Sub_Source__c"];
        if (!subSourceValue) {
            component.set("v.isSubmitting", false);
            component.set('v.spinner', false);
            helper.toastMsg('error', 'Error', 'Please select a Primary Sub Source.');
            return;
        }

        let countryCode = component.get('v.selectedCountryCode');
        if (countryCode) {
            eventFields["Country_Code__c"] = countryCode;
        }

        /* commented out by claude 30-03-26 08:49 - Sales User manual assignment, replaced with round-robin
        let salesUser = eventFields["Sales_User__c"];
        if (salesUser) {
            eventFields["OwnerId"] = salesUser;
            eventFields["Lead_Assigned__c"] = true;
        } else {
            eventFields["Lead_Assigned__c"] = false;
        }
        */

        // added by claude 30-03-26 08:49 - Lead will be assigned via round-robin after creation
        eventFields["Lead_Assigned__c"] = false;
        // Set Lead_source__c to Walk-in so the trigger uses the correct Sales record type path
        eventFields["Lead_source__c"] = "Walk-in";
        // Prevent trigger's round-robin — assignLeadRoundRobin handles it after creation
        eventFields["Round_Robin_Off__c"] = true;
        eventFields["Pushed_On__c"] = new Date().toISOString();
        eventFields["Pushed_By__c"] = $A.get("$SObjectType.CurrentUser.Id");

        var isWalkinCP = component.get("v.isWalkinCP");
        if (isWalkinCP) {
            var cpId = component.get("v.selectedCPId");
            if (!cpId) {
                component.set("v.isSubmitting", false);
                component.set('v.spinner', false);
                helper.toastMsg('error', 'Error', 'Please select a Channel Partner.');
                return;
            }
            eventFields["Primary_Channel_Partner__c"] = cpId;
            eventFields["Channel_Partner__c"] = cpId;
        }

        component.find('myform').submit(eventFields);
    },
    // updated by claude 30-03-26 15:32 - handleSuccess: close modal immediately, use handleSelectLead instead of getLeadDetailsById
    handleSuccess : function(component, event, helper) {
        component.set("v.isSubmitting", false);

        var returnData = event.getParam("response");
        var leadId = returnData.id;
        console.log('Lead Id: ' + leadId);

        // Close modal and reset form immediately
        component.set('v.newLeadForm', false);
        /* commented out for later use - WALKIN - CP state reset
        component.set('v.isWalkinCP', false);
        component.set('v.selectedCPId', null);
        */

        // Set lead ID so handleSelectLead can fetch details
        component.set('v.selectedLeadId', leadId);
        component.set('v.selectedLead', { Id: leadId });

        // Assign lead via round-robin (also auto-creates Site Visit)
        var rrAction = component.get("c.assignLeadRoundRobin");
        rrAction.setParams({ "leadId": leadId });
        rrAction.setCallback(this, function(rrResponse) {
            var rrState = rrResponse.getState();
            if (rrState === "SUCCESS") {
                console.log('Round Robin assignment successful');
            } else {
                var errors = rrResponse.getError();
                var errMsg = 'Lead created but auto-assignment failed.';
                if (errors && errors[0] && errors[0].message) {
                    errMsg = errors[0].message;
                }
                helper.toastMsg('warning', 'Assignment Warning', errMsg);
            }

            // Show success toast
            var toastEvent = $A.get("e.force:showToast");
            toastEvent.setParams({
                message: 'Lead created successfully',
                type: 'success'
            });
            toastEvent.fire();

            // Load lead detail view using handleSelectLead (queries Lead__c correctly)
            component.set('v.spinner', false);
            helper.handleSelectLead(component, event, helper);
        });
        $A.enqueueAction(rrAction);
    },
    
    getLeads: function(component, event, helper) {
        var searchValue = event.target.value;
        console.log('Search Value: ' + searchValue);
        
        var action = component.get("c.fetchLeads");
        action.setParams({'searchValue': searchValue});
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            console.log('State: ' + state);
            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                component.set('v.projectOptions',result.ProjLst);
                component.set('v.projectUserMap',result.prjUserList);
                component.set('v.salesRecordTypeId',result.salesRecordTypeId);
                
                var leads = result.leadRecords;
                // Format the CreatedDate for each lead
                leads.forEach(function(lead) {
                    lead.formattedCreatedDate = helper.formatDate(lead.CreatedDate);
                });
                
                // Set the formatted leads in the component attribute
                component.set("v.leads", leads); 
            } else {
                console.error("Error fetching leads: " + response.getError());
            }
        });
        
        $A.enqueueAction(action); 
        helper.fetchSalesUsers(component,event,helper);
    },
    onSelectLead: function(component, event, helper) {
        var selectedLead = event.currentTarget.name;
        console.log('Selected Lead '+ JSON.stringify(selectedLead));
        component.set('v.selectedLead', selectedLead);
        component.set('v.selectedLeadId', selectedLead.Id);
        component.set('v.selectedLeadProject', selectedLead.Allocated_Project__c);
        component.set('v.recordTypeName', selectedLead.RecordType.Name);
        helper.handleSelectLead(component, event, helper);
    },
    onGobackToList: function(component, event, helper) {
        component.set('v.selectedLead',[]);
        component.set('v.isSelectedLead',false);
    },
    
    onCreateSiteVisit: function(component, event, helper) {
        if (component.get("v.siteVisitInProgress")) {
            return;
        }
        console.log('here5');
        component.set("v.siteVisitInProgress", true);
        var leadId = component.get("v.selectedLeadId");
        var projectName = component.get("v.selectedLeadProject");
        var HandledBy = component.get("v.selectedHandleByUserValue");
        if (!leadId) {
            alert("Please select a lead first.");
            component.set("v.siteVisitInProgress", false);
            return;
        }
      
        var action = component.get("c.createSiteVisit");
        action.setParams({ leadId: leadId, projectName: projectName, handledById: HandledBy });
        action.setCallback(this, function(response) {
            component.set("v.siteVisitInProgress", false);
            var state = response.getState();
            if (state === "SUCCESS") {
                var newSiteVisit = response.getReturnValue();
                var existingSiteVisit = {};
                existingSiteVisit.siteVisitNumber = newSiteVisit.Name;
                existingSiteVisit.projectName = newSiteVisit.Project__c;
                existingSiteVisit.status = newSiteVisit.Status__c;
                existingSiteVisit.scheduledDate = helper.formatDateTime(newSiteVisit.Date__c);
                existingSiteVisit.ownerName = newSiteVisit.Owner.Name;
                existingSiteVisit.Id = newSiteVisit.Id;
                existingSiteVisit.completedDate = helper.formatDateTime(newSiteVisit.SV_Completed_Date_Time__c);
                component.set("v.scheduledSiteVisit", existingSiteVisit);
                
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    message: 'New site visit created',
                    type: 'success'
                });
                toastEvent.fire(); 
                
            } else {
                console.log('Error');
                console.error("Error: ", response.getError());
            }
        });
        
        $A.enqueueAction(action);
    },
    completeSiteVisit: function(component, event, helper) {
        //alert('hi');
        var siteVisit = component.get("v.scheduledSiteVisit");
        console.log('siteVisit '+JSON.stringify(siteVisit));
        // Check if the site visit exists
        if (!siteVisit || !siteVisit.Id) {
            console.error("No site visit available to complete.");
            alert("Error: No site visit available to mark as Remark.");
            return;
        }
        var Remark = component.get("v.Remark");
        //alert('Remark '+Remark);
        if(!Remark){
           alert("Error: Remark is Mandatory. Please fill.");
            return;
        }
        /*var checkIn = component.get("v.checkInDateTime");*/
        var checkOut = component.get("v.checkOutDateTime");  
		if (!checkOut) {
            // Show an error message if the field is empty
            console.log("Error: Date and Time is required.");
            //alert("Error: Check OUT date and Time is Mandatory. Please fill.");
            component.set("v.showError", true);
            return;
        } 
        else{
            component.set("v.showError", false);
        }
        
        // Update the status of the site visit to "Completed"
        siteVisit.status = "Completed";
        
        // Show loading spinner while waiting for the Apex call
        component.set("v.isLoading", true);
        
        // Call Apex to update the site visit status
          var action = component.get("c.updateSiteVisitStatus");
        action.setParams({
            "siteVisitId": siteVisit.Id,
            "status": siteVisit.status,
            "Remark":Remark,
            "checkouttime":checkOut
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var newSiteVisit = response.getReturnValue();
                var existingSiteVisit = {};
                existingSiteVisit.siteVisitNumber = newSiteVisit.Name;
                existingSiteVisit.projectName = newSiteVisit.Project__c;
                existingSiteVisit.status = newSiteVisit.Status__c;
                existingSiteVisit.scheduledDate = helper.formatDateTime(newSiteVisit.Date__c);
                existingSiteVisit.ownerName = newSiteVisit.Owner.Name;
                existingSiteVisit.Id = newSiteVisit.Id;
                existingSiteVisit.completedDate = helper.formatDateTime(newSiteVisit.SV_Completed_Date_Time__c);
                component.set("v.scheduledSiteVisit", existingSiteVisit);
                
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    message: 'Site Visit Updated',
                    type: 'success'
                });
                toastEvent.fire(); 
                component.set("v.Remark",'');
                component.set("v.checkOutDateTime", null);
                component.set("v.isLoading", false);
                
            } else if (state === "ERROR") {
                // Handle Apex errors
                var errors = response.getError();
                if (errors && errors.length > 0) {
                    console.error("Error updating site visit: " + errors[0].message);
                    alert("Error updating site visit: " + errors[0].message);
                } else {
                    console.error("Unknown error occurred while updating site visit.");
                    alert("An unknown error occurred while updating the site visit.");
                }
                
                // Hide the loading spinner in case of error
                component.set("v.isLoading", false);
            }
        });
        
        // Enqueue the action to call Apex
        $A.enqueueAction(action);
    },
    handlepushToSales : function(component, event, helper) {
        var leadId = component.get('v.selectedLeadId');
        var noteValue = component.get("v.newNote");
        var salesUser = component.get("v.selectedUserValue");
        
        // Get reference to the textarea component
        var noteInputCmp = component.find("noteInput");
        
        // Clear any previous error
        noteInputCmp.setCustomValidity("");
        noteInputCmp.reportValidity();
        
        // Validate
        if (!noteValue || noteValue.trim() === "") {
            noteInputCmp.setCustomValidity("Please provide the lead transfer note");
            noteInputCmp.reportValidity();
            return; // Stop execution
        }
        
        
        // Proceed with Apex call
        var action = component.get("c.moveToSales");
        action.setParams({ 
            LeadId: leadId,
            addNote: noteValue,
            salesUser:salesUser
        });
        
        component.set("v.isButtonDisabled", true);
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === 'SUCCESS') {
                var newRecordType = response.getReturnValue();
                component.set('v.recordTypeName',newRecordType);
                
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    message: 'Lead moved to sales team',
                    type: 'success'
                });
                toastEvent.fire(); 
            }
        });
        
        $A.enqueueAction(action);
    },
    isChannelPartner: function(component, event, helper) {
        var eventFields = event.getParam("fields");
        var source = component.get("v.leadSource");
        if(source == "Channel Partner"){
            component.set('v.isChannelPartner',true);
        }
        else{
            component.set('v.isChannelPartner',false);
        }

    },

    handleSubSourceChange : function(component, event, helper) {
        var fields = event.getParam("fields") || {};
        var subSource = fields.Primary_Sub_Source__c;
        if (subSource === undefined || subSource === null) {
            subSource = event.getSource().get("v.value");
        }
        var isCP = (subSource === "WALKIN - CP");
        component.set("v.isWalkinCP", isCP);
        if (!isCP) {
            component.set("v.selectedCPId", null);
        }
    },
    
    onPrjChange :function(component, event, helper) {
        var prjval = event.getSource().get("v.value");
        var projectUserMap = component.get("v.projectUserMap");
        component.set("v.handledByOptions", projectUserMap[prjval] || []);
    },
    
    openSVCompModal1 : function(component, event, helper) {
        
        var svId = event.currentTarget.dataset.id;
        var svStatus = event.currentTarget.dataset.status;
        
        // Always load user details first
        var action = component.get("c.getCurrentUserDetails");
        action.setCallback(this, function(resp) {
            
            if (resp.getState() === "SUCCESS") {
                
                var u = resp.getReturnValue();
                var profile = u.profileName;
                var userProject = u.projectPicklistValue;
                
                component.set("v.currentUserProfile", profile);
                component.set("v.currentUserProject", userProject);
                
                // ===== EXISTING SV FLOW =====
                if (svId && svStatus) {
                    
                    var visits = component.get("v.siteVisits");
                    var matchedSV = visits.find(function(sv) {
                        return sv.Id === svId;
                    });
                    
                    console.log('Matched Site Visit:', JSON.stringify(matchedSV));
                    
                    if (profile === 'GRE' && userProject !== matchedSV.Project__c) {
                        console.log('GRE cannot open other project SV');
                        helper.toastMsg("error", "Access Denied", "GRE cannot open other project SV.");
                        return;
                    }
                    
                    if (svStatus === 'Scheduled' || svStatus === 'Rescheduled') {
                        
                        component.set("v.newSiteVisit", {
                            Id: matchedSV.Id,
                            Project__c: matchedSV.Project__c,
                            Handled_By__c: '',
                            Remark__c: ''
                        });
                        
                        var map = component.get("v.projectUserMap");
                        component.set("v.handledByOptions", map[matchedSV.Project__c] || []);
                        
                        component.set("v.isFromExistingSV", true);
                        component.set("v.isSVCompModalOpen", true);
                    }
                    return;
                }
                
                // ===== NEW SV FLOW =====
                component.set("v.isFromExistingSV", false);
                component.set("v.isSVCompModalOpen", true);
                
                component.set("v.newSiteVisit", {
                    Id: null,
                    Project__c: '',
                    Handled_By__c: '',
                    Remark__c: '',
                    Date__c: new Date().toISOString()
                });
                
                component.set("v.handledByOptions", []);
                
                if (profile === 'GRE') {
                    
                    component.set("v.isGREUser", true);
                    component.set("v.newSiteVisit.Project__c", userProject);
                    
                    var map = component.get("v.projectUserMap");
                    component.set("v.handledByOptions", map[userProject] || []);
                }
            }
        });
        
        $A.enqueueAction(action);
    },
    openSVCompModal : function(component, event, helper) {
        
        var svId = event.currentTarget.dataset.id;
        var svStatus = event.currentTarget.dataset.status;
        
        var action = component.get("c.getCurrentUserDetails");
        action.setCallback(this, function(resp) {
            
            if (resp.getState() !== "SUCCESS") {
                return;
            }
            
            var u = resp.getReturnValue();
            var profile = u.profileName;
            var userProject = u.projectPicklistValue;
            
            // ⭐ Round Robin is always enabled (manual selection hidden)
            component.set("v.useRoundRobin", true);
            component.set("v.currentUserProfile", profile);
            component.set("v.currentUserProject", userProject);
            
            var visits = component.get("v.siteVisits");
            var matchedSV = visits.find(function(sv) {
                return sv.Id === svId;
            });
            
            /* ---------------------------------------------
           CASE 1: COMPLETED + CHECKOUT NOT FILLED
           --------------------------------------------- */
        if (matchedSV &&
            matchedSV.Status__c === "Completed" &&
            (!matchedSV.Check_Out__c || matchedSV.Check_Out__c === "")) {
            
            if (profile === "GRE" && userProject !== matchedSV.Project__c) {
                helper.toastMsg("error", "Access Denied", "GRE cannot open other project SV.");
                return;
            }
            
            component.set("v.checkoutSVId", svId);
            component.set("v.isCheckoutModalOpen", true);
            return;
        }

        /* ---------------------------------------------
           CASE 2: EXISTING SITE VISIT (Scheduled/Rescheduled)
           --------------------------------------------- */
        if (svId && svStatus) {
            
            if (profile === "GRE" && userProject !== matchedSV.Project__c) {
                helper.toastMsg("error", "Access Denied", "GRE cannot open other project SV.");
                return;
            }
            
            if (svStatus === "Scheduled" || svStatus === "Rescheduled") {

                component.set("v.newSiteVisit", {
                    Id: matchedSV.Id,
                    Project__c: matchedSV.Project__c,
                    Handled_By__c: "",
                    Remark__c: ""
                });

                var map = component.get("v.projectUserMap");
                component.set("v.handledByOptions", map[matchedSV.Project__c] || []);

                component.set("v.svVisitType", matchedSV.Visit_Type__c || "");
                component.set("v.svVisitSourceType", "");
                component.set("v.svChannelPartnerId", "");

                component.set("v.isFromExistingSV", true);
                component.set("v.isSVCompModalOpen", true);
            }
            
            return;
        }
        
        /* ---------------------------------------------
           CASE 3: NEW SITE VISIT
           --------------------------------------------- */
        component.set("v.isFromExistingSV", false);
        component.set("v.isSVCompModalOpen", true);

        component.set("v.newSiteVisit", {
            Id: null,
            Project__c: "",
            Handled_By__c: "",
            Remark__c: "",
            Date__c: new Date().toISOString()
        });

        component.set("v.svVisitType", "On-Site");
        component.set("v.svVisitSourceType", "");
        component.set("v.svChannelPartnerId", "");

        component.set("v.handledByOptions", []);
        
        if (profile === "GRE") {
            
            component.set("v.isGREUser", true);
            component.set("v.newSiteVisit.Project__c", userProject);
            
            var map2 = component.get("v.projectUserMap");
            component.set("v.handledByOptions", map2[userProject] || []);
        }
    });
        
        $A.enqueueAction(action);
    },



    closeSVCompModal : function(component, event, helper) {
        component.set("v.isSVCompModalOpen", false);
        component.set("v.svVisitType", "");
        component.set("v.svVisitSourceType", "");
        component.set("v.svChannelPartnerId", "");
    },
    
    //og code 18-02-26
    saveSiteVisit1 : function(component, event, helper) {
        var TotalSV = component.get("v.siteVisits");
        var SvRec = component.get("v.newSiteVisit");
        var leadId = component.get("v.selectedLeadId");
        if(SvRec.Project__c == undefined || SvRec.Project__c ==null || SvRec.Project__c ==''){
            helper.toastMsg('error','Error','Select Project');
            return;
        }
        if(SvRec.Handled_By__c == undefined || SvRec.Handled_By__c ==null || SvRec.Handled_By__c ==''){
            helper.toastMsg('error','Error','Select Handled By User');
            return;
        }
        //added by karthik 18-11-25
        if(SvRec.Remark__c == undefined || SvRec.Remark__c ==null || SvRec.Remark__c ==''){
            helper.toastMsg('error','Error','Remarks is mandatory.');
            return;
        }
        var duplicateFound = false;
        for (var i = 0; i < TotalSV.length; i++) {
            var existingSV = TotalSV[i];
            if (existingSV.Status__c === 'Scheduled' && existingSV.Project__c === SvRec.Project__c && existingSV.Id !== SvRec.Id ) {
                duplicateFound = true;
                break;
            }
        }
        if (duplicateFound) {
            helper.toastMsg('error', 'Duplicate Site Visit', 'A Scheduled Site Visit already exists for this Project.');
            return;
        }
        
        SvRec.Check_In__c = new Date().toISOString();
        SvRec.CLead__c = leadId;
        SvRec.SV_Completed_Date_Time__c = new Date().toISOString();
        SvRec.Status__c = 'Completed';
        component.set("v.newSiteVisit",SvRec);

        var Lead = component.get('v.selectedLead');
        var rs = {};

        var actionType = '';
        
        if(Lead.Lead_Status__c == 'Unqualified' || Lead.Lead_Status__c == 'Closed Lost'){
            actionType = 'insertRelatedSource';
            Lead.RecordTypeId = component.get('v.salesRecordTypeId');
            Lead.Lead_Assigned__c = true;
            Lead.OwnerId = SvRec.Handled_By__c;
            Lead.Lead_Status__c = 'Site Visit Completed';
            Lead.Lead_Type__c ='Re-Opened';
            Lead.Last_Re_Opened_Date__c = new Date().toISOString();
            Lead.Allocated_Project__c = SvRec.Project__c;
            
            // Need to add Related Source Record
            rs.sobjectType = 'Related_Source__c';
            rs.New_Lead__c = Lead.Id;
            rs.Source__c = 'Walk-in';
            rs.Sub_Source__c = 'GRE';
            rs.Phone__c = Lead.Phone__c;
            rs.Country_Code__c = Lead.Country_Code__c;
            rs.Secondary_Phone__c = Lead.Secondary_Phone__c;
            rs.Secondary_Contry_Code__c = Lead.Secondary_Country_Code__c;
            rs.Email__c = Lead.Email;
            rs.Secondary_Email__c = Lead.Secondary_Email__c;
            rs.Allocated_Project__c = SvRec.Project__c;
            rs.Lead_Type__c = 'Re-Opened';
            component.set('v.newRelatedSource', rs);
        }
        else if(Lead.RecordType.Name == 'Pre Sales'){
            actionType = 'CancelFollowups';
            Lead.RecordTypeId = component.get('v.salesRecordTypeId');
            Lead.Lead_Assigned__c = true;
            Lead.Pre_Sales_User__c = Lead.OwnerId;
            Lead.OwnerId = SvRec.Handled_By__c;
            Lead.Lead_Status__c = 'Site Visit Completed';
            Lead.Pushed_On__c = new Date().toISOString();
            Lead.Pushed_By__c = $A.get("$SObjectType.CurrentUser.Id");
            Lead.Lead_Transfer_Note__c = SvRec.Remark__c;
            //Need to Cancell all the scheduled Followups
        }
        else if(Lead.RecordType.Name == 'Sales'){
            if(Lead.Lead_Status__c == 'New Sales Enquiry' || Lead.Lead_Status__c == 'RNR' || Lead.Lead_Status__c == 'Site Visit Scheduled'){
                Lead.Lead_Status__c = 'Site Visit Completed';
            }
            actionType = 'NoAction';
            if(Lead.OwnerId != SvRec.Handled_By__c){
                actionType = 'ShareRecords';
                //Share Lead to SvRec.Handled_By__c
                //Share Sv to Lead.OwnerId
            }
        }
        
        component.set('v.selectedLead', Lead);

        
        //Calling Apex Class:
        var action = component.get("c.saveChanges");
        action.setParams({
            ldRec: component.get("v.selectedLead"),
            svRec: component.get("v.newSiteVisit"),
            rsRec: component.get("v.newRelatedSource"),
            LeadOwner: Lead.OwnerId,
            SVOwner: SvRec.Handled_By__c,
            actionType: actionType
        });
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === 'SUCCESS') {
                //var returnval = response.getReturnValue();
                component.set("v.isSVCompModalOpen", false);
                helper.toastMsg('success','Success','Site Visit Captured Successfully');
                helper.handleSelectLead(component, event, helper);
            }
            else{
                helper.toastMsg('error','Error','Error while updating the Request');
            }	
        });
        $A.enqueueAction(action);
    },
    
    //karthik 18-02-26
    saveSiteVisit : function(component, event, helper) {
        var TotalSV = component.get("v.siteVisits");
        var SvRec = component.get("v.newSiteVisit");
        var leadId = component.get("v.selectedLeadId");
        
        // Validate Project
        if(SvRec.Project__c == undefined || SvRec.Project__c == null || SvRec.Project__c == ''){
            helper.toastMsg('error','Error','Select Project');
            return;
        }
        
        // ⭐ NEW: Check if using Round Robin
        var useRR = component.get("v.useRoundRobin");
        
        // ⭐ UPDATED: Only validate Handled By if NOT using Round Robin
        if(!useRR && (SvRec.Handled_By__c == undefined || SvRec.Handled_By__c == null || SvRec.Handled_By__c == '')){
            helper.toastMsg('error','Error','Select Handled By User or enable Round Robin');
            return;
        }
        
        // Validate Remark
        if(SvRec.Remark__c == undefined || SvRec.Remark__c == null || SvRec.Remark__c == ''){
            helper.toastMsg('error','Error','Remarks is mandatory.');
            return;
        }

        var svVisitType = component.get("v.svVisitType");
        var svVisitSourceType = component.get("v.svVisitSourceType");
        var svChannelPartnerId = component.get("v.svChannelPartnerId");

        if (svVisitType === 'On-Site' && !svVisitSourceType) {
            helper.toastMsg('error', 'Error', 'Please select a Visit Source Type.');
            return;
        }
        if (svVisitSourceType === 'CP' && !svChannelPartnerId) {
            helper.toastMsg('error', 'Error', 'Please select a Channel Partner.');
            return;
        }

        // Check for duplicate scheduled SV
        var duplicateFound = false;
        for (var i = 0; i < TotalSV.length; i++) {
            var existingSV = TotalSV[i];
            if (existingSV.Status__c === 'Scheduled' && existingSV.Project__c === SvRec.Project__c && existingSV.Id !== SvRec.Id ) {
                duplicateFound = true;
                break;
            }
        }
        if (duplicateFound) {
            helper.toastMsg('error', 'Duplicate Site Visit', 'A Scheduled Site Visit already exists for this Project.');
            return;
        }

        SvRec.Check_In__c = new Date().toISOString();
        SvRec.CLead__c = leadId;
        SvRec.SV_Completed_Date_Time__c = new Date().toISOString();
        SvRec.Status__c = 'Completed';
        if (svVisitType) SvRec.Visit_Type__c = svVisitType;
        if (svVisitSourceType) SvRec.Visit_Source_Type__c = svVisitSourceType;
        if (svChannelPartnerId) SvRec.Channel_Partner__c = svChannelPartnerId;
        component.set("v.newSiteVisit",SvRec);

        var Lead = component.get('v.selectedLead');
        var rs = {};
        var actionType = '';
        
        if(Lead.Lead_Status__c == 'Unqualified' || Lead.Lead_Status__c == 'Closed Lost'){
            actionType = 'insertRelatedSource';
            Lead.RecordTypeId = component.get('v.salesRecordTypeId');
            Lead.Lead_Assigned__c = true;
            
            // ⭐ UPDATED: Only set OwnerId if manual (not Round Robin - Apex will handle it)
            if(!useRR){
                Lead.OwnerId = SvRec.Handled_By__c;
            }
            
            Lead.Lead_Status__c = 'Site Visit Completed';
            Lead.Lead_Type__c ='Re-Opened';
            Lead.Last_Re_Opened_Date__c = new Date().toISOString();
            
            rs.sobjectType = 'Related_Source__c';
            rs.New_Lead__c = Lead.Id;
            rs.Source__c = 'Walk-in';
            rs.Sub_Source__c = 'GRE';
            rs.Phone__c = Lead.Phone__c;
            rs.Country_Code__c = Lead.Country_Code__c;
            rs.Secondary_Phone__c = Lead.Secondary_Phone__c;
            rs.Secondary_Contry_Code__c = Lead.Secondary_Country_Code__c;
            rs.Email__c = Lead.Email;
            rs.Secondary_Email__c = Lead.Secondary_Email__c;
            rs.Allocated_Project__c = SvRec.Project__c;
            rs.Lead_Type__c = 'Re-Opened';
            component.set('v.newRelatedSource', rs);
        }
        else if(Lead.RecordType.Name == 'Pre Sales'){
            actionType = 'CancelFollowups';
            Lead.RecordTypeId = component.get('v.salesRecordTypeId');
            Lead.Lead_Assigned__c = true;
            Lead.Pre_Sales_User__c = Lead.OwnerId;
            
            // ⭐ UPDATED: Only set OwnerId if manual (not Round Robin - Apex will handle it)
            if(!useRR){
                Lead.OwnerId = SvRec.Handled_By__c;
            }
            
            Lead.Lead_Status__c = 'Site Visit Completed';
            Lead.Pushed_On__c = new Date().toISOString();
            Lead.Pushed_By__c = $A.get("$SObjectType.CurrentUser.Id");
            Lead.Lead_Transfer_Note__c = SvRec.Remark__c;
        }
            // updated by claude 30-03-26 15:32 - Sales leads: skip round-robin, keep current owner
            else if(Lead.RecordType.Name == 'Sales'){
                useRR = false; // Sales leads keep their current owner
                SvRec.Handled_By__c = Lead.OwnerId; // SV assigned to lead's current owner
                component.set("v.newSiteVisit", SvRec);

                if(Lead.Lead_Status__c == 'New Sales Enquiry' || Lead.Lead_Status__c == 'RNR' || Lead.Lead_Status__c == 'Site Visit Scheduled'){
                    Lead.Lead_Status__c = 'Site Visit Completed';
                }
                actionType = 'NoAction';

                if(Lead.OwnerId != SvRec.Handled_By__c){
                    actionType = 'ShareRecords';
                }
            }
        
        component.set('v.selectedLead', Lead);
        
        // ⭐ UPDATED: Calling Apex with Round Robin flag
        var action = component.get("c.saveChanges");
        action.setParams({
            ldRec: component.get("v.selectedLead"),
            svRec: component.get("v.newSiteVisit"),
            rsRec: component.get("v.newRelatedSource"),
            LeadOwner: Lead.OwnerId,
            SVOwner: SvRec.Handled_By__c,
            actionType: actionType,
            useRoundRobin: useRR  // ⭐ NEW parameter
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === 'SUCCESS') {
                component.set("v.isSVCompModalOpen", false);
                component.set("v.svVisitType", "");
                component.set("v.svVisitSourceType", "");
                component.set("v.svChannelPartnerId", "");
                helper.toastMsg('success','Success','Site Visit Captured Successfully');
                helper.handleSelectLead(component, event, helper);
            }
            else{
                var errors = response.getError();
                var errorMsg = 'Error while updating the Request';
                if (errors && errors[0] && errors[0].message) {
                    errorMsg = errors[0].message;
                }
                helper.toastMsg('error','Error', errorMsg);
            }	
        });
        $A.enqueueAction(action);
    },
    
    //added by karthik 18-11-25
    openCheckoutModal : function(component, event, helper) {
        event.stopPropagation(); // prevent parent card click
        var svId = event.currentTarget.dataset.id;

        component.set("v.checkoutSVId", svId);
        component.set("v.isCheckoutModalOpen", true);
    },

    closeCheckoutModal : function(component) {
        component.set("v.isCheckoutModalOpen", false);
        component.set("v.checkoutTime", null);
    },

    saveCheckoutTime : function(component, event, helper) {
        var checkoutTime = component.get("v.checkoutTime");
        if ($A.util.isEmpty(checkoutTime)) {
            var input = component.find("checkoutTimeInput");
            if (input) {
                input.showHelpMessageIfInvalid();
            }
            helper.toastMsg("error", "Missing Fields", "Checkout Date and Time is required.");
            return;
        }
        helper.updateCheckoutTime(component, true);
    },

    svVisitSourceTypeChange : function(component, event, helper) {
        var v = event.getSource().get("v.value");
        component.set("v.svVisitSourceType", v);
        component.set("v.svChannelPartnerId", "");
    },
    
    //karthik 18-02-26
    handleRoundRobinToggle: function(component, event, helper) {
        var isChecked = event.getSource().get("v.checked");
        component.set("v.useRoundRobin", isChecked);

        // Clear manually selected user when switching to Round Robin
        if(isChecked) {
            component.set("v.newSiteVisit.Handled_By__c", "");
        }
    },

    /* commented out for later use - Source Type change handler shows CP lookup when WALKIN - CP
    onSourceTypeChange: function(component, event, helper) {
        var sourceTypeField = component.find("sourceTypeField");
        var sourceType = sourceTypeField.get("v.value");
        if (sourceType === 'WALKIN - CP') {
            component.set('v.isWalkinCP', true);
        } else {
            component.set('v.isWalkinCP', false);
            component.set('v.selectedCPId', null);
        }
    },
    */


})