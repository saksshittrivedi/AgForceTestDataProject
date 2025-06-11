public without sharing class TestDataCreationController {
    static final String PROMPT_TEMPLATE_API_NAME = 'Create_Test_Data_Prompt_Template';
    @AuraEnabled(cacheable=true)
    public static List<String> getAllSObjectNames() {
        return new List<String>(Schema.getGlobalDescribe().keySet());
    }

    @AuraEnabled
    public static Map<String, Object> getFieldsForObject(String objectName) {
        if (!Schema.getGlobalDescribe().containsKey(objectName)) {
            throw new AuraHandledException('Invalid object name: ' + objectName);
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        Set<String> requiredFields = new Set<String>();
        Set<String> optionalFields = new Set<String>();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();

            // Skip non-createable, system, auto fields
            if (!fieldDescribe.isCreateable()) continue;
            if (fieldDescribe.isAutoNumber() || fieldDescribe.isCalculated() || fieldDescribe.isDefaultedOnCreate()) continue;
            if (fieldName.endsWithIgnoreCase('Id') &&
                !(fieldName.equalsIgnoreCase('accountId') || fieldName.equalsIgnoreCase('contactId'))) {
                continue;
            }

            if (!fieldDescribe.isNillable()) {
                requiredFields.add(fieldName);
            } else {
                optionalFields.add(fieldName);
            }
        }

        // Remove required fields from optionalFields
        optionalFields.removeAll(requiredFields);

        return new Map<String, Object>{
            'requiredFields' => new List<String>(requiredFields),
            'optionalFields' => new List<String>(optionalFields)
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getRecordTypesForObject(String objectApiName) {
        List<Map<String, String>> recordTypeList = new List<Map<String, String>>();

        // Check if object has record types
        DescribeSObjectResult describeResult = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        Map<Id, Schema.RecordTypeInfo> recordTypeInfos = describeResult.getRecordTypeInfosById();

        for (Schema.RecordTypeInfo rtInfo : describeResult.getRecordTypeInfos()) {
            if (rtInfo.isAvailable()) {
                // Optional: skip master if you want
                if (rtInfo.getName().equalsIgnoreCase('Master')) {
                    continue; // skip Master record type
                }
   
                recordTypeList.add(new Map<String, String>{
                    'label' => rtInfo.getName(),
                    'value' => rtInfo.getRecordTypeId()
                });
            }
        }
        System.debug('recordTypeList --> '+recordTypeList);
        return recordTypeList;
    }

    @AuraEnabled
    public static String callPromptBuilder(String objectApiName, Integer numberOfRecords, List<String> fieldApiNames){

        try {
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
            Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();

            String promptInput = 'Generate strictly '+numberOfRecords+' Salesforce '+objectApiName+' records. Each record should only include the following fields:\n';
            for(String fieldName : fieldApiNames){
                String fieldLine = '- ' + fieldName;
                if (fieldMap.containsKey(fieldName)) {
                    Schema.DescribeFieldResult describeResult = fieldMap.get(fieldName).getDescribe();
                    if (describeResult.getType() == Schema.DisplayType.Picklist) {
                        List<Schema.PicklistEntry> pickVals = describeResult.getPicklistValues();
                        List<String> validValues = new List<String>();
                        for (Schema.PicklistEntry entry : pickVals) {
                            if (!entry.isActive()) continue;
                            validValues.add(entry.getLabel());
                        }
                        if (!validValues.isEmpty()) {
                            fieldLine += ' (Valid values are ' + String.join(validValues, ', ') + ')';
                        }
                    }
                }
                promptInput += fieldLine + ',\n';
            }

            Integer lastCommaIndex = promptInput.lastIndexOf(',');
            promptInput = promptInput.substring(0, lastCommaIndex) + promptInput.substring(lastCommaIndex + 1);

            promptInput += '\n Output in a list of json format. Do not create nested json';

            System.debug('promptInput -->'+promptInput);
            return promptInput;
           
        } catch(Exception e) {
            System.debug(e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }


    @AuraEnabled
    public static string createTestData(String promptInput, String objectApiName, List<String> fieldApiNames, String recordTypeId){
        try {

            Boolean createParentAccount = false;
            Boolean createParentContact = false;
            Account acc;
            Contact con;
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
            System.debug('objectApiName --> '+objectApiName);
            System.debug('sObjType is null? --? '+(sObjType == null));
            Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
           
            for(String fieldName : fieldApiNames){
                if(fieldName.equalsIgnoreCase('accountId')) {
                    createParentAccount = true;
                    acc = new Account(Name=objectApiName+' Test Account');
                    // accountToInsert.add(acc);
                    continue;
                }
                if(fieldName.equalsIgnoreCase('contactId')){
                    createParentContact = true;
                    con = new Contact(LastName=objectApiName+' Test Contact');
                    // contactToInsert.add(con);
                    continue;
                }
            }
           
            ConnectApi.WrappedValue objPromptValue = new ConnectApi.WrappedValue();
            objPromptValue.value = promptInput;
            Map <String, ConnectApi.WrappedValue > inputParamsMap = new Map <String, ConnectApi.WrappedValue >();
            inputParamsMap.put('Input:PromptText', objPromptValue);

            ConnectApi.EinsteinPromptTemplateGenerationsInput executeTemplateInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            executeTemplateInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            executeTemplateInput.additionalConfig.applicationName = 'PromptBuilderPreview';
            executeTemplateInput.isPreview = false;
            executeTemplateInput.inputParams = inputParamsMap;

           
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                PROMPT_TEMPLATE_API_NAME,
                executeTemplateInput
            );


            //System.debug('Full response: ' + JSON.serializePretty(generationsOutput));
            ConnectApi.EinsteinLLMGenerationItemOutput response = generationsOutput.generations[0];
           

            String strResponse = response.text;
            System.debug('Response is ' + strResponse );
               
            Integer startIndex = strResponse.indexOf('[');
            Integer endIndex = strResponse.lastIndexOf(']');
            String jsonString = '';
            if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
                jsonString = strResponse.substring(startIndex, endIndex + 1);
            }else{
                return 'invalid response received from the prompt builder';
            }
           
            System.debug('jsonString --> '+jsonString);
            if (sObjType == null) {
                return 'Error: Invalid object name - ' + objectApiName;
            }

            List<SObject> recordsToInsert = new List<SObject>();

            List<Object> rawRecords = (List<Object>) JSON.deserializeUntyped(jsonString);
            for(Object rawRecord : rawRecords){
                Map<String, Object> recordMap = (Map<String, Object>) rawRecord;
                SObject record = sObjType.newSObject();
                record.put('Test_Record__c',true);
                if(recordTypeId != null && String.isNotBlank(recordTypeId)){
                    record.put('RecordTypeId',recordTypeId);
                }

                for(String fieldApiName : recordMap.keySet()){
                    System.debug(fieldApiName + ': ' + recordMap.get(fieldApiName));

                    if (fieldMap.containsKey(fieldApiName)) {
                        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
                        Object value = recordMap.get(fieldApiName);

                        if (value == null) {
                            record.put(fieldApiName, null);
                            continue;
                        }

                        // Convert String to appropriate type based on field type
                        if (fieldDescribe.getType() == Schema.DisplayType.Date && value instanceof String) {
                            record.put(fieldApiName, Date.valueOf((String)value));
                        } else if (fieldDescribe.getType() == Schema.DisplayType.Datetime && value instanceof String) {
                            record.put(fieldApiName, Datetime.valueOf((String)value));
                        } else if (fieldDescribe.getType() == Schema.DisplayType.Boolean && value instanceof String) {
                            record.put(fieldApiName, ((String)value).toLowerCase() == 'true');
                        } else if ((fieldDescribe.getType() == Schema.DisplayType.Currency ||
                                    fieldDescribe.getType() == Schema.DisplayType.Double ||
                                    fieldDescribe.getType() == Schema.DisplayType.Percent) && value instanceof String) {
                            record.put(fieldApiName, Decimal.valueOf((String)value));
                        } else if ((fieldDescribe.getType() == Schema.DisplayType.Integer) && value instanceof String) {
                            record.put(fieldApiName, Integer.valueOf((String)value));
                        } else if ((fieldDescribe.getType() == Schema.DisplayType.String ||
                                    fieldDescribe.getType() == Schema.DisplayType.TextArea) && !(value instanceof String)) {
                            record.put(fieldApiName, String.valueOf(value));
                        } else {
                            // Default fallback, use as-is
                            record.put(fieldApiName, value);
                        }
                    }
                }
                recordsToInsert.add(record);
            }

            if(createParentAccount){
                insert acc;
                System.debug('Account created successfully with ID:'+acc.Id);
                for(SObject record : recordsToInsert){
                    record.put('accountId', acc.Id);
                }
            }

            if(createParentContact){
                if(createParentAccount){
                    con.AccountId = acc.Id;
                }
                insert con;
                System.debug('Contact created successfully with ID:'+con.Id);
                for(SObject record : recordsToInsert){
                    record.put('contactId', con.Id);
                }
            }

            insert recordsToInsert;
            return 'success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
