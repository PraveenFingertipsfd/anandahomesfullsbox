public with sharing class  UserAvailabilityController {

    public static final String TELEPHONE_USER_FILTER = 'Telephone User';

    @AuraEnabled
    public static List<User> getAllUsers(string profile){
        system.debug('profile'+profile);
        if(profile == TELEPHONE_USER_FILTER){
            return [SELECT Id,Name,Username,Profile.Name,Availability__c,Manager.Name,is_working__c,
                           Telephone_User__c,Todays_Backup_Caller__c,Todays_Backup_Caller__r.Name
                    FROM User
                    WHERE isActive = true AND Telephone_User__c = true
                    ORDER BY NAME ASC];
        }
        return [SELECT Id,Name,Username,Profile.Name,Availability__c,Manager.Name,is_working__c,
                       Telephone_User__c,Todays_Backup_Caller__c,Todays_Backup_Caller__r.Name
                FROM User Where isActive = true and Profile.Name=:profile ORDER BY NAME ASC];
    }

    /**
     * Telephone users who are working today and can be picked as a backup caller for the given user.
     * Excludes the user themself and anyone who already has that user as their own backup
     * (the User hierarchy field does not allow circular references).
     */
    @AuraEnabled
    public static List<User> getWorkingTelephoneUsers(Id forUserId){
        return [SELECT Id,Name,Username,Availability__c,is_working__c
                FROM User
                WHERE isActive = true
                  AND Telephone_User__c = true
                  AND is_working__c = true
                  AND Id != :forUserId
                  AND Todays_Backup_Caller__c != :forUserId
                ORDER BY Name ASC];
    }

    @AuraEnabled
    public static User assignBackupCaller(Id userId, Id backupUserId){
        if(userId == null){
            throw buildAuraException('User is required.');
        }
        if(backupUserId == null){
            throw buildAuraException('Select a backup caller.');
        }
        if(userId == backupUserId){
            throw buildAuraException('A user cannot be their own backup caller.');
        }
        List<User> backups = [SELECT Id FROM User
                              WHERE Id = :backupUserId AND isActive = true
                                AND Telephone_User__c = true AND is_working__c = true
                              LIMIT 1];
        if(backups.isEmpty()){
            throw buildAuraException('Backup caller must be an active telephone user who is working today.');
        }
        User toUpdate = new User(Id = userId, Todays_Backup_Caller__c = backupUserId);
        try{
            update toUpdate;
        }catch(DmlException e){
            throw buildAuraException(e.getDmlMessage(0));
        }
        return [SELECT Id,Todays_Backup_Caller__c,Todays_Backup_Caller__r.Name FROM User WHERE Id = :userId];
    }

    private static AuraHandledException buildAuraException(String message){
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    @AuraEnabled
    public static List<User> getMyUsers(){
        User curUser = [select id,name,Profile.name from user where id=:UserInfo.getUserId() ];

        if(curUser.profile.name == 'Presales Head' || curUser.profile.name == 'Sales Head' || curUser.profile.name == 'Site visit Head' || curUser.Profile.Name == 'Recovery Head' ){
            return [SELECT Id,Name,Username,Profile.Name,Availability__c,Manager.Name,is_working__c FROM User WHERE (Manager.ManagerId = :UserInfo.getUserId() or ManagerId=:UserInfo.getUserId()) and isActive = true ];
        }
        else{
            return [SELECT Id,Name,Username,Profile.Name,Availability__c,Manager.Name,is_working__c FROM User WHERE ManagerId = :UserInfo.getUserId() and isActive = true ];
        }



    }

    @AuraEnabled
    public static void updateUser(String selUserId,User selUser){

        //List<User> userList = [select id,name,availability__c from user where id =:selUserId];
        //createDailyLog(selUser);
        update selUser;
        system.debug('selUser: '+selUser);

    }
    @AuraEnabled
    public static void updateUser2(User selUser){
        system.debug('selUser: '+selUser);

        if(selUser.is_working__c==false){
            selUser.Availability__c=false;
            update selUser;
        }
        if(selUser.is_working__c){
            selUser.Availability__c=true;
            update selUser;
        }
        /*if(selUser.On_Site__c){
Daily_Logs__c log=new Daily_Logs__c();
log.Name=selUser.Name;
log.OwnerId = selUser.Id;
log.Reasone__c = 'Start lead assigment';
log.Start_Time__c = system.now();
insert log;
}else{
Daily_Logs__c log=new Daily_Logs__c();
log.Name=selUser.Name;
log.OwnerId = selUser.Id;
log.Reasone__c = 'Stop lead assignment';
log.End_Time__c = system.now();
insert log;
}*/

    }
    /* @AuraEnabled
public static void createDailyLog(User selUser)
{

System.debug('user list'+selUser);

if(selUser.Availability__c){
Daily_Logs__c log=new Daily_Logs__c();
log.Start_Time__c=datetime.now();
log.Name=selUser.Name;
log.OwnerId = selUser.Id;
insert log;
}else{
list<Daily_Logs__c> dayLog=[select Name,Start_Time__c,End_Time__c,Reasone__c from Daily_Logs__c  where (OwnerId=:selUser.Id AND CreatedDate = TODAY AND Start_Time__c!=null AND End_Time__c=null) ORDER BY CreatedDate DESC  limit 1];
if(dayLog.size()>0){
dayLog[0].End_Time__c = datetime.now();
//dayLog[0].Reasone__c = Reasone;
update dayLog[0];
}else{
Daily_Logs__c lg = new Daily_Logs__c();
lg.Name=  selUser.Name;
lg.End_Time__c = system.now();
//lg.Reasone__c = Reasone;
insert lg;
}


}

}*/
}
