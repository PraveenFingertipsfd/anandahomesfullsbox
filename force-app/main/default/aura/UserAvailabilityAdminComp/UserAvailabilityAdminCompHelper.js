({
	 getUsers: function(component) {
         var pageSize = component.get("v.pageSize");
       
        var action = component.get('c.getAllUsers');
          action.setParams({
            "profile": component.get('v.selProfileFilter')
        });
        action.setCallback(this,function(response){
            var state=response.getState();            
            if(state==='SUCCESS'){
                var userDetails = response.getReturnValue();
                component.set("v.users",userDetails);
                 component.set("v.totalSize", component.get("v.users").length);
                component.set("v.start",0);
                component.set("v.end",pageSize-1);
                
                 var paginationList = [];
                for(var i=0; i< pageSize; i++)
                {
                    paginationList.push(response.getReturnValue()[i]);
                }
                component.set("v.paginationList", paginationList);
                
                //alert(userDetails)
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
      submit: function(component, event, helper){
        //alert(event.currentTarget.dataset.id +  '----' + event.currentTarget.dataset.value)
        //alert(JSON.stringify(component.get('v.users')))
        var selUser = event.currentTarget.dataset.id;
        var action = component.get('c.updateUser');
        //alert(component.get('v.selUser'))
        action.setParams({
            "selUserId": selUser,
            "selUser": component.get('v.selUser')
        });
        action.setCallback(this, function(response){
            var state = response.getState();
            if (state === "SUCCESS") {
                var toastsuccessEvent = $A.get("e.force:showToast");
                toastsuccessEvent.setParams({
                    "title": "Success!",
                    "message": "Status Updated sucessfully!",
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
       submit2: function(component, event, helper){
        var selUser = event.currentTarget.dataset.id;
        var action = component.get('c.updateUser2');
       
        action.setParams({
            "selUser": component.get('v.selUser')
        });
        action.setCallback(this, function(response){
            var state = response.getState();
            if (state === "SUCCESS") {
                var toastsuccessEvent = $A.get("e.force:showToast");
                toastsuccessEvent.setParams({
                    "title": "Success!",
                    "message": "Status Updated sucessfully!",
                    "type" : "success"
                });
                
                toastsuccessEvent.fire();
                 $A.get('e.force:refreshView').fire();
                //  window.location.reload();
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
    }
    
    
})