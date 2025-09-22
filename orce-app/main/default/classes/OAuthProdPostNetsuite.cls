global class OAuthProdPostNetsuite {

    //private OAuth_Service__c service;

    private static String token;

    private static String tokenSecret;

    private static Boolean isAccess;

    private static String verifier;

    private static String nonce;

    private static String timestamp;

    private static String signature;

    private static String realm;

    private static String consumerKey;

    private static String consumerSecret;

    private static String oauthversion;
    //public String prodId;
    private static Map<String,String> parameters = new Map<String,String>();

    private static Map<String, Integer> subsidiaryMap = new Map<String, Integer>{
        'The Futurum Group' => 1,
        'Visible Impact, LLC' => 2,
        'Evaluator Group, LLC' => 4,
        'Dash Network, JV' => 5,
        'Futurum, LLC' => 6,
        'Wainhouse Research, LLC' => 7
    };

    //public static void processAfterInsert(Id prodId) {
        // Use the prodId in your SOQL query
        
    //}

    public static String message { get; set; }
    

    /**

     * Looks up service name and starts a new authorization process

     * returns the authorization URL that the user should be redirected to

     * If null is returned, the request failed. The message property will contain

     * the reason.

     */ 
    @future(callout=true)
    public static void newAuthorization(String serviceName, String productId, Boolean isCreate) {
        
    OAuth_Service__c service = [SELECT realm__c, request_token_url__c, access_token_url__c, consumer_key__c, 
                      consumer_secret__c, authorization_url__c,
                      (select token__c, secret__c, isAccess__c FROM tokens__r ) 
                      FROM OAuth_Service__c WHERE name = :serviceName LIMIT 1];

    if (service == null) {
        System.debug('Couldn\'t find Oauth Service ' + serviceName);
        message = 'Service ' + serviceName + ' was not found in the local configuration';
        return; // Add this line to exit the method if the service is not found
    }
    Product2 prod = [SELECT Id, Name, NS_Deferred_Revenue_Account__c, NS_Account_Name__c, IsActive, celigo_sfnsio__NetSuite_Id__c FROM Product2 WHERE Id = :productId LIMIT 1];
    
        Http h = new Http();

        HttpRequest req = new HttpRequest();
        if(isCreate)
        {
            req.setMethod('POST');
            req.setEndpoint(service.request_token_url__c);
        }
        else
        {
            req.setMethod('PATCH');
            String endpoint = service.request_token_url__c + '/' + prod.celigo_sfnsio__NetSuite_Id__c;
            req.setEndpoint(endpoint);  
        }
        req.setHeader('Accept', 'application/json'); // Add this line
        req.setHeader('Content-Type', 'application/json');
        System.debug('Request body set to: ' + req.getBody());

        realm = service.Realm__c;

        consumerKey = service.consumer_key__c;

        consumerSecret = service.consumer_secret__c;

        token = service.Tokens__r[0].isAccess__c ? service.Tokens__r[0].Token__c : '';

        tokenSecret = service.Tokens__r[0].isAccess__c ? service.Tokens__r[0].Secret__c : '';

        // Your payload
        String deferredrevenueaccount = '';
        if(prod.NS_Deferred_Revenue_Account__c !=null)
        {
            deferredrevenueaccount = '"deferredrevenueaccount": "'+prod.NS_Deferred_Revenue_Account__c+'", ';
        }
        String payload = '{"itemId": "'+prod.name+'", "incomeaccount": "'+prod.NS_Account_Name__c+'", '+deferredrevenueaccount+' "custitem_celigo_sfio_sf_id": "'+prod.id+'"}';
        req.setBody(payload);
        
        sign(req);

        HttpResponse res = null;

            try{
                res = h.send(req);
                system.debug('req '+req.getHeader('Authorization'));
                system.debug('res '+res);
                system.debug('resp body '+res.getBody());
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');
                if(isCreate)
                {
                    String href = ( res.getHeader('Location') );
                    if(href != null)
                        {
                            URL url = new URL(href);
                            String[] urlParts = url.getPath().split('/');

                            // Get the last element of the array
                            String netsuiteId = urlParts[urlParts.size() - 1];
                            prod.celigo_sfnsio__NetSuite_Id__c = netsuiteId;
                            update prod;
                        }
                }
            }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
            }

        System.debug('Response from request token request: ('+res.getStatusCode()+')'+res.getBody());

        if(res.getStatusCode()>299) {

            message = 'Request failed. HTTP Code = '+res.getStatusCode()+

                      '. Message: '+res.getStatus()+'. Response Body: '+res.getBody();

        }
    

    }

    @future(callout=true)
    public static void createSale(String serviceName, String acctId, String opptyId)
    {
        Boolean updateOppty = false;
        Boolean updateAcct = false;
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        Account acct = [SELECT Id, Name, Phone, celigo_sfnsio__NetSuite_Id__c FROM Account WHERE Id = :acctId LIMIT 1];
        Opportunity oppty = [SELECT Id, Name, celigo_sfnsio__NetSuite_Id__c, AccountId, CloseDate, subsidiary__c, terms__c, Other_Billing_Terms__c, Payment_Terms__c, Number_of_InstallmentsMilestones__c FROM Opportunity WHERE Id = :opptyId LIMIT 1];
        String subsidiaryValue = String.valueOf(subsidiaryMap.get(oppty.subsidiary__c));

        if(service != null){
            if(acct.celigo_sfnsio__NetSuite_Id__c == null)
            {
                Http h = new Http();

                HttpRequest req = new HttpRequest();
                req.setMethod('POST');
                String endpoint = service.customer_endpoint__c;
                req.setEndpoint(endpoint);  
                req.setHeader('Accept', 'application/json'); // Add this line
                req.setHeader('Content-Type', 'application/json');
                req.setTimeout(120000); // Set timeout to 120 seconds (120000 milliseconds)

                realm = service.Realm__c;
                consumerKey = service.consumer_key__c;
                consumerSecret = service.consumer_secret__c;
                token = service.Tokens__r[0].isAccess__c ? service.Tokens__r[0].Token__c : '';
                tokenSecret = service.Tokens__r[0].isAccess__c ? service.Tokens__r[0].Secret__c : '';
                // Your payload
                String acctPhoneValue = '';
                if(acct.phone != null)
                {
                    acctPhoneValue = acct.phone;
                }
                String payload = '{"entityid": "'+acct.name+'","companyName": "'+acct.name+'", "phone": "'+acctPhoneValue+'", "custentity_celigo_sfio_sf_id": "'+acct.id+'", "subsidiary": { "id": "1"} }';
                req.setBody(payload);               

                sign(req);
        
                HttpResponse res = null;
        
                    try
                    {
                        res = h.send(req);
                        callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                        callOutHandler.routeResponse(res.getBody(), 'netsuite');
                        String href = ( res.getHeader('Location') );
                        if(href != null)
                        {
                            URL url = new URL(href);
                            String[] urlParts = url.getPath().split('/');
        
                            // Get the last element of the array
                            String netsuiteId = urlParts[urlParts.size() - 1];
                            acct.celigo_sfnsio__NetSuite_Id__c = netsuiteId;
                            updateAcct = true;
                            createCustomerSubsidiaryRelation(serviceName, netsuiteId, '6');
                        }
                    }
                    catch(exception e) {
                        system.debug('exception '+e);
                        callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                        if(res!= null)
                        {
                            callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                        }
                        else{
                            callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                        }   
                        if(updateAcct)
                        {
                            update acct;
                        }            
                    }
        
                
        
                System.debug('Response from request token request: ('+res.getStatusCode()+')'+res.getBody());
        
                if(res.getStatusCode()>299) {
        
                    message = 'Request failed. HTTP Code = '+res.getStatusCode()+
        
                              '. Message: '+res.getStatus()+'. Response Body: '+res.getBody();
        
                }
                
            }

            List<Opportunitylineitem> OppLines = new List<OpportunityLineItem>();
            if(oppty.celigo_sfnsio__NetSuite_Id__c == null)
            {
                // Your opportunity payload
                String itemsPayload = getOpportunityProductPayload(opptyId);
                System.debug('Oppty payload2='+ itemsPayload);
                String billingTermsPayLoad = '';
                if(oppty.Terms__c != null)
                {
                    billingTermsPayLoad = '"custbodybillingterms": "'+oppty.Terms__c+'", '; 
                }
                if(oppty.Other_Billing_Terms__c != null)
                {

                    billingTermsPayLoad = billingTermsPayLoad + '"custbodyotherbillingterms": "'+oppty.Other_Billing_Terms__c+'", ';
                }
                if(oppty.Payment_Terms__c  != null)
                {

                    billingTermsPayLoad = billingTermsPayLoad + '"custbodypaymentterms": "'+oppty.Payment_Terms__c+'", ';
                }
                if(oppty.Number_of_InstallmentsMilestones__c  != null)
                {

                    billingTermsPayLoad = billingTermsPayLoad + '"custbodynumberofinstallments": '+oppty.Number_of_InstallmentsMilestones__c+', ';
                }
                String payload = '{"entity": {"id":"'+acct.celigo_sfnsio__NetSuite_Id__c+'"}, "custbody_celigo_sfio_sf_id": "'+oppty.Id+'", "custitem_celigo_sfio_sf_id": "'+acct.id+'", "subsidiary": { "id": "'+subsidiaryValue+'" }, '+ billingTermsPayLoad + itemsPayload+' }';
                System.debug('Oppty payload3='+ payload);
                HttpRequest req = createRequest('POST', service.salesOrder_endpoint__c, payload);

                Http h = new Http();
                setauthorizationParams(service);
                //req.setBody(payload);             

                sign(req);
        
                HttpResponse res = null;
        
                    try
                    {
                        res = h.send(req);
                        callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                        callOutHandler.routeResponse(res.getBody(), 'netsuite');
                        String href = ( res.getHeader('Location') );
                        if(href != null)
                        {
                            URL url = new URL(href);
                            String[] urlParts = url.getPath().split('/');
        
                            // Get the last element of the array
                            String netsuiteId = urlParts[urlParts.size() - 1];
                            oppty.celigo_sfnsio__NetSuite_Id__c = netsuiteId;
                            updateOppty = true;
                            //update oppty;
                            List<String> lineItemIds = getSalesItemIds(serviceName, netsuiteId);
                            for(String lineItemId:  lineItemIds)
                            {
                                Opportunitylineitem OppLine = getSalesItemOpportunityLineItem(serviceName, netsuiteId, lineItemId);
                                OppLines.add(OppLine);
                            }
                        }
                    }
                    catch(exception e) {
                        system.debug('exception '+e);
                        if(res!= null)
                        {
                            callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                            callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                        }
                        else{
                            callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                        }   
                        if(updateAcct)
                        {
                            update acct;
                        }
                        if(updateOppty)
                        {
                            update oppty;
                            update oppLines;
                        }            
                    }         
            }
            if(updateAcct)
            {
                update acct;
            }
            if(updateOppty)
            {
                update oppty;
                update oppLines;
            }
        }
    } 
    
    public static void createCustomerSubsidiaryRelation(String serviceName, String NetsuiteCustomerId, String NetsuiteSubsidiary){
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        String payload = '{"entity": "'+NetsuiteCustomerId+'", "subsidiary": "'+NetsuiteSubsidiary+'"}';
        HttpRequest req = createRequest('POST', service.customerSubsidiary_endpoint__c, payload);
        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;
            try
            {
                res = h.send(req);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');
            }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
                throw e;
            }
    }

    public static List<String> getInvoiceIds(String serviceName){
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        List<String> invoiceIds = new List<String>();
        HttpRequest req = createRequest('GET', service.invoice_endpoint__c, null);
        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;
            try
            {
                res = h.send(req);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');
                // Convert JSON string to a Map
                Map<String, Object> jsonObject = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                // Access the 'item' object from the JSON
                List<Object> items = (List<Object>)jsonObject.get('items');
                // If the 'item' object is not null, extract its ID
                for(Object itemObject: items){
                    Map<String, Object> itemMap = (Map<String, Object>)itemObject;
                    String id = (String)itemMap.get('id');
                    invoiceIds.add(id);
                }
                
            }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
            }

        
        return invoiceIds;
    }

  public static Invoice__c createSFInvoice(String serviceName, String invoiceId)
  {
    Invoice__c sfInvoice = new Invoice__c();
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
    String invoiceDetailEndpoint = service.invoice_endpoint__c + '/' + invoiceId;
        HttpRequest req = createRequest('GET', invoiceDetailEndpoint, null);
        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;
            try
            {
                res = h.send(req);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');
                // Convert JSON string to a Map
                Map<String, Object> jsonObject = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                // Access the 'item' object from the JSON
                Map<String, Object> accountMap = (Map<String, Object>)jsonObject.get('entity');
        String accountId = (String)accountMap.get('id');
        String trandate = (String)jsonObject.get('tranDate');
        String OpportunityId = (String)jsonObject.get('custbody_celigo_sfio_sf_id');
        sfInvoice = getInvoiceObj(accountId, OpportunityId, tranDate, invoiceId);
        System.debug('accountid'+accountId + 'trandate' + tranDate);
            }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
            }
        
    return sfInvoice;
    }

  public static List<String> getInvoiceItemIds(String serviceName, String invoiceId){
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        List<String> invoiceItemIds = new List<String>();
    String invoiceItemsEndpoint = service.invoice_endpoint__c + '/' + invoiceId + '/item';
    
        HttpRequest req = createRequest('GET', invoiceItemsEndpoint, null);
        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;
            try
            {
                res = h.send(req);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');
                // Convert JSON string to a Map
                Map<String, Object> jsonObject = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                // Access the 'item' object from the JSON
                List<Object> items = (List<Object>)jsonObject.get('items');
                // If the 'item' object is not null, extract its ID
                for(Object itemObject: items){
                    Map<String, Object> itemMap = (Map<String, Object>)itemObject;          
                    List<Object> links = (List<Object>)itemMap.get('links');
          for(Object link: links)
          {
            Map<String, Object> linkMap = (Map<String, Object>)link;
            String href = (String)LinkMap.get('href');
            if(href != null)
                        {
                            URL url = new URL(href);
                            String[] urlParts = url.getPath().split('/');
                            // Get the last element of the array
                            String itemId = urlParts[urlParts.size() - 1];
              invoiceItemIds.add(itemId);
                        }

          }
        }
                
            }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
            }

        
        return invoiceItemIds;
    }

  public static Invoice_Line_Item__c createSFInvoiceItem(String serviceName, String invoiceId, String itemId)
  {
    Invoice_Line_Item__c invoiceItem = new Invoice_Line_Item__c();
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
    String invoiceDetailEndpoint = service.invoice_endpoint__c + '/' + invoiceId + '/item/' + itemId;
        HttpRequest req = createRequest('GET', invoiceDetailEndpoint, null);
        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;
             try
            {
                res = h.send(req);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');
                // Convert JSON string to a Map
                Map<String, Object> jsonObject = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                // Access the 'item' object from the JSON
        Decimal qty = (Decimal)jsonObject.get('quantity');
        Decimal rate = (Decimal)jsonObject.get('rate');
                String opplinItemId = null;
                if(jsonObject.get('custcol_celigo_sfio_sf_id')!=null)
                {
                    opplinItemId = (String)jsonObject.get('custcol_celigo_sfio_sf_id');
                }
                Map<String, Object> itemMap = (Map<String, Object>)jsonObject.get('item');
        String productId = (String)itemMap.get('id');

        invoiceItem = getInvoiceItemObject(invoiceId, productId, rate, qty, opplinItemId);
        System.debug('itemId'+itemId + 'rate' + rate);
            }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
            }
        
    return invoiceItem;
    }

  private static Invoice__c getInvoiceObj(String accounId, String OpportunityId, String tranDate, String NetsuiteInvoiceId){
    Invoice__c invoice = new Invoice__c();
    Account acct = [Select Id from Account where celigo_sfnsio__NetSuite_Id__c = : accounId];
    invoice.Account__c = acct.id;
    invoice.Opportunity__c = OpportunityId;
    invoice.invoice_date__c = Date.valueOf(trandate);
    invoice.Netsuite_ID__c = NetsuiteInvoiceId;
    return invoice;
  }

  private static Invoice_Line_Item__c getInvoiceItemObject(String invoiceId, String ns_productId, Decimal rate, Decimal qty, String oppLineItemId){
    Invoice_Line_Item__c invoiceItem = new Invoice_Line_Item__c();
    Product2 prod = [Select Id from Product2 where celigo_sfnsio__NetSuite_Id__c = : ns_productId];
    invoiceItem.ProductService__c = prod.id;
    invoiceItem.quantity__c = qty;
    invoiceItem.rate__c = rate;
        if(opplineItemId != null)
        {
            invoiceItem.Opportunity_Product__c = oppLineItemId;
        }
        return invoiceItem;
  }

    public static List<String> getSalesItemIds(String serviceName, String salesOrderId)
    {
        List<String> netsuiteIds = new List<String>();
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        String salesOrderEndpoint = service.salesOrder_endpoint__c + '/' + salesOrderId + '/item';
        HttpRequest req = createRequest('GET', salesOrderEndpoint, null);
        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;

        try{
                res = h.send(req);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');

                // Convert JSON string to a Map
                Map<String, Object> jsonObject = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                // Access the 'item' object from the JSON
                List<Object> items = (List<Object>)jsonObject.get('items');
                // If the 'item' object is not null, extract its ID
                for(Object itemObject: items){
                    Map<String, Object> itemMap = (Map<String, Object>)itemObject;          
                    List<Object> links = (List<Object>)itemMap.get('links');
          for(Object link: links)
          {
            Map<String, Object> linkMap = (Map<String, Object>)link;
            String href = (String)LinkMap.get('href');
            if(href != null)
                        {
                            URL url = new URL(href);
                            String[] urlParts = url.getPath().split('/');
                            // Get the last element of the array
                            String itemId = urlParts[urlParts.size() - 1];
              netsuiteIds.add(itemId);
                        }

          }
                }
           }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
            }

            if(res.getStatusCode()>299) {
            message = 'Request failed. HTTP Code = '+res.getStatusCode()+
                      '. Message: '+res.getStatus()+'. Response Body: '+res.getBody();
            }
            
            return netsuiteIds;
    }

    public static OpportunityLineItem getSalesItemOpportunityLineItem(String serviceName, String salesOrderId, String salesLineId)
    {
        Opportunitylineitem oppLineItem = new OpportunityLineItem();
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        String salesOrderEndpoint = service.salesOrder_endpoint__c + '/' + salesOrderId + '/item/' + salesLineId;
        HttpRequest req = createRequest('GET', salesOrderEndpoint, null);
        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;

        try{
                res = h.send(req);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                callOutHandler.routeResponse(res.getBody(), 'netsuite');

                // Convert JSON string to a Map
                Map<String, Object> jsonObject = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                // Access the 'item' object from the JSON
                String lineNum = String.valueOf((Integer)jsonObject.get('line'));
                String oppItemsSFId = (String)jsonObject.get('custcol_celigo_sfio_sf_id');
                oppLineItem.id = oppItemsSFId;
                oppLineItem.SF_Netsuite_ID__c = lineNum;
           }
            catch(exception e) {
                system.debug('exception '+e);
                callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                if(res!= null)
                {
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                }
                else{
                    callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                }   
            }

            if(res.getStatusCode()>299) {
            message = 'Request failed. HTTP Code = '+res.getStatusCode()+
                      '. Message: '+res.getStatus()+'. Response Body: '+res.getBody();
            }
            
            return opplineItem;
    }


    @future(callout=true)
    public static void updateSalesItem(String serviceName, String OppLineId){
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        OpportunityLineItem OppLine = [Select Quantity, UnitPrice, Total_Product_Price__c, Estimated_Billing_Date__c, Netsuite_Line_Item_Actual_Billing_Date__c, SF_Netsuite_ID__c, Total_Amount_After_Discount__c, Change_Order_Reason__c, Opportunity.celigo_sfnsio__NetSuite_Id__c, Practice_Area__c, Business_Unit__c from OpportunityLineItem  where id = : OppLineId limit 1];

        String salesItemendpoint = service.salesOrder_endpoint__c + '/' +OppLine.Opportunity.celigo_sfnsio__NetSuite_Id__c+ '/item/' +  OppLine.SF_Netsuite_ID__c;
        String billDatesPayload = '';
        if(OppLine.Estimated_Billing_Date__c != null)
        {
            Date estimatedBillDate = OppLine.Estimated_Billing_Date__c;
            Datetime billDateDt = DateTime.newInstance(estimatedBillDate.year(), estimatedBillDate.month(), estimatedBillDate.day());
            String estimatedBillDateStr = billDateDt.format('yyyy-MM-dd');
            billDatesPayload = '"custcolestimated_billing_date": "'+estimatedBillDateStr+'", ';
        }
        if(OppLine.Netsuite_Line_Item_Actual_Billing_Date__c != null)
        {
            Date actualBillDate = OppLine.Netsuite_Line_Item_Actual_Billing_Date__c;
            Datetime actualBillDt = DateTime.newInstance(actualBillDate.year(), actualBillDate.month(), actualBillDate.day());
            String actualBillDateStr = actualBillDt.format('yyyy-MM-dd');
            billDatesPayload = billDatesPayload + '"custcolactual_billing_date_sf": "'+actualBillDateStr+'", ';
        }
        /*String totalAfterDiscount = '';
        if(oppline.Total_Amount_After_Discount__c != null)
        {            
            totalAfterDiscount = String.valueOf(oppline.Total_Amount_After_Discount__c);
        }*/
        String classStr = '';
        if(oppline.Practice_Area__c != null)
        {
            classStr = '"Class": "'+oppline.Practice_Area__c+'", ';
        }
        String department = '';
        if(oppline.Business_Unit__c != null)
        {
            department = '"Department": "'+oppline.Business_Unit__c+'", ';
        }
        String changOrderReason = '';
        if(OppLine.Change_Order_Reason__c != null){
            changOrderReason = '"custcol1": "'+OppLine.Change_Order_Reason__c+'", ';
        }
        String payload = ' {'+billDatesPayload+changOrderReason+department+classStr+' "quantity": '+OppLine.Quantity+', "rate": '+OppLine.UnitPrice+', "amount": '+OppLine.Total_Product_Price__c+'}';
        HttpRequest req = createRequest('PATCH', salesItemendpoint , payload);

        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;
    
            try
            {
                    res = h.send(req);
                    callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                    callOutHandler.routeResponse(res.getBody(), 'netsuite');
                }
                catch(exception e) {
                    system.debug('exception '+e);
                    callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                    if(res!= null)
                    {
                        callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                    }
                    else{
                        callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                    }
            }
    }

    @future(callout=true)
    public static void updateSale(String serviceName, String OpportunityId){
        OAuth_Service__c service = OAuthProdPostNetsuite.getService(serviceName);
        Opportunity opp = [Select celigo_sfnsio__NetSuite_Id__c, Sales_Order_Actual_Billing_Date__c from Opportunity where id = : OpportunityId limit 1];

        String salesendpoint = service.salesOrder_endpoint__c + '/' +opp.celigo_sfnsio__NetSuite_Id__c;
        String billDatesPayload = '';
        if(opp.Sales_Order_Actual_Billing_Date__c != null)
        {
            Date actualBillDate = opp.Sales_Order_Actual_Billing_Date__c;
            Datetime actualBillDt = DateTime.newInstance(actualBillDate.year(), actualBillDate.month(), actualBillDate.day());
            String actualBillDateStr = actualBillDt.format('yyyy-MM-dd');
            billDatesPayload = billDatesPayload + '"custbodyprojectcompletiondate": "'+actualBillDateStr+'"';
        
        String payload = ' {'+billDatesPayload+'}';
        HttpRequest req = createRequest('PATCH', salesendpoint , payload);

        Http h = new Http();
        setauthorizationParams(service);
        sign(req);

        HttpResponse res = null;
    
            try
            {
                    res = h.send(req);
                    callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                    callOutHandler.routeResponse(res.getBody(), 'netsuite');
                }
                catch(exception e) {
                    system.debug('exception '+e);
                    callOutHandler.createLog(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody());
                    if(res!= null)
                    {
                        callOutHandler.logException(req.getEndpoint(), req.getMethod(), res.getStatusCode(), req.getHeader('Content-Type'), req.getBody(), res.getBody(), e);
                    }
                    else{
                        callOutHandler.logException(req.getEndpoint(), req.getMethod(), null, req.getHeader('Content-Type'), req.getBody(),null, e);
                    }
            }
        }
    }

    private static String getOpportunityProductPayload(String opptyId){
        String payload = '"item": { "items": [';
        List<OpportunityLineItem> opptyLineItems = [SELECT Id, Name, OpportunityId, Product2Id, Product2.celigo_sfnsio__NetSuite_Id__c, Estimated_Billing_Date__c, Netsuite_Line_Item_Actual_Billing_Date__c, Practice_Area__c, Business_Unit__c, Taxable__c, Quantity, UnitPrice, Total_Product_Price__c, Total_Amount_After_Discount__c FROM OpportunityLineItem WHERE OpportunityId = :opptyId];
        for(OpportunityLineItem oli : opptyLineItems){
            String billDatesPayload = '';
            if(oli.Estimated_Billing_Date__c != null)
            {
                Date estimatedBillDate = oli.Estimated_Billing_Date__c;
                Datetime billDateDt = DateTime.newInstance(estimatedBillDate.year(), estimatedBillDate.month(), estimatedBillDate.day());
                String estimatedBillDateStr = billDateDt.format('yyyy-MM-dd');
                billDatesPayload = '"custcolestimated_billing_date": "'+estimatedBillDateStr+'", ';
            }
            if(oli.Netsuite_Line_Item_Actual_Billing_Date__c != null)
            {
                Date actualBillDate = oli.Netsuite_Line_Item_Actual_Billing_Date__c;
                Datetime actualBillDt = DateTime.newInstance(actualBillDate.year(), actualBillDate.month(), actualBillDate.day());
                String actualBillDateStr = actualBillDt.format('yyyy-MM-dd');
                billDatesPayload = billDatesPayload + '"custcolactual_billing_date_sf": "'+actualBillDateStr+'", ';
            }
            /*String totalAfterDiscount = '';
            if(oli.Total_Amount_After_Discount__c != null)
            {            
                totalAfterDiscount = String.valueOf(oli.Total_Amount_After_Discount__c);
            }*/
            String classStr = '';
            if(oli.Practice_Area__c != null)
            {
                classStr = '"Class": "'+oli.Practice_Area__c+'", ';
            }
            String department = '';
            if(oli.Business_Unit__c != null)
            {
                department = '"Department": "'+oli.Business_Unit__c+'", ';
            }
            payload += '{"item": {"id": '+oli.product2.celigo_sfnsio__NetSuite_Id__c+'}, "custcol_celigo_sfio_sf_id": "'+oli.id+'", '+billDatesPayload+department+classStr+'"quantity": '+oli.Quantity+', "rate": '+oli.UnitPrice+', "amount": '+oli.Total_Product_Price__c+'},';
        }
        System.debug('Opp payload='+ payload);
        payload = payload.removeEnd(',');
        payload += '] }';
        System.debug('Opp payload final='+ payload);
        return payload;
    }

    private static OAuth_Service__c getService(String serviceName) {
        OAuth_Service__c service = [SELECT realm__c, request_token_url__c, access_token_url__c, consumer_key__c, customer_endpoint__c, salesOrder_endpoint__c, invoice_endpoint__c,
        consumer_secret__c, authorization_url__c, customerSubsidiary_endpoint__c,
        (select token__c, secret__c, isAccess__c FROM tokens__r ) 
        FROM OAuth_Service__c WHERE name = :serviceName LIMIT 1];
        
        if (service == null) {
            System.debug('Couldn\'t find Oauth Service ' + serviceName);
            message = 'Service ' + serviceName + ' was not found in the local configuration';
            return null; // Add this line to exit the method if the service is not found
        }
        return service;
    }

    private static void setauthorizationParams(Oauth_Service__c service){
        realm = service.Realm__c;
        consumerKey = service.consumer_key__c;
        consumerSecret = service.consumer_secret__c;
        token = service.Tokens__r[0].isAccess__c ? service.Tokens__r[0].Token__c : '';
        tokenSecret = service.Tokens__r[0].isAccess__c ? service.Tokens__r[0].Secret__c : '';
    }

    // Create a new HTTP request with the given endpoint and method
    private static HttpRequest createRequest(String method, String endpoint, String body) {

        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(endpoint);
        req.setHeader('Accept', 'application/json'); 
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000); // Set timeout to 120 seconds (120000 milliseconds)

        if(body != null)
        {
            req.setBody(body);
        }
        return req;

    }


