public without sharing class CustomLookupGlobalController {
    @AuraEnabled
    public static List<RecordsData> fetchRecords(String objectName, String filterField, String additionalField, String searchString, String value, String queryField, String queryValue,String queryField1, String queryValue1) {
        try {
            List<RecordsData> recordsDataList = new List<RecordsData>();
            
            System.debug('value: ' + value + ', objectName: ' + objectName + ', filterField: ' + filterField + 
                         ', searchString: ' + searchString + ', specialField: ' + queryField1 + ', specialValue: ' + queryValue1 +
                         ', additionalField: ' + additionalField);
            
            String query = 'SELECT Id, ' + filterField;
            if (filterField != 'Name') {
                query += ', Name';
            }
            if (String.isNotBlank(additionalField)) {
                query += ', ' + additionalField;
            }
            if (String.isNotBlank(queryField)){
                query += ', ' + queryField;
            }
            if (String.isNotBlank(queryField1)){
                query += ', ' + queryField1;
            }
            query += ' FROM ' + String.escapeSingleQuotes(objectName);

            // Wrap searchString with wildcards for partial matching
            if (String.isNotBlank(searchString)) {
                searchString = '%' + searchString + '%';
            }

            String whereClause = '';

            if (String.isNotBlank(value) && value.length() > 15) {
                whereClause = ' WHERE Id = :value LIMIT 1';
            }else if (String.isNotBlank(queryField) && String.isNotBlank(queryValue)) {
                whereClause += ' WHERE ' + String.escapeSingleQuotes(queryField) + ' =: queryValue';

                if (String.isNotBlank(queryField1) && String.isNotBlank(queryValue1)) {
                    whereClause += ' AND ' + String.escapeSingleQuotes(queryField1) + ' =: queryValue1';
                }
                if (String.isNotBlank(searchString)) {
                    whereClause += ' AND (' + String.escapeSingleQuotes(filterField) + ' LIKE :searchString';
                    whereClause += ' OR Name LIKE :searchString';
                    if (String.isNotBlank(additionalField)) {
                        whereClause += ' OR ' + String.escapeSingleQuotes(additionalField) + ' LIKE :searchString';
                    }
                    whereClause += ')';
                }
            }else if (String.isNotBlank(queryField1) && String.isNotBlank(queryValue1)) {
                if (String.isNotBlank(searchString)) {
                    whereClause += ' AND (' + String.escapeSingleQuotes(filterField) + ' LIKE :searchString';
                    whereClause += ' OR Name LIKE :searchString';
                    if (String.isNotBlank(additionalField)) {
                        whereClause += ' OR ' + String.escapeSingleQuotes(additionalField) + ' LIKE :searchString';
                    }
                    whereClause += ')';
                }
            } else if (String.isNotBlank(searchString)) {
                whereClause += ' WHERE (' + String.escapeSingleQuotes(filterField) + ' LIKE :searchString';
                whereClause += ' OR Name LIKE :searchString';
                if (String.isNotBlank(additionalField)) {
                    whereClause += ' OR ' + String.escapeSingleQuotes(additionalField) + ' LIKE :searchString';
                }
                whereClause += ')';
            }
            
            if (String.isNotBlank(whereClause)) {
                whereClause += ' LIMIT 49999';
                query += whereClause;
            }
            
            System.debug('SOQL Query: ' + query);
            
            for (SObject s : Database.query(query)) {
                String label = (String) s.get(filterField);
                String id = (String) s.get('Id');
                String additionalValue = additionalField != null ? (String) s.get(additionalField) : null;
                recordsDataList.add(new RecordsData(label, id, additionalValue));
            }
            
            return recordsDataList;
        } catch (Exception err) {
            System.debug('Error: ' + err.getMessage());
            if (String.isNotBlank(err.getMessage()) && err.getMessage().contains('error:')) {
                throw new AuraHandledException(err.getMessage().split('error:')[1].split(':')[0] + '.');
            } else {
                throw new AuraHandledException(err.getMessage());
            }
        }
    }
    
    @AuraEnabled
    public static List<RecordsData> fetchRecordsGB(String objectName, String filterField, String additionalFields, String query, String value, String searchString) {
        // Check if the object name and filter field are provided
        List<RecordsData> recordsDataList = new List<RecordsData>();
        if (String.isBlank(objectName) || String.isBlank(filterField)) {
            throw new AuraHandledException('Object Name and Filter Field are required.');
        }
        
        // Start building the query string
        String searchQuery = 'SELECT Id, ' + filterField;
        List<String> additionalValueList = new List<String>();
        
        // Append additional fields if provided
        if (String.isNotBlank(additionalFields)) {
            additionalValueList = additionalFields.split(',');
            searchQuery += ', ' + additionalFields;
        }
        
        // Append the object name
        searchQuery += ' FROM ' + objectName;
        
        // Append any additional filtering query
        if (!String.isBlank(query)) {
            searchQuery += ' WHERE ' + query;
        }
        
        // Add search string filtering if provided
        if (!String.isBlank(searchString)) {
            if (searchQuery.contains('WHERE')) {
                searchQuery += ' AND ' + filterField + ' LIKE \'%' + searchString + '%\'';
            } else {
                searchQuery += ' WHERE ' + filterField + ' LIKE \'%' + searchString + '%\'';
            }
        }
        searchQuery += ' Limit 10';
        System.debug('Final Query: ' + searchQuery); // Corrected debugging statement
        
        try {
            // Execute the query dynamically
            for (SObject s : Database.query(searchQuery)) { // Use 'searchQuery'
                String label = (String) s.get(filterField);
                String id = (String) s.get('Id');
                
                // Handle additional fields dynamically
                String additionalValue = null;
                if (!additionalValueList.isEmpty() && additionalValueList[0] != null) {
                    additionalValue = (String) s.get(additionalValueList[0]);
                }
                
                // Add record data to the list
                recordsDataList.add(new RecordsData(label, id, additionalValue));
            }
            return recordsDataList;
        } catch (Exception e) {
            throw new AuraHandledException('An error occurred while fetching records: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<RecordsData> fetchCPRecords(String objectName, String filterField, String additionalField, String searchString, String value, String queryField, String queryValue,String queryField1, String queryValue1)
    {
        List<RecordsData> recordsDataList = new List<RecordsData>();
        // Add wildcard for LIKE
        String key = '%' + searchString + '%';
        
        List<Channel_Partner__c> results = [
            SELECT Id, Name, Mobile_Number_Text__c, Channel_Partner_Name__c
            FROM Channel_Partner__c
            WHERE Channel_Partner_Status__c = 'Active'
            AND (
                Mobile_Number_Text__c LIKE :key
                OR Channel_Partner_Name__c LIKE :key
                OR Name LIKE :key
            )
            LIMIT 50
        ];
        
        for (SObject s : results) {
                String label = (String) s.get(filterField);
                String id = (String) s.get('Id');
                String additionalValue = additionalField != null ? (String) s.get(additionalField) : null;
                recordsDataList.add(new RecordsData(label, id, additionalValue));
            }
        
        return recordsDataList;
    }
    
    // RecordsData class definition
    public class RecordsData {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String label2;
        
        public RecordsData(String label, String value, String label2) {
            this.label = label;
            this.value = value;
            this.label2 = label2;
        }
    }
    
}