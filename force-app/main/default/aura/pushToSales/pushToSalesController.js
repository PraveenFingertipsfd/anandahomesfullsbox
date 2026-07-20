({
    pushToSalesComp : function(component, event, helper){
        component.set("v.isButtonDisabled", true);
        var transferNotes = component.get("v.newNote");

        if(transferNotes == '' || transferNotes == 'None' || transferNotes == null || transferNotes == undefined){
            component.set("v.isButtonDisabled", false);
            var toastEvent = $A.get("e.force:showToast");
            toastEvent.setParams({
                message: 'Please Enter transfer notes',
                type : 'error'
            });
            toastEvent.fire();
        } else {
            var action = component.get("c.moveToSales");
            action.setParams({
                LeadId: component.get("v.recordId"),
                addNote: component.get("v.newNote"),
                salesUser: ''
            });

            action.setCallback(this, function(response) {
                var state = response.getState();
                if (state === 'SUCCESS') {
                    var toastEvent = $A.get("e.force:showToast");
                    toastEvent.setParams({
                        message: 'Lead moved to sales team',
                        type: 'success'
                    });
                    toastEvent.fire();

                    var listviews = response.getReturnValue();
                    var navEvt = $A.get("e.force:navigateToSObject");
                    navEvt.setParams({
                        "recordId": listviews
                    });
                    navEvt.fire();
                    $A.get('e.force:refreshView').fire();
                } else {
                    component.set("v.isButtonDisabled", false);
                    var errors = response.getError();
                    var message = 'An unexpected error occurred.';
                    if (errors && errors[0] && errors[0].message) {
                        message = errors[0].message;
                    }
                    var toastEvent = $A.get("e.force:showToast");
                    toastEvent.setParams({
                        message: message,
                        type: 'error'
                    });
                    toastEvent.fire();
                }
            });
            $A.enqueueAction(action);
        }
    },
    closeModel : function(component, event, helper){
        $A.get("e.force:closeQuickAction").fire();
    }
})