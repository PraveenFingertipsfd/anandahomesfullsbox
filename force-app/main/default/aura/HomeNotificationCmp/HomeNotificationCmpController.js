({
	doInit : function(component, event, helper) {
        helper.getFollowUpDetails(component, event);
        helper.getSiteVisitDetails(component, event);
        helper.getPendingFollowUpDetails(component, event);
        helper.getPendingSiteVisitDetails(component, event);
        helper.renderEveryMin(component, event, helper);
        helper.loadRecords(component);
        
	},
    onCallHandler:function(component, event, helper) {
        var leadRecordID=event.getSource().get("v.name");
        //alert(leadRecordID);
         component.set("v.leadRecID",leadRecordID);
         component.set("v.isCall",true);
        
	},
    onsvHandler:function(component, event, helper) {
         var svleadRecordID=event.getSource().get("v.name");
         //alert(svleadRecordID);
         component.set("v.SvleadRecID",svleadRecordID);
         component.set("v.isSv",true);   
	},
    onfollowupHandler:function(component, event, helper) {
        var flsleadRecordID=event.getSource().get("v.name");
        component.set("v.FlsleadRecId",flsleadRecordID);
        component.set("v.isfls",true);   
    },
    
     onChange:function(component,event,helper){
         component.set("v.isCancelled",false);
         component.set("v.isConducted",false);
         component.set("v.isReschedule",false);
          component.set("v.updateValue","");
         
        var StatusValue=component.find('StatusID').get('v.value');
        if(StatusValue=='Cancelled')
            	component.set("v.isCancelled",true);
        else if(StatusValue=='Completed')
            component.set("v.isConducted",true);
        else if(StatusValue=='Rescheduled')
             component.set("v.isReschedule",true);
    },
      onChange1:function(component,event,helper){
          component.set("v.isScheduled1",false);
          component.set("v.isMissed1",false);
          component.set("v.isCompleted1",false);
         
        var StatusValue1=component.find('StatusID1').get('v.value');
        if(StatusValue1=='Scheduled')
            	component.set("v.isScheduled1",true);
        // 'Missed' follow-up status removed
        // else if(StatusValue1=='Missed')
        //     component.set("v.isMissed1",true);
        else if(StatusValue1=='Completed')
             component.set("v.isCompleted1",true);
    },
    UpdateSvStatus:function(component,event,helper){
        
        var StatusValue=component.find('StatusID').get('v.value');
        var UpdatedValue=component.get("v.updateValue");
        if(StatusValue=='Rescheduled' && UpdatedValue !='')
            UpdatedValue= new Date(UpdatedValue).toLocaleString('en-GB');
        if(StatusValue!='' && UpdatedValue !='')
        {
         helper.updateSvDetails(component, event,StatusValue,UpdatedValue,helper);
         var closeMethod = component.get('c.closeModel');
          
        	$A.enqueueAction(closeMethod);
        }
    },
    UpdateflsStatus:function(component,event,helper){
        var StatusValue1=component.find('StatusID1').get('v.value');
         var RemarksValue = component.find("remarks").get("v.value");
        if(StatusValue1!='' && RemarksValue!='' && RemarksValue!=undefined)
        {
            helper.UpdateflsDetails(component, event,StatusValue1,RemarksValue,helper);
            var closeMethod = component.get('c.closeModel');
            
            $A.enqueueAction(closeMethod);
            
        }
    },
    closeModel: function(component, event, helper) {
        component.set("v.isCall",false);
        component.set("v.isSv",false);
        component.set("v.isfls",false);
        component.set("v.isCancelled",false);
        component.set("v.isConducted",false);
        component.set("v.isReschedule",false);
        component.set("v.updateValue","");
        
        component.set("v.isScheduled1",false);
        component.set("v.isMissed1",false);
        component.set("v.isCompleted1",false);
        
        component.set("v.SvleadRecID","");
        component.set("v.FlsleadRecId","");
        component.set("v.leadRecID","");
	},

     previousPage: function (component, event, helper) {
        // Decrement current page and load previous records
        var currentPage = component.get("v.currentPage");
        component.set("v.currentPage", currentPage - 1);
        helper.loadRecords(component);
    },
    nextPage: function (component, event, helper) {
        // Increment current page and load next records
        var currentPage = component.get("v.currentPage");
        component.set("v.currentPage", currentPage + 1);
        helper.loadRecords(component);
    },
    navigateToLeadRecord: function(component, event, helper) {
        var recordId = event.currentTarget.getAttribute("value");
        var navigateEvent = $A.get("e.force:navigateToSObject");
        navigateEvent.setParams({
            "recordId": recordId,
            "slideDevName": "detail"
        });
        navigateEvent.fire();
    },
     addCustomerEvent: function(component, event, helper) {
        component.set('v.isModalOpen',true);
    },
 
})