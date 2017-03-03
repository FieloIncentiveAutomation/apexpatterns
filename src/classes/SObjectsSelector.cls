public with sharing class SObjectsSelector {

	public List<SObject> queryRecords(Set<Id> recordIds, Map<String,Set<String>> fieldsMap, String objectName, Set<String> defaultFields){
        Set<String> setFields = new Set<String>{'Id','Name'};
        if(defaultFields != null){
            setFields.addAll(defaultFields);
        }

        if(fieldsMap != null && fieldsMap.containsKey(objectName) && !fieldsMap.get(objectName).isEmpty()){
            setFields.addAll(fieldsMap.get(objectName));
            fieldsMap.remove(objectName);
        }


        String query = 'SELECT ' + String.join(new List<String>(setFields),',');

        if(fieldsMap != null){
            for(String type : fieldsMap.keySet()){
                fieldsMap.get(type).add('Name');
                query += ', (SELECT ' + String.join(new List<String>(fieldsMap.get(type)),',') + ' FROM ' + type + ')';
            }
        }

        query += ' FROM ' + objectName + ' WHERE Id in : recordIds';

        return Database.query(query);
    }

}