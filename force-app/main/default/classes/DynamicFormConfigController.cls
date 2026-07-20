public with sharing class DynamicFormConfigController {

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAllObjects() {
        List<ObjectOption> objects = new List<ObjectOption>();

        for (Schema.SObjectType objType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();

            if (objDescribe.isCreateable() && objDescribe.isAccessible()) {
                objects.add(new ObjectOption(
                    objDescribe.getLabel(),
                    objDescribe.getName()
                ));
            }
        }

        objects.sort();
        return objects;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectFields(String objectApiName) {
        return getObjectFieldsInternal(objectApiName, true);
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getAllObjectFields(String objectApiName) {
        return getObjectFieldsInternal(objectApiName, false);
    }

    /**
     * @description Field-path picker for "default value from field" in Form Configurator.
     * Returns every accessible field on the target object plus every accessible field on
     * each parent object reachable by one lookup hop. Values are dotted SOQL paths
     * (e.g. "OwnerId", "Project__r.Project_Manager__c"). Labels are human readable
     * (e.g. "Owner Id", "Project → Project Manager").
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getFieldPathOptions(String objectApiName) {
        List<FieldOption> out = new List<FieldOption>();

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return out;

        Schema.DescribeSObjectResult d = objType.getDescribe();
        Map<String, Schema.SObjectField> fmap = d.fields.getMap();

        // Same-object fields
        for (String fName : fmap.keySet()) {
            Schema.DescribeFieldResult fd = fmap.get(fName).getDescribe();
            if (!fd.isAccessible()) continue;
            out.add(new FieldOption(
                fd.getLabel(),
                fd.getName(),
                String.valueOf(fd.getType()),
                !fd.isNillable() && !fd.isDefaultedOnCreate()
            ));
        }

        // One hop into parents via Reference fields
        Set<String> seenRelationships = new Set<String>();
        for (String fName : fmap.keySet()) {
            Schema.DescribeFieldResult fd = fmap.get(fName).getDescribe();
            if (!fd.isAccessible()) continue;
            if (fd.getType() != Schema.DisplayType.REFERENCE) continue;
            String rel = fd.getRelationshipName();
            if (String.isBlank(rel) || seenRelationships.contains(rel)) continue;
            seenRelationships.add(rel);

            for (Schema.SObjectType refType : fd.getReferenceTo()) {
                Schema.DescribeSObjectResult refDesc = refType.getDescribe();
                if (!refDesc.isAccessible()) continue;
                String parentLabel = fd.getLabel();
                Map<String, Schema.SObjectField> pmap = refDesc.fields.getMap();
                for (String pName : pmap.keySet()) {
                    Schema.DescribeFieldResult pfd = pmap.get(pName).getDescribe();
                    if (!pfd.isAccessible()) continue;
                    // Skip system audit fields on the parent to keep the list usable
                    String n = pfd.getName().toLowerCase();
                    if (n == 'createddate' || n == 'lastmodifieddate' || n == 'systemmodstamp') continue;
                    out.add(new FieldOption(
                        parentLabel + ' → ' + pfd.getLabel(),
                        rel + '.' + pfd.getName(),
                        String.valueOf(pfd.getType()),
                        false
                    ));
                }
                // Only one referenced object per polymorphic field (the first) for simplicity
                break;
            }
        }

        // Stable alphabetical for the UI
        Map<String, FieldOption> sortMap = new Map<String, FieldOption>();
        for (FieldOption fo : out) sortMap.put(fo.label.toLowerCase() + '|' + fo.value, fo);
        List<String> keys = new List<String>(sortMap.keySet());
        keys.sort();
        List<FieldOption> sorted = new List<FieldOption>();
        for (String k : keys) sorted.add(sortMap.get(k));
        return sorted;
    }

    private static List<FieldOption> getObjectFieldsInternal(String objectApiName, Boolean updateableOnly) {
        List<FieldOption> fields = new List<FieldOption>();

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) {
            return fields;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();

            if (fieldDescribe.isAccessible() && (!updateableOnly || fieldDescribe.isUpdateable())) {
                fields.add(new FieldOption(
                    fieldDescribe.getLabel(),
                    fieldDescribe.getName(),
                    String.valueOf(fieldDescribe.getType()),
                    !fieldDescribe.isNillable() && !fieldDescribe.isDefaultedOnCreate()
                ));
            }
        }

        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<ChildRelationshipOption> getChildRelationships(String objectApiName) {
        List<ChildRelationshipOption> childRels = new List<ChildRelationshipOption>();

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) {
            return childRels;
        }

        for (Schema.ChildRelationship rel : objType.getDescribe().getChildRelationships()) {
            Schema.DescribeSObjectResult childDescribe = rel.getChildSObject().getDescribe();

            if (childDescribe.isCreateable() && childDescribe.isAccessible() && rel.getField() != null) {
                String relationshipName = rel.getRelationshipName();
                if (String.isNotBlank(relationshipName)) {
                    childRels.add(new ChildRelationshipOption(
                        childDescribe.getLabel() + ' (' + childDescribe.getName() + ')',
                        childDescribe.getName(),
                        rel.getField().getDescribe().getName(),
                        relationshipName
                    ));
                }
            }
        }

        return childRels;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupOption> getAllProfiles() {
        List<LookupOption> profiles = new List<LookupOption>();

        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name]) {
            profiles.add(new LookupOption(p.Name, p.Id));
        }

        return profiles;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupOption> getAllRoles() {
        List<LookupOption> roles = new List<LookupOption>();

        for (UserRole r : [SELECT Id, Name FROM UserRole ORDER BY Name]) {
            roles.add(new LookupOption(r.Name, r.Id));
        }

        return roles;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupOption> searchUsers(String searchTerm) {
        List<LookupOption> users = new List<LookupOption>();

        String searchKey = '%' + searchTerm + '%';
        for (User u : [SELECT Id, Name, Email FROM User
                       WHERE Name LIKE :searchKey OR Email LIKE :searchKey
                       LIMIT 20]) {
            users.add(new LookupOption(u.Name + ' (' + u.Email + ')', u.Id));
        }

        return users;
    }

    @AuraEnabled
    public static String saveConfiguration(String configId, String configName, String objectApiName,
                                           String contextObjectApiName, String buttonLabel,
                                           String configJson, String description, Boolean active,
                                           String matchingCriteria) {
        try {
            Dynamic_Form_Configuration__c config;

            if (String.isNotBlank(configId)) {
                config = [SELECT Id FROM Dynamic_Form_Configuration__c WHERE Id = :configId LIMIT 1];
            } else {
                config = new Dynamic_Form_Configuration__c();
            }

            config.Name = configName;
            config.Object_API_Name__c = objectApiName;
            config.Context_Object__c = contextObjectApiName;
            config.Button_Label__c = buttonLabel;
            config.Configuration_JSON__c = configJson;
            config.Description__c = description;
            config.Active__c = active;
            config.Matching_Criteria__c = String.isBlank(matchingCriteria) ? null : matchingCriteria;

            upsert config;

            return config.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Dynamic_Form_Configuration__c getConfiguration(String configId) {
        return [SELECT Id, Name, Object_API_Name__c, Context_Object__c, Button_Label__c,
                Configuration_JSON__c, Description__c, Active__c, Matching_Criteria__c
                FROM Dynamic_Form_Configuration__c
                WHERE Id = :configId LIMIT 1];
    }

    @AuraEnabled(cacheable=true)
    public static List<Dynamic_Form_Configuration__c> getAllConfigurations() {
        return [SELECT Id, Name, Object_API_Name__c, Context_Object__c, Button_Label__c,
                Description__c, Active__c, CreatedDate, LastModifiedDate
                FROM Dynamic_Form_Configuration__c
                ORDER BY LastModifiedDate DESC];
    }

    @AuraEnabled(cacheable=true)
    public static List<Dynamic_Form_Configuration__c> getConfigurationsByObject(String objectApiName) {
        return [SELECT Id, Name, Object_API_Name__c, Context_Object__c, Button_Label__c,
                Configuration_JSON__c, Description__c, Active__c
                FROM Dynamic_Form_Configuration__c
                WHERE Object_API_Name__c = :objectApiName
                AND Active__c = true
                ORDER BY Name];
    }

    @AuraEnabled
    public static void deleteConfiguration(String configId) {
        try {
            delete [SELECT Id FROM Dynamic_Form_Configuration__c WHERE Id = :configId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String cloneConfiguration(String configId) {
        try {
            Dynamic_Form_Configuration__c original = [
                SELECT Name, Object_API_Name__c, Context_Object__c, Button_Label__c,
                       Configuration_JSON__c, Description__c, Active__c
                FROM Dynamic_Form_Configuration__c
                WHERE Id = :configId LIMIT 1
            ];

            Dynamic_Form_Configuration__c cloneRec = original.clone(false, true);
            cloneRec.Name = original.Name + ' (Copy)';
            cloneRec.Active__c = false;
            insert cloneRec;

            return cloneRec.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error cloning configuration: ' + e.getMessage());
        }
    }

    // Wrapper classes
    public class ObjectOption implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public ObjectOption(String label, String value) {
            this.label = label;
            this.value = value;
        }

        public Integer compareTo(Object compareTo) {
            ObjectOption other = (ObjectOption) compareTo;
            return this.label.compareTo(other.label);
        }
    }

    public class FieldOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean isSystemRequired;

        public FieldOption(String label, String value, String type, Boolean isSystemRequired) {
            this.label = label;
            this.value = value;
            this.type = type;
            this.isSystemRequired = isSystemRequired;
        }
    }

    public class ChildRelationshipOption {
        @AuraEnabled public String label;
        @AuraEnabled public String childObjectName;
        @AuraEnabled public String relationshipFieldName;
        @AuraEnabled public String relationshipName;

        public ChildRelationshipOption(String label, String childObjectName,
                                        String relationshipFieldName, String relationshipName) {
            this.label = label;
            this.childObjectName = childObjectName;
            this.relationshipFieldName = relationshipFieldName;
            this.relationshipName = relationshipName;
        }
    }

    public class LookupOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public LookupOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * Get document categories and types from ContentVersion picklist metadata.
     * Uses 3-level dependency: Object_API_Name__c → Document_Category__c → Document_Type__c
     * Filters categories based on objectApiName dependency.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getDocumentCategoriesForObject(String objectApiName) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        Schema.DescribeFieldResult objField = ContentVersion.Object_API_Name__c.getDescribe();
        Schema.DescribeFieldResult categoryField = ContentVersion.Document_Category__c.getDescribe();
        Schema.DescribeFieldResult typeField = ContentVersion.Document_Type__c.getDescribe();

        List<Schema.PicklistEntry> objEntries = objField.getPicklistValues();
        List<Schema.PicklistEntry> categoryEntries = categoryField.getPicklistValues();
        List<Schema.PicklistEntry> typeEntries = typeField.getPicklistValues();

        // Step 1: Find the controlling index for the given objectApiName
        Integer objectIndex = -1;
        for (Integer i = 0; i < objEntries.size(); i++) {
            if (objEntries[i].getValue() == objectApiName) {
                objectIndex = i;
                break;
            }
        }

        // Step 2: Find categories valid for this object (Object → Category dependency)
        // If no category has a validFor set, no dependency is configured — fall back to all
        // active categories rather than returning an empty list.
        Set<String> validCategories = new Set<String>();
        String catEntriesJson = JSON.serialize(categoryEntries);
        List<Object> catEntriesParsed = (List<Object>) JSON.deserializeUntyped(catEntriesJson);

        Boolean anyCategoryHasValidFor = false;
        for (Object ceObj : catEntriesParsed) {
            Map<String, Object> ce = (Map<String, Object>) ceObj;
            if (String.isNotBlank((String) ce.get('validFor'))) {
                anyCategoryHasValidFor = true;
                break;
            }
        }

        for (Integer i = 0; i < catEntriesParsed.size(); i++) {
            Map<String, Object> ce = (Map<String, Object>) catEntriesParsed[i];
            Boolean isActive = ce.get('active') == true;
            if (!isActive) continue;

            String catValue = (String) ce.get('value');

            if (objectIndex == -1 || !anyCategoryHasValidFor) {
                // Either objectApiName isn't in the picklist, or no Object→Category
                // dependency is configured at all — show every active category.
                validCategories.add(catValue);
            } else {
                String validFor = (String) ce.get('validFor');
                if (String.isNotBlank(validFor)) {
                    String hex = EncodingUtil.convertToHex(EncodingUtil.base64Decode(validFor));
                    if (isBitSet(hex, objectIndex)) {
                        validCategories.add(catValue);
                    }
                }
            }
        }

        if (validCategories.isEmpty()) return result;

        // Step 3: Find types valid for each category (Category → Type dependency)
        // Same fallback: if no type has validFor, treat every active type as valid for every category.
        Map<String, List<Map<String, String>>> categoryToTypes = new Map<String, List<Map<String, String>>>();
        for (String catVal : validCategories) {
            categoryToTypes.put(catVal, new List<Map<String, String>>());
        }

        String typeEntriesJson = JSON.serialize(typeEntries);
        List<Object> typeEntriesParsed = (List<Object>) JSON.deserializeUntyped(typeEntriesJson);

        Boolean anyTypeHasValidFor = false;
        for (Object teObj : typeEntriesParsed) {
            Map<String, Object> te = (Map<String, Object>) teObj;
            if (String.isNotBlank((String) te.get('validFor'))) {
                anyTypeHasValidFor = true;
                break;
            }
        }

        for (Object teObj : typeEntriesParsed) {
            Map<String, Object> te = (Map<String, Object>) teObj;
            Boolean isActive = te.get('active') == true;
            if (!isActive) continue;

            String teLabel = (String) te.get('label');
            String teValue = (String) te.get('value');
            String validFor = (String) te.get('validFor');

            if (!anyTypeHasValidFor) {
                // No Category→Type dependency configured: every active type belongs to every category.
                for (String catVal : validCategories) {
                    categoryToTypes.get(catVal).add(new Map<String, String>{
                        'label' => teLabel,
                        'value' => teValue
                    });
                }
                continue;
            }

            if (String.isBlank(validFor)) continue;

            String validForHex = EncodingUtil.convertToHex(EncodingUtil.base64Decode(validFor));

            for (Integer i = 0; i < categoryEntries.size(); i++) {
                String catValue = categoryEntries[i].getValue();
                if (!validCategories.contains(catValue)) continue;
                if (isBitSet(validForHex, i)) {
                    categoryToTypes.get(catValue).add(new Map<String, String>{
                        'label' => teLabel,
                        'value' => teValue
                    });
                }
            }
        }

        // Step 4: Build result - only include categories that have types
        for (Schema.PicklistEntry ce : categoryEntries) {
            if (!ce.isActive()) continue;
            String catValue = ce.getValue();
            if (!validCategories.contains(catValue)) continue;

            List<Map<String, String>> types = categoryToTypes.get(catValue);

            Map<String, Object> cat = new Map<String, Object>();
            cat.put('label', ce.getLabel());
            cat.put('value', ce.getValue());
            cat.put('documentTypes', types != null ? types : new List<Map<String, String>>());
            result.add(cat);
        }

        return result;
    }

    private static Boolean isBitSet(String hexString, Integer bitIndex) {
        if (String.isBlank(hexString)) return false;
        Integer byteIndex = bitIndex / 8;
        Integer bitPosition = 7 - Math.mod(bitIndex, 8);
        if (byteIndex * 2 + 1 >= hexString.length()) return false;
        String hexByte = hexString.substring(byteIndex * 2, byteIndex * 2 + 2);
        // Convert hex to integer manually (Apex doesn't have Integer.parseInt with radix)
        Integer byteValue = 0;
        for (Integer c = 0; c < hexByte.length(); c++) {
            Integer charVal = 0;
            String ch = hexByte.substring(c, c + 1).toLowerCase();
            if (ch >= '0' && ch <= '9') charVal = ch.charAt(0) - 48;
            else if (ch >= 'a' && ch <= 'f') charVal = ch.charAt(0) - 87;
            byteValue = byteValue * 16 + charVal;
        }
        return (byteValue & (1 << bitPosition)) != 0;
    }
}