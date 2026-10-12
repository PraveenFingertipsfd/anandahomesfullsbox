({
	doInit : function(component, event, helper) {
          const profile = component.get('v.CurrentUser')['Profile'].Name;
       //alert(profile)
        component.set('v.profileNames',profile);
        component.set('v.todayLabel', helper.formatToday());

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
        helper.getUsers(component);
    },

    /* ---------- Backup caller ---------- */
    openBackupModal : function(component, event, helper){
        var userId = event.getSource().get('v.value');
        var users = component.get('v.users') || [];
        var target = null;
        for(var i=0;i<users.length;i++){
            if(users[i] && users[i].Id === userId){ target = users[i]; break; }
        }
        if(!target){ return; }
        component.set('v.backupForUser', target);
        component.set('v.selBackupUserId', target.Todays_Backup_Caller__c || '');
        component.set('v.backupCandidates', []);
        component.set('v.showBackupModal', true);
        helper.getBackupCandidates(component, userId);
    },
    closeBackupModal : function(component, event, helper){
        component.set('v.showBackupModal', false);
        component.set('v.backupForUser', null);
        component.set('v.backupCandidates', []);
        component.set('v.selBackupUserId', '');
    },
    onBackupChange : function(component, event, helper){
        component.set('v.selBackupUserId', event.getSource().get('v.value') || '');
    },
    saveBackupCaller : function(component, event, helper){
        helper.saveBackupCaller(component);
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
