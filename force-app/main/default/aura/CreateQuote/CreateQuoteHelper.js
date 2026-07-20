({
    // Translate a raw platform access error into a friendly message.
    mapLeadAccessError: function(msg) {
        if (msg && /INSUFFICIENT_ACCESS_OR_READONLY|insufficient access/i.test(msg)) {
            return "You don't have edit access to this lead. Please contact your administrator.";
        }
        return msg;
    },

    addProductRecord: function(component,event,helper) {
        console.log('a')
        var shcdules = component.get("v.CustompaymentSchedules");
        console.log(shcdules)
        var sno =  shcdules.length+ 1;
        console.log(sno)
        shcdules.push({
            'sobjectType': 'Cost_Sheet_Line_Item__c',
            'Payment_Schedule_Name__c': '',
            'Payment_percent__c': '',
            'Payment_Due_Date__c':'',
            'Tentative_TimeLine__c':'',
            'Amount__c': '',
            'Last_Payment_Date__c':'',
            'status__c':'',
            'Master_Payment_Schedule__c':'',
            'S_No__c':sno,
            'Received_Amount__c':'',
            'Recived_Per__c':''
            
        });
        component.set("v.CustompaymentSchedules", shcdules);
        // alert(JSON.stringify( component.get('v.paymentSchedules')));
        // alert('v.paymentSchedules');
    },
    validate: function(component, event) {
        var isValid = true;
        var oppPlot = component.get('v.oppPlot');

        if (oppPlot.Unit__c == null) {
            isValid = false;
        }

        if (oppPlot.Payment_Type__c == null) {
            isValid = false;
        }

        // Discount-cap check: no per-charge discount may exceed its original Plot rate.
        if (oppPlot.Apply_Discount__c) {
            var selected   = component.get('v.selectedDiscounts') || [];
            var config     = component.get('v.discountConfig') || [];
            var originals  = component.get('v.originalCharges') || {};
            var byQuote    = {};
            for (var i = 0; i < config.length; i++) {
                byQuote[config[i].quoteField] = config[i];
            }
            for (var j = 0; j < selected.length; j++) {
                var qf  = selected[j];
                var cfg = byQuote[qf];
                if (!cfg || !cfg.discountField) continue;
                var discount = parseFloat(oppPlot[cfg.discountField]) || 0;
                var original = parseFloat(originals[cfg.unitField]) || 0;
                if (discount > original) {
                    this.showToast(
                        cfg.label + ' discount (₹' + discount + ') cannot exceed the original rate of ₹' + original,
                        'error'
                    );
                    return false;
                }
            }
        }

        return isValid;
    },
    validateSave: function(component, event) {
        if (!this.validate(component, event)) {
            return false;
        }
        var oppPlot = component.get('v.oppPlot');
        if (oppPlot.Payment_Type__c !== 'Custom') {
            // Standard: master-driven percentages must total 100%
            var stdSchedules = component.get('v.paymentSchedules') || [];
            var stdTotal = 0;
            for (var s = 0; s < stdSchedules.length; s++) {
                var spct = parseFloat(stdSchedules[s].Payment_percent__c);
                if (!isNaN(spct)) {
                    stdTotal += spct;
                }
            }
            if (stdTotal !== 100) {
                this.showToast('Payment percentages must total 100%. Current total: ' + stdTotal + '%', 'error');
                return false;
            }
            return true;
        }
        var schedules = component.get('v.CustompaymentSchedules') || [];
        for (var r = 0; r < schedules.length; r++) {
            var row = schedules[r];
            var rowLabel = 'Row ' + (r + 1) + ': ';
            if (!row.Payment_Schedule_Name__c || String(row.Payment_Schedule_Name__c).trim() === '') {
                this.showToast(rowLabel + 'Description is required', 'error');
                return false;
            }
            if (row.Payment_percent__c === null || row.Payment_percent__c === undefined || String(row.Payment_percent__c).trim() === '') {
                this.showToast(rowLabel + 'Percent is required', 'error');
                return false;
            }
            if (!row.status__c) {
                this.showToast(rowLabel + 'Status is required', 'error');
                return false;
            }
            if ((row.status__c === 'Scheduled' || row.status__c === 'Demanded') && !row.Payment_Due_Date__c) {
                this.showToast(rowLabel + 'Due Date is required', 'error');
                return false;
            }
            if (row.status__c === 'Paid' && !row.Last_Payment_Date__c) {
                this.showToast(rowLabel + 'Completed Date is required', 'error');
                return false;
            }
        }
        var totalPercent = 0;
        for (var i = 0; i < schedules.length; i++) {
            var pct = parseFloat(schedules[i].Payment_percent__c);
            if (!isNaN(pct)) {
                totalPercent += pct;
            }
        }
        if (totalPercent !== 100) {
            this.showToast('Payment percentages must total 100%. Current total: ' + totalPercent + '%', 'error');
            return false;
        }
        return true;
    },
    save  : function(component, event, helper){
        var oppPlot = component.get("v.oppPlot");
        component.set("v.paymentType",oppPlot.Payment_Type__c);

        // Reuse the quote created in a prior (failed) attempt instead of creating a duplicate.
        // insertSchedules fails all-or-nothing, so a failed first attempt leaves no schedule
        // rows behind; jumping straight to saveSchedules re-inserts them against the same quote
        // and avoids re-firing the after-insert trigger (approval submit / unit "Blocked").
        var existingQuoteId = component.get("v.quoteId");
        if (existingQuoteId && existingQuoteId !== '' && existingQuoteId !== 'notc'
            && existingQuoteId.indexOf('ERROR') !== 0) {
            helper.saveSchedules(component, event, helper);
            return;
        }

        var action=component.get("c.saveOppPlot");
        action.setParams({
            oppPlot:component.get("v.oppPlot"),
        });
        action.setCallback(this,function(response){
            if(response.getState()==="SUCCESS"){
                var quotid = response.getReturnValue();
                // saveOppPlot swallows exceptions and returns 'ERROR: ...' on failure, so a
                // SUCCESS state does not guarantee a real Id. Only proceed when we got one.
                if(quotid && quotid.indexOf('ERROR') !== 0){
                    component.set("v.quoteId",quotid);
                    helper.saveSchedules(component,event,helper);
                }
                else{
                    component.set('v.isSubmitting', false);
                    helper.showToast(quotid ? quotid.replace(/^ERROR:\s*/, '') : 'Unable to save the quote. Please try again.', 'error');
                }
            } else {
                component.set('v.isSubmitting', false);
                var errors = response.getError();
                helper.showToast((errors && errors.length && errors[0].message) ? helper.mapLeadAccessError(errors[0].message) : 'Unable to save the quote. Please try again.', 'error');
            }
        });
        $A.enqueueAction(action);
    },
    saveSchedules : function(component, event, helper) {
        //alert('saveSchedules');
        var schedules;
        var patType = component.get('v.oppPlot.Payment_Type__c');
        console.log(patType);
        //alert('patType '+patType);
        // Check for payment type and assign correct payment schedules
        if (patType == 'Standard') {
        schedules = component.get('v.paymentSchedules');
        //alert('paymentSchedules '+ JSON.stringify(schedules));
        } else if (patType == 'Custom') {
            schedules = component.get('v.CustompaymentSchedules');
            for (var r = 0; r < schedules.length; r++) {
                var row = schedules[r];
                var rowLabel = 'Row ' + (r + 1) + ': ';
                if (!row.Payment_Schedule_Name__c || String(row.Payment_Schedule_Name__c).trim() === '') {
                    helper.showToast(rowLabel + 'Description is required', 'error');
                    component.set('v.isSubmitting', false);
                    return;
                }
                if (row.Payment_percent__c === null || row.Payment_percent__c === undefined || String(row.Payment_percent__c).trim() === '') {
                    helper.showToast(rowLabel + 'Percent is required', 'error');
                    component.set('v.isSubmitting', false);
                    return;
                }
                if (!row.status__c) {
                    helper.showToast(rowLabel + 'Status is required', 'error');
                    component.set('v.isSubmitting', false);
                    return;
                }
                if ((row.status__c === 'Scheduled' || row.status__c === 'Demanded') && !row.Payment_Due_Date__c) {
                    helper.showToast(rowLabel + 'Due Date is required', 'error');
                    component.set('v.isSubmitting', false);
                    return;
                }
                if (row.status__c === 'Paid' && !row.Last_Payment_Date__c) {
                    helper.showToast(rowLabel + 'Completed Date is required', 'error');
                    component.set('v.isSubmitting', false);
                    return;
                }
            }
            // Validate that payment percentages sum to 100%
            var totalPercent = 0;
            for (var i = 0; i < schedules.length; i++) {
                var pct = parseFloat(schedules[i].Payment_percent__c);
                if (!isNaN(pct)) {
                    totalPercent += pct;
                }
            }
            if (totalPercent !== 100) {
                helper.showToast('Payment percentages must total 100%. Current total: ' + totalPercent + '%', 'error');
                component.set('v.isSubmitting', false);
                return;
            }
        }

        // Define Apex action to insert schedules
        var action = component.get("c.insertSchedules");
        action.setParams({
            'payList': schedules,
            'gt': component.get('v.GrandTotalGST'),
            'quoteid': component.get('v.quoteId')
        });
        
        // Callback for the Apex response
        action.setCallback(this, function(response) {
            var state = response.getState();
            
            if (state === "SUCCESS") {
                // Clear payment schedules after successful operation
                component.set("v.paymentSchedules", []);
                component.set('v.GrandTotal', 0.00);

                // Close quick action panel
                var dismissActionPanel = $A.get("e.force:closeQuickAction");
                dismissActionPanel.fire();

                // Navigate to Quote page
                var navEvt = $A.get("e.force:navigateToSObject");
                navEvt.setParams({
                    "recordId": component.get('v.quoteId'),
                    "slideDevName": "detail"
                });
                navEvt.fire();

                // Show success message
                helper.showToast("Quote Created Successfully.", "success");
                component.set('v.quoteId', '');
                
            } else if (state === "ERROR") {
                component.set('v.isSubmitting', false);
                var errors = response.getError();
                if (errors && errors.length > 0) {
                    console.error("Apex Error: ", errors[0].message);
                    helper.showToast(helper.mapLeadAccessError(errors[0].message), "error");
                } else {
                    console.error("Unknown Error occurred while creating the quote.");
                    helper.showToast("An unknown error occurred. Please contact support.", "error");
                }
            } else {
                component.set('v.isSubmitting', false);
                console.error("Unexpected response state: ", state);
                helper.showToast("Unexpected response from the server. Please try again.", "error");
            }
            
            // Debugging: Inspect the response
            debugger;
        });
        
        // Enqueue the action to send it to the server
        $A.enqueueAction(action);
    },
    
    
    getFilteredLead: function(component, event,helper) {
         //alert('hh')
        var oppPlot = component.get('v.oppPlot');
        var pymplan = oppPlot.Payment_Plan__c;
        var project = oppPlot.Projects__c;
        
        // alert(pymplan+'--'+project)
        var action = component.get("c.getPaymentSchedules");
        
        action.setParams({'Pay':  pymplan,
                          'Project': project,
                          'gt': oppPlot.Grand_Total__c, // example field
                          'unitId': oppPlot.Id          // or the related Unit Id
                         })
        action.setCallback(this,function(response){
            var state = response.getState();
            
            if(state == "SUCCESS" ){ 
                //  alert(1);
                var db = response.getReturnValue();
                
                console.log(db.payList.length());
                if(db.payList !=null){
                    console.log('if');
                    
                    component.set('v.paymentSchedules', db.payList );
                    
                    //alert(JSON.stringify(component.get('v.paymentSchedules')))
                }
                else{
                    
                    //  helper.addProductRecord(component,event,helper);
                    console.log('else');
                    
                }
                
            }
        });
        $A.enqueueAction(action); 
        
    },
    
    showToast : function(message,type) {
        console.log(message)
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "type":type,
            "message":  message
        });
        toastEvent.fire();
    },
    
    handleProjectChange: function(component, event, helper, selectedValue) {
        
               
        var action=component.get("c.getPlots");  
        
        action.setParams({'project':selectedValue});
        action.setCallback(this,function(response){
            
            if(response.getState()=="SUCCESS"){ 
                var plots = response.getReturnValue();
                
                console.log('plots:'+plots);
                component.set("v.plots",plots);
                
                // getting Payment Plan
                
                var action4=component.get("c.getPyamentPlan");  
                
                action4.setParams({'project':selectedValue});
                action4.setCallback(this,function(response){
                    
                    if(response.getState()=="SUCCESS"){ 
                        var pymnpln = response.getReturnValue();
                        
                        component.set("v.paymentplan",pymnpln);
                    }
                });
                $A.enqueueAction(action4);
                
            }
        });
        $A.enqueueAction(action);
    },
    getmasterpaymentschedule: function(component, event,helper) {
         //alert('welcome');
        var oppPlot = component.get('v.oppPlot');
        
        console.log('oppPlot:', oppPlot);
        
        var pymplan = oppPlot.Payment_Type__c;
        console.log('Payment Type:', pymplan);
        
        var project = oppPlot.Project1__c;
        console.log('Project:', project);
        
        var towerId = oppPlot.Tower__c;
        console.log('Tower Id:', towerId);
        console.log('GrandTotalGST:', component.get('v.GrandTotalGST'));


        var action = component.get("c.getPaymentSchedules");
        action.setParams({'Pay':  pymplan,
                          'Project': project,
                          'gt':component.get('v.GrandTotalGST'),
                          'towerId': towerId
                         })
        action.setCallback(this, function(response){
            var state = response.getState();
            if (state == "SUCCESS") {
                var db = response.getReturnValue();
                if (db && db.payList && db.payList.length > 0) {
                    component.set('v.paymentSchedules', db.payList);
                    console.log('paymentSchedules SET SUCCESSFULLY');
                    component.set("v.showNextCmp", true);
                } else {
                    console.log('No payment schedules found');
                    helper.showToast('No master payment schedule found for this tower.', 'error');
                }
            } else {
                console.error('getPaymentSchedules failed:', response.getError());
                component.set("v.showNextCmp", true);
            }
        });
        $A.enqueueAction(action); 
        
    },
    fetchLeadDetails: function(component, event, helper) {
        var recordId = component.get("v.recordId");
        var action = component.get("c.getLeadDetails");
        action.setParams({ 'recordId': recordId });
        action.setCallback(this, function(response) {
            if (response.getState() === "SUCCESS") {
                var LeadList = response.getReturnValue();
                console.log('LeadList',LeadList);
                //component.set('v.preSaleUser',LeadList.Owner.Name);
                component.set('v.preSaleUser',LeadList.Old_Owner_Name__r.Name);
                component.set('v.relatoinshipManager',LeadList.Relationship_Manager__c);
            } else {
                console.error('Error in fetching allocated project value');
            }
        });
        $A.enqueueAction(action);
    }
})