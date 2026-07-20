({
    doInit: function(component, event, helper) {
        helper.getUsers(component);
    },
    
    selectChange:function(component, event, helper) {
        var user = component.get('v.usr');
        if (user.Availability__c === false) {
            component.set('v.reasone', '');
            component.set('v.isFalse', true);
        } else {
            helper.onChange(component, event, '');
        }
    },
    closePopUP:function(component, event, helper)
    {
         var user=component.get('v.usr');
        user.Availability__c = true;
        component.set('v.usr', user);
        component.set("v.isFalse", false);
    },
    submitDetails:function(component, event, helper)
    {
        var reasone = component.find('reasone').get('v.value');
        reasone = (reasone || '').trim();
        if (reasone.length > 0) {
            helper.onChange(component, event, reasone);
            component.set('v.isFalse', false);
        } else {
            var toastsuccessEvent = $A.get("e.force:showToast");
            toastsuccessEvent.setParams({
                "title": "Reason required.",
                "message": "Please enter a reason for turning off your availability.",
                "type": "error"
            });
            toastsuccessEvent.fire();
        }
    }
})