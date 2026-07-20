({
    closePanel: function(component) {
        var overlayLib = component.find('overlayLib');
        overlayLib.notifyClose();
    },

    refreshRecord: function(component, recordId) {
        var navService = component.find("navService");
        var pageReference = {
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        };
        event.preventDefault();
        navService.navigate(pageReference);
    },
    
    showToast: function(title, message, type) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            title: title,
            message: message,
            type: type
        });
        toastEvent.fire();
    },

    loadRemarks: function(component) {
        var leadId = component.get("v.recordId");
        var action = component.get("c.fetchLeadLastNotes");
        action.setParams({ "leadId": leadId });
        action.setCallback(this, function(response) {
            if (response.getState() === "SUCCESS") {
                component.set("v.ShowRecords", response.getReturnValue());
            }
        });
        $A.enqueueAction(action);
    }
})