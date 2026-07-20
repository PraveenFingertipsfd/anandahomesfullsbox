public class LightningFileUploadHandler{
    @AuraEnabled  
    public static List<ContentDocument> getFiles(String recordId,List<String> IdsList){ 
        System.debug('vff  '+IdsList);
        System.debug(recordId);
             ID filter = recordId;
        List<ContentDocumentLink> cdlList = [SELECT Id, LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId=:filter];                         
        Set<Id> documentIds = new Set<Id>(); 
       
        for(ContentDocumentLink cdl:cdlList){  
            documentIds.add(cdl.ContentDocumentId);  
        }    
        return [SELECT Id, Title, FileType FROM ContentDocument WHERE Id IN :IdsList];        
    } 
    
    @AuraEnabled  
    public static void deleteFile(String contentDocumentId){ 
        delete [SELECT Id from ContentDocument WHERE Id = :contentDocumentId];       
    }  
}