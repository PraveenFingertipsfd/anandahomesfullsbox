({
	doCancel: function (component, event, helper) {
        $A.get("e.force:closeQuickAction").fire();
        $A.get('e.force:refreshView').fire();
    },
    doSave : function(component, event, helper){
        var todayDate = new Date().toISOString().split('T')[0];
        var RecId = component.get("v.recordId");
        var Notes= component.get('v.newNote');
        var FollowUpdate = component.get('v.followUpDate');
        var revisitDate = component.get("v.followUpDate");
        var inputCmp = component.find("revisitDate");

        if (revisitDate) {
            var selectedDate = new Date(revisitDate);
            var today = new Date();

            // ⚡ Remove milliseconds and seconds for clean comparison
            today.setSeconds(0,0);

            if (selectedDate < today) {
                inputCmp.setCustomValidity("Re-visit Date cannot be in the past.");
                inputCmp.reportValidity();
                return;
            } else {
                inputCmp.setCustomValidity(""); // clear error
                inputCmp.reportValidity();
            }
        }

        // proceed with save logic
        //alert("Valid date, saving record..."); 
        
        if(FollowUpdate == ''|| FollowUpdate == null || FollowUpdate == undefined){
            helper.Toast('Error','Error','Please Select Revisit Date');
            return;
        }
        if(Notes == ''|| Notes == null || Notes == undefined || !Notes.trim()){
            helper.Toast('Error','Error','Please enter Notes');
            return;
        }
        
        
        var action = component.get("c.updateLastNote");
        action.setParams({"SVId": RecId,
                          "newNote": Notes,
                          "RSVDate": FollowUpdate
                         });
        action.setCallback(this, function(response){
            var state = response.getState();
            if (state === "SUCCESS"){
                helper.Toast('SUCCESS','Success','Record Updated');
                $A.get("e.force:closeQuickAction").fire();
                $A.get('e.force:refreshView').fire();
            }
            else if(state === "ERROR"){
                var errors = response.getError();
                helper.Toast('Error','Error','Facing Some Technical Issue while storing Notes');
                return;
            }
        });
        $A.enqueueAction(action);
        
    },
})