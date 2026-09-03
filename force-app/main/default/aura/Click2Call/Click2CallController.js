({
    doInit : function(component, event, helper) {
        var action = component.get("c.getPhoneNumbers");
        action.setParams({ recordId : component.get("v.recordId") });

        action.setCallback(this, function(response) {
            if (response.getState() === "SUCCESS") {
                var res = response.getReturnValue();
                component.set("v.primaryPhone", res.primaryPhone);
                component.set("v.secondaryPhone", res.secondaryPhone);
            } else {
                helper.showError(response);
            }
            component.set("v.isLoading", false);
        });

        $A.enqueueAction(action);
    },

    makeCall : function(component, event, helper) {
        var number = event.getSource().get("v.value");
        component.set("v.isLoading", true);

        var action = component.get("c.clickToCall");
        action.setParams({
            recordId : component.get("v.recordId"),
            customerNumber : number
        });

        action.setCallback(this, function(response) {
            component.set("v.isLoading", false);
            if (response.getState() === "SUCCESS") {
                helper.showToast("Success", "success", "Call initiated");
                $A.get("e.force:closeQuickAction").fire();
            } else {
                helper.showError(response);
            }
        });

        $A.enqueueAction(action);
    }
})