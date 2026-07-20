({
    formatDate: function(date) {
        // Create a new Date object from the Salesforce date string..
        var dateObj = new Date(date);
        
        // Format the date as MM/DD/YYYY (or any custom format)
        var month = dateObj.getMonth() + 1; // Months are zero-based
        var day = dateObj.getDate();
        var year = dateObj.getFullYear();
        
        // Pad month and day with leading zero if necessary
        month = month < 10 ? '0' + month : month;
        day = day < 10 ? '0' + day : day;
        
        return month + '/' + day + '/' + year; // Change format here as needed
    },
    toastMsg : function (type, title, msg) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": title,
            "type": type,
            "message": msg
        });
        toastEvent.fire();
    },
    // Build a readable message from a lightning:recordEditForm onerror event
    extractFormError: function (event) {
        var parts = [];
        var output = event.getParam("output");
        if (output) {
            (output.errors || []).forEach(function (e) { if (e && e.message) parts.push(e.message); });
            var fe = output.fieldErrors || {};
            Object.keys(fe).forEach(function (f) {
                (fe[f] || []).forEach(function (x) { if (x && x.message) parts.push(x.message); });
            });
        }
        if (!parts.length && event.getParam("detail")) parts.push(event.getParam("detail"));
        if (!parts.length && event.getParam("message")) parts.push(event.getParam("message"));
        return parts.length ? parts.join(' ') : 'An error occurred. Please try again.';
    },
    validatePhoneNumber: function( phoneNumber) {
        if (!phoneNumber) return false;
        
        // Remove all non-digit characters
        let cleaned = phoneNumber.replace(/\D/g, '');
        
        // Check if it's a valid 10-digit number (after removing country code)
        if (cleaned.length === 10 && /^[6-9]\d{9}$/.test(cleaned)) {
            return true;
        }
        
        // Check if it's a valid number with country code
        if (cleaned.length === 12 && cleaned.startsWith('91') && /^[6-9]\d{9}$/.test(cleaned.substring(2))) {
            return true;
        }
        
        return false;
    },
    getRecordTypeId: function(component,event) {
        
        var action = component.get("c.getSalesRecordTypeId");
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                
                let recordTypeId = response.getReturnValue();
                component.set("v.recordTypeId",recordTypeId);

            } else {
                console.error('Failed to fetch RecordTypeId:', response.getError());
            }
        });
        
        $A.enqueueAction(action);
    },
    formatDateTime: function(date) {
        if (!date) return '';
        
        var d = new Date(date);
        var day = String(d.getDate()).padStart(2, '0'); // Ensure two-digit day
        var month = String(d.getMonth() + 1).padStart(2, '0'); // Ensure two-digit month
        var year = d.getFullYear();
        var hours = String(d.getHours()).padStart(2, '0'); // Ensure two-digit hours
        var minutes = String(d.getMinutes()).padStart(2, '0'); // Ensure two-digit minutes
        
        return day + '/' + month + '/' + year + ', ' + hours + ':' + minutes;
    },
    handleSelectLead: function(component, event, helper) {
        
        var selectedLead = component.get('v.selectedLead');
        component.set('v.isSelectedLead', true);
        
        var action = component.get("c.getLeadandSiteVisitDetails"); 
        action.setParams({ 'leadId': selectedLead.Id });
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                
                /*
                var siteVisit = result.siteVisits[0]; 
                if (siteVisit) {
                    component.set("v.scheduledSiteVisit", {
                        siteVisitNumber: siteVisit.Name,
                        projectName: siteVisit.Project__c,
                        status: siteVisit.Status__c,
                        scheduledDate: helper.formatDateTime(siteVisit.Date__c),
                        ownerName: siteVisit.Owner.Name,
                        completedDate:helper.formatDateTime(siteVisit.SV_Completed_Date_Time__c),
                        Id:siteVisit.Id
                    });
                }
                console.log("Formatted Date: " + helper.formatDateTime(siteVisit.Date__c));
                console.log('siteVisit '+JSON.stringify(component.get("v.scheduledSiteVisit")));
               */
                
                var ld = result.selectedld;
                component.set("v.selectedLead",ld);
                component.set("v.recordTypeName", ld.RecordType.Name);
                
                var visits = result.siteVisits;
                component.set("v.siteVisits", visits);
                
                // Step 1: Group by Status__c only
                var statusMap = {};
                visits.forEach(function(v) {
                    var status = v.Status__c || 'Unknown';
                    if (!statusMap[status]) {
                        statusMap[status] = [];
                    }
                    statusMap[status].push(v);
                });
                
                // Step 2: Convert map to iterable list (in fixed order)
                var orderedStatuses = ['Scheduled', 'Rescheduled', 'Completed', 'Cancelled'];
                var groupedStatusList = [];
                
                // Add statuses in the specified order if they exist
                orderedStatuses.forEach(function(statusKey) {
                    if (statusMap[statusKey]) {
                        groupedStatusList.push({ key: statusKey, value: statusMap[statusKey] });
                    }
                });
                
                // Add any remaining statuses (not in the above order) at the end
                for (var statusKey in statusMap) {
                    if (!orderedStatuses.includes(statusKey)) {
                        groupedStatusList.push({ key: statusKey, value: statusMap[statusKey] });
                    }
                }
                
                component.set("v.groupedStatus", groupedStatusList);
                
                setTimeout(function() {
                    var gridContainer = document.querySelector('.slds-page-header__row_gutters .slds-grid');
                    if (gridContainer) {
                        gridContainer.style.display = 'flex';
                        gridContainer.style.flexWrap = 'wrap';
                    }
                }, 50);
                
                
            } else {
                console.error("Error fetching leads: " + response.getError());
            }
        });
        
        $A.enqueueAction(action);
    },
    fetchSalesUsers:function(component, event, helper){
        var action = component.get("c.fetchSalesUsers");
        action.setCallback(this, function(response) {
            var state = response.getState();
            
            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                //alert("result "+JSON.stringify(result));
                component.set("v.options",result);
            }
        });                
        $A.enqueueAction(action);                   
    },

    //added by karthik 18-11-25
    updateCheckoutTime : function(component, refreshAfter) {

        var action = component.get("c.updateSVCheckoutTime");
        action.setParams({
            svId: component.get("v.checkoutSVId"),
            checkoutTime: component.get("v.checkoutTime")
        });

        action.setCallback(this, function(resp){

            if(resp.getState() === "SUCCESS"){

                this.toastMsg("success", "Success", "Checkout time updated.");

                component.set("v.isCheckoutModalOpen", false);
                component.set("v.checkoutTime", null);

                // ⭐ Refresh site visits so the Fill Checkout button hides
                if (refreshAfter) {
                    this.handleSelectLead(component);
                }
            }
            else {
                this.toastMsg("error", "Error", "Something went wrong!");
            }
        });

        $A.enqueueAction(action);
    }


})