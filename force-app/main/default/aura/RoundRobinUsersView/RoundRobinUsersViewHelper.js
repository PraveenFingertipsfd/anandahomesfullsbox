({
    getRoundRobinMembers: function(component,event,helper) {
        var action = component.get("c.fetchRoundRobinMembers");
         //action.setParams({ 'recordId': component.get("v.recordId") });
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                component.set("v.roundRobinMembers", response.getReturnValue());
                console.log(response.getReturnValue());
            }
        });
        $A.enqueueAction(action);
    },

    toggleMemberActiveStatus: function(component, userId,event,helper) {
        var action = component.get("c.toggleMemberStatus");
        action.setParams({ 'memId': userId,
                         'recId' :  component.get('v.recordId')});
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                // Refresh the member list after toggling status
                helper.getRoundRobinMembers(component,event,helper);
                $A.get('e.force:refreshView').fire();
                window.location.reload();
            }
        });
        $A.enqueueAction(action);
    }
})