/**
 * ArloHttpService
 * 
 * Shared utility class for building HTTP requests to Arlo API.
 * Centralizes HTTP request creation to reduce code duplication.
 * 
 * @author System Generated
 * @version 1.0
 */
public with sharing class ArloHttpService {
    
    // Arlo API Configuration
    public static final String ARLO_API_BASE_URL = 'https://lifeeducationtrust.arlo.co/api/2012-02-01/auth';
    private static final Integer DEFAULT_TIMEOUT = 30000; // 30 seconds
    
    /**
     * Create a basic HTTP request for Arlo API
     * 
     * @param endpoint The API endpoint (relative or full URL)
     * @param method HTTP method (GET, POST, etc.)
     * @param username Arlo username for Basic Auth
     * @param password Arlo password for Basic Auth
     * @return Configured HttpRequest object
     */
    public static HttpRequest createRequest(String endpoint, String method, String username, String password) {
        return createRequest(endpoint, method, username, password, DEFAULT_TIMEOUT);
    }
    
    /**
     * Create a basic HTTP request for Arlo API with custom timeout
     * 
     * @param endpoint The API endpoint (relative or full URL)
     * @param method HTTP method (GET, POST, etc.)
     * @param username Arlo username for Basic Auth
     * @param password Arlo password for Basic Auth
     * @param timeout Timeout in milliseconds
     * @return Configured HttpRequest object
     */
    public static HttpRequest createRequest(String endpoint, String method, String username, String password, Integer timeout) {
        HttpRequest req = new HttpRequest();
        
        // Build full URL if endpoint is relative
        if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
            req.setEndpoint(endpoint);
        } else {
            req.setEndpoint(ARLO_API_BASE_URL + endpoint);
        }
        
        req.setMethod(method);
        req.setHeader('Accept', 'application/xml');
        
        // Basic Authentication
        if (String.isNotBlank(username) && String.isNotBlank(password)) {
            Blob authBlob = Blob.valueOf(username + ':' + password);
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
            req.setHeader('Authorization', authHeader);
        }
        
        req.setTimeout(timeout != null ? timeout : DEFAULT_TIMEOUT);
        
        return req;
    }
    
    /**
     * Execute HTTP request and return response
     * 
     * @param req HttpRequest object
     * @return HttpResponse object
     */
    public static HttpResponse sendRequest(HttpRequest req) {
        Http http = new Http();
        return http.send(req);
    }
    
    /**
     * Create and execute a GET request in one call
     * 
     * @param endpoint The API endpoint (relative or full URL)
     * @param username Arlo username for Basic Auth
     * @param password Arlo password for Basic Auth
     * @return HttpResponse object
     */
    public static HttpResponse get(String endpoint, String username, String password) {
        HttpRequest req = createRequest(endpoint, 'GET', username, password);
        return sendRequest(req);
    }
    
    /**
     * Build full URL from relative endpoint
     * 
     * @param endpoint Relative endpoint (e.g., '/resources/contacts/100/')
     * @return Full URL
     */
    public static String buildUrl(String endpoint) {
        if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
            return endpoint;
        }
        return ARLO_API_BASE_URL + endpoint;
    }
}
