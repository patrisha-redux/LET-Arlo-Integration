/**
 * ArloApiClient
 *
 * Single responsibility: HTTP communication with Arlo API.
 * All callouts go through this class for consistent auth, error handling, and logging.
 */
public with sharing class ArloApiClient {

    public static final String BASE_URL = 'https://lifeeducationtrust.arlo.co/api/2012-02-01/auth';
    private static final Integer TIMEOUT_MS = 30000;

    private String username;
    private String password;

    public ArloApiClient(String username, String password) {
        this.username = username;
        this.password = password;
    }

    /**
     * Load credentials from custom settings
     */
    public static ArloApiClient fromCustomSettings() {
        Arlo_Credentials__c creds = Arlo_Credentials__c.getOrgDefaults();
        if (creds == null || String.isBlank(creds.Username__c) || String.isBlank(creds.Password__c)) {
            throw new ArloApiException('Arlo credentials not configured. Set up Arlo_Credentials__c custom setting.');
        }
        return new ArloApiClient(creds.Username__c, creds.Password__c);
    }

    /**
     * Make GET request to Arlo API
     */
    public HttpResponse get(String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint.startsWith('http') ? endpoint : BASE_URL + endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/xml');
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(username + ':' + password)));
        req.setTimeout(TIMEOUT_MS);

        return new Http().send(req);
    }

    /**
     * Get XML response body, returns null on error
     */
    public String getXml(String endpoint) {
        try {
            HttpResponse res = get(endpoint);
            if (res.getStatusCode() == 200) {
                return res.getBody();
            }
            System.debug('ArloApiClient: HTTP ' + res.getStatusCode() + ' for ' + endpoint);
            return null;
        } catch (Exception e) {
            System.debug('ArloApiClient: Error fetching ' + endpoint + ': ' + e.getMessage());
            return null;
        }
    }

    /**
     * Get remaining callouts in current transaction
     */
    public static Integer getRemainingCallouts() {
        return Limits.getLimitCallouts() - Limits.getCallouts();
    }

    /**
     * Check if we have enough callouts remaining
     */
    public static Boolean hasCalloutsRemaining(Integer needed) {
        return getRemainingCallouts() >= needed;
    }

    public class ArloApiException extends Exception {}
}