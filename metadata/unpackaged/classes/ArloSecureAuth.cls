/**
 * ArloSecureAuth
 *
 * Secure authentication handler for Arlo API.
 * Supports multiple auth methods in order of preference:
 * 1. Named Credential (most secure - recommended for production)
 * 2. Custom Settings with encrypted password (legacy support)
 *
 * Named Credential Setup:
 * 1. Setup > Named Credentials > New Named Credential
 * 2. Label: Arlo API, Name: Arlo_API
 * 3. URL: https://lifeeducationtrust.arlo.co
 * 4. Identity Type: Named Principal
 * 5. Authentication Protocol: Password Authentication
 * 6. Username/Password: Your Arlo credentials
 */
public with sharing class ArloSecureAuth {

    // Named Credential name (create in Setup > Named Credentials)
    public static final String NAMED_CREDENTIAL = 'Arlo_API';

    // Base path for API (used with Named Credential)
    public static final String API_PATH = '/api/2012-02-01/auth';

    // Full URL for legacy auth
    public static final String FULL_BASE_URL = 'https://lifeeducationtrust.arlo.co/api/2012-02-01/auth';

    /**
     * Authentication mode
     */
    public enum AuthMode {
        NAMED_CREDENTIAL,  // Uses Salesforce Named Credential (secure, password never in Apex)
        CUSTOM_SETTING,    // Uses Arlo_Credentials__c custom setting (legacy)
        PROVIDED           // Credentials provided directly (testing only)
    }

    private AuthMode mode;
    private String username;
    private String password;

    /**
     * Private constructor - use factory methods
     */
    private ArloSecureAuth(AuthMode mode, String username, String password) {
        this.mode = mode;
        this.username = username;
        this.password = password;
    }

    /**
     * Get auth instance using best available method
     */
    public static ArloSecureAuth getInstance() {
        // Try Named Credential first (most secure)
        if (isNamedCredentialConfigured()) {
            return new ArloSecureAuth(AuthMode.NAMED_CREDENTIAL, null, null);
        }

        // Fall back to Custom Setting
        Arlo_Credentials__c creds = Arlo_Credentials__c.getOrgDefaults();
        if (creds != null && String.isNotBlank(creds.Username__c) && String.isNotBlank(creds.Password__c)) {
            System.debug('ArloSecureAuth: Using Custom Settings (consider migrating to Named Credential for better security)');
            return new ArloSecureAuth(AuthMode.CUSTOM_SETTING, creds.Username__c, creds.Password__c);
        }

        throw new ArloAuthException('No Arlo credentials configured. Set up Named Credential "Arlo_API" or Arlo_Credentials__c custom setting.');
    }

    /**
     * Get auth instance with provided credentials (for testing)
     */
    public static ArloSecureAuth withCredentials(String username, String password) {
        if (String.isBlank(username) || String.isBlank(password)) {
            return getInstance();
        }
        return new ArloSecureAuth(AuthMode.PROVIDED, username, password);
    }

    /**
     * Check if Named Credential is configured
     */
    private static Boolean isNamedCredentialConfigured() {
        try {
            // Try to query for the Named Credential
            List<NamedCredential> ncs = [
                SELECT Id, DeveloperName
                FROM NamedCredential
                WHERE DeveloperName = :NAMED_CREDENTIAL
                LIMIT 1
            ];
            return !ncs.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Get the authentication mode being used
     */
    public AuthMode getMode() {
        return mode;
    }

    /**
     * Build endpoint URL based on auth mode
     */
    public String buildEndpoint(String path) {
        if (mode == AuthMode.NAMED_CREDENTIAL) {
            // Named Credential format: callout:NamedCredential/path
            String cleanPath = path.startsWith('/') ? path : '/' + path;
            if (!cleanPath.startsWith(API_PATH)) {
                cleanPath = API_PATH + cleanPath;
            }
            return 'callout:' + NAMED_CREDENTIAL + cleanPath;
        }

        // Custom Setting or Provided - use full URL
        if (path.startsWith('http')) {
            return path;
        }
        return FULL_BASE_URL + (path.startsWith('/') ? path : '/' + path);
    }

    /**
     * Configure HttpRequest with authentication
     */
    public HttpRequest configureRequest(HttpRequest req) {
        // Named Credential automatically adds auth header
        if (mode != AuthMode.NAMED_CREDENTIAL && String.isNotBlank(username) && String.isNotBlank(password)) {
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(username + ':' + password));
            req.setHeader('Authorization', authHeader);
        }
        return req;
    }

    /**
     * Make a GET request
     */
    public HttpResponse get(String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(buildEndpoint(path));
        req.setMethod('GET');
        req.setHeader('Accept', 'application/xml');
        req.setTimeout(30000);
        configureRequest(req);

        return new Http().send(req);
    }

    /**
     * Get XML response, returns null on error
     */
    public String getXml(String path) {
        try {
            HttpResponse res = get(path);
            if (res.getStatusCode() == 200) {
                return res.getBody();
            }
            System.debug('ArloSecureAuth: HTTP ' + res.getStatusCode() + ' for ' + path);
            return null;
        } catch (Exception e) {
            System.debug('ArloSecureAuth: Error - ' + e.getMessage());
            return null;
        }
    }

    /**
     * Check remaining callouts
     */
    public static Integer getRemainingCallouts() {
        return Limits.getLimitCallouts() - Limits.getCallouts();
    }

    public class ArloAuthException extends Exception {}
}