public static List<User> getUsersOfService(String serviceName) {
    List<User> result = new List<User>();
    
    // Declare l outside of the query
    List<tokens__c> l = [SELECT OAuth_Service__r.name, isAccess__c, Owner__r.name FROM tokens__c WHERE OAuth_Service__r.name = :serviceName AND isAccess__c = true];

    for(tokens__c t : l) {
        result.add(t.Owner__r);
    }

    return result;
}


    private static void refreshParameters() {

        parameters.clear();

        parameters.put('realm',realm);

        parameters.put('oauth_consumer_key',consumerKey);

        if(token!=null) {

            parameters.put('oauth_token',token);

        }

        if(verifier!=null) {

            parameters.put('oauth_verifier',verifier);

        }

        parameters.put('oauth_signature_method','HMAC-SHA256');

        parameters.put('oauth_version','1.0');

        parameters.put('oauth_timestamp',timestamp);

        parameters.put('oauth_nonce',nonce);

    }

    private static Map<String,String> getUrlParams(String value) {

        Map<String,String> res = new Map<String,String>();

        if(value==null || value=='') {

            return res;

        }

        for(String s : value.split('&')) {

            System.debug('getUrlParams: '+s);

            List<String> kv = s.split('=');

            if(kv.size()>1) {

              // RFC 5849 section 3.4.1.3.1 and 3.4.1.3.2 specify that parameter names 

              // and values are decoded then encoded before being sorted and concatenated

              // Section 3.6 specifies that space must be encoded as %20 and not +

              String encName = EncodingUtil.urlEncode(EncodingUtil.urlDecode(kv[0], 'UTF-8'), 'UTF-8').replace('+','%20');

              String encValue = EncodingUtil.urlEncode(EncodingUtil.urlDecode(kv[1], 'UTF-8'), 'UTF-8').replace('+','%20');

              System.debug('getUrlParams:  -> '+encName+','+encValue);

              res.put(encName,encValue);

            }

        }

        return res;

    }

    private static String createBaseString(Map<String,String> oauthParams, HttpRequest req) {

        Map<String,String> p = oauthParams.clone();

        p.remove('realm');

        p.remove('deploy');

        p.remove('script');

        for(string k : oauthParams.keySet()){

            system.debug('oauthParams '+k+' '+p.get(k));

        }

        if(req.getMethod().equalsIgnoreCase('post') && req.getBody()!=null && 

           req.getHeader('Content-Type')=='application/x-www-form-urlencoded') {

            p.putAll(getUrlParams(req.getBody()));

        }

        String host = req.getEndpoint();

        Integer n = host.indexOf('?');

        if(n>-1) {

            p.putAll(getUrlParams(host.substring(n+1)));

            host = host.substring(0,n);

        }

        List<String> keys = new List<String>();

        keys.addAll(p.keySet());

        for(string k2 : keys) {

            system.debug('keys '+k2);

        }

        keys.sort();

        String s = keys.get(0)+'='+p.get(keys.get(0));

        for(Integer i=1;i<keys.size();i++) {

            s = s + '&' + keys.get(i)+'='+p.get(keys.get(i));

        }

        // According to OAuth spec, host string should be lowercased, but Google and LinkedIn

        // both expect that case is preserved.

        return req.getMethod().toUpperCase()+ '&' + 

            EncodingUtil.urlEncode(host, 'UTF-8') + '&' +

            EncodingUtil.urlEncode(s, 'UTF-8');

    }

    public static void sign(HttpRequest req) {

        nonce = String.valueOf(Crypto.getRandomLong());

        timestamp = String.valueOf(DateTime.now().getTime()/1000);

        refreshParameters();

        String s = createBaseString(parameters, req);

        System.debug('Token Secret: '+tokenSecret);

        System.debug('Signature base string: '+s);

        Blob sig = Crypto.generateMac('HmacSHA256', Blob.valueOf(s), 

                       Blob.valueOf(consumerSecret+'&'+tokenSecret));      

        signature = EncodingUtil.urlEncode(EncodingUtil.base64encode(sig), 'UTF-8');

        String header = 'OAuth ';

        for (String key : parameters.keySet()) {

            header = header + key + '="'+parameters.get(key)+'", ';

        }

        header = header + 'oauth_signature="'+signature+'"';

        System.debug('Authorization: '+header);

        req.setHeader('Authorization',header);

    }   

}
