public class UserStatusController {
    
    @AuraEnabled
    public static User getUserRec(){
        return [SELECT Id,Name,Availability__c,is_working__c FROM User Where id =:UserInfo.getUserId()];
    }
    
    @AuraEnabled
    public static void updateUser(User ulist,String reasone){
        System.debug('===========>'+reasone);
        //createDailyLog(ulist,reasone);
        UserAvailabilityHistoryHandler.turnOffReason = reasone;
        update ulist;
        system.debug('list'+ulist);
        
        
        User currentUser = [SELECT Id,Name, ManagerId,Availability__c FROM User WHERE Id = :ulist.id LIMIT 1];
        if(currentUser.Availability__c==false){
           // currentUser.is_working__c=false;
            update currentUser;
          /*  if (currentUser.ManagerId != null) {
                CustomNotificationType notificationType = [SELECT Id, DeveloperName FROM CustomNotificationType WHERE DeveloperName='User_Avilablilty_Notification'];
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                Id userId = currentUser.ManagerId;
                String recordId = Userinfo.getUserId();
                notification.setTitle('User Unavailability Notification');
                notification.setBody('User '+ currentUser.Name +' is not available');
                notification.setNotificationTypeId(notificationType.Id);
                notification.setSenderId(userId);
                notification.setTargetId(recordId);
                
              //  notification.send(new Set<String> {userId});
                
            } else {
                System.debug('No manager assigned to this user.');
            }*/
        }
        else{
             currentUser.is_working__c=true;
            update currentUser;
           
        }
        
    }
}