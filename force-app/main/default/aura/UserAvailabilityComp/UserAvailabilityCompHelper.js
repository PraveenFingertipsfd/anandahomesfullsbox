({
    getUsers: function(component) {
        var action = component.get('c.getUserRec');
        action.setCallback(this,function(response){
            var state=response.getState();            
            if(state==='SUCCESS'){
                var userDetails = response.getReturnValue();
                component.set("v.usr",userDetails);
            }else if(state==='ERROR'){
                var toastsuccessEvent = $A.get("e.force:showToast");
                toastsuccessEvent.setParams({
                    "title": "Something went wrong.",
                    "message": "Please contact System Administrator.",
                    "type" : "error"
                });
                toastsuccessEvent.fire(); 
            }
        });
        $A.enqueueAction(action);  
    },
    
    onChange: function(component,event,resp) {

        resp+='';
        var action = component.get('c.updateUser');
        action.setParams({
            "ulist": component.get('v.usr'),
            "reasone":resp
        });
        action.setCallback(this, function(response){
            var state = response.getState();
            if (state === "SUCCESS") {
                var toastsuccessEvent = $A.get("e.force:showToast");
                toastsuccessEvent.setParams({
                    "title": "Success!",
                    "message": "Status Updated.. Successfully!",
                    "type" : "success"
                });
                toastsuccessEvent.fire();
            }else if(state === "ERROR") {
                var toastsuccessEvent = $A.get("e.force:showToast");
                toastsuccessEvent.setParams({
                    "title": "Something went wrong.",
                    "message": "Please contact System Administrator.",
                    "type" : "error"
                });
                toastsuccessEvent.fire(); 
            }
        });
        $A.enqueueAction(action);
    },
})