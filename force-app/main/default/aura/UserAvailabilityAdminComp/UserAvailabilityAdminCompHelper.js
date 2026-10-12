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
                this.showToast('Something went wrong.', 'Please contact System Administrator.', 'error');
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
                this.showToast('Success!', 'Status Updated sucessfully!', 'success');
            }else if(state === "ERROR") {
                this.showToast('Something went wrong.', 'Please contact System Administrator.', 'error');
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
                this.showToast('Success!', 'Status Updated sucessfully!', 'success');
                if(component.get('v.selProfileFilter') === 'Telephone User'){
                    // Keep the page in place: mirror what the server did to the row
                    // (Availability follows Working; Working on clears the backup caller).
                    this.applyWorkingToLists(component, component.get('v.selUser'));
                }else{
                    $A.get('e.force:refreshView').fire();
                }
            }else if(state === "ERROR") {
                this.showToast('Something went wrong.', 'Please contact System Administrator.', 'error');
            }
        });
        $A.enqueueAction(action);
    },

    /* ---------- Backup caller ---------- */
    getBackupCandidates: function(component, forUserId){
        var action = component.get('c.getWorkingTelephoneUsers');
        action.setParams({ "forUserId": forUserId });
        action.setCallback(this, function(response){
            if(response.getState() === 'SUCCESS'){
                component.set('v.backupCandidates', response.getReturnValue() || []);
            }else{
                this.showToast('Something went wrong.', this.errorMessage(response), 'error');
            }
        });
        $A.enqueueAction(action);
    },

    saveBackupCaller: function(component){
        var target = component.get('v.backupForUser');
        var backupId = component.get('v.selBackupUserId');
        if(!target || !backupId){ return; }

        component.set('v.backupSaving', true);
        var action = component.get('c.assignBackupCaller');
        action.setParams({ "userId": target.Id, "backupUserId": backupId });
        action.setCallback(this, function(response){
            component.set('v.backupSaving', false);
            if(response.getState() === 'SUCCESS'){
                var updated = response.getReturnValue();
                this.applyBackupToLists(component, updated);
                var backupName = updated && updated.Todays_Backup_Caller__r ? updated.Todays_Backup_Caller__r.Name : '';
                this.showToast('Success!', 'Backup caller for ' + target.Name + ' set to ' + backupName + '.', 'success');
                component.set('v.showBackupModal', false);
                component.set('v.backupForUser', null);
                component.set('v.backupCandidates', []);
                component.set('v.selBackupUserId', '');
            }else{
                this.showToast('Could not assign backup caller.', this.errorMessage(response), 'error');
            }
        });
        $A.enqueueAction(action);
    },

    // After a Working toggle: Availability mirrors Working (see Apex updateUser2) and the
    // backup caller is cleared when Working turns on (see UserTrigger). Patch both lists
    // so the row re-renders without a page refresh.
    applyWorkingToLists: function(component, toggled){
        if(!toggled){ return; }
        var working = toggled.is_working__c === true;
        var patch = function(list){
            if(!list){ return list; }
            for(var i=0;i<list.length;i++){
                if(list[i] && list[i].Id === toggled.Id){
                    list[i].is_working__c = working;
                    list[i].Availability__c = working;
                    if(working){
                        list[i].Todays_Backup_Caller__c = null;
                        list[i].Todays_Backup_Caller__r = null;
                    }
                }
            }
            return list;
        };
        component.set('v.users', patch(component.get('v.users')));
        component.set('v.paginationList', patch(component.get('v.paginationList')));
    },

    // Patch the updated user into both lists so the row refreshes without losing the current page.
    applyBackupToLists: function(component, updated){
        if(!updated){ return; }
        var patch = function(list){
            if(!list){ return list; }
            for(var i=0;i<list.length;i++){
                if(list[i] && list[i].Id === updated.Id){
                    list[i].Todays_Backup_Caller__c = updated.Todays_Backup_Caller__c;
                    list[i].Todays_Backup_Caller__r = updated.Todays_Backup_Caller__r;
                }
            }
            return list;
        };
        component.set('v.users', patch(component.get('v.users')));
        component.set('v.paginationList', patch(component.get('v.paginationList')));
    },

    formatToday: function(){
        var now = new Date();
        var days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
        var months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        return days[now.getDay()] + ', ' + now.getDate() + ' ' + months[now.getMonth()] + ' ' + now.getFullYear();
    },

    errorMessage: function(response){
        var errors = response.getError();
        if(errors && errors[0] && errors[0].message){ return errors[0].message; }
        return 'Please contact System Administrator.';
    },

    showToast: function(title, message, type){
        var evt = $A.get("e.force:showToast");
        evt.setParams({ "title": title, "message": message, "type": type });
        evt.fire();
    }
})
