({
	pushToSales : function(component, event, helper) {
		var action = component.get("c.moveToSales");
        action.setParams({ LeadId : component.get("v.recordId"),
                          //project : component.get("v.selectedProject"),
                          addNote : component.get("v.newNote")
                         });
        action.setCallback(this, function(response){
            var state = response.getState();
            if(state == 'SUCCESS') {
                var toastEvent = $A.get("e.force:showToast");
                        toastEvent.setParams({
                            message: 'Lead moved to sales team',
                            type : 'success'
                        });
                        toastEvent.fire();
                      //  $A.get("e.force:closeQuickAction").fire();
                
                var listviews = response.getReturnValue();
            var navEvt = $A.get("e.force:navigateToList");
            navEvt.setParams({
                    "listViewName": listviews,
					"scope": "Lead"
            });
            navEvt.fire();
                $A.get('e.force:refreshView').fire();
            }
        });
        $A.enqueueAction(action);
        
	},
    showToast : function(type,message){
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "type":type,
            "message":  message
        });
        toastEvent.fire();
        
    }
})