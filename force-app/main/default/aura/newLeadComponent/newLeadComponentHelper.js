({
    getPickListValue : function(component, event, helper)
    {
        //var recoooordif = component.get("v.recordId");
        //alert('hiii getPickListValue  '+ recoooordif)
        var action = component.get("c.getPickListValues");
        
        action.setCallback(this, function(response){
            var state = response.getState();
            if(state == 'SUCCESS') {
                var ProjectPickList = response.getReturnValue();
                console.log(ProjectPickList);
                component.set('v.projectName',ProjectPickList)
            }
        });
        $A.enqueueAction(action);
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
    
})