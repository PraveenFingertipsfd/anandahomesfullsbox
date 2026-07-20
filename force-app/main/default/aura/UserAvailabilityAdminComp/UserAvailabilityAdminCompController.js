({
	doInit : function(component, event, helper) {
          const profile = component.get('v.CurrentUser')['Profile'].Name;
       //alert(profile) 
        component.set('v.profileNames',profile);
       
        if(profile == 'Recovery Head'){
            component.set('v.selProfileFilter','Recovery Presales');
        }
        else if(profile == 'Sales Head'){
            component.set('v.selProfileFilter','Sales Project Head');
        }else{
           component.set('v.selProfileFilter','Pre-Sales Executive'); 
        }
        
		helper.getUsers(component);
        
	},
     selectChange:function(component, event, helper) {
        //var options = component.find("option");
       // alert(event.currentTarget.dataset.id)
        //options = options? []: options.length? options: [options];
        var selUserId = event.currentTarget.dataset.id;
        var users = component.get('v.users');
       // alert(JSON.stringify(users))
        var user;
        for(var i=0;i<=users.length;i++){
            if(users[i].Id === selUserId){
                
                user = users[i];
                //alert(JSON.stringify(user))
                break;
            }
        }
       
        component.set("v.selUser",user);
       helper.submit(component,event,helper);
          
    },
       selectChange2:function(component, event, helper) {
      
        var selUserId = event.currentTarget.dataset.id;
        var users = component.get('v.users');
       
        var user;
        for(var i=0;i<=users.length;i++){
            if(users[i].Id === selUserId){
                
                user = users[i];
             
                break;
            }
        }
       
        component.set("v.selUser",user);
       helper.submit2(component,event,helper);
          
    },
    onChange : function(component, event, helper){
        //alert(component.get('v.selProfileFilter'));
         var pageSize = component.get("v.pageSize");
       var action = component.get('c.getAllUsers');
          action.setParams({
            "profile": component.get('v.selProfileFilter')
        });
        action.setCallback(this,function(response){
            //alert(response.getState());
            var state=response.getState();            
            if(state==='SUCCESS'){
                var userDetails = response.getReturnValue();
                //alert(response.getReturnValue());
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
    first : function(component, event, helper)
    {
        
        var oppList = component.get("v.users");
        var pageSize = component.get("v.pageSize");
        var paginationList = [];
        for(var i=0; i< pageSize; i++)
        {
            paginationList.push(oppList[i]);
        }
        component.set("v.paginationList", paginationList);
        component.set("v.start",0);
        component.set("v.end",1);
    },
    
    last : function(component, event, helper)
    {
        
        var oppList = component.get("v.users");
        var pageSize = component.get("v.pageSize");
        var totalSize = component.get("v.totalSize");
        var paginationList = [];
        
        for(var i=totalSize-pageSize+1; i< totalSize; i++)
        {
            paginationList.push(oppList[i]);
        }
        component.set("v.paginationList", paginationList);
       component.set("v.start",1);
        component.set("v.end",totalSize);
    },
    
    next : function(component, event, helper)
    {
        
        var oppList = component.get("v.users");
        var end = component.get("v.end");
        var start = component.get("v.start");
        var pageSize = component.get("v.pageSize");
        var paginationList = [];
        var counter = 0;
        
        for(var i=end+1; i<end+pageSize+1; i++)
        {
            if(oppList.length > end)
            {
                paginationList.push(oppList[i]);
                counter ++ ;
            }
        }
        
        start = start + counter;
        end = end + counter;
        component.set("v.start",start);
        component.set("v.end",end);
        component.set("v.paginationList", paginationList);
        
    },
    
    previous : function(component, event, helper)
    {
        
        var oppList = component.get("v.users");
        var end = component.get("v.end");
        var start = component.get("v.start");
        var pageSize = component.get("v.pageSize");
        var paginationList = [];
        var counter = 0;
        
        for(var i= start-pageSize; i < start ; i++)
        {
            if(i > -1)
            {
                paginationList.push(oppList[i]);
                counter ++;
            }
            else {
                start++;
            }
        }
        
        start = start - counter;
        end = end - counter;
        component.set("v.start",start);
        component.set("v.end",end);
        component.set("v.paginationList", paginationList);
    },
})