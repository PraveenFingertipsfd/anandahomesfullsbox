({
    
    getFollowUpDetails: function(component, event) {
        let action = component.get("c.getFollowUpInformation");
        action.setCallback(this, function(response) {
            
            let state = response.getState();
            
            if (state == "SUCCESS") {
                var result = response.getReturnValue();
                component.set("v.DuefollowUpDetails",JSON.parse(JSON.stringify(result)));
                console.log('FOL modfif=====>');
                console.log(component.get("v.DuefollowUpDetails"));
                result.forEach(ele => {
                    
                    var scheduledTime = new Date(
                    ele.Scheduled_Date__c
                    ).toLocaleTimeString("en-US");
                    ele.Scheduled_Date__c = scheduledTime;
                });
                component.set("v.followUpDetails", result);
                component.set("v.todaysFollowupCount", result.length); 
                var todaycount= component.get('v.todayssitevistCount') + component.get('v.todaysFollowupCount');;
                var tabLabel = component.find("Agenda").get("v.label");
                var miss = "Today's Agendas("+todaycount+")";
                tabLabel[0].set("v.value", miss);
                
            }
        });
        $A.enqueueAction(action);
    },
    getSiteVisitDetails: function(component, event) {
        let action = component.get("c.getSiteVistInformation");
        action.setCallback(this, function(response) {
            let state = response.getState();
            
            if (state == "SUCCESS") {
                let result = response.getReturnValue();
                //alert(JSON.stringify(result));
                component.set("v.DuesiteVisitDetails", JSON.parse(JSON.stringify(result)));
                result.forEach(ele => {
                    
                    console.log(ele);
                    var scheduledTime = new Date(ele.Date__c).toLocaleTimeString("en-US");
                    ele.Date__c = scheduledTime;
                });
                    component.set("v.siteVisitDetails", result);
                    component.set("v.todayssitevistCount", result.length); 
                    var todaycount= component.get('v.todayssitevistCount') + component.get('v.todaysFollowupCount');;
                    var tabLabel = component.find("Agenda").get("v.label");
                    var miss = "Today's Agendas("+todaycount+")";
                    tabLabel[0].set("v.value", miss);
                    
                }
                });
                    $A.enqueueAction(action);
                },
    getPendingFollowUpDetails: function(component, event) {
                        let action = component.get("c.getPendingFollowUpInformation");
                        action.setCallback(this, function(response) {
                            let state = response.getState();
                            if (state == "SUCCESS") {
                                let result = response.getReturnValue();
                                let check=[];
                                result.forEach(ele => {
                                    
                                    var scheduledTime = new Date(
                                    ele.Scheduled_Date__c
                                    ).toLocaleTimeString("en-US");
                                    ele.Scheduled_Date__c = scheduledTime;
                                });
                                component.set("v.pendingFollowUpDetails", result);
                                component.set("v.pendingFollowupCount", result.length); 
                                var pendingcount= component.get('v.pendingsitevistCount') + component.get('v.pendingFollowupCount');;
                                var tabLabel = component.find("pending").get("v.label");
                                var miss = "Pending items("+pendingcount+")";
                                tabLabel[0].set("v.value", miss);
                            }
                        });
                        $A.enqueueAction(action);
                    },
    getPendingSiteVisitDetails: function(component, event) {
                        let action = component.get("c.getPendingSiteVistInformation");
                        action.setCallback(this, function(response) {
                            let state = response.getState();
                            
                            if (state == "SUCCESS") {
                                let result = response.getReturnValue();
                                result.forEach(ele => {
                                    console.log(ele);
                                    var scheduledTime = new Date(ele.Date__c).toLocaleTimeString("en-US");
                                    ele.Date__c = scheduledTime;
                                });
                                    component.set("v.pendingSiteVisitDetails", result);
                                    component.set("v.pendingsitevistCount", result.length);
                                    var pendingcount= component.get('v.pendingsitevistCount') + component.get('v.pendingFollowupCount');;
                                    var tabLabel = component.find("pending").get("v.label");
                                    var miss = "Pending items("+pendingcount+")";
                                    tabLabel[0].set("v.value", miss);
                                }
                                });
                                    $A.enqueueAction(action);
                                },
   /* getMissedTaskDetails: function(component, event) {
                                        let action = component.get("c.getMissedCallTask");
                                        
                                        action.setCallback(this, function(response) {
                                            let state = response.getState();
                                            
                                            if (state == "SUCCESS") {
                                                let result = response.getReturnValue();
                                                console.log(result);
                                                component.set("v.MissedTask", result);
                                                var tabLabel = component.find("missedCalls").get("v.label");
                                                var miss = "Missed calls("+result.length+")";
                                                tabLabel[0].set("v.value", miss);
                                                
                                            }
                                        });
                                        $A.enqueueAction(action);
                                    },*/          
    updateSvDetails:function(component, event,status,updateValue,helper) {
        alert('helper');
                                        var conductedDate=component.get("v.conductedDate");
                                        alert(conductedDate);
                                        if(conductedDate!=null && conductedDate!='')
                                            conductedDate= new Date(conductedDate).toLocaleString('en-GB');
                                        var svrecID = component.get("v.SvleadRecID");
                                        let action = component.get("c.updateSvDetils");
                                        action.setParams({ 
                                            recID:svrecID,
                                            svStatus: status,
                                            updateValue: updateValue,
                                            conducatedDate: conductedDate
                                        });
                                        action.setCallback(this, function(response) {
                                            let state = response.getState();
                                            if (state == "SUCCESS") {
                                                let result = response.getReturnValue();
                                                if(result!=null)
                                                { 
                                                    helper.displayMessage(component,"Site Visit Updated successfully", "SUCCESS");
                                                    $A.get('e.force:refreshView').fire();
                                                }
                                                else
                                                {
                                                    helper.displayMessage(component,"Something went wrong. Message-", "error");
                                                }
                                            }
                                        });
                                        $A.enqueueAction(action);
                                        
                                    },
    UpdateflsDetails:function(component, event,status,RemarksValue,helper) {
                                        var svrecID1 = component.get("v.FlsleadRecId");
                                        //alert(svrecID1);
                                        let action = component.get("c.updateFollowupDetails");
                                        action.setParams({ 
                                            recID:svrecID1,
                                            FLStatus: status,
                                            FLRemarks : RemarksValue,
                                        });
                                        action.setCallback(this, function(response) {
                                            let state = response.getState();
                                            if (state == "SUCCESS") {
                                                let result = response.getReturnValue();
                                                if(result!=null)
                                                {
                                                    helper.displayMessage(component,"Follow-Up Updated successfully", "SUCCESS");
                                                    $A.get('e.force:refreshView').fire();
                                                }
                                                else
                                                {
                                                    helper.displayMessage(component,"Something went wrong. Message-", "error");
                                                }
                                            }
                                            else if (state == "ERROR") {
                                                let errors = response.getError();
                                                let msg = (errors && errors[0] && errors[0].message) ? errors[0].message : "Unknown error";
                                                helper.displayMessage(component, msg, "error");
                                            }
                                        });
                                        $A.enqueueAction(action);
                                        
                                    },
    loadRecords: function (component) {
                                        var pageNumber = component.get("v.currentPage");
                                        var pageSize = component.get("v.pageSize");
                                        
                                        var action = component.get("c.todaysLeads");
                                        //alert(action);
                                        action.setParams({
                                            pageNumber: pageNumber,
                                            pageSize: pageSize
                                        });
                                        action.setCallback(this, function (response) {
                                            var state = response.getState();
                                            //alert('Response state: ' + state);
                                            if (state === "SUCCESS") {
                                                var records = response.getReturnValue();
                                                component.set("v.recordList", records.ldListtodays);
                                                component.set("v.Todayscount", records.todaysldCount);
                                                //component.set("v.reengagedleads", records.ldreengagedleads);
                                                //alert('Response state: ' + records.ldListtodays);
                                                component.set("v.isPreviousDisabled", pageNumber === 1);
                                                component.set("v.isNextDisabled", response.getReturnValue().length < pageSize);
                                            }
                                        });
                                        $A.enqueueAction(action);
},
    previousPage: function (component) {
                                        var currentPage = component.get("v.currentPage");
                                        component.set("v.currentPage", currentPage - 1);
                                        this.loadRecords(component);
}, 
   nextPage: function (component) {
                                        var currentPage = component.get("v.currentPage");
                                        component.set("v.currentPage", currentPage + 1);
                                        this.loadRecords(component);
 },
    
   displayMessage : function(component,message,type){
                                        var toastEvent = $A.get("e.force:showToast");
                                        toastEvent.setParams({
                                            "type": type,
                                            "message": message
                                        });
                                        toastEvent.fire();
                                    },
   renderEveryMin :function(component, event, helper){
                                        window.setTimeout(
                                            $A.getCallback(function() {    
                                                console.log('setTimeOut');
                                                self.doneRendering(component, event);
                                            }), 2000
                                        );  
                                        
                                        //execute callApexMethod() again after 5 sec each
                                        var self=  this; 
                                        
                                        window.setInterval(
                                            $A.getCallback(function() {    
                                                console.log('setInterval');
                                                self.doneRendering(component, event);
                                            }), 30000
                                        );  
                                        
                                    },
   doneRendering: function(cmp, event){
                                        console.log('here');
                                        var Followup = cmp.get("v.DuefollowUpDetails");
                                        var sv = cmp.get("v.DuesiteVisitDetails");
                                        console.log(sv);
                                        var today = new Date();
                                        var curTime=today;
                                        var indexList;
                                        //console.log(Followup.length);
                                        //Followup Render
                                        if(Followup.length>0)
                                        {	indexList=[];
                                         Followup.forEach((e,index)=>{
                                             var fDate= new Date(e.Scheduled_Date__c);
                                             if( fDate.getTime()< curTime.valueOf() )
                                             indexList.push(index);
                                         });
                                         
                                         var changeID=(cmp.find('OverTimeFollow'));
                                         
                                         if(changeID!=undefined && changeID.length==undefined && indexList.length>0)
                                         {
                                             $A.util.addClass(changeID,'overDue');     
                                         }	
                                         else if(changeID.length>0){
                                             
                                             changeID.forEach((e,index)=>{
                                                 if(indexList.includes(index))
                                                 $A.util.addClass(e,'overDue'); 
                                             });
                                             
                                         }
                                        }
                                        
                                        //SV Render 
                                        if(sv.length>0)
                                        {
                                            indexList=[];
                                            sv.forEach((e,index)=>{ 
                                                var svDate= new Date(e.Date__c);
                                                if(svDate.getTime() < curTime.valueOf() )
                                                indexList.push(index);
                                            });
                                            
                                            var changeSV=(cmp.find('OverTimeSV'));  
                                            
                                            if(changeSV!=undefined && changeSV.length==undefined && indexList.length>0)
                                            {
                                                $A.util.addClass(changeSV,'overDue');     
                                            }
                                            else if(changeSV.length>0)
                                            {
                                                
                                                changeSV.forEach((e,index)=>{        
                                                    if(indexList.includes(index))
                                                    $A.util.addClass(e,'overDue'); 
                                                }); 
                                            }
                                        }
                                    },
                                    
});