({
    doInit: function(component, event, helper) {
        var action = component.get("c.fetchRoundRobinMembers");
        action.setParams({ 'recordId': component.get("v.recordId") });
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var PreSalesUers=[];
                var SalesUers=[];
                var ChannelUsers=[];
                var result = response.getReturnValue();
                
                for (var i = 0; i < result.length; i++) {
                    if (result[i].User_Type__c === 'Pre Sales') {
                      	PreSalesUers.push(result[i]);
                    }
                    if (result[i].User_Type__c === 'Sales') {
                      	SalesUers.push(result[i]);
                    }
                    if (result[i].User_Type__c === 'CRM') {
                      	ChannelUsers.push(result[i]);
                    }
                }
                component.set("v.roundRobinMemberspresale", PreSalesUers);
                component.set("v.roundRobinMemberspostsale", SalesUers);
                component.set("v.roundRobinMembersChannel", ChannelUsers);
                console.log(response.getReturnValue());
            }
        });
        $A.enqueueAction(action);
    },

    toggleActiveStatus: function(component, event, helper) {
        var userId = event.getSource().get("v.value");
        console.log(userId);
        var action = component.get("c.toggleMemberStatus");
        action.setParams({ 'memId': userId,
                         'recId' :  component.get('v.recordId')});
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                // Refresh the member list after toggling status
                //this.doInit(component,event,helper);
                $A.get('e.force:refreshView').fire();
                var PreSalesUers=[];
                var SalesUers=[];
                var ChannelUsers=[];
                var result = response.getReturnValue();
                
                for (var i = 0; i < result.length; i++) {
                    if (result[i].User_Type__c === 'Pre Sales') {
                      	PreSalesUers.push(result[i]);
                    }
                    if (result[i].User_Type__c === 'Sales') {
                      	SalesUers.push(result[i]);
                    }
                    if (result[i].User_Type__c === 'CRM') {
                      	ChannelUsers.push(result[i]);
                    }
                }
                component.set("v.roundRobinMemberspresale", PreSalesUers);
                component.set("v.roundRobinMemberspostsale", SalesUers);
                component.set("v.roundRobinMembersChannel", ChannelUsers);
                console.log('yes got it',response.getReturnValue());
                //window.location.reload();
            }
        });
        $A.enqueueAction(action);
    }
})