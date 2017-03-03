/**
 * @brief      API para procesamiento de
 * @ingroup Redemption
 * \~Spanish
 * @details    La API contiene metodos estaticos para realizar pedidos de datos sobre Redemptions y Redemption Items
 */
global with sharing class SObjectService {

    /**
     * @brief       habilita para modificar campos sensibles de una transaccion
     * @details     Luego de llamar el metodo se puede realizar un dml sobre una transaccion pudiendo modificar cualquier campo
     * @version     10.0
     * @param       value           Valor para habilitar y desahibilitar la edicion
     * @returns     Void
     * @test
     * @code
     *          FieloEE.validateAdminFieldsTransaction(false);
     *          FieloEE__Transaction__c transaction = [SELECT Id, FieloEE__Processed__c FROM FieloEE__Transaction__c LIMIT 1];
     *          transaction.FieloEE__Processed__c = false;
     *          update transaction;
     * @endcode
     */
    global static void enableAdminPermission(Boolean value){
        Members.validateAdminFields = !value;
        Transactions.validateAdminFields = !value;
        Points.validateAdminFields = !value;
        Redemptions.validateAdminFields = !value;
        RedemptionItems.validateAdminFields = !value;
        Programs.validateAdminFields = !value;
        Challenges.validateAdminFields = !value;
        Promotions.validateAdminFields = !value;
        Actions.validateAdminFields = !value;
        RuleTriggers.validateAdminFields = !value;
        Rewards.validateAdminFields = !value;
    }

    public static void sortList(List<Sobject> items, String sortField, String order){

        List<Sobject> resultList = new List<Sobject>();

        //Create a map that can be used for sorting
        Map<object, List<Sobject>> objectMap = new Map<object, List<Sobject>>();

        for(Sobject ob : items){
            if(objectMap.get(ob.get(sortField)) == null){  // For non Sobject use obj.ProperyName
                objectMap.put(ob.get(sortField), new List<Sobject>());
            }
            objectMap.get(ob.get(sortField)).add(ob);
        }
        //Sort the keys
        List<object> keys = new List<object>(objectMap.keySet());
        keys.sort();

        for(object key : keys){
            resultList.addAll(objectMap.get(key));
        }

        //Apply the sorted values to the source list
        items.clear();
        if(order.toLowerCase() == 'asc'){
            items.addAll(resultList);
        }else if(order.toLowerCase() == 'desc'){
            for(integer i = resultList.size()-1; i >= 0; i--){
                items.add(resultList[i]);
            }
        }
    }


    public static Boolean applyCriteria(List<sObject> criterias, sObject record, String logicalExpression){
        if(criterias.isEmpty())
            return true;

        if(criterias != null && criterias.size() > 0){
            Schema.DescribeSObjectResult objectDescribe  = criterias[0].getSObjectType().getDescribe();
        }

        if(String.isNotBlank(logicalExpression)){
            Map<String,sObject> criteriasMap = new Map<String,sObject>();
            for(sObject c : criterias){
                criteriasMap.put(String.valueOf(((Decimal)c.get('FieloPLT__Order__c')).intValue()), c);
            }

            return processCriterias(logicalExpression, criteriasMap, record);
        }else{
            //AND MODE
            for(sObject c : criterias){
                Boolean result;
                if(c.getSObjectType() == Criterion__c.SObjectType){
                    result = applyCriterion(c, record);
                }else if(c.getSObjectType() == CriterionGroup__c.SObjectType){
                    result = applyMDCriterion((CriterionGroup__c)c, record);
                }

                if(!result)
                    return false;
            }

            return true;
        }
    }

    public static Boolean applyMDCriterion(CriterionGroup__c critGroup, sObject record){
        Decimal value = 0;
        if(critGroup.Mode__c == 'COUNT'){
            for(SObject childRecord : record.getSObjects(critGroup.RelatedList__c)){
                if(applyCriteria(critGroup.Criteria__r, childRecord, critGroup.LogicalExpression__c)){
                    value++;
                }

                if(critGroup.Operator__c == 'greater or equal' && value >= critGroup.Value__c){
                    return true;
                }
            }
        }else if(critGroup.Mode__c == 'SUM'){
            for(SObject childRecord : record.getSObjects(critGroup.RelatedList__c)){
                if(applyCriteria(critGroup.Criteria__r, childRecord, critGroup.LogicalExpression__c)){
                    value += Double.valueOf(childRecord.get(critGroup.Field__c));
                }

                if(critGroup.Operator__c == 'greater or equal' && value >= critGroup.Value__c){
                    return true;
                }
            }
        }
        if(critGroup.Operator__c == 'equals' && value == critGroup.Value__c){
            return true;
        }
        return false;
    }

    public static Boolean applyCriterion(sObject c, sObject record){
        String[] fieldNameSplited = String.valueOf(c.get('FieldName__c')).split('\\.');
        Object valueObject = null;

        SObject relationObject = record;
        Integer index = 0;
        for(; index < fieldNameSplited.size() - 1; index++){
            relationObject = relationObject.getSObject(fieldNameSplited[index].removeEnd('Id'));
            if(relationObject == null)
                return false;
        }

        valueObject = relationObject.get(fieldNameSplited[index]);

        if( c.get('FieldType__c') == 'Date' ){
            Date fieldValue = null;

            if(valueObject != null){
                try{
                    fieldValue = DateTime.valueOf( valueObject ).date();
                }catch(Exception e){
                    fieldValue = Date.valueOf(valueObject);
                }
            }

            Date value = Date.valueOf(c.get('DateValue__c'));
            if ( (c.get('Operator__c') == 'equals' &&  fieldValue != value) || (fieldValue == null || (c.get('Operator__c') == 'not equals' &&  fieldValue == value) || (c.get('Operator__c') == 'greater or equal' &&  fieldValue < value) || (c.get('Operator__c') == 'less or equal' &&  fieldValue > value) || (c.get('Operator__c') == 'greater than' &&  fieldValue <= value) || (c.get('Operator__c') == 'less than' &&  fieldValue >= value) ) )
                return false;

        } else if ( c.get('FieldType__c') == 'Number' ) {
            Double fieldValue = null;
            if( valueObject != null ){
                fieldValue = Double.valueOf( valueObject );
            }

            Double value = null;
            if( c.get('NumberValue__c') != null ){
                value = Double.valueOf( c.get('NumberValue__c') );
            }

            //Caso Nulos
            if(fieldValue == null || value == null){
                if( (c.get('Operator__c') == 'equals' && fieldValue != value) || (c.get('Operator__c') == 'not equals' && fieldValue == value) || (c.get('Operator__c') == 'greater or equal' || c.get('Operator__c') == 'less or equal' || c.get('Operator__c') == 'greater than' || c.get('Operator__c') == 'less than') ) {
                    return false;
                }
            }

            if ( (c.get('Operator__c') == 'equals' &&  fieldValue != value) || (c.get('Operator__c') == 'not equals' &&  fieldValue == value) || (c.get('Operator__c') == 'greater or equal' &&  fieldValue < value) || (c.get('Operator__c') == 'less or equal' &&  fieldValue > value) || (c.get('Operator__c') == 'greater than' &&  fieldValue <= value) || (c.get('Operator__c') == 'less than' &&  fieldValue >= value) )
                return false;

        } else if ( c.get('FieldType__c') == 'Boolean' ) {
            if(valueObject == null){
                return false;
            }
            Boolean fieldValue = Boolean.valueOf( valueObject );
            Boolean value = Boolean.valueOf(c.get('BooleanValue__c'));
            if ( (c.get('Operator__c') == 'equals' &&  fieldValue != value) || (c.get('Operator__c') == 'not equals' &&  fieldValue == value)  )
                return false;
        } else {
            //Por default Text, List o Reference
            //if(c.get('FieldType__c') == 'Text' || c.get('FieldType__c') == 'List' || c.get('FieldType__c') == 'REFERENCE') {

            String fieldValue = '';
            if(valueObject != null){
                fieldValue = String.valueOf( valueObject );
            }
            String value;

            Boolean containsField; try{c.get('Field__c'); containsField = true;}catch(Exception e){containsField = false;}
            if(containsField && Boolean.valueOf(c.get('Field__c'))){
                value = (String)record.get(String.valueOf(c.get('Values__c')));
            }else{
                value = String.valueOf(c.get('Values__c'));
            }

            if(fieldValue == null) fieldValue = '';
            if(value == null) value = '';

            List<String> valor = value.split(',');
            Boolean aux = true;
            for(String val : valor){
                if(val.startsWith(' ')){
                    val = val.replaceFirst(' ','');
                }

                if ( (c.get('Operator__c') == 'equals' &&  (fieldValue != val) ) || (c.get('Operator__c') == 'greater or equal' &&  (fieldValue < val) ) || (c.get('Operator__c') == 'less or equal' &&  (fieldValue > val) ) || (c.get('Operator__c') == 'greater than' &&  (fieldValue <= val) ) || (c.get('Operator__c') == 'less than' &&  (fieldValue >= val) ) || (c.get('Operator__c') == 'contains' && (!fieldValue.contains(val)) )
                || (c.get('Operator__c') == 'not equals' &&  fieldValue == val) || (c.get('Operator__c') == 'not contains' && fieldValue.contains(val))){
                    aux = false;
                }else{
                    aux = true;
                    break;
                }

                if(c.get('FieldType__c') == 'REFERENCE'){//esto está para comparar Id's y que sean los dos de 15, ya que si uno es de 15 y el otro de 18 va a parecer que son distintos cuando en realidad son lo mismo
                    aux = fieldValue.substring(0 ,15) == val.substring(0, 15);
                }

            }
            if(aux == false){
                return false;
            }
        }

        return true;
    }

    public static Boolean validateFormula(String operation){
        String upOperation = operation.toUpperCase();
        List<String> resultList = upOperation.split('[^0-9]+');
        resultList.remove(0);
        List<Integer> sortList = new List<Integer>();
        for(String s : resultList){
            sortList.add(Integer.valueOf(s));
        }
        sortList.sort();
        for(Integer i = (sortList.size()-1); i >= 0; i--) {
            upOperation = upOperation.replace(String.valueOf(sortList.get(i)), 'true');
        }
        return validateConditional(upOperation);
    }

    private static boolean validateConditional(String conditional){

        if(conditional.trim() == 'true' || conditional.trim() == 'false'){
            return conditional.trim() == 'true';
        }

        //first check for wrong simple format
        Pattern mySingleFormatPattern = Pattern.compile('^(true|false) (AND|OR) (true|false)$');
        Matcher mySingleFormatMatcher = mySingleFormatPattern.matcher(conditional);
        boolean singleFormatResult = mySingleFormatMatcher.find();
        if(!conditional.contains('(') && !singleFormatResult){
            return false;
        }

        while(conditional.contains('(')){
            Pattern myPattern = Pattern.compile('\\([^\\(]*?\\)');
            Matcher myMatcher = myPattern.matcher(conditional);
            myMatcher.find();
            conditional = conditional.replaceFirst('\\([^\\(]*?\\)', dynamicConditionals(myMatcher.group()));
        }
        String resultadoFinalString = dynamicConditionals(conditional);
        return resultadoFinalString == 'true';
    }

    private static String dynamicConditionals(String operation){

        //take out parenthesis
        operation = operation.replace('(', '').replace(')', '');

        //if the expression has only one operator
        if(operation.trim() == 'true' || operation.trim() == 'false'){
            return operation.trim();
        }

        //wrong format
        Pattern mySingleFormatPattern = Pattern.compile('^(true|false) (AND|OR) (true|false)$');
        Matcher mySingleFormatMatcher = mySingleFormatPattern.matcher(operation);
        boolean singleFormatResult = mySingleFormatMatcher.find();
        if(!singleFormatResult){
            return 'false';
        }

        List<string> operators = operation.split (' ');
        if(operators[1] == 'AND'){
            if(operators[0] == 'true' && operators[2] == 'true'){
                return 'true';
            }
        }else if(operators[1] == 'OR'){
            if (operators[0] == 'true' || operators[2] == 'true'){
                return 'true';
            }
        }
        return 'false';
    }

    public static Boolean processCriterias(String condition, Map<String,sObject> criteriasMap, sObject record){

        //separate the values into a list
        String conditionString = condition.replace(' ','');
        List<String> resultList = conditionString.split('[^0-9]+');
        resultList.remove(0);

        List<Integer> sortList = new List<Integer>();
        for(String s : resultList){
            sortList.add(Integer.valueOf(s));
        }
        sortList.sort();

        //process each of the criterias and put them in a map
        Map<String,String> criteriasResult = new Map<String,String>();
        for(Integer i = (sortList.size()-1); i >= 0; i--) {
            if(!criteriasResult.containsKey( String.valueOf(sortList.get(i)) )){
                //TODO: funcionalidad MD
                SObject crit = criteriasMap.get(String.valueOf(sortList.get(i)));
                if(crit.getSObjectType() == Criterion__c.SObjectType){
                    criteriasResult.put(String.valueOf(sortList.get(i)), String.valueOf(applyCriterion(criteriasMap.get(String.valueOf(sortList.get(i))), record)));
                }else if(crit.getSObjectType() == CriterionGroup__c.SObjectType){
                    criteriasResult.put(String.valueOf(sortList.get(i)), String.valueOf(applyMDCriterion((CriterionGroup__c)criteriasMap.get(String.valueOf(sortList.get(i))), record)));
                }
            }
        }
        return processResults(criteriasResult, condition);
    }

    public static Boolean processResults(Map<String,String> resultsMap, String condition){
        String upOperation = condition.toUpperCase();
        List<String> resultList = upOperation.split('[^0-9]+');
        if(resultList.size() > 0){
            resultList.remove(0);
        }
        //Si no tiene numeros ni operadores -> ej: ()
        if(resultList.size() == 0 && resultsMap.isEmpty() ){
            return true;
        }

        List<Integer> sortList = new List<Integer>();
        for(String s : resultList){
            sortList.add(Integer.valueOf(s));
        }
        sortList.sort();
        for(Integer i = (sortList.size()-1); i >= 0; i--) {
            upOperation = upOperation.replace(String.valueOf(sortList.get(i)), resultsMap.get(String.valueOf(sortList.get(i))) );
        }

        //process the expression
        return processConditionals(upOperation);
    }

    public static Boolean processConditionals(String condition){
        String conditionString = condition;
        while(conditionString.contains('(')){
            Pattern myPattern = Pattern.compile('\\([^\\(]*?\\)');
            Matcher myMatcher = myPattern.matcher(conditionString);
            myMatcher.find();
            conditionString = conditionString.replaceFirst('\\([^\\(]*?\\)', processOperation(myMatcher.group()));
        }
        String result = processOperation(conditionString);
        return result == 'true';
    }

    public static String processOperation(String operation){
        operation = operation.replace('(', '').replace(')', '');
        //exception when there is only one operator
        if(operation.trim() == 'true' || operation.trim() == 'false'){
            return operation.trim();
        }

        List<string> operators = operation.split(' ');

        if(operators[1] == 'AND'){
            if(operators[0] == 'true' && operators[2] == 'true'){
                return 'true';
            }
        }else if(operators[1] == 'OR'){
            if(operators[0] == 'true' || operators[2] == 'true'){
                return 'true';
            }
        }
        return 'false';
    }

    public static String typeOfFormula(String formula, Integer qCriteria){
        if (String.isBlank(formula)){
            return 'ALL';
        }
        if(formula.contains('OR') && (formula.split('OR').size() == qCriteria)){
            return 'ANY';
        }

        return 'CUSTOM';
    }

    public static String generateFormula(Integer qCriteria, String typeOfFormula){
        return '(' + getLogicalExpresion(qCriteria, typeOfFormula) + ')';
    }

    private static String getLogicalExpresion(Integer qCriteria, String typeOfFormula){
        String concatenator;
        if(typeOfFormula.toUpperCase() == 'ALL'){
            concatenator = ' AND ';
        }
        if(typeOfFormula.toUpperCase() == 'ANY'){
            concatenator = ' OR ';
        }

        String formula = '';
        String aux = '';

        aux = qCriteria + concatenator;
        if(qCriteria > 2){
            formula = aux + '(' + getLogicalExpresion(qCriteria - 1, typeOfFormula) + ')';
        }else if(qCriteria == 2){
            formula = aux + getLogicalExpresion(qCriteria - 1, typeOfFormula);
        }else if(qCriteria == 1){
            formula = aux;
        }
        formula = formula.removeEnd(concatenator);
        return formula;
    }

    public static String getObjectPrefix(String obj){
        return Schema.getGlobalDescribe().get(obj).getDescribe().getKeyPrefix();
    }

    public static String getType(String typeValue){
        if ( typeValue == 'Time' || typeValue == 'DateTime'  ) return 'Date';
        if ( typeValue == 'Double' || typeValue == 'Integer' || typeValue == 'Phone' || typeValue == 'PERCENT' || typeValue == 'Currency' ) return 'Number';
        if ( typeValue == 'anytype' || typeValue == 'String' || typeValue == 'email' || typeValue == 'base64' || typeValue == 'TEXTAREA') return 'Text';
        if ( typeValue == 'PICKLIST' ) return  'List';
        if ( typeValue == 'REFERENCE' ) return  'Reference';
        if ( typeValue == 'BOOLEAN' ) return  'Boolean';
        return typeValue;
    }

    private static String docURL;
    public static String getDocURL(){
            if(docURL == null){
                String instance = PublicSettings__c.getOrgDefaults().Instance__c;
                if(String.isNotBlank(instance)){
                    docURL = '//c.' + instance + '.content.force.com';
                }else{
                    docURL = '';
                }
            }
            return docURL;
    }

    public static void processTransactionRecords(List<Transaction__c> records, Map<Id,Transaction__c> existingRecords){
        SObjectUnitOfWork uow = new SObjectUnitOfWork(new List<Schema.SObjectType>{Transaction__c.SObjectType, Member__c.SObjectType, Point__c.SObjectType, BadgeMember__c.SObjectType,Redemption__c.SObjectType, RedemptionItem__c.SObjectType});
        processTransactionRecords(records, existingRecords, uow);
        Transactions.validateAdminFields = false;
        uow.commitWork();
        SObjectService.enableAdminPermission(true);
    }

    public static void processTransactionRecords(List<Transaction__c> records, Map<Id,Transaction__c> existingRecords, SObjectUnitOfWork uow){
        String objectPrefix = String.valueOf(records[0].Id).subString(0,3);

        Map<Id,Transaction__c> recordsAppliedMap = new Map<Id,Transaction__c>();
        List<Transaction__c> transactionsToProcess = new List<Transaction__c>();
        Set<Id> transactionsWithAction = new Set<Id>();
        Boolean existRulesMasterDetail = false;
        Boolean existRulesCrossFields = false;
        List<CriteriaWrapper> rulesCriteriasList = new List<CriteriaWrapper>();

        for(RuleTrigger__c rt : new RuleTriggersSelector().selectByPrefixWithActions(objectPrefix)){
            if(!rt.Actions__r.isEmpty()){
                //por cada registro
                for(Transaction__c record : records){
                    //Si no tiene criterios o si el ConditionValue = recordField => aplica para procesar
                    String field = rt.ConditionField__c;
                    if( field == null && rt.ConditionValue__c == null ){
                        recordsAppliedMap.put(record.Id, record);
                    } else {
                        if( rt.ConditionType__c == 'Text' ){
                            if( String.valueOf(record.get(field)) == rt.ConditionValue__c && (existingRecords == null || existingRecords.get(record.Id).get(field) != rt.ConditionValue__c)){
                                recordsAppliedMap.put(record.Id, record);
                            }
                        } else {
                            Decimal recordValue = (Decimal)(record.get(field));
                            Decimal conditionValue = Decimal.valueOf(rt.ConditionValue__c);
                            if( recordValue == conditionValue && (existingRecords == null || (Decimal)(existingRecords.get(record.Id).get(field)) != conditionValue)){
                                recordsAppliedMap.put(record.Id, record);
                            }
                        }
                    }
                }

                if(!recordsAppliedMap.isEmpty()){
                    Map<Id,Map<Id,SObject>> recordsByAction = new Map<Id,Map<Id,SObject>>();
                    for(Action__c action : rt.Actions__r){
                        List<String> fieldSplitted = action.TargetMember__c.split('\\.');
                        Boolean crossLevel = fieldSplitted.size() > 1;
                        String recordLookup;
                        String memberLookup;
                        if(crossLevel){
                            recordLookup = fieldSplitted[0].replace('__r','__c');
                            memberLookup = fieldSplitted[1];
                            Set<Id> relatedIds = new Set<Id>();
                            for(Transaction__c t : recordsAppliedMap.values()){
                                if(t.get(recordLookup) != null){
                                    relatedIds.add((Id)t.get(recordLookup));
                                }
                            }
                            recordsByAction.put(action.Id, new Map<Id,SObject>(new SObjectsSelector().queryRecords(relatedIds, null, action.TargetObject__c, new Set<String>{memberLookup})));
                        }

                        Map<String,CriteriaWrapper> criteriasMetaDataMap = (Map<String,CriteriaWrapper>)JSON.deserialize(action.CriteriaFields__c, Map<String,CriteriaWrapper>.class);
                        if(criteriasMetaDataMap.containsKey('rules')){
                            CriteriaWrapper cmd = criteriasMetaDataMap.get('rules');
                            existRulesMasterDetail = existRulesMasterDetail || cmd.isMasterDetail;
                            existRulesCrossFields = existRulesCrossFields || cmd.isCrossField;
                            rulesCriteriasList.add(cmd);
                        }

                        for(Transaction__c tran : recordsAppliedMap.values()){
                            if( !tran.IsOffline__c ){
                                if(!transactionsWithAction.contains(tran.Id) && action.TargetMember__c == 'FieloPLT__Member__c'){
                                    Transaction__c originalTransaction = tran.clone(true);
                                    originalTransaction.action__c = action.Id;

                                    transactionsToProcess.add(originalTransaction);
                                    transactionsWithAction.add(tran.Id);
                                }else{
                                    Transaction__c additionalTransaction = tran.clone(false);
                                    additionalTransaction.action__c = action.Id;
                                    additionalTransaction.SkipEngine__c = true;

                                    if(crossLevel){
                                        if(tran.get(recordLookup) != null && recordsByAction.get(action.Id).get((Id)tran.get(recordLookup)).get(memberLookup) != null){
                                            additionalTransaction.Member__c = (Id)recordsByAction.get(action.Id).get((Id)tran.get(recordLookup)).get(memberLookup);
                                        }
                                    }else{
                                        if(tran.get(action.TargetMember__c) != null){
                                            additionalTransaction.Member__c = (Id)tran.get(action.TargetMember__c);
                                        }
                                    }
                                    additionalTransaction.put(rt.LookupFromTransaction__c, tran.Id);

                                    transactionsToProcess.add(additionalTransaction);
                                }
                            } else {
                                Transaction__c newTransaction = tran.clone(true);
                                newTransaction.action__c = action.Id;
                                uow.registerDirty(newTransaction);
                            }
                        }
                    }
                }
            }
        }

        if(recordsAppliedMap.size() > 1 && existRulesMasterDetail){
            processOffline(transactionsToProcess, uow);
        }else{
            if(existRulesMasterDetail || existRulesCrossFields){
                //recordsAppliedMap = new Map<Id,Transaction__c>((List<Transaction__c>)new SObjectsSelector().queryRecords(recordsAppliedMap.keySet(), getFieldsMap(actionsApplied), 'Transaction__c', new Set<String>{'Name'}));
                recordsAppliedMap = new Map<Id,Transaction__c>((List<Transaction__c>)new SObjectsSelector().queryRecords(recordsAppliedMap.keySet(), getFieldsMap(rulesCriteriasList), 'Transaction__c', new Set<String>{'Name'}));
            }
            processTransactions(transactionsToProcess, recordsAppliedMap, true, uow);
        }
    }

    /**
     * @details     Dado un set de Ids de registros que ya fueron procesados por el MultiObjectEngine revierte las acciones realizadas
     * @version     10.0
     * @param       recordIds    recordIds de los registros a revertir
     * @returns     Mapa con los Id's de registros que hayan fallado, y sus correspondientes errores asociados
     * @retval      Map<Id,String>
     *                      <ul>
     *                         <li> null = Operacion exitosa
     *                         <li> Map<Id,String> = Mapa que contiene solo los Id's de contactos con error
     *                      </ul>
     * @warning     Los ids del set deben ser todos del mismo objeto
     * @test
     * @code {.java}
     *         Set<Id> eventIds = new Set<Id>();
     *         for(FieloEE__Event__c event : [SELECT Id FROM FieloEE__Event__c LIMIT 10]){
     *              eventIds.add(event.Id);
     *         }
     *         FieloEE__Program__c program = FieloEE.ProgramService.getDefaultProgram();
     *
     *         Map<Id,String> resultsMap = FieloEE.SObjectService.revertRecords(eventIds);
     *         if(resultsMap != null){
     *             for(Id recordId : resultsMap.keySet()){
     *                 ApexPages.addMessage(new ApexPages.Message(severity.ERROR, resultsMap.get(recordId)));
     *             }
     *         }
     * @endcode
     */
    global static Map<Id,String> revertRecords(Set<Id> recordIds){
        Map<Id,String> results = new Map<Id,String>();
        //Busca el RuleTrigger relacionado al objeto a revertir para obtener los Fields necesarios para evaluar el RuleTrigger
        String objectPrefix = String.valueOf(new List<Id>(recordIds)[0]).subString(0,3);
        Map<Id,RuleTrigger__c> ruleTriggersMap = new Map<Id,RuleTrigger__c>(new RuleTriggersSelector().selectByPrefixWithActions(objectPrefix));
        Set<String> fields = new Set<String>();
        for(RuleTrigger__c rt : ruleTriggersMap.values()){
            fields.add(rt.ConditionField__c);
        }
        List<SObject> records = new SObjectsSelector().queryRecords(recordIds, null, ruleTriggersMap.values()[0].Object__c, fields);

        //Evalua los RulesTriggers para cada registro a revertir para armar las colecciones
        Set<Id> idsToRevert = new Set<Id>();
        Set<String> lookupFromTransactionFields = new Set<String>();
        Set<String> lookupFromTrackerFields = new Set<String>();
        Map<Id,Set<Id>> recordIdsByRT = new Map<Id,Set<Id>>();
        for(RuleTrigger__c rt : ruleTriggersMap.values()){
            Set<Id> appliedRecordIds = new Set<Id>();
            for(SObject record : records){
                if(record.get(rt.ConditionField__c) == rt.ConditionValue__c){
                    appliedRecordIds.add(record.Id);
                }
            }

            if(!appliedRecordIds.isEmpty()){
                idsToRevert.addAll(appliedRecordIds);
                recordIdsByRT.put(rt.Id, appliedRecordIds);
                lookupFromTransactionFields.add(rt.LookupFromTransaction__c);
                lookupFromTrackerFields.add(rt.LookupFromTracker__c);
            }
        }

        if(!idsToRevert.isEmpty()){
            //Busca las Transacciones que todavia no fueron revertidas, relacionadas al registro a revertir y al RuleTrigger que aplico
            List<Transaction__c> trans = new TransactionsSelector(new Set<String>{'Action__r.RuleTrigger__c'}).selectByRuleTriggerAndRecord(recordIdsByRT.keySet(), idsToRevert, lookupFromTransactionFields);
            List<Tracker__c> trackers = new TrackersSelector(new Set<String>{'Action__r.RuleTrigger__c'}).selectByRuleTriggerAndRecord(recordIdsByRT.keySet(), idsToRevert, lookupFromTrackerFields);
            List<Id> transactionIds = new List<Id>();
            Set<Id> trackerIds = new Set<Id>();
            //TODO: Ver cuando puede pasar esto!
            if(idsToRevert.size() > 1 && recordIdsByRT.size() > 1){
                for(Transaction__c t : trans){
                    RuleTrigger__c rt = ruleTriggersMap.get(t.Action__r.RuleTrigger__c);
                    //
                    if(recordIdsByRT.get(rt.Id).contains( (Id)t.get(rt.LookupFromTransaction__c) )){
                        transactionIds.add(t.Id);
                    }
                }

                //
            }else{
                for(Transaction__c t : trans){
                    transactionIds.add(t.Id);
                }

                //
                for(Tracker__c t : trackers){
                    trackerIds.add(t.Id);
                }
            }
            if(!transactionIds.isEmpty()){
                Map<Id, String> aux = TransactionService.revertTransactions(transactionIds);

                if( aux != null )
                    results.putAll( aux );
            }

            if(!trackerIds.isEmpty()){
                Map<Id, String> aux = TrackerService.revertTrackers(trackerIds, idsToRevert, ruleTriggersMap);

                if( aux != null )
                    results.putAll( aux );
            }
        }
        return results;
    }

    public static void processEngine(List<SObject> records, Map<Id,SObject> existingRecords, SObjectUnitOfWork uow, Set<Id> memberIds){

        Boolean isSimulation = false;
        String objectPrefix = '';
        Map<Id,SObject> recordsMap = new Map<Id,SObject>();
        //Si no es simulacion entonces tengo Id de registros por q es AfterInsert
        if( records[0].Id != null ){
            objectPrefix = String.valueOf(records[0].Id).subString(0,3);
            recordsMap.putAll(records);
        } else {
            isSimulation = true;
            objectPrefix = records.get(0).getSobjectType().getDescribe().getKeyPrefix();
            //Si no tienen Id => les asigno autonumerico
            Integer s_num = 1;
            for(SObject s : records){
                String result = String.valueOf(s_num++);
                String fakeId = objectPrefix + '0'.repeat( 12 - result.length() ) + result;
                s.put('Id', fakeId);
            }
            recordsMap.putAll(records);
        }

        //Obtengo los RuleTriggers
        List<RuleTrigger__c> ruleTriggers = new RuleTriggersSelector().selectByPrefixWithActions(objectPrefix);
        Map<Id,Action__c> actionsMap = new Map<Id,Action__c>();
        Map<Id, List<Transaction__c>> transactionsByRecordId = new Map<Id,List<Transaction__c>>();
        Map<Id, List<Tracker__c>> trackersByRecordId = new Map<Id, List<Tracker__c>>();

        //Verifica que el registro cumpla con los criterios de filtro del Rule Trigger
        for(RuleTrigger__c rt : ruleTriggers){
            if(!rt.Actions__r.isEmpty()){
                List<SObject> recordsApplied = new List<SObject>();
                for(SObject record : records){
                    //Si no tiene criterios o si el ConditionValue = recordField => aplica para procesar
                    String field = rt.ConditionField__c;
                    if( field == null && rt.ConditionValue__c == null ){
                        recordsApplied.add(record);
                    } else {
                        if( rt.ConditionType__c == 'Text' ){
                            if( String.valueOf(record.get(field)) == rt.ConditionValue__c && (existingRecords == null || existingRecords.get(record.Id).get(field) != rt.ConditionValue__c)){
                                recordsApplied.add(record);
                            }
                        } else {
                            Decimal recordValue = (Decimal)(record.get(field));
                            Decimal conditionValue = Decimal.valueOf(rt.ConditionValue__c);
                            if( recordValue == conditionValue && (existingRecords == null || (Decimal)(existingRecords.get(record.Id).get(field)) != conditionValue)){
                                recordsApplied.add(record);
                            }
                        }
                    }
                }

                if(!recordsApplied.isEmpty()){
                    // Si tiene actions de SAMO entonces crea mapa de record -> lista de transactions

                    // TODO: Que no haga el putAll (merge)
                    Map<Id,List<Transaction__c>> transByRecordsApplied = createTransactionsMap(rt, recordsApplied);//este método hace un query y está adentro de un ciclo, ver de cambiarlo
                    transactionsByRecordId.putAll(transByRecordsApplied);
                    actionsMap.putAll(rt.Actions__r);

                    if( !isSimulation ){
                        Map<Id, List<Tracker__c>> trackerByRecordsApplied;
                        if(rt.LookupFromTracker__c != null){
                            trackerByRecordsApplied = createTrackersMap(rt, recordsApplied);
                            trackersByRecordId.putAll(trackerByRecordsApplied);
                        }
                    }
                }
            }
        }

        // TODO: OR hay registros MAMO
        if( !transactionsByRecordId.isEmpty() || !trackersByRecordId.isEmpty() ){
            //Si tiene Members entonces "limpio" el listado de transacciones
            if( !memberIds.isEmpty() ){
                for(List<Transaction__c> transactions : transactionsByRecordId.values()){
                    for (Integer i = 0; i < transactions.size(); i++) {
                        //Si la transaccion no pertenece a los members a evaluar la elimino
                        if( !memberIds.contains( transactions.get(i).Member__c ) ){
                            transactions.remove(i);
                        }
                    }
                }

                for(List<Tracker__c> trackers : trackersByRecordId.values()){
                    for (Integer i = 0; i < trackers.size(); i++) {
                        //Si la transaccion no pertenece a los members a evaluar la elimino
                        if( !memberIds.contains( trackers.get(i).Member__c) ){
                            trackers.remove(i);
                        }
                    }
                }
            } else {
                //Sino obtengo los Id de members para membersMapActivos
                for(List<Transaction__c> transactions : transactionsByRecordId.values()){
                    for(Transaction__c t : transactions){
                        memberIds.add(t.Member__c);
                    }
                }

                //Sino obtengo los Id de members para membersMapActivos
                for(List<Tracker__c> trackers : trackersByRecordId.values()){
                    for(Tracker__c t : trackers){
                        memberIds.add(t.Member__c);
                    }
                }
            }

            List<Transaction__c> onlineTransactions = new List<Transaction__c>();
            List<Tracker__c> onlineTrackers = new List<Tracker__c>();
            Map<Id,Member__c> membersMap = new Map<Id,Member__c>(new MembersSelector(new Set<String>{'FieloPLT__Program__r.FieloPLT__OnlineTransactionProcessing__c'}).selectActiveById(memberIds));
            Map<Id,Action__c> actionsToEvaluateMap = new Map<Id,Action__c>();
            Map<Id,SObject> recordsToProcessRulesMap = new Map<Id,SObject>();
            Map<Id,SObject> recordsToProcessMissionMap = new Map<Id,SObject>();

            for(Id recordId : transactionsByRecordId.keySet()){
                Integer transactionsDeleted = 0;
                for(Transaction__c t : transactionsByRecordId.get(recordId)){
                    //Si el Member esta Active
                    if( membersMap.containsKey(t.Member__c) ){
                        // Analizar evaluacion Offline
                        if( !membersMap.get(t.Member__c).Program__r.OnlineTransactionProcessing__c ){
                            t.IsOffline__c = true;
                            uow.registerNew(t);
                            transactionsDeleted++;
                        }else{
                            onlineTransactions.add(t);
                            actionsToEvaluateMap.put(t.Action__c,actionsMap.get(t.Action__c));
                        }
                    }
                }

                //si todas las transactions del record van offline entonces el record no procesa
                if(transactionsDeleted != transactionsByRecordId.get(recordId).size()){
                    recordsToProcessRulesMap.put(recordId, recordsMap.get(recordId));
                }
            }

            for(Id recordId : trackersByRecordId.keySet()){
                Integer trackersDeleted = 0;
                for(Tracker__c t : trackersByRecordId.get(recordId)){
                    if( membersMap.containsKey(t.Member__c) ){
                        //Analizar evaluacion Offline
                        if(!membersMap.get(t.Member__c).Program__r.OnlineTransactionProcessing__c){
                            t.IsOffline__c = true;
                            uow.registerNew(t);
                            trackersDeleted++;
                        }else{
                            onlineTrackers.add(t);
                            actionsToEvaluateMap.put(t.Action__c,actionsMap.get(t.Action__c));
                        }
                    }
                }

                //si todos los trackers del record van offline entonces el record no procesa
                if(trackersDeleted != trackersByRecordId.get(recordId).size()){
                    recordsToProcessMissionMap.put(recordId, recordsMap.get(recordId));
                }
            }

            Boolean existRulesMasterDetail = false;
            Boolean existRulesCrossFields = false;
            List<CriteriaWrapper> rulesCriteriasList = new List<CriteriaWrapper>();

            Boolean existMissionsMasterDetail = false;
            Boolean existMissionsCrossFields = false;
            List<CriteriaWrapper> missionsCriteriasList = new List<CriteriaWrapper>();

            for(Action__c action : actionsToEvaluateMap.values()){
                Map<String,CriteriaWrapper> criteriasMetaDataMap = (Map<String,CriteriaWrapper>)JSON.deserialize(action.CriteriaFields__c, Map<String,CriteriaWrapper>.class);

                if(criteriasMetaDataMap.containsKey('rules')){
                    CriteriaWrapper cmd = criteriasMetaDataMap.get('rules');
                    existRulesMasterDetail = existRulesMasterDetail || cmd.isMasterDetail;
                    existRulesCrossFields = existRulesCrossFields || cmd.isCrossField;
                    rulesCriteriasList.add(cmd);
                }

                if(criteriasMetaDataMap.containsKey('missions')){
                    CriteriaWrapper cmd = criteriasMetaDataMap.get('missions');
                    existMissionsMasterDetail = existMissionsMasterDetail || cmd.isMasterDetail;
                    existMissionsCrossFields = existMissionsCrossFields || cmd.isCrossField;
                    missionsCriteriasList.add(cmd);
                }
            }

            if(recordsToProcessRulesMap.size() > 0){
                //En la simulacion los registros padres con los hijos vienen relacionados en memoria.
                if( !isSimulation ){
                    if(existRulesMasterDetail || existRulesCrossFields){
                        recordsToProcessRulesMap = new Map<Id,SObject>(new SObjectsSelector().queryRecords(recordsToProcessRulesMap.keySet(), getFieldsMap(rulesCriteriasList), ruleTriggers[0].Object__c, new Set<String>{'Name'}));
                    }
                }
                if(onlineTransactions.size() > 0){
                    processTransactions(onlineTransactions, recordsToProcessRulesMap, true, uow);
                }
            }

            if(recordsToProcessMissionMap.size() > 0){
                Integer cpuTime = SObjectService.getCpuTime();
                if(cpuTime != null && Limits.getLimitCpuTime() - Limits.getCpuTime() <= cpuTime){
                    processOffline(onlineTrackers, uow);
                }else{
                    //TODO analizar si vale la pena que el Json de criteriaFields__c en action haga separacion por rules y missions para no queriar related lists al pedo
                    //TODO en ese caso variable isMasterDetail y useCrossFields tendrian que estar separadas por transaction y tracker
                    if(existMissionsMasterDetail || existMissionsCrossFields){
                        recordsToProcessMissionMap = new Map<Id,SObject>(new SObjectsSelector().queryRecords(recordsToProcessMissionMap.keySet(), getFieldsMap(missionsCriteriasList), ruleTriggers[0].Object__c, new Set<String>{'Name'}));
                    }
                    if( onlineTrackers.size() > 0){
                        processTrackers(onlineTrackers, recordsToProcessMissionMap, true, uow);
                    }
                }
            }
        }
    }

    global static Map<String, List<Sobject>> simulateProcessRecords(List<SObject> records, Set<Id> memberIds){
        SObjectUnitOfWork uow = new SObjectUnitOfWork(new List<Schema.SObjectType>{Transaction__c.SObjectType, Member__c.SObjectType, Point__c.SObjectType, BadgeMember__c.SObjectType,Redemption__c.SObjectType, RedemptionItem__c.SObjectType, ChallengeMember__c.SObjectType, MissionMember__c.SObjectType, Tracker__c.SObjectType});

        if(memberIds == null)
            memberIds = new Set<Id>();

        //llamo al simulador de procesamiento
        SObjectService.processEngine(records, null, uow, memberIds);

        //Devuelve lista de registros que se van a insertar por el UnitOfWork
        return uow.m_newListByType;
    }

    /**
     * @details     Procesa un set de registros por el multi object engine y asigna puntos en base a la configuracion
     * @version     10.0
     * @param       records             registros a procesar
     * @param       existingRecords     mapa con valores previos a la actualizacion, esta pensado para el mapa de Trigger.old en triggers
     * @returns     Void
     * @warning     Los registros deben estar insertados en la base.
     * @test
     * @code {.java}
     *              trigger Event on Event__c (after insert, after update) {
     *                   SObjectService.processRecords((List<Event__c>) Trigger.new, null);
     *              }
     * @endcode
     */
    global static void processRecords(List<SObject> records, Map<Id,SObject> existingRecords){
        SObjectUnitOfWork uow = new SObjectUnitOfWork(new List<Schema.SObjectType>{Transaction__c.SObjectType, Member__c.SObjectType, Point__c.SObjectType, BadgeMember__c.SObjectType,Redemption__c.SObjectType, RedemptionItem__c.SObjectType, ChallengeMember__c.SObjectType, MissionMember__c.SObjectType, Tracker__c.SObjectType});

        //llamo al procesador
        SObjectService.processEngine(records, existingRecords, uow, new Set<Id>());

        Transactions.validateAdminFields = false;
        try{
            uow.commitWork();
        }catch(Exception e){
            system.debug(e.getMessage());
        }
        SObjectService.enableAdminPermission(true);
    }

    public static List<Transaction__c> createTransactions(RuleTrigger__c rt, List<SObject> records){
        List<Transaction__c> transactions = new List<Transaction__c>();
        for(List<Transaction__c> transactionsFromRecord : createTransactionsMap(rt, records).values()){
            transactions.addAll(transactionsFromRecord);
        }
        return transactions;
    }

    public static Map<Id,List<Transaction__c>> createTransactionsMap(RuleTrigger__c rt, List<SObject> records){
        // TODO: Solo en update
        // Arma un mapa con las transacciones que ya existen (para no crearlas)
        List<Transaction__c> existingTransactions = new TransactionsSelector(new Set<String>{rt.LookupFromTransaction__c, 'Action__c'}).selectByActionAndRecord(rt.Actions__r, records, rt.LookupFromTransaction__c);
        Map<Id,Set<Id>> actionsByRecordId = new Map<Id,Set<Id>>();
        for(Transaction__c t : existingTransactions){
            Id recordId = (Id)t.get(rt.LookupFromTransaction__c);
            if(actionsByRecordId.containsKey(recordId)){
                actionsByRecordId.get(recordId).add(t.Action__c);
            }else{
                actionsByRecordId.put(recordId, new Set<Id>{t.Action__c});
            }
        }

        // En caso de haber cross members los querea
        Map<Id,Map<Id,SObject>> recordsByAction = new Map<Id,Map<Id,SObject>>();
        for(Action__c action : rt.Actions__r){
            List<String> fieldSplitted = action.TargetMember__c.split('\\.');
            if(fieldSplitted.size() > 1){
                String recordLookup = fieldSplitted[0].replace('__r','__c');
                fieldSplitted.remove(0);
                //String memberLookup = fieldSplitted[1];
                String memberLookup = String.join(fieldSplitted,'.');
                Set<Id> relatedIds = new Set<Id>();
                for(SObject record : records){
                    if(record.get(recordLookup) != null){
                        relatedIds.add((Id)record.get(recordLookup));
                    }
                }
                recordsByAction.put(action.Id, new Map<Id,SObject>(new SObjectsSelector().queryRecords(relatedIds, null, action.TargetObject__c, new Set<String>{memberLookup})));
            } else {
                recordsByAction.put( action.Id, new Map<Id, SObject>(records) );
            }
        }

        Map<Id,List<Transaction__c>> transactionsByRecordId = new Map<Id,List<Transaction__c>>();
        if( !recordsByAction.isEmpty() ){
            // crea transactions y las relaciona en un mapa por registro
            for(SObject record : records){
                List<Transaction__c> transactions = new List<Transaction__c>();
                Datetime dateForTransaction;
                if(rt.Date__c != null && record.get(rt.Date__c) != null){
                    dateForTransaction = ((DateTime)record.get(rt.Date__c));
                }else {
                    dateForTransaction = Datetime.now();
                }

                for(Action__c action : rt.Actions__r){
                    // verifica que para esa action no tenga transaction
                    if(!actionsByRecordId.containsKey(record.Id) || !actionsByRecordId.get(record.Id).contains(action.Id)){

                        List<String> fieldSplitted = action.TargetMember__c.split('\\.');
                        if(fieldSplitted.size() > 1){
                            String recordLookup = fieldSplitted[0].replace('__r','__c');
                            if(record.get(recordLookup) != null && recordsByAction.containskey(action.Id) && recordsByAction.get(action.Id).get((Id)record.get(recordLookup)) != null){
                                fieldSplitted.remove(0);
                                SObject relatedRecord = recordsByAction.get(action.Id).get((Id)record.get(recordLookup));
                                Integer index = 0;
                                String fieldName = fieldSplitted[index];
                                for(; index < fieldSplitted.size() -1 ; index++){
                                    relatedRecord = relatedRecord.getSObject(fieldName);
                                    if(relatedRecord == null){
                                        break;
                                    }
                                    fieldName = fieldSplitted[index+1];
                                }

                                if(relatedRecord != null){
                                    Transaction__c newTransaction = new Transaction__c(Member__c = (Id)relatedRecord.get(fieldName), Action__c = action.Id, Date__c = dateForTransaction, SkipEngine__c = true);
                                    newTransaction.put(rt.LookupFromTransaction__c, record.Id);
                                    transactions.add(newTransaction);
                                }
                            }

                        }else{
                            if(record.get(action.TargetMember__c) != null){
                                Transaction__c newTransaction = new Transaction__c(Member__c = (Id)(record.get(action.TargetMember__c)), Action__c = action.Id, Date__c = dateForTransaction, SkipEngine__c = true);
                                newTransaction.put(rt.LookupFromTransaction__c, record.Id);
                                transactions.add(newTransaction);
                            }
                        }
                    }
                }
                if(!transactions.isEmpty()){
                    transactionsByRecordId.put(record.Id, transactions);
                }
            }
        }

        return transactionsByRecordId;
    }

    public static Map<Id, List<Tracker__c>> createTrackersMap(RuleTrigger__c rt, List<SObject> records){
        // TODO: Solo en update
        // Arma un mapa con los trackers que ya existen (para no crearlas)
        List<Tracker__c> existingTrackers = new TrackersSelector(new Set<String>{rt.LookupFromTracker__c, 'Action__c'}).selectByActionAndRecord(rt.Actions__r, records, rt.LookupFromTracker__c);
        Map<Id,Set<Id>> actionsByRecordId = new Map<Id,Set<Id>>();
        for(Tracker__c t : existingTrackers){
            Id recordId = (Id)t.get(rt.LookupFromTracker__c);
            if(actionsByRecordId.containsKey(recordId)){
                actionsByRecordId.get(recordId).add(t.Action__c);
            }else{
                actionsByRecordId.put(recordId, new Set<Id>{t.Action__c});
            }
        }

        // En caso de haber cross members los querea
        Map<Id,Map<Id,SObject>> recordsByAction = new Map<Id,Map<Id,SObject>>();
        for(Action__c action : rt.Actions__r){
            if( action.MissionsQuantity__c > 0 ){
                List<String> fieldSplitted = action.TargetMember__c.split('\\.');
                if(fieldSplitted.size() > 1){
                    String recordLookup = fieldSplitted[0].replace('__r','__c');
                    String memberLookup = fieldSplitted[1];
                    Set<Id> relatedIds = new Set<Id>();
                    for(SObject record : records){
                        if(record.get(recordLookup) != null){
                            relatedIds.add((Id)record.get(recordLookup));
                        }
                    }
                    recordsByAction.put(action.Id, new Map<Id,SObject>(new SObjectsSelector().queryRecords(relatedIds, null, action.TargetObject__c, new Set<String>{memberLookup})));
                } else {
                    recordsByAction.put( action.Id, new Map<Id, SObject>(records) );
                }
            }
        }

        // crea trackers y las relaciona en un mapa por registro
        Map<Id, List<Tracker__c>> trackersByRecordId = new Map<Id, List<Tracker__c>>();
        if( !recordsByAction.isEmpty() ){
            for(SObject record : records){
                List<Tracker__c> trackers = new List<Tracker__c>();
                Datetime dateForTracker;
                if(rt.Date__c != null){
                    dateForTracker = ((DateTime)record.get(rt.Date__c));
                }else {
                    dateForTracker = Datetime.now();
                }

                for(Action__c action : rt.Actions__r){
                    // verifica que para esa action no tenga trackers
                    if(!actionsByRecordId.containsKey(record.Id) || !actionsByRecordId.get(record.Id).contains(action.Id)){
                        List<String> fieldSplitted = action.TargetMember__c.split('\\.');
                        // verifica que tenga el member completo
                        Id memberId;
                        if(fieldSplitted.size() > 1){
                            String recordLookup = fieldSplitted[0].replace('__r','__c');
                            String memberLookup = fieldSplitted[1];
                            if(record.get(recordLookup) != null && recordsByAction.get(action.Id).get((Id)record.get(recordLookup)).get(memberLookup) != null){
                                memberId = (Id)recordsByAction.get(action.Id).get((Id)record.get(recordLookup)).get(memberLookup);
                            }
                        }else{
                            if(record.get(action.TargetMember__c) != null){
                               memberId =  (Id)record.get(action.TargetMember__c);
                            }
                        }
                        if( memberId != null){
                            Tracker__c newTracker = new Tracker__c(Member__c = memberId, Action__c = action.Id, Date__c = dateForTracker);
                            newTracker.put(rt.LookupFromTracker__c, record.Id);
                            trackers.add(newTracker);
                        }
                    }
                }
                if(!trackers.isEmpty()){
                    trackersByRecordId.put(record.Id, trackers);
                }
            }
        }
        return trackersByRecordId;
    }

    public static void processTrackers(List<Tracker__c> trackers, Map<Id,SObject> recordsMap, Boolean online, SObjectUnitOfWork uow){
        Set<Id> actionIds = new Set<Id>();
        Set<Id> memberIds = new Set<Id>();
        Set<Id> activeMemberIds = new Set<Id>();
        DateStructure limitDates = new DateStructure();
        for(Tracker__c t : trackers){
            actionIds.add(t.Action__c);
            memberIds.add(t.Member__c);

            if(limitDates.fromDate == null || t.Date__c <= limitDates.fromDate){
                limitDates.fromDate = t.Date__c.date();
            }
            if(limitDates.toDate == null || t.Date__c >= limitDates.toDate){
                limitDates.toDate = t.Date__c.date();
            }
        }

        Map<Id,Action__c> actionsMap = new Map<Id,Action__c>(new ActionsSelector(new Set<String>{'FieloPLT__RuleTrigger__r.FieloPLT__Date__c','FieloPLT__RuleTrigger__r.FieloPLT__LookupFromTracker__c','FieloPLT__RuleTrigger__r.FieloPLT__Object__c'}).selectActiveById(actionIds));

        //TODO: armar mapa de Program por query en Selector
        Map<Id,Program__c> programsMap = new Map<Id,Program__c>();
        for(Member__c member : new MembersSelector(new Set<String>{'FieloPLT__Program__c','FieloPLT__Program__r.FieloPLT__CriteriaFields__c'}).selectActiveById(memberIds)){
            activeMemberIds.add(member.Id);
            if(!programsMap.containsKey(member.Program__c)){
                programsMap.put(member.Program__c, member.Program__r);
            }
        }

        // CHALLENGES //
        //por cada Challenge
        Map<Id, Challenge__c> challengesMap = new Map<Id, Challenge__c>(new ChallengesSelector(new Set<String>{'FieloPLT__Segment__c','FieloPLT__Program__c', 'FieloPLT__StartDate__c', 'FieloPLT__EndDate__c','FieloPLT__Subscription__c'}).selectWithMissionsAndMembersByProgram(programsMap.keySet(), limitDates.fromDate, limitDates.toDate, actionIds, activeMemberIds));
        Map<Id, Set<Id>> challengesByProgram = new Map<Id,Set<Id>>();
        Map<Id, Map<Id,Set<Id>>> missionsByChallengesByAction = new Map<Id, Map<Id,Set<Id>>>();
        Set<Id> missionsIds = new Set<Id>();
        Set<Id> segmentIds = new Set<Id>();
        Map<Id, Set<Id>> challengesByMember = new Map<Id, Set<Id>>();
        Map<Id, Map<Id, ChallengeMember__c>> mapaChallengesMembers = new Map<Id, Map<Id, ChallengeMember__c>>();
        Set<String> alternativeKeys = new Set<String>();
        ChallengesMembers.alternativeKeysProcessed = new Set<String>();

        //get json fields from programs to query members and related list for promotion segmentation analize
        Boolean existCriterionGroups = false;
        List<SObjectService.CriteriaWrapper> criteriasList = new List<SObjectService.CriteriaWrapper>();
        for(Program__c program : programsMap.values()){
            if(program.CriteriaFields__c != null){
                Map<String,SObjectService.CriteriaWrapper> criteriasMetaDataMap = (Map<String,SObjectService.CriteriaWrapper>)JSON.deserialize(program.CriteriaFields__c, Map<String,SObjectService.CriteriaWrapper>.class);
                if(criteriasMetaDataMap.containsKey('segments')){
                    SObjectService.CriteriaWrapper cmd = criteriasMetaDataMap.get('segments');
                    existCriterionGroups = cmd.isUsingCriterionGroup;
                    criteriasList.add(cmd);
                }
            }
        }

        //VER Para Subscripcion Global con Segmentacion
        Map<Id,Member__c> membersMap = new Map<Id,Member__c>(((List<Member__c>)new SObjectsSelector().queryRecords(activeMemberIds, SObjectService.getFieldsMap(criteriasList), 'FieloPLT__Member__c', new Set<String>{'FieloPLT__Program__c'})));
        //Map<Id,Member__c> membersMap = new Map<Id,Member__c>(new MembersSelector(getMemberFields(programsMap.values(), null)).selectById(memberIds));

        //Si los members estan Activos => proceso
        if( membersMap.size() > 0 ){
            for(Challenge__c c : challengesMap.values()){
                for(ChallengeMember__c chm : c.ChallengesMembers__r){
                    if( mapaChallengesMembers.containsKey(chm.Challenge__c) ){
                        mapaChallengesMembers.get(chm.Challenge__c).put( chm.Member__c, chm );
                    } else {
                        mapaChallengesMembers.put(chm.Challenge__c, new Map<Id, ChallengeMember__c> { chm.Member__c => chm } );
                    }
                    //Guardo los Challenges para cada Member para armar AlternativeKey y para ver si el member esta subscripto
                    if( challengesByMember.containskey(chm.Member__c) ){
                        challengesByMember.get(chm.Member__c).add( chm.Challenge__c );
                    } else {
                        challengesByMember.put(chm.Member__c, new Set<Id>{ chm.Challenge__c } );
                    }
                }

                //Si es Global y tiene segmento guardo el Id del segment para evaluar con los segmentos del member, sino compruebo si esta subscripto
                if( c.Subscription__c == 'Global' ){
                    if( c.Segment__c != null ){
                        segmentIds.add(c.Segment__c);
                    } else {
                        for(Id memberId : membersMap.keySet()){
                            //Si el Challenge no esta en el mapa, o si el member no esta en el Challenge le creo un ChallengeMember
                            if( !mapaChallengesMembers.containsKey(c.Id) || (mapaChallengesMembers.containsKey(c.Id) && !mapaChallengesMembers.get(c.Id).containsKey(memberId)) ){
                                ChallengeMember__c chm = new ChallengeMember__c(Challenge__c = c.Id, Member__c = memberId);
                                 if( mapaChallengesMembers.containsKey(chm.Challenge__c) ){
                                    mapaChallengesMembers.get(c.Id).put( memberId, chm );
                                } else {
                                    mapaChallengesMembers.put(c.Id, new Map<Id, ChallengeMember__c> { memberId => chm } );
                                }

                                //Guardo los Challenges para cada Member para armar AlternativeKey y para ver si el member esta subscripto
                                if( challengesByMember.containskey(memberId) ){
                                    challengesByMember.get(memberId).add( c.Id );
                                } else {
                                    challengesByMember.put(memberId, new Set<Id>{ c.Id } );
                                }
                            }
                        }
                    }
                }

                //Si existe misiones relacionadas a las Actions de los Rule Triggers
                if(!c.Missions__r.isEmpty()){
                    //agrega la promotion al program correspondiente
                    if(challengesByProgram.containsKey(c.Program__c)){
                        challengesByProgram.get(c.Program__c).add(c.Id);
                    }else{
                        challengesByProgram.put(c.Program__c, new Set<Id>{c.Id});
                    }

                    //por cada mission
                    for(Mission__c mission : c.Missions__r){
                        //logica para agregar la mission al challenge correspondiente
                        if(missionsByChallengesByAction.containsKey(mission.Action__c)){
                            if(missionsByChallengesByAction.get(mission.Action__c).containsKey(c.Id)){
                                missionsByChallengesByAction.get(mission.Action__c).get(c.Id).add(mission.Id);
                            }else{
                                missionsByChallengesByAction.get(mission.Action__c).put(c.Id, new Set<Id>{mission.Id});
                            }
                        }else{
                            missionsByChallengesByAction.put(mission.Action__c, new Map<Id,Set<Id>>{c.Id => new Set<Id>{mission.Id}});
                        }

                        missionsIds.add(mission.Id);

                        //Armo alternativeKeys del challenge con Mission Id y Member Id
                        for(Id memberId : challengesByMember.keySet()){
                            alternativeKeys.add( String.valueOf(mission.Id) + String.valueOf(memberId) );
                        }
                    }
                }
            }

            Map<Id, Mission__c> missionsMap = new Map<Id, Mission__c>( new MissionsSelector( new Set<String>{'FieloPLT__Type__c','FieloPLT__LogicalExpression__c','FieloPLT__FieldToAggregate__c','FieloPLT__ObjectiveValue__c','FieloPLT__DynamicObjective__c','FieloPLT__ObjectiveField__c','FieloPLT__Operator__c','FieloPLT__ObjectiveType__c','FieloPLT__ObjectiveValue__c'} ).selectWithCriteriaByActive(missionsIds) );
            Map<String, MissionMember__c> mapaMissionMember = new Map<String, MissionMember__c>();
            for(MissionMember__c missionMember : new MissionsMembersSelector().selectByAlternativeKey(alternativeKeys)){
                mapaMissionMember.put( missionMember.AlternativeKey__c, missionMember );
            }

            //TODO: funcionalidad MD
            Map<Id,List<CriterionGroup__c>> criteriaGroupMap = new Map<Id,List<CriterionGroup__c>>();
            //TODO: agregar variable de si hay o no master detail
            if(existCriterionGroups){
                for(CriterionGroup__c cg : [SELECT Id, Mission__c, Segment__c, LogicalExpression__c, Mode__c, Field__c, RelatedList__c, Operator__c, Value__c, (SELECT Operator__c, Order__c, FieldType__c, FieldName__c, DateValue__c, NumberValue__c, BooleanValue__c, Values__c, IsField__c FROM Criteria__r) FROM CriterionGroup__c WHERE Mission__c in : missionsMap.keySet() OR Segment__c in : segmentIds]){
                    if(cg.Mission__c != null){
                        if(criteriaGroupMap.containsKey(cg.Mission__c)){
                            criteriaGroupMap.get(cg.Mission__c).add(cg);
                        }else{
                            criteriaGroupMap.put(cg.Mission__c, new List<CriterionGroup__c>{cg});
                        }
                    }else if(cg.Segment__c != null){
                        if(criteriaGroupMap.containsKey(cg.Segment__c)){
                            criteriaGroupMap.get(cg.Segment__c).add(cg);
                        }else{
                            criteriaGroupMap.put(cg.Segment__c, new List<CriterionGroup__c>{cg});
                        }
                    }
                }
            }

            //Si hay segmentos
            if( !segmentIds.isEmpty() ){
                //Agrupo segmentos por Programa
                Map<Id,Map<Id,Segment__c>> segmentsByProgram = new Map<Id,Map<Id,Segment__c>>();
                List<Segment__c> segments = new SegmentsSelector().selectByProgramOrWithoutProgramAndActive(programsMap.keySet(), segmentIds, activeMemberIds);
                Map<Id,Segment__c> segmentsWithoutProgram = new Map<Id,Segment__c>();
                for(Segment__c segment : segments){
                    if(segment.Program__c != null){
                        if(segmentsByProgram.containsKey(segment.Program__c)){
                            segmentsByProgram.get(segment.Program__c).put(segment.Id, segment);
                        }else{
                            segmentsByProgram.put(segment.Program__c, new Map<Id,Segment__c>{segment.Id => segment});
                        }
                    }else{
                        segmentsWithoutProgram.put(segment.Id,segment);
                    }
                }

                //Para cada Challenge que tiene Segmentacion, verifico que los members cumplan la segmentacion y los agrego para subscribir
                for(Challenge__c c : challengesMap.values()){
                    if(c.Segment__c != null){
                        for(Id memberId : membersMap.keySet()){
                            Map<Id,Segment__c> mapSegments = new Map<Id,Segment__c>();
                            if(segmentsByProgram.containsKey(membersMap.get(memberId).Program__c)){
                                mapSegments.putAll(segmentsByProgram.get(membersMap.get(memberId).Program__c));
                            }
                            mapSegments.putAll(segmentsWithoutProgram);
                            //Si cumple con la segmentacion lo agrego al mapaChallengeMembers
                            if( appliesIncentives(c.Segment__c, membersMap.get(memberId), mapSegments, criteriaGroupMap) ){
                                //Si el Challenge no esta en el mapa, o si el member no esta en el Challenge le creo un ChallengeMember
                                if( !mapaChallengesMembers.containsKey(c.Id) || (mapaChallengesMembers.containsKey(c.Id) && !mapaChallengesMembers.get(c.Id).containsKey(memberId)) ){
                                    ChallengeMember__c chm = new ChallengeMember__c(Challenge__c = c.Id, Member__c = memberId);
                                     if( mapaChallengesMembers.containsKey(chm.Challenge__c) ){
                                        mapaChallengesMembers.get(c.Id).put( memberId, chm );
                                    } else {
                                        mapaChallengesMembers.put(c.Id, new Map<Id, ChallengeMember__c> { memberId => chm } );
                                    }

                                    //Guardo los Challenges para cada Member para armar AlternativeKey y para ver si el member esta subscripto
                                    if( challengesByMember.containskey(memberId) ){
                                        challengesByMember.get(memberId).add( c.Id );
                                    } else {
                                        challengesByMember.put(memberId, new Set<Id>{ c.Id } );
                                    }
                                }
                            }
                            ChallengesMembers.alternativeKeysProcessed.add(String.valueOf(c.Id) + String.valueOf(memberId));
                        }
                    }
                }
            }

            Set<String> alternativeKeyAdded = new Set<String>();
            for(Tracker__c t : trackers){
                if( membersMap.containskey(t.Member__c) ){
                    //Si no se definio un CPUMargin o si todavia tiene CPU Limit disponible entonces lo procesa -> Si no tiene valor, y no esta en contexto asyncronico toma valor 1000 por default
                    Integer cpuTime = SObjectService.getCpuTime();
                    if(cpuTime == null || Limits.getLimitCpuTime() - Limits.getCpuTime() > cpuTime){
                        Action__c action = actionsMap.get(t.Action__c);
                        RuleTrigger__c rt = action.RuleTrigger__r;
                        SObject record = recordsMap.get( (Id)t.get(rt.LookupFromTracker__c) );
                        Member__c member = membersMap.get(t.Member__c);

                        //Si el Member esta subscripto en algun Challenge
                        if(challengesByMember.containsKey(member.Id)){
                            Map<Id, Set<Id>> missionsByChallenge = missionsByChallengesByAction.get(action.Id);

                            //Para las misiones de cada Challenge, evaluo el registro relacionado a cada tracker
                            Boolean trackerAdded = false;
                            for(Id challengeId : challengesByMember.get(member.Id)){
                                Challenge__c challenge = challengesMap.get(challengeId);
                                //Obtengo el date de la transaction, porque sino la end date es con el mismo día pero a las 0 horas y la transaction tiene como datetime el mismo día pero con horario mayor a las 0 horas y no cumple la condición cuando sí debería
                                Date trackerDate = t.Date__c.date();

                                if((challenge.StartDate__c == null || challenge.EndDate__c == null) || (challenge.StartDate__c <= trackerDate && challenge.EndDate__c >= trackerDate)){
                                    if(missionsByChallenge != null && missionsByChallenge.containsKey(challenge.Id)){
                                        for(Id missionId : missionsByChallenge.get(challenge.Id)){
                                            Mission__c mission = missionsMap.get(missionId);

                                            //Si el registro cumple con los criterios de la mission
                                            if( evaluateMission(mission, criteriaGroupMap.get(mission.Id), record) ){
                                                String alternativeKey = String.valueof(mission.Id) + String.valueOf(member.Id);
                                                MissionMember__c missionMember = new MissionMember__c();
                                                if( !mapaMissionMember.containsKey(alternativeKey) ){
                                                    missionMember.Counter__c = 0;
                                                    missionMember.MaxValue__c = 0;
                                                    missionMember.Summary__c = 0;
                                                    missionMember.AlternativeKey__c = alternativeKey;
                                                    missionMember.Status__c = null;
                                                    mapaMissionMember.put( alternativeKey, missionMember );
                                                }

                                                //Si el MissionMember con el alternativeKey no fue agregado
                                                if( !alternativeKeyAdded.contains(alternativeKey) ){
                                                    if( mapaMissionMember.get(alternativeKey).Id == null ){
                                                        uow.registerNew(mapaMissionMember.get(alternativeKey));
                                                    } else {
                                                        uow.registerDirty(mapaMissionMember.get(alternativeKey));
                                                    }
                                                    alternativeKeyAdded.add(alternativeKey);
                                                }

                                                //Actualizo los acumuladores
                                                if(mapaMissionMember.get(alternativeKey).Status__c != 'Accomplished'){
                                                    //Relaciono el missionMember a la Mission y al ChallengeMember
                                                    mapaMissionMember.get(alternativeKey).Mission__c = mission.Id;
                                                    uow.registerRelationship(mapaMissionMember.get(alternativeKey), MissionMember__c.ChallengeMember__c, mapaChallengesMembers.get(challenge.Id).get(member.Id));

                                                    //Agrego el ChallengeMember para que se inserte en la base de datos
                                                    if( mapaChallengesMembers.get(challenge.Id).get(member.Id).Id == null && !alternativeKeyAdded.contains( String.valueOf(challenge.Id)+String.valueOf(member.Id) ) ){
                                                        uow.registerNew(mapaChallengesMembers.get(challenge.Id).get(member.Id));
                                                        alternativeKeyAdded.add( String.valueOf(challenge.Id)+String.valueOf(member.Id) );
                                                    }

                                                    //Actualiza Contadores
                                                    mapaMissionMember.get(alternativeKey).Counter__c++;
                                                    if(missionsMap.get( mission.Id ).FieldToAggregate__c != null ){
                                                        //Busco el campo sobre para obtener el valor
                                                        Decimal value = (Decimal)record.get( mission.FieldToAggregate__c );

                                                        if(value != null){
                                                            //Modifico Summary y MaxValue
                                                            mapaMissionMember.get(alternativeKey).Summary__c += value;

                                                            if( mapaMissionMember.get(alternativeKey).MaxValue__c < value)
                                                                mapaMissionMember.get(alternativeKey).MaxValue__c = value;

                                                            //Guarda el ultimo valor de la accion
                                                            mapaMissionMember.get(alternativeKey).Last__c = value;
                                                        }
                                                    }

                                                    //Compara valores actualizados contra objetivo de la mision
                                                    if( missionAccomplished(missionsMap.get(mission.Id), mapaMissionMember.get(alternativeKey), record) ){
                                                        mapaMissionMember.get(alternativeKey).Status__c = 'Accomplished';
                                                    }

                                                    //Si el tracker ya fue agregado al UOW, lo clono para tener uno nuevo -- Por cada Mission que cumple tiene que tener su tracker asociado al registro procesado
                                                    t.IsProcessed__c = true;
                                                    if( trackerAdded ){
                                                        t = t.clone(false);
                                                    }
                                                    //Si el record aplico a la mission entonces creo el tracker (y si no existía de antes porque si viene de procesamiento offline ya estaba insertado de antes)
                                                    if(t.Id == null){
                                                        uow.registerNew(t);
                                                    }
                                                    uow.registerRelationship(t, Tracker__c.MissionMember__c, mapaMissionMember.get(alternativeKey));
                                                    trackerAdded = true;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }else{
                        //TODO resolver y agregar register new o dirty, desconocemos la logica
                        t.IsOffline__c = true;
                        if(t.Id == null){
                            uow.registerNew(t);
                        }else{
                            uow.registerDirty(t);
                        }
                    }
                }
            }
            //TODO: Trackers.validateAdminFields

        }
    }

    public static boolean evaluateMission(Mission__c mission, List<CriterionGroup__c> critGroups, sObject record){
        //TODO: funcionalidad MD
        List<SObject> criteriaList = new List<SObject>();
        criteriaList.addAll((List<SObject>)mission.MissionCriteria__r);
        if(critGroups != null)
            criteriaList.addAll((List<SObject>)critGroups);

        return SObjectService.applyCriteria(criteriaList, record, mission.LogicalExpression__c);
    }

    public static boolean missionAccomplished(Mission__c mission, MissionMember__c missionMember, sObject accion){
        Boolean accomplished = false;

        //Get value to compare to
        Decimal value;
        if(mission.DynamicObjective__c){
            //value = (Decimal)accion.getsObject('FieloEE__Member__r').get(mission.ObjectiveField__c);
        }else{
            value = mission.ObjectiveValue__c;
        }

        if( mission.Type__c == 'With Objective'){
            if(mission.ObjectiveType__c == 'Counter'){
                if( isAccomplished(mission.Operator__c, value, missionMember.Counter__c) ){
                    accomplished = true;
                }
            }else if(mission.ObjectiveType__c == 'Summary'){
                if( isAccomplished(mission.Operator__c, value, missionMember.Summary__c) ){
                    accomplished = true;
                }
            }else if(mission.ObjectiveType__c == 'Max Value'){
                if( isAccomplished(mission.Operator__c, value, missionMember.MaxValue__c) ){
                    accomplished = true;
                }
            }else if(mission.ObjectiveType__c == 'Average'){
                if( isAccomplished(mission.Operator__c, value, missionMember.Summary__c / missionMember.Counter__c) ){
                        accomplished = true;
                }
            }else if(mission.ObjectiveType__c == 'Last'){
                if( isAccomplished(mission.Operator__c, value, missionMember.Last__c) ){
                        accomplished = true;
                }
            }
        }
        return accomplished;
    }

    public static Boolean isAccomplished(String operator, Decimal objective, Decimal value){
        Boolean aux = false;
        if( (operator == 'equals' && value == objective) || (operator == 'greater than' && value > objective) || (operator == 'less than' && value < objective) || (operator == 'greater or equal' && value >= objective)
            || (operator == 'less or equal' && value <= objective)){
                aux = true;
            }
        return aux;
    }

    private static Integer getCpuTime(){
        Integer aux;
        if( PublicSettings__c.getInstance(UserInfo.getUserId()) == null || PublicSettings__c.getInstance(UserInfo.getUserId()).CPUTimeMargin__c == null ){
            //Si estoy asincronico el default es 6000
            if( System.isFuture() || System.isBatch() ){
                aux = 6000;
            } else {
                aux = 1000;
            }
        } else {
            aux = Integer.valueOf(PublicSettings__c.getInstance(UserInfo.getUserId()).CPUTimeMargin__c);
        }
        return aux;
    }

    /**
     * @details     Procesa una lista de transactions sin evaluar criterios de rule trigger ni asignacion de actions
     * @version     10.0
     * @param       transactions        registros a procesar
     * @returns     Void
     * @warning     Los registros deben tener un member y un action relacionado
     * @test
     * @code {.java}
     *              List<FieloEE__Transaction__c> transactions = [SELECT Id FROM Transaction__c WHERE Member__c != null AND Action__c != null AND IsProcessed__c = false];
     *              SObjectService.processTransactions(transactions);
     * @endcode
     */
    public static void processTransactions(List<Transaction__c> transactions){
        SObjectUnitOfWork uow = new SObjectUnitOfWork(new List<Schema.SObjectType>{Transaction__c.SObjectType, Member__c.SObjectType, Point__c.SObjectType, BadgeMember__c.SObjectType,Redemption__c.SObjectType, RedemptionItem__c.SObjectType});
        processTransactions(transactions, uow);
        uow.commitWork();
    }

    public static void processTrackers(List<Tracker__c> trackers){
        SObjectUnitOfWork uow = new SObjectUnitOfWork(new List<Schema.SObjectType>{Tracker__c.SObjectType, Transaction__c.SObjectType, Member__c.SObjectType, Point__c.SObjectType, BadgeMember__c.SObjectType,Redemption__c.SObjectType, RedemptionItem__c.SObjectType, MissionMember__c.SObjectType});
        processTrackers(trackers, uow);
        uow.commitWork();
    }

    public static void processTransactions(List<Transaction__c> trans, SObjectUnitOfWork uow){
        Set<Id> actionIds = new Set<Id>();
        for(Transaction__c t : trans){
            actionIds.add(t.Action__c);
        }

        Map<Id,Action__c> actionsMap = new Map<Id,Action__c>(new ActionsSelector(new Set<String>{'RuleTrigger__r.LookupFromTransaction__c','RuleTrigger__r.Object__c','CriteriaFields__c'}).selectActiveById(actionIds));
        Set<Id> recordIds = new Set<Id>();
        for(Transaction__c t : trans){
            recordIds.add((Id)t.get(actionsMap.get(t.Action__c).RuleTrigger__r.LookupFromTransaction__c));
        }

        List<CriteriaWrapper> rulesCriteriasList = new List<CriteriaWrapper>();
        for(Action__c action : actionsMap.values()){
            Map<String,CriteriaWrapper> criteriasMetaDataMap = (Map<String,CriteriaWrapper>)JSON.deserialize(action.CriteriaFields__c, Map<String,CriteriaWrapper>.class);

            if(criteriasMetaDataMap.containsKey('rules')){
                rulesCriteriasList.add(criteriasMetaDataMap.get('rules'));
            }
        }

        Map<String,Set<String>> fieldsMap = getFieldsMap(rulesCriteriasList);
        Map<Id,SObject> recordsMap = new Map<Id,SObject>(new SObjectsSelector().queryRecords(recordIds, fieldsMap, actionsMap.values()[0].RuleTrigger__r.Object__c, new Set<String>{'Name'}));

        processTransactions(trans, recordsMap, false, uow);
        Transactions.validateAdminFields = false;
    }

    public static void processTrackers(List<Tracker__c> trackers, SObjectUnitOfWork uow){
        Set<Id> actionIds = new Set<Id>();
        for(Tracker__c t : trackers){
            actionIds.add(t.Action__c);
        }

        Map<Id,Action__c> actionsMap = new Map<Id,Action__c>(new ActionsSelector(new Set<String>{'FieloPLT__RuleTrigger__r.FieloPLT__LookupFromTransaction__c','FieloPLT__RuleTrigger__r.FieloPLT__Object__c','FieloPLT__CriteriaFields__c'}).selectActiveById(actionIds));
        Set<Id> recordIds = new Set<Id>();
        for(Tracker__c t : trackers){
            recordIds.add((Id)t.get(actionsMap.get(t.Action__c).RuleTrigger__r.LookupFromTransaction__c));
        }

        List<CriteriaWrapper> missionsCriteriasList = new List<CriteriaWrapper>();
        for(Action__c action : actionsMap.values()){
            Map<String,CriteriaWrapper> criteriasMetaDataMap = (Map<String,CriteriaWrapper>)JSON.deserialize(action.CriteriaFields__c, Map<String,CriteriaWrapper>.class);

            if(criteriasMetaDataMap.containsKey('missions')){
                missionsCriteriasList.add(criteriasMetaDataMap.get('missions'));
            }
        }

        Map<String,Set<String>> fieldsMap = getFieldsMap(missionsCriteriasList);
        Map<Id,SObject> recordsMap = new Map<Id,SObject>(new SObjectsSelector().queryRecords(recordIds, fieldsMap, actionsMap.values()[0].RuleTrigger__r.Object__c, new Set<String>{'Name'}));

        processTrackers(trackers, recordsMap, false, uow);
    }

    /*public static Map<String,Set<String>> getFieldsMap(List<Action__c> actions){
        Map<String,Set<String>> fieldsMap = new Map<String,Set<String>>();
        for(Action__c action : actions){
            if(action.CriteriaFields__c != null){

                Map<String, Object> fieldsFromAction = (Map<String, Object>)JSON.deserializeUntyped(action.CriteriaFields__c);
                for(String type : fieldsFromAction.keySet()){
                    String fields = (String)fieldsFromAction.get(type);
                    if(fieldsMap.containsKey(type)){
                        fieldsMap.get(type).addAll(fields.split(','));
                    }else{
                        fieldsMap.put(type,new Set<String>(fields.split(',')));
                    }
                }
            }
        }
        return fieldsMap;
    }*/

    public static Map<String,Set<String>> getFieldsMap(List<CriteriaWrapper> criterias){
        Map<String,Set<String>> fieldsMap = new Map<String,Set<String>>();
        for(CriteriaWrapper cw : criterias){
            for(String objectType : cw.fieldsByObject.keySet()){
                Set<String> fields = cw.fieldsByObject.get(objectType);
                if(fieldsMap.containsKey(objectType)){
                    fieldsMap.get(objectType).addAll(fields);
                }else{
                    fieldsMap.put(objectType,new Set<String>(fields));
                }
            }
        }
        return fieldsMap;
    }

    public class CriteriaWrapper{
        public Boolean isCrossField;
        public Boolean isMasterDetail;
        public Boolean isUsingCriterionGroup;
        public Map<String,Set<String>> fieldsByObject;

        public CriteriaWrapper(){
            this.isCrossField = false;
            this.isMasterDetail = false;
            this.isUsingCriterionGroup = false;
            this.fieldsByObject = new Map<String,Set<String>>();
        }
    }

    public static Set<String> getMemberBalanceFields(List<Program__c> programs, Map<Id,Map<Id,ProgramPointType__c>> pointsTypeByProgram){
        Set<String> memberFields = new Set<String>();//{'Name', 'FieloPLT__Points__c', 'FieloPLT__User__c','FieloPLT__Program__c','FieloPLT__OrganizationAccount__r.FieloPLT__Points__c','FieloPLT__Type__c'};
        for(Program__c program : programs){
            if(pointsTypeByProgram != null && pointsTypeByProgram.containsKey(program.Id)){
                for(ProgramPointType__c ppt : pointsTypeByProgram.get(program.Id).values()){
                    memberFields.add(ppt.PointType__r.MemberBalanceField__c);
                }
            }
        }

        return memberFields;
    }

    public static void processOffline(List<sObject> ts, SObjectUnitOfWork uow){//this method can receive transactions or trackers
        for(sObject t : ts){
            t.put('FieloPLT__IsOffline__c', true);
            if(t.Id != null){
                uow.registerDirty(t);
            }else{
                uow.registerNew(t);
            }
        }
    }

    private class DateStructure{
        public Date fromDate;
        public Date toDate;
    }

    public static void processTransactions(List<Transaction__c> trans, Map<Id,SObject> recordsMap, Boolean online, SObjectUnitOfWork uow){
        Set<Id> actionIds = new Set<Id>();
        Set<Id> memberIds = new Set<Id>();
        Set<Id> activeMemberIds = new Set<Id>();
        DateStructure limitDates = new DateStructure();
        for(Transaction__c t : trans){
            actionIds.add(t.Action__c);
            memberIds.add(t.Member__c);

            if(limitDates.fromDate == null || t.Date__c <= limitDates.fromDate){
                limitDates.fromDate = t.Date__c.date();
            }
            if(limitDates.toDate == null || t.Date__c >= limitDates.toDate){
                limitDates.toDate = t.Date__c.date();
            }
        }

        Map<Id,Action__c> actionsMap = new Map<Id,Action__c>(new ActionsSelector(new Set<String>{'FieloPLT__RuleTrigger__r.FieloPLT__Date__c','FieloPLT__RuleTrigger__r.FieloPLT__LookupFromTransaction__c','FieloPLT__RuleTrigger__r.FieloPLT__Object__c'}).selectActiveById(actionIds));
        Map<Id,Program__c> programsMap = new Map<Id,Program__c>();
        for(Member__c member : new MembersSelector(new Set<String>{'FieloPLT__Program__c','FieloPLT__Program__r.FieloPLT__CriteriaFields__c'}).selectActiveById(memberIds)){
            activeMemberIds.add(member.Id);
            if(!programsMap.containsKey(member.Program__c)){
                programsMap.put(member.Program__c, member.Program__r);
            }
        }

        //PROMOTIONS/////
        //por cada promotion
        Map<Id,Promotion__c> promotionsMap = new Map<Id,Promotion__c>(new PromotionsSelector(new Set<String>{'FieloPLT__Segment__c', 'FieloPLT__Program__c', 'FieloPLT__StartDate__c', 'FieloPLT__EndDate__c'}).selectWithRulesByProgram(programsMap.keySet(), limitDates.fromDate, limitDates.toDate, actionIds));
        Map<Id,Set<Id>> promotionsByProgram = new Map<Id,Set<Id>>();
        Map<Id,Map<Id,Set<Id>>> rulesByPromotionByAction = new Map<Id,Map<Id,Set<Id>>>();
        Set<Id> ruleIds = new Set<Id>();
        Set<Id> segmentIds = new Set<Id>();
        //TODO optimizar antes de queriar los records afuera que se fije en action si la rule esta con promotions
        for(Promotion__c p : promotionsMap.values()){
            if(!p.Rules__r.isEmpty()){
                //agrega la promotion al program correspondiente
                if(promotionsByProgram.containsKey(p.Program__c)){
                    promotionsByProgram.get(p.Program__c).add(p.Id);
                }else{
                    promotionsByProgram.put(p.Program__c, new Set<Id>{p.Id});
                }

                //por cada rule
                for(Rule__c rule : p.Rules__r){
                    //logica para agregar la rule a la promotion correspondiente
                    if(rulesByPromotionByAction.containsKey(rule.Action__c)){
                        if(rulesByPromotionByAction.get(rule.Action__c).containsKey(p.Id)){
                            rulesByPromotionByAction.get(rule.Action__c).get(p.Id).add(rule.Id);
                        }else{
                            rulesByPromotionByAction.get(rule.Action__c).put(p.Id, new Set<Id>{rule.Id});
                        }
                    }else{
                        rulesByPromotionByAction.put(rule.Action__c, new Map<Id,Set<Id>>{p.Id => new Set<Id>{rule.Id}});
                    }

                    ruleIds.add(rule.Id);
                }

                //agrega al set el id de segment
                segmentIds.add(p.Segment__c);
            }
        }

        //get rules map
        Map<Id,Rule__c> rulesMap = new Map<Id,Rule__c>(new RulesSelector().selectWithCriterias(ruleIds));

        //get json fields from programs to query members and related list for promotion segmentation analize
        Boolean existCriterionGroups = false;
        List<SObjectService.CriteriaWrapper> criteriasList = new List<SObjectService.CriteriaWrapper>();
        for(Program__c program : programsMap.values()){
            if(program.CriteriaFields__c != null){
                Map<String,SObjectService.CriteriaWrapper> criteriasMetaDataMap = (Map<String,SObjectService.CriteriaWrapper>)JSON.deserialize(program.CriteriaFields__c, Map<String,SObjectService.CriteriaWrapper>.class);
                if(criteriasMetaDataMap.containsKey('segments')){
                    SObjectService.CriteriaWrapper cmd = criteriasMetaDataMap.get('segments');
                    existCriterionGroups = cmd.isUsingCriterionGroup;
                    criteriasList.add(cmd);
                }
            }
        }

        //TODO: funcionalidad MD
        Map<Id,List<CriterionGroup__c>> criteriaGroupMap = new Map<Id,List<CriterionGroup__c>>();
        //TODO: agregar variable de si hay o no master detail
        if(existCriterionGroups){
            for(CriterionGroup__c cg : [SELECT Id, Rule__c, Segment__c, LogicalExpression__c, Mode__c, Field__c, RelatedList__c, Operator__c, Value__c, (SELECT Operator__c, Order__c, FieldType__c, FieldName__c, DateValue__c, NumberValue__c, BooleanValue__c, Values__c, IsField__c FROM Criteria__r) FROM CriterionGroup__c WHERE Rule__c in : rulesMap.keySet() OR Segment__c in : segmentIds]){
                if(cg.Rule__c != null){
                    if(criteriaGroupMap.containsKey(cg.Rule__c)){
                        criteriaGroupMap.get(cg.Rule__c).add(cg);
                    }else{
                        criteriaGroupMap.put(cg.Rule__c, new List<CriterionGroup__c>{cg});
                    }
                }else if(cg.Segment__c != null){
                    if(criteriaGroupMap.containsKey(cg.Segment__c)){
                        criteriaGroupMap.get(cg.Segment__c).add(cg);
                    }else{
                        criteriaGroupMap.put(cg.Segment__c, new List<CriterionGroup__c>{cg});
                    }
                }
            }
        }

        //SEGMENTS BY PROGRAM
        Map<Id,Map<Id,Segment__c>> segmentsByProgram = new Map<Id,Map<Id,Segment__c>>();
        List<Segment__c> segments = new SegmentsSelector().selectByProgramOrWithoutProgramAndActive(programsMap.keySet(), segmentIds, activeMemberIds);
        Map<Id,Segment__c> segmentsWithoutProgram = new Map<Id,Segment__c>();
        for(Segment__c segment : segments){
            if(segment.Program__c != null){
                if(segmentsByProgram.containsKey(segment.Program__c)){
                    segmentsByProgram.get(segment.Program__c).put(segment.Id, segment);
                }else{
                    segmentsByProgram.put(segment.Program__c, new Map<Id,Segment__c>{segment.Id => segment});
                }
            }else{
                segmentsWithoutProgram.put(segment.Id,segment);
            }
        }

        //GET MULTI POINTS BY PROGRAM
        Map<Id,Map<Id,ProgramPointType__c>> pointsTypeByProgram = PointTypeService.getProgramPointTypesByProgram(programsMap.keySet());

        //GROUP PROMOTIONS BY MEMBER
        Set<String> fieldSetMember = getMemberBalanceFields(programsMap.values(), pointsTypeByProgram);
        fieldSetMember.add('FieloPLT__Program__c');
        fieldSetMember.add('FieloPLT__Type__c');
        fieldSetMember.add('FieloPLT__OrganizationAccount__r.FieloPLT__LastTransactionDate__c');
        fieldSetMember.add('FieloPLT__Points__c');
        fieldSetMember.add('FieloPLT__OrganizationAccount__r.FieloPLT__Points__c');
        //Set<String> memberFields = new Set<String>{'Name', 'Points__c', 'User__c','Program__c','OrganizationAccount__r.Points__c','Type__c'};
        /*Map<String,Set<String>> fieldsMap = SObjectService.getFieldsMap(criteriasList);
        fieldsMap.put('FieloPLT__OrganizationAccount__r',new Set<String>{'FieloPLT__LastTransactionDate__c'});*/
        Map<Id,Member__c> membersMap = new Map<Id,Member__c>(((List<Member__c>)new SObjectsSelector().queryRecords(activeMemberIds, SObjectService.getFieldsMap(criteriasList), 'FieloPLT__Member__c', fieldSetMember)));
        Map<Id,List<Promotion__c>> promotionsByMember = new Map<Id,List<Promotion__c>>();
        //por cada member
        for(Member__c member : membersMap.values()){
            if(promotionsByProgram.containsKey(member.Program__c)){
                //trae las promotions de ese program desde el mapa y analiza solo las del program
                Set<Id> promotionIds = promotionsByProgram.get(member.Program__c);

                //filtra las promotions segun la segmentacion del member y las agrega al mapa
                List<Promotion__c> promotionsOfMember = new List<Promotion__c>();
                Map<Id,Segment__c> mapSegments = new Map<Id,Segment__c>();
                if(segmentsByProgram.containsKey(member.Program__c)){
                    mapSegments.putAll(segmentsByProgram.get(member.Program__c));
                }
                mapSegments.putAll(segmentsWithoutProgram);
                for(Id promotionId : promotionIds){
                    if(appliesIncentives(promotionsMap.get(promotionId).Segment__c, member, mapSegments, criteriaGroupMap)){
                        promotionsOfMember.add(promotionsMap.get(promotionId));
                    }
                }
                if(!promotionsOfMember.isEmpty()){
                    promotionsByMember.put(member.Id, promotionsOfMember);
                }
            }
        }

        //Si hay members activos
        if( membersMap.size() > 0){
            Map<Id,List<RedemptionService.MemberRewardWrapper>> instantRewardsByRecord = new Map<Id,List<RedemptionService.MemberRewardWrapper>>();
            for(Transaction__c t : trans){
                if( membersMap.containskey(t.Member__c) ){
                    //Si no se definio un CPUMargin o si todavia tiene CPU Limit disponible entonces lo procesa
                    Integer cpuTime = SObjectService.getCpuTime();
                    if(cpuTime == null || Limits.getLimitCpuTime() - Limits.getCpuTime() > cpuTime){
                        Member__c member = membersMap.get(t.Member__c);
                        Map<Id,ProgramPointType__c> pointTypesMap = pointsTypeByProgram.get(member.Program__c);

                        //setea en 0 los balances de la transaction
                        for(ProgramPointType__c ppt : pointTypesMap.values()){
                            t.put(ppt.PointType__r.TransactionBalanceField__c, 0);
                        }

                        if(promotionsByMember.containsKey(member.Id)){
                            Action__c action = actionsMap.get(t.Action__c);
                            RuleTrigger__c rt = action.RuleTrigger__r;
                            SObject record;
                            if((Id)t.get(rt.LookupFromTransaction__c) != null){
                                record = recordsMap.get((Id)t.get(rt.LookupFromTransaction__c));
                            }else{
                                record = t;
                            }
                            Member__c accountMember = member.Type__c == 'Organization Contributor' ? member.OrganizationAccount__r : member;

                            //agrupo las rules que voy a procesar en base al action y promotions que aplican segmento del member y la fecha de la transaction
                            Set<Id> ruleIdsToProcess = new Set<Id>();
                            Map<Id,Set<Id>> rulesByPromotion = rulesByPromotionByAction.get(action.Id);
                            //loop the applied promotions and relate in a map 1 rule only related to 1 promotion
                            for(Promotion__c p : promotionsByMember.get(member.Id)){

                                //Obtengo el date de la transaction, porque sino la end date es con el mismo día pero a las 0 horas y la transaction tiene como datetime el mismo día pero con horario mayor a las 0 horas y no cumple la condición cuando sí debería
                                Date transactionDate = t.Date__c.date();

                                if((p.StartDate__c == null || p.EndDate__c == null) || (p.StartDate__c <= transactionDate && p.EndDate__c >= transactionDate)){
                                    if(rulesByPromotion.containsKey(p.Id)){
                                        ruleIdsToProcess.addAll(rulesByPromotion.get(p.Id));
                                    }
                                }
                            }

                            Map<String, Point__c> mapBestPoint = new Map<String, Point__c>();
                            Boolean ruleEngineGaveRewards = false;
                            for(Id ruleId : ruleIdsToProcess){
                                Rule__c rule = rulesMap.get(ruleId);
                                ProgramPointType__c ppt = pointTypesMap.get(rule.PointType__c);
                                if(rule.RelatedList__c == rt.Object__c){
                                    ruleEngineGaveRewards = evaluateRule(accountMember, rule, criteriaGroupMap.get(rule.Id), record, accountMember.Id, t, uow, instantRewardsByRecord, mapBestPoint, ppt) || ruleEngineGaveRewards;
                                }else{
                                    for(SObject detail : record.getSObjects(rule.RelatedList__c)){
                                        ruleEngineGaveRewards = evaluateRule(accountMember, rule, null, detail, accountMember.Id, t, uow, instantRewardsByRecord, mapBestPoint, ppt) || ruleEngineGaveRewards;
                                    }
                                }
                            }

                            if(ruleEngineGaveRewards){
                                if(!mapBestPoint.isEmpty()){
                                    for(Point__c point : mapBestPoint.values()){
                                        ProgramPointType__c ppt = pointTypesMap.get(point.PointType__c);
                                        if(point.Status__c == 'Approved'){
                                            accountMember.put(ppt.PointType__r.MemberBalanceField__c, (Decimal)accountMember.get(ppt.PointType__r.MemberBalanceField__c) + point.TotalPoints__c);
                                        }
                                        t.put(ppt.PointType__r.TransactionBalanceField__c, (Decimal)t.get(ppt.PointType__r.TransactionBalanceField__c) + point.TotalPoints__c);
                                        uow.registerNew(point, Point__c.Transaction__c, t);
                                    }
                                }

                                List<String> memberFieldsToModify = new List<String>{'FieloPLT__LastTransactionDate__c'};
                                for(ProgramPointType__c ppt : pointTypesMap.values()){
                                    memberFieldsToModify.add(ppt.PointType__r.MemberBalanceField__c);
                                }

                                accountMember.LastTransactionDate__c = t.Date__c.date();
                                uow.registerDirty(accountMember, memberFieldsToModify);

                                t.IsProcessed__c = true;
                                t.SkipEngine__c = true;
                                if(online && t.Id == null){
                                    uow.registerNew(t);
                                }else{
                                    uow.registerDirty(t);
                                }
                            }
                        }
                    }else{
                        t.IsOffline__c = true;
                        if(t.Id == null){
                            uow.registerNew(t);
                        }else{
                            uow.registerDirty(t);
                        }
                    }
                }
            }

            //instant rewards process and set of errors status
            List<RedemptionService.MemberRewardWrapper> instantRewardsList = new List<RedemptionService.MemberRewardWrapper>();
            for(Id recordId : instantRewardsByRecord.keySet()){
                instantRewardsList.addAll(instantRewardsByRecord.get(recordId));
            }

            if(!instantRewardsList.isEmpty()){
                RedemptionService.instantRedemption(uow, instantRewardsList, 'BackEnd');
                for(Id recordId : instantRewardsByRecord.keySet()){
                    for(RedemptionService.MemberRewardWrapper instantReward : instantRewardsByRecord.get(recordId)){
                        if(instantReward.status == 'Insufficient stock' || instantReward.status == 'Reward not found'){
                            recordsMap.get(recordId).addError(instantReward.status);
                        }
                    }
                }
            }
            Members.validateAdminFields = false;
        }
    }

    //TODO: funcionalidad MD
    public static Boolean evaluateRule(Member__c member, Rule__c rule, List<CriterionGroup__c> critGroups, SObject record, Id memberId, Transaction__c t, SObjectUnitOfWork uow, Map<Id,List<RedemptionService.MemberRewardWrapper>> instantRewardsByRecord, Map<String, Point__c> mapBestPoint, ProgramPointType__c programPointType){
        Boolean gaveRewards = false;
        //TODO: funcionalidad MD
        List<SObject> criteriaList = new List<SObject>();
        criteriaList.addAll((List<SObject>)rule.RuleCriteria__r);
        if(critGroups != null)
            criteriaList.addAll((List<SObject>)critGroups);

        if(SObjectService.applyCriteria(criteriaList, record, rule.LogicalExpression__c)){
            gaveRewards = true;
            if(rule.Type__c == 'No Competition'){
                processRule(member, rule, record, memberId, t, uow, instantRewardsByRecord, programPointType);
            }else{
                processBestRule(rule, record, memberId, t, uow, mapBestPoint, programPointType);
            }
        }
        return gaveRewards;
    }

    public static void processRule(Member__c member, Rule__c rule, SObject record, Id memberId, Transaction__c t, SObjectUnitOfWork uow, Map<Id,List<RedemptionService.MemberRewardWrapper>> instantRewardsByRecord, ProgramPointType__c programPointType){
        //si el premio son puntos
        if(!String.isBlank(rule.PointConversionMode__c)){
            String description = record != null ? '[' + record.get('Name') + ']' : '[' + t.get('Name') + ']';
            //crea los registros de points calculado y suma en los points del registro
            Point__c pointRecord = new Point__c(Member__c = memberId, Rule__c = rule.Id, ActionDescription__c = description, PointType__c = rule.Pointtype__c, Status__c = programPointType.RequestPointApproval__c ? 'Pending' : 'Approved');
            applyAction(pointRecord, rule, record, t);
            if(pointRecord.Status__c == 'Approved'){
                member.put(programPointType.PointType__r.MemberBalanceField__c, (Decimal)member.get(programPointType.PointType__r.MemberBalanceField__c) + pointRecord.TotalPoints__c);
            }
            t.put(programPointType.PointType__r.TransactionBalanceField__c, (Decimal)t.get(programPointType.PointType__r.TransactionBalanceField__c) + pointRecord.TotalPoints__c);

            uow.registerNew(pointRecord, Point__c.Transaction__c, t);
        }
        //si el premio es un reward
        if(!String.isBlank(rule.RewardMode__c)){
            //crea un instant reward segun la rule
            RedemptionService.MemberRewardWrapper instantReward = getInstantReward(rule,t,record);
            if(instantRewardsByRecord.containsKey(record.Id)){
                instantRewardsByRecord.get(record.Id).add(instantReward);
            }else{
                instantRewardsByRecord.put(record.Id, new List<RedemptionService.MemberRewardWrapper>{instantReward});
            }
        }
        //si el premio es un badge
        if(!String.isBlank(rule.BadgeMode__c)){
            //crea un memberbadge para el member segun la rule, o aumenta el contador
            Id badgeId;
            if(rule.BadgeMode__c == 'Fixed Value'){
                badgeId = rule.InstantBadge__c;
            }else if(rule.BadgeMode__c == 'Badge Field'){
                badgeId = (Id)record.get(rule.BadgeFieldName__c);
            }
            uow.registerNew(new BadgeMember__c(Member__c = t.Member__c, Badge__c = badgeId, Quantity__c = 1), BadgeMember__c.Transaction__c, t);
        }
    }

    public static void processBestRule(Rule__c rule, SObject record, Id memberId, Transaction__c t, SObjectUnitOfWork uow, Map<String,Point__c> bestPointsMap, ProgramPointType__c programPointType){
        //TODO
        //trae el pointrecord segun point type
        //si el mapa no tiene point record, lo calcula y lo relaciona
        //si el mapa ya tiene point record, lo trae y lo compara y coloca el que da mas puntos

        // If the record doesn't exist creates it and assign it
        Point__c bestPoint = bestPointsMap.get(rule.RelatedList__c + record.id + rule.PointType__c);
        if(bestPoint == null){
            bestPoint = new Point__c(Member__c = memberId, Rule__c = rule.Id, ActionDescription__c = '[' + record.get('Name') + ']', PointType__c = rule.Pointtype__c, Status__c = programPointType.RequestPointApproval__c ? 'Pending' : 'Approved');
            applyAction(bestPoint, rule, record, t);
        }else{
            // compare with the highest value
            Point__c comparePoints = new Point__c(Member__c = memberId, Rule__c = rule.Id, ActionDescription__c = '[' + record.get('Name') + ']', PointType__c = rule.Pointtype__c, Status__c = programPointType.RequestPointApproval__c ? 'Pending' : 'Approved');
            applyAction(comparePoints, rule, record, t);
            if(comparePoints.TotalPoints__c > bestPoint.TotalPoints__c){
                bestPoint = comparePoints.clone(false);
            }
        }
        bestPointsMap.put(rule.RelatedList__c + record.id + rule.PointType__c, bestPoint);
    }

    private static void applyAction(Point__c points, Rule__c rule, SObject record, Transaction__c t){
        if(rule.PointConversionMode__c == 'Fixed Value'){
            points.TotalPoints__c = rule.ConversionValue__c.round(RoundingMode.HALF_UP );
        }else if(!String.isEmpty(rule.PointConversionMode__c)){
            //Get the value of the field required
            String[] fieldNameSplited = rule.RecordFieldName__c.split('\\.');
            Object valueObject = null;
            //it's a field of the transaction
            if(fieldNameSplited.size() == 1){
                valueObject = record.get(fieldNameSplited[0]);
            //it's a field of a related object
            }else{
                sObject relationObject = record.getSObject(fieldNameSplited[0]);
                if(relationObject != null){
                    if(fieldNameSplited.size() == 2){
                        valueObject = relationObject.get(fieldNameSplited[1]);
                    }
                }
            }
            Decimal fieldValue = (Decimal)valueObject;

            if(fieldValue != null){
                if( rule.PointConversionMode__c == 'Multiplier'){
                    points.TotalPoints__c = (rule.ConversionValue__c * fieldValue).round(RoundingMode.HALF_UP );
                }else if(rule.PointConversionMode__c == 'Factor'){
                    points.TotalPoints__c = (fieldValue / rule.ConversionValue__c).round(RoundingMode.HALF_UP );
                }else if(rule.PointConversionMode__c == 'Custom'){
                    points.TotalPoints__c = fieldValue.round(RoundingMode.HALF_UP );
                }
            }else{
                points.TotalPoints__c = 0;
            }
        }

        if(rule.MonthsUntilExpiration__c != null && rule.MonthsUntilExpiration__c > 0){
            points.ExpirationDate__c = Date.newInstance(t.Date__c.year(), t.Date__c.month(), t.Date__c.day()).addMonths( Integer.ValueOf(rule.MonthsUntilExpiration__c) );
        }
    }

    private static RedemptionService.MemberRewardWrapper getInstantReward(Rule__c rule, Transaction__c tran, SObject record){
        Id rewardId;
        if(rule.RewardMode__c == 'Fixed Value'){
            rewardId = rule.InstantReward__c;
        }else if(rule.RewardMode__c == 'Specified by Field'){
            rewardId = (Id)record.get(rule.RewardFieldName__c);
        }

        if(rewardId != null){
            return new RedemptionService.MemberRewardWrapper(tran.Member__c, rewardId, tran, rule.StockControl__c);
        }else{
            return null;
        }
    }

    public static String getInjectCondition(Id memberId, String condition){
        List<String> wcComponents = condition.split(';');
        String fieldset = wcComponents[0];
        String whereCondition = wcComponents[1];
        if(memberId != null && !String.isBlank(fieldset)){
            List<String> fieldsList = fieldSet.split(',');
            Member__c member = new MembersSelector(new Set<String>(fieldsList)).selectById(new Set<Id>{memberId})[0];
            for(String field : fieldsList){
                List<String> fieldMeta = field.split(':');
                String apiName = fieldMeta[0];
                String type = fieldMeta[1];
                if(type == 'Text'){
                    whereCondition = whereCondition.replace('[' + apiName + ']', '\'' + (String)member.get(apiName) + '\'');
                }else if(type == 'List'){
                    String listValues = '(';
                    if(!String.isBlank((String)member.get(apiName))){
                        listValues += '\'';
                        listValues += String.join(((String)member.get(apiName)).split(','),'\',\'');
                        listValues += '\'';
                    }else{
                        listValues += null;
                    }
                    listValues += ')';
                    whereCondition = whereCondition.replace('[' + apiName + ']', listValues);
                }
            }
        }else if(!String.isBlank(fieldset)){
            return '';
        }
        return whereCondition;
    }

    public static void usePoints(List<SObject> records, Map<Id,Member__c> membersMap){
        Set<Id> memberIds = new Set<Id>();
        Set<Id> recordIds = new Set<Id>();
        Set<Id> recordIdsWithAudit = new Set<Id>();
        Map<Id,Point__c> pointsToUpdate = new Map<Id,Point__c>();
        Map<Id,Map<Id,List<Point__c>>> membersPoints = new Map<Id,Map<Id,List<Point__c>>>();
        Set<Id> adjustTransactionIds = new Set<Id>();

        Boolean isTransaction = !records.isEmpty() && records.get(0).getSObjectType() == Transaction__c.sObjectType;

        Map<Id,Map<Id,ProgramPointType__c>> pointsTypeByProgram = PointTypeService.getProgramPointTypesByProgram(null);

        for(sObject r : records){
            Boolean transactionNegativeBalance = false;
            if(isTransaction){
                for(ProgramPointType__c ppt : pointsTypeByProgram.get(membersMap.get((Id)r.get('FieloPLT__Member__c')).Program__c).values()){
                    if((Decimal)r.get(ppt.PointType__r.TransactionBalanceField__c) < 0){
                        transactionNegativeBalance = true;
                        break;
                    }
                    if(ppt.AuditPoints__c){
                        recordIdsWithAudit.add((Id)r.get('Id'));
                    }
                }
            }

            if(transactionNegativeBalance || !isTransaction){
                if(isTransaction && r.get('RevertedTransaction__c') != null){
                    adjustTransactionIds.add((Id)r.get('RevertedTransaction__c'));
                }else{
                    memberIds.add((Id)r.get('FieloPLT__Member__c'));
                }
            }
            recordIds.add((Id)r.get('Id'));
        }

        Map<Id,Transaction__c> revertedTransactionsMap;
        if(!adjustTransactionIds.isEmpty()){
            revertedTransactionsMap = new Map<Id,Transaction__c>([SELECT Id, RevertedTransaction__c, (SELECT TotalPoints__c, UsedPoints__c, Balance__c, ExpiredPoints__c, ExpirationDate__c, Member__c, PointType__c FROM Points__r WHERE Status__c = 'Approved' ) FROM Transaction__c WHERE Id in : adjustTransactionIds]);
        }

        if(!memberIds.isEmpty()){
            //look for all the points records related to the members and group them by member
            for(Point__c p : [SELECT TotalPoints__c, UsedPoints__c, ExpiredPoints__c, ExpirationDate__c, Member__c, PointType__c FROM Point__c WHERE (ExpirationDate__c >=: date.today() OR ExpirationDate__c = null) AND Transaction__c != null AND Balance__c > 0 AND Status__c = 'Approved'  AND Member__c IN: memberIds ORDER BY ExpirationDate__c ASC NULLS LAST, CreatedDate]){
                processPoints(membersPoints, p);
            }
        }

        List<PointsUsage__c> poinstAudit = new List<PointsUsage__c>();
        //Get the Redemption/Transaction Points created for audit points (because it can be a negative transaction)
        Map<Id, Map<Id,List<Point__c>>> redTransMap = new Map<Id, Map<Id,List<Point__c>>>();
        //verifica si por lo menos hay algun registro que necesite de auditoria de puntos
        if(!recordIdsWithAudit.isEmpty()){
            for(Point__c p : [SELECT Id, Redemption__c, Transaction__c, PointType__c FROM Point__c WHERE Redemption__c IN: recordIds OR Transaction__c IN : recordIds]){
                Id relationId = p.Redemption__c != null ? p.Redemption__c : (p.Transaction__c != null ? p.Transaction__c : null);
                if(relationId != null){
                    if(redTransMap.containsKey(relationId)){
                        if(redTransMap.get(relationId).containsKey(p.PointType__c)){
                            redTransMap.get(relationId).get(p.PointType__c).add(p);
                        }else{
                            redTransMap.get(relationId).put(p.PointType__c, new List<Point__c>{p});
                        }
                    }else{
                        Map<Id,List<Point__c>> pointsMap = new Map<Id,List<Point__c>>{p.Pointtype__c => new List<Point__c>{p}};
                        redTransMap.put(relationId, pointsMap);
                    }
                }
            }
        }

        //loop the records
        for(sObject r : records){
            //if the map contains the member, that means that the member has points to use
            if(membersPoints.containsKey((Id)r.get('FieloPLT__Member__c'))){
                for(ProgramPointType__c ppt : pointsTypeByProgram.get(membersMap.get((Id)r.get('FieloPLT__Member__c')).Program__c).values()){
                    if((isTransaction && (Decimal)r.get(ppt.PointType__r.TransactionBalanceField__c) != null) || (!isTransaction && (Decimal)r.get(ppt.PointType__r.RedemptionBalanceField__c) != 0)){
                        //bring the points of the member
                        List<Point__c> pointList = membersPoints.get((Id)r.get('FieloPLT__Member__c')).get(ppt.PointType__c);

                        Double pointsToSubstract = isTransaction ? -(Double) r.get(ppt.PointType__r.TransactionBalanceField__c) : (Double) r.get(ppt.PointType__r.RedemptionBalanceField__c);
                        //loop the list of points until all the required points are used
                        while(pointsToSubstract > 0 && !pointList.isEmpty()){
                            Point__c point = pointList.get(0);
                            //If still have points available
                            if(point.UsedPoints__c == null)
                                point.UsedPoints__c = 0;
                            if(point.UsedPoints__c < point.TotalPoints__c){
                                Decimal pointsUsed = 0;
                                //If one record of points is enough for the redemption points
                                if( (point.TotalPoints__c - point.UsedPoints__c) > pointsToSubstract ){
                                    point.UsedPoints__c += pointsToSubstract;
                                    pointsUsed = pointsToSubstract;
                                    pointsToSubstract = 0;
                                } else {
                                    pointsToSubstract -= point.TotalPoints__c - point.UsedPoints__c;
                                    pointsUsed = point.TotalPoints__c - point.UsedPoints__c;
                                    point.UsedPoints__c = point.TotalPoints__c;
                                    pointList.remove(0);
                                }
                                if(ppt.AuditPoints__c){
                                    poinstAudit.add( new PointsUsage__c(Quantity__c = pointsUsed, PointsSource__c = point.Id, UsedPoints__c = redTransMap.get((Id)r.get('Id')).get(ppt.PointType__c)[0].Id ));
                                }
                            }
                            pointsToUpdate.put(point.Id,point);
                        }
                    }
                }
            //negative reverted transactions
            }else if(isTransaction && (Id)r.get('RevertedTransaction__c') != null){
                for(Point__c point : revertedTransactionsMap.get((Id)r.get('RevertedTransaction__c')).Points__r){
                    Point__c pointUpdated = new Point__c(Id = point.Id);
                    pointUpdated.UsedPoints__c = point.UsedPoints__c + point.Balance__c;
                    pointsToUpdate.put(point.Id,pointUpdated);
                    if(pointsTypeByProgram.get(membersMap.get(point.Member__c).Program__c).get(point.PointType__c).AuditPoints__c){
                        poinstAudit.add(new PointsUsage__c(Quantity__c = point.Balance__c, PointsSource__c = point.Id, UsedPoints__c = redTransMap.get((Id)r.get('Id')).get(point.PointType__c)[0].Id));
                    }
                }
            }
        }
        update pointsToUpdate.values();

        if(!poinstAudit.isEmpty()){
            insert poinstAudit;
        }
    }

    private static void processPoints(Map<Id,Map<Id,List<Point__c>>> membersPoints, Point__c point){
        if(membersPoints.containsKey(point.Member__c)){
            if(membersPoints.get(point.Member__c).containsKey(point.PointType__c)){
                membersPoints.get(point.Member__c).get(point.PointType__c).add(point);
            }else{
                membersPoints.get(point.Member__c).put(point.PointType__c, new List<Point__c>{point});
            }
        } else {
            Map<Id,List<Point__c>> pointsMap = new Map<Id,List<Point__c>>{point.PointType__c => new List<Point__c>{point}};
            membersPoints.put(point.Member__c, pointsMap);
        }
    }

    public static Boolean appliesIncentives(Id segmentId, Member__c member, Map<Id,Segment__c> mapSegments, Map<Id,List<CriterionGroup__c>> criteriaGroupsMap){
        if(segmentId != null){
            Segment__c segment = mapSegments.get(segmentId);

            Boolean applySegment;
            if(member.Program__c == segment.Program__c || segment.Program__c == null){
                if(segment.RecordType.DeveloperName != 'Manual'){
                    //TODO: funcionalidad MD
                    List<SObject> criteriaList = new List<SObject>();
                    criteriaList.addAll((List<SObject>)segment.SegmentCriteria__r);
                    if(criteriaGroupsMap.containsKey(segment.Id))
                        criteriaList.addAll((List<SObject>)criteriaGroupsMap.get(segment.Id));

                    applySegment = SObjectService.applyCriteria(criteriaList, member, segment.LogicalExpression__c);
                }else{
                    applySegment = false;
                    for(MemberSegment__c ms : segment.getsObjects('MembersSegments__r')){
                        if(member.Id == ms.Member__c){
                            applySegment = true;
                            break;
                        }
                    }
                }
            }else{
                applySegment = false;
            }

            if(applySegment)
                return true;
            return false;
        }else{
            return true;
        }
    }

    public static Boolean testPersonAccountEnabled = false;
    public static Boolean isPersonAccountEnabled(){
        if(System.Test.isRunningTest()){
            return testPersonAccountEnabled;
        }
        Map<String, Schema.SObjectField> M = Schema.SObjectType.Account.fields.getMap();
        //Boolean flag to detect person account enabled or not
        Boolean isPersonAccountEnabled = M.containsKey('IsPersonAccount');
        return isPersonAccountEnabled;
    }

    public static Decimal getPerformanceValue(sObject record, String objectiveType){
        Decimal aux = 0;
        if(objectiveType == 'Counter' && record.get('Counter__c') != null){
            aux += (Decimal)record.get('Counter__c') ;
        }else if(objectiveType == 'Max Value' && record.get('MaxValue__c') != null){
            aux += (Decimal)record.get('MaxValue__c') ;
        }else if(objectiveType == 'Summary' && record.get('Summary__c') != null){
            aux += (Decimal)record.get('Summary__c') ;
        }else if(objectiveType == 'Average' && record.get('Average__c') != null){
            aux += (Decimal)record.get('Average__c') ;
        }
        return aux;
    }

}
