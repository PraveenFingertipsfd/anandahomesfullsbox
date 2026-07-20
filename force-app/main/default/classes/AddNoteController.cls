public without sharing class AddNoteController {
    
    @AuraEnabled
    public static void updateLastNote(String leadId, String newNote) {
        Lead__c leadRecord = [SELECT Id, Last_Note__c,Lead_Status__c,RecordType.Name FROM Lead__c WHERE Id = :leadId LIMIT 1];
        User us = [select id,name from User where id =: userInfo.getUserId()];
        Datetime dt = Datetime.now();
        Timezone tz = Timezone.getTimeZone('Asia/Kolkata');
        String recordType = leadRecord.RecordType.Name;
        String status = leadRecord.Lead_Status__c;
        //dt = dt.addSeconds(tz.getOffset(dt)/1000);
       // String strTimeInAMorPM = dt.format('MMMMM dd, yyyy hh:mm a');
		   String strTimeInAMorPM = dt.format('dd-MM-yy HH:mm a');

        Integer noteCount = 1;
        if (leadRecord.Last_Note__c == null) {
            leadRecord.Last_Note__c = '';
        } else if (!leadRecord.Last_Note__c.trim().equals('')) {
            List<String> notes = leadRecord.Last_Note__c.split('\n');
            noteCount = notes.size() + 1;
        }
       // leadRecord.Last_Note__c += '\nNote ' + noteCount +' : ('+us.Name+')' + ' - (' + strTimeInAMorPM + ') :      '+newNote  ;
        leadRecord.Last_Note__c += '\nRemark ' + noteCount + ': ['+ recordType +'] ' + us.Name + ' - ['+ status +'] ' + '[' + strTimeInAMorPM + ']: ' + newNote;
   
        update leadRecord;
    }
    
    
    @AuraEnabled
    public static List<String> fetchLeadLastNotes(String leadId) {
        Lead__c leadRecord = [SELECT Id, Last_Note__c FROM Lead__c WHERE Id = :leadId LIMIT 1];
        List<String> lastNotes = new List<String>();
        
        if (leadRecord != null && leadRecord.Last_Note__c != null) {
            lastNotes = leadRecord.Last_Note__c.split('\n');
            
            // Filter out empty strings or null values
            List<String> filteredNotes = new List<String>();
            for (String note : lastNotes) {
                if (note != null && note != '') {
                    filteredNotes.add(note);
                }
            }
            
            lastNotes = filteredNotes;
             // Reverse the list to get notes in descending order
        List<String> reversedNotes = new List<String>();
        for (Integer i = lastNotes.size() - 1; i >= 0; i--) {
            reversedNotes.add(lastNotes[i]);
        }
            lastNotes = reversedNotes;

        }
        
        return lastNotes;
    }
    
    
    @AuraEnabled
    public static Boolean isPrivilegedUser() {
        String labelValue = System.Label.Privileged_Profiles;
        Set<String> allowedProfiles = new Set<String>();

        if (!String.isBlank(labelValue)) {
            for (String name : labelValue.split(',')) {
                allowedProfiles.add(name.trim());
            }
        }

        String userProfile = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId()].Profile.Name;

        if (allowedProfiles.isEmpty()) {
            allowedProfiles.add('System Administrator');
        }

        // These profiles can always add/clear remarks, regardless of the label value
        allowedProfiles.add('Pre-Sales Executive');
        allowedProfiles.add('Associate Manager');

        return allowedProfiles.contains(userProfile);
    }


}