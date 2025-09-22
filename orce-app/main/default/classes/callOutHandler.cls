public class CallOutHandler {

    public static void createLog(String endpoint, String method, Integer statusCode, String contentType, String requestBody, String responseBody) {
        // Customize this method to suit your logging requirements
        System.debug('Creating log for the callout:');
        System.debug('Endpoint: ' + endpoint);
        System.debug('Method: ' + method);
        System.debug('Status Code: ' + statusCode);
        System.debug('Content Type: ' + contentType);
        System.debug('Request Body: ' + requestBody);
        System.debug('Response Body: ' + responseBody);
        // Add your custom logic here to save logs or perform other actions
    }

    public static void logException(String endpoint, String method, Integer statusCode, String contentType, String requestBody, String responseBody, Exception e){
        Netsuite_log__c nsLog = new Netsuite_Log__c();
        nsLog.message__c = 'Endpoint: ' + endpoint 
        + ' exception ' + e
        + ' Method: ' + method 
        + ' Status Code: ' + statusCode 
        + ' Request Body: ' + requestBody
        + ' Response Body: ' + responseBody;
        insert nsLog;
    }

    public static void routeResponse(String responseBody, String destination) {
        // Customize this method to suit your response routing requirements
        System.debug('Routing response to: ' + destination);
        // Add your custom logic here to process the response or perform other actions
    }
}
