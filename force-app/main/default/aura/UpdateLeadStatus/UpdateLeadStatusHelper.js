({
    // Last modified: 2026-05-06T10:49:27Z
	toastMsg : function (type, title, msg) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": title,
            "type": type,
            "message": msg
        });
        toastEvent.fire();
    },

    // Apex call to create the Follow-up record added new comment 
    createFollowUp : function(component, followUpRecord,myRecordId, callback) {
        //alert('createFollowUp');
        var action = component.get("c.createFollowUpApex");
        action.setParams({
            followUpRecord: JSON.stringify(followUpRecord),
            SiteVisitId: '',
            LeadId:myRecordId
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            //alert(state);
            if(state === "SUCCESS") {
                callback({ success: true });
            } else {
                callback({ success: false });
            }
        });
        $A.enqueueAction(action);
    },
    
    createSiteVisit: function(component, siteVisitRecord,myRecordId, callback) {
        //alert('createSiteVisit');
        var action = component.get("c.createSiteVisitApex");
        action.setParams({
            siteVisitRecord: JSON.stringify(siteVisitRecord)
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            //alert(state);
            if(state === "SUCCESS") {
                callback({ success: true });
            } else {
                callback({ success: false });
            }
        });
        $A.enqueueAction(action);
    },
    
    checkExistingFollowup: function(component, leadId, callback) {
        var action = component.get("c.getFollowUpDetails");
        action.setParams({ leadId: leadId });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var rows = response.getReturnValue();
                callback({ exists: rows && rows.length > 0 });
            } else {
                callback({ exists: false }); // Fail open if server call fails
            }
        });
        $A.enqueueAction(action);
    },
    
    navigateToRecord: function(recordId) {
        var navEvt = $A.get("e.force:navigateToSObject");
        navEvt.setParams({
            "recordId": recordId,
            "slideDevName": "detail"
        });
        navEvt.fire();
        $A.get("e.force:refreshView").fire();
    },
    
    fetchInitData: function(component, event, helper) {
        var action = component.get("c.fetchInitData");
        action.setParams({ recordId: component.get("v.recordId") });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                
                // Lead Details
                var lead = result.leadRecord;
                component.set("v.status", lead.Lead_Status__c);
                component.set("v.recordTypeName", lead.RecordType.Name);
                //Added By Pattu
                component.set("v.leadProject", lead.Allocated_Project__c);

                // Picklists
                component.set("v.Subject", result.subjectList);
                component.set("v.UnqualifiedReasonList", result.unqualifiedReasonList);
                component.set("v.ProjectList", result.projectList);
                component.set("v.closedLostReasonList", result.closedLostReasonList);
                component.set("v.VisitTypeList", result.visitTypeList);

                // Defer SVStatus so the <option> elements rendered by the
                // aura:iteration above exist before the select binds its value.
                window.setTimeout($A.getCallback(function() {
                    component.set("v.SVStatus", lead.Lead_Status__c);
                }), 0);

            } else {
                helper.toastMsg("Error", "Failed to fetch initialization data", "error");
            }
        });
        $A.enqueueAction(action);
    },
    
    //added by karthik 14-11-25
    checkExistingSV: function(component, leadId, projectName, callback) {
        var action = component.get("c.hasScheduledSV");
        action.setParams({
            leadId: leadId,
            projectName: projectName
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                callback(response.getReturnValue()); // true/false
            } else {
                callback(false); // Safe fallback
            }
        });
        
        $A.enqueueAction(action);
    }


})