/**
 * ArloContactSync
 * 
 * Syncs contacts from Arlo API to Salesforce using Basic Authentication.
 * Gets ALL contacts from organization 2774 and creates/updates them in Salesforce.
 * NOTE: Appends "TEST" to first and last names for testing purposes.
 * 
 * Usage in Developer Console:
 * // Sync all contacts from organization 2774
 * // Note: Credentials should be configured in Arlo_Credentials__c Custom Setting
 * ArloContactSync.syncContactsFromArlo('2774', 'Life Education Trust (NZ) National Office');
 * 
 * @author System Generated
 * @version 1.0
 */
public with sharing class ArloContactSync {
    
    // Arlo API Configuration
    private static final String ARLO_API_BASE_URL = 'https://lifeeducationtrust.arlo.co/api/2012-02-01/auth';
    private static final String ARLO_API_VERSION = '2012-02-01';
    
    // Organization name mapping: Arlo Organization Name -> Salesforce Account Name
    private static final Map<String, String> ORG_NAME_MAPPING = new Map<String, String>{
        'Life Education Trust National Office' => 'Life Education Trust (NZ) National Office'
        // Add more mappings as needed
    };
    
    // Store credentials for Basic Auth (for backward compatibility)
    private static String arloUsername = null;
    private static String arloPassword = null;
    
    // Track the last insert count (for syncContactsToSalesforceStatic to return accurate count)
    private static Integer lastInsertCount = 0;
    
    /**
     * Get credentials from Custom Settings
     */
    private static void loadCredentialsFromCustomSettings() {
        Arlo_Credentials__c credentials = Arlo_Credentials__c.getOrgDefaults();
        if (credentials != null && String.isNotBlank(credentials.Username__c) && String.isNotBlank(credentials.Password__c)) {
            arloUsername = credentials.Username__c;
            arloPassword = credentials.Password__c;
            System.debug('ArloContactSync: Loaded credentials from Custom Settings');
        } else {
            throw new ArloSyncException('Arlo Credentials not configured. Please set up Arlo_Credentials__c Custom Setting with Username__c and Password__c.');
        }
    }
    
    /**
     * Main method to sync contacts from Arlo to Salesforce
     * Can be called from Developer Console
     * 
     * @param arloOrgId The ID of the organization in Arlo (e.g., "2774")
     * @param salesforceAccountName The name of the Account in Salesforce
     */
    public static void syncContactsFromArlo(String arloOrgId, String salesforceAccountName) {
        syncContactsFromArloWithFilters(arloOrgId, salesforceAccountName, null, null);
    }
    
    /**
     * Sync a single contact from Arlo by Contact ID
     * Automatically finds the correct Account using organisation ID from employment endpoint
     * Usage in Developer Console:
     * // Note: Credentials should be configured in Arlo_Credentials__c Custom Setting
     * ArloContactSync.syncSingleContact('100', null, null); // Uses Custom Settings
     * // Or provide credentials: ArloContactSync.syncSingleContact('100', 'username', 'password');
     * 
     * @param arloContactId The Arlo Contact ID (e.g., "100")
     * @param username Arlo username
     * @param password Arlo password
     */
    public static void syncSingleContact(String arloContactId, String username, String password) {
        Id logId = null;
        String apiEndpoint = null;
        String httpStatusCode = null;
        
        try {
            System.debug('ArloContactSync: Starting single contact sync for Contact ID: ' + arloContactId);
            
            // Get single contact from Arlo (HTTP callout - must be before any DML)
            // This will also fetch employment data to get organisation ID
            ArloContact arloContact = getSingleArloContact(arloContactId);
            
            // Get API endpoint and status for logging (stored in class variables if needed)
            apiEndpoint = ARLO_API_BASE_URL + '/resources/contacts/' + arloContactId + '/';
            httpStatusCode = '200'; // Assuming success if we got here
            if (arloContact == null) {
                // Create error log after callout (callout is done, so DML is OK)
                createLogRecord('Single Contact Sync', 'Error', arloContactId, null, 'Arlo Contact not found: ' + arloContactId, apiEndpoint, httpStatusCode, null, null);
                throw new ArloSyncException('Arlo Contact not found: ' + arloContactId);
            }
            
            System.debug('ArloContactSync: Retrieved contact: ' + arloContact.firstName + ' ' + arloContact.lastName);
            System.debug('ArloContactSync: Organisation ID: ' + arloContact.organisationId);
            
            // Get Salesforce Account by CodePrimary (AccountNumber)
            Account sfAccount = null;
            if (String.isBlank(arloContact.organisationId)) {
                createLogRecord('Single Contact Sync', 'Error', arloContactId, null, 
                    'No organisation ID found for contact. Employment data may be missing.', 
                    apiEndpoint, httpStatusCode, null, null);
                throw new ArloSyncException('No organisation ID found for contact ' + arloContactId + '. Employment data may be missing.');
            }
            
            // Fetch organisation CodePrimary
            String codePrimary = getOrganisationCodePrimary(arloContact.organisationId);
            if (String.isBlank(codePrimary)) {
                // Skip this contact - many organizations don't have CodePrimary, this is normal
                System.debug('ArloContactSync: No CodePrimary found for organisation ' + arloContact.organisationId + '. Skipping contact. This is normal - many organizations do not have CodePrimary.');
                // Clear credentials and return without throwing exception or logging
                arloUsername = null;
                arloPassword = null;
                return;
            }
            
            arloContact.organisationCodePrimary = codePrimary;
            System.debug('ArloContactSync: Found CodePrimary ' + codePrimary + ' for organisation ' + arloContact.organisationId);
            
            // Find Account by CodePrimary (AccountNumber)
            sfAccount = getSalesforceAccountByNumber(codePrimary);
            if (sfAccount == null) {
                // Create error log after validation (no callout yet, so DML is OK)
                createLogRecord('Single Contact Sync', 'Error', arloContactId, arloContact.organisationId, 
                    'Salesforce Account not found with AccountNumber: ' + codePrimary, 
                    apiEndpoint, httpStatusCode, null, null);
                throw new ArloSyncException('Salesforce Account not found with AccountNumber: ' + codePrimary + '. Please ensure the Account exists with this AccountNumber.');
            }
            
            System.debug('ArloContactSync: Found Account by CodePrimary ' + codePrimary + ': ' + sfAccount.Name);
            
            // Now create log record (after callout, before DML operations)
            logId = createLogRecord('Single Contact Sync', 'In Progress', arloContactId, arloContact.organisationId, 
                'Retrieved contact from Arlo: ' + arloContact.firstName + ' ' + arloContact.lastName + '. Organisation ID: ' + arloContact.organisationId, 
                apiEndpoint, httpStatusCode, null, null);
            
            // Sync contact to Salesforce (DML operation)
            // Note: syncContactsToSalesforce will use organisation ID to find the correct Account
            List<ArloContact> contacts = new List<ArloContact>{ arloContact };
            Id contactId = syncContactsToSalesforce(contacts, sfAccount.Id, logId);
            
            // Update log with success
            updateLogRecord(logId, 'Success', 'Successfully synced contact: ' + arloContact.firstName + ' ' + arloContact.lastName, contactId, 1, 1);
            
            System.debug('ArloContactSync: Single contact sync completed successfully');
            
            // Clear credentials after use
            arloUsername = null;
            arloPassword = null;
            
        } catch (Exception e) {
            // Clear credentials on error
            arloUsername = null;
            arloPassword = null;
            System.debug('ArloContactSync: Error in single contact sync: ' + e.getMessage());
            System.debug('ArloContactSync: Stack trace: ' + e.getStackTraceString());
            
            // Update log with error (if log exists) or create new one
            if (logId != null) {
                updateLogRecord(logId, 'Error', 'Sync failed: ' + e.getMessage() + '\nStack trace: ' + e.getStackTraceString(), null, 1, 0);
            } else {
                // Create error log (callout is done, so DML is OK)
                createLogRecord('Single Contact Sync', 'Error', arloContactId, null, 'Sync failed: ' + e.getMessage(), apiEndpoint, httpStatusCode, null, null);
            }
            
            throw new ArloSyncException('Sync failed: ' + e.getMessage(), e);
        }
    }
    
    /**
     * Static method to get single contact (for use by Queueable)
     * Also fetches employment data to get organisation ID
     */
    public static ArloContact getSingleArloContactStatic(String contactId, String username, String password) {
        // Temporarily set credentials
        String oldUsername = arloUsername;
        String oldPassword = arloPassword;
        arloUsername = username;
        arloPassword = password;
        
        try {
            ArloContact contact = getSingleArloContact(contactId);
            // getSingleArloContact already fetches employment data, so we're good
            return contact;
        } finally {
            // Restore credentials
            arloUsername = oldUsername;
            arloPassword = oldPassword;
        }
    }
    
    /**
     * Static method to sync contacts (for use by Queueable)
     * @param accountId Optional default Account ID (used only if CodePrimary lookup fails for a contact)
     * @return Count of actually inserted contacts (after filtering out existing ones)
     */
    public static Integer syncContactsToSalesforceStatic(List<ArloContact> arloContacts, Id accountId) {
        // Call the sync method (does the insert and sets lastInsertCount)
        syncContactsToSalesforce(arloContacts, accountId, null);
        
        // Return the actual count of inserted contacts (after filtering out existing ones)
        System.debug('ArloContactSync: Actually inserted ' + lastInsertCount + ' new contacts (attempted to process ' + arloContacts.size() + ' contacts, some may have been skipped if already exist)');
        return lastInsertCount;
    }
    
    /**
     * Set credentials (for use by Queueable)
     */
    public static void setCredentials(String username, String password) {
        arloUsername = username;
        arloPassword = password;
    }
    
    /**
     * Clear credentials (for use by Queueable)
     */
    public static void clearCredentials() {
        arloUsername = null;
        arloPassword = null;
    }
    
    /**
     * Extract contact ID from link (public for Queueable)
     */
    public static String extractContactIdFromLink(String contactLink) {
        if (String.isBlank(contactLink)) {
            return null;
        }
        
        try {
            // Extract the ID from the href
            // Pattern: .../contacts/{ID}/
            Pattern idPattern = Pattern.compile('/contacts/(\\d+)/');
            Matcher matcher = idPattern.matcher(contactLink);
            if (matcher.find()) {
                return matcher.group(1);
            }
        } catch (Exception e) {
            System.debug('ArloContactSync: Error extracting contact ID from link: ' + e.getMessage());
        }
        
        return null;
    }
    
    private static ArloContact getSingleArloContact(String contactId) {
        try {
            // Endpoint: /api/2012-02-01/auth/resources/contacts/{contactId}/
            String endpoint = ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/';
            
            System.debug('ArloContactSync: Fetching single contact from: ' + endpoint);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/xml');
            
            // Use Basic Authentication
            Blob authBlob = Blob.valueOf(arloUsername + ':' + arloPassword);
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
            req.setHeader('Authorization', authHeader);
            
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            // Store API call details for logging (don't create log here - will be done after callout)
            // The caller will handle logging after the callout completes
            
            System.debug('ArloContactSync: Single contact response status: ' + res.getStatusCode());
            String responseBody = res.getBody();
            System.debug('ArloContactSync: Single contact response body length: ' + responseBody.length());
            System.debug('ArloContactSync: Single contact response body (first 1000 chars): ' + (responseBody.length() > 1000 ? responseBody.substring(0, 1000) : responseBody));
            
            if (res.getStatusCode() == 200) {
                // Parse XML response - should be a single Contact element
                List<ArloContact> contacts = parseContactsFromXml(responseBody, null);
                if (!contacts.isEmpty()) {
                    ArloContact contact = contacts[0];
                    
                    // Store the numeric Contact ID from the link (parameter contactId)
                    contact.numericContactId = contactId;
                    
                    // Fetch employment data to get organisation ID
                    String orgId = getOrganisationIdFromEmployment(contactId);
                    if (String.isNotBlank(orgId)) {
                        contact.organisationId = orgId;
                        System.debug('ArloContactSync: Found organisation ID ' + orgId + ' for contact ' + contactId);
                        
                        // Fetch organisation CodePrimary
                        String codePrimary = getOrganisationCodePrimary(orgId);
                        if (String.isNotBlank(codePrimary)) {
                            contact.organisationCodePrimary = codePrimary;
                            System.debug('ArloContactSync: Found CodePrimary ' + codePrimary + ' for organisation ' + orgId);
                        } else {
                            System.debug('ArloContactSync: No CodePrimary found for organisation ' + orgId);
                        }
                    } else {
                        System.debug('ArloContactSync: No organisation ID found for contact ' + contactId);
                    }
                    
                    System.debug('ArloContactSync: Successfully parsed contact');
                    return contact;
                } else {
                    System.debug('ArloContactSync: No contacts found in response');
                    return null;
                }
            } else {
                System.debug('ArloContactSync: Error getting contact. Status: ' + res.getStatusCode() + ', Body: ' + responseBody);
                throw new ArloSyncException('Failed to get contact. Status: ' + res.getStatusCode());
            }
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error getting single Arlo contact: ' + e.getMessage());
            throw e;
        }
    }
    
    /**
     * Get organisation CodePrimary from organisation endpoint
     * @param organisationId Arlo organisation ID (e.g., "28")
     * @return CodePrimary (e.g., "2220") or null if not found
     */
    private static String getOrganisationCodePrimary(String organisationId) {
        try {
            // Endpoint: /api/2012-02-01/auth/resources/organisations/{organisationId}
            String endpoint = ARLO_API_BASE_URL + '/resources/organisations/' + organisationId;
            
            System.debug('ArloContactSync: Fetching organisation details from: ' + endpoint);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/xml');
            
            // Use Basic Authentication
            Blob authBlob = Blob.valueOf(arloUsername + ':' + arloPassword);
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
            req.setHeader('Authorization', authHeader);
            
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('ArloContactSync: Organisation response status: ' + res.getStatusCode());
            
            System.debug('ArloContactSync: Organisation API response status: ' + res.getStatusCode());
            
            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();
                System.debug('ArloContactSync: Organisation response body length: ' + responseBody.length());
                System.debug('ArloContactSync: Organisation response body (first 500 chars): ' + (responseBody.length() > 500 ? responseBody.substring(0, 500) : responseBody));
                
                // Try DOM parsing first (more robust)
                try {
                    Dom.Document doc = new Dom.Document();
                    doc.load(responseBody);
                    Dom.XmlNode root = doc.getRootElement();
                    System.debug('ArloContactSync: DOM root element name: ' + root.getName());
                    
                    // Search for CodePrimary node (handle namespaces)
                    Dom.XmlNode codePrimaryNode = findNodeByName(root, 'CodePrimary');
                    if (codePrimaryNode != null) {
                        String codePrimary = codePrimaryNode.getText().trim();
                        System.debug('ArloContactSync: Extracted CodePrimary via DOM: ' + codePrimary);
                        return codePrimary;
                    } else {
                        System.debug('ArloContactSync: CodePrimary node not found via DOM. Searching all nodes...');
                        // Debug: List all node names
                        List<String> nodeNames = new List<String>();
                        collectNodeNames(root, nodeNames);
                        System.debug('ArloContactSync: All node names in XML: ' + String.join(nodeNames, ', '));
                    }
                } catch (Exception domEx) {
                    System.debug('ArloContactSync: DOM parsing failed, trying regex: ' + domEx.getMessage());
                    System.debug('ArloContactSync: DOM exception stack: ' + domEx.getStackTraceString());
                }
                
                // Fallback to regex (handle namespaces and whitespace)
                System.debug('ArloContactSync: Trying regex pattern matching...');
                Pattern codePrimaryPattern = Pattern.compile('(?i)<CodePrimary[^>]*>(.*?)</CodePrimary>');
                Matcher matcher = codePrimaryPattern.matcher(responseBody);
                if (matcher.find()) {
                    String codePrimary = matcher.group(1).trim();
                    System.debug('ArloContactSync: Extracted CodePrimary via regex: ' + codePrimary);
                    return codePrimary;
                } else {
                    System.debug('ArloContactSync: No CodePrimary found in organisation response via regex');
                    // Try alternative patterns
                    Pattern altPattern1 = Pattern.compile('(?i)CodePrimary[^>]*>([^<]+)</');
                    Matcher altMatcher1 = altPattern1.matcher(responseBody);
                    if (altMatcher1.find()) {
                        String codePrimary = altMatcher1.group(1).trim();
                        System.debug('ArloContactSync: Extracted CodePrimary via alternative regex: ' + codePrimary);
                        return codePrimary;
                    }
                    
                    // CodePrimary not found - log full response for debugging (truncated to 2000 chars)
                    System.debug('ArloContactSync: CodePrimary not found in organisation ' + organisationId + '. Full response (truncated): ' + (responseBody.length() > 2000 ? responseBody.substring(0, 2000) + '...' : responseBody));
                    System.debug('ArloContactSync: This may be normal - some Arlo organizations do not have a CodePrimary value.');
                }
            } else {
                System.debug('ArloContactSync: Error getting organisation data. Status: ' + res.getStatusCode());
                System.debug('ArloContactSync: Response body: ' + res.getBody());
                return null; // Organisation data is optional, don't throw error
            }
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error getting CodePrimary from organisation ' + organisationId + ': ' + e.getMessage());
            System.debug('ArloContactSync: Exception stack: ' + e.getStackTraceString());
            return null; // Organisation data is optional, don't throw error
        }
        System.debug('ArloContactSync: Returning null for CodePrimary (organisationId: ' + organisationId + ') - This may be normal if the organization does not have a CodePrimary value in Arlo.');
        return null;
    }
    
    /**
     * Helper method to collect all node names for debugging
     */
    private static void collectNodeNames(Dom.XmlNode node, List<String> nodeNames) {
        if (node == null) {
            return;
        }
        String name = node.getName();
        if (String.isNotBlank(name) && !nodeNames.contains(name)) {
            nodeNames.add(name);
        }
        if (node.getChildElements() != null) {
            for (Dom.XmlNode child : node.getChildElements()) {
                collectNodeNames(child, nodeNames);
            }
        }
    }
    
    /**
     * Helper method to find XML node by name (handles namespaces)
     */
    private static Dom.XmlNode findNodeByName(Dom.XmlNode parent, String nodeName) {
        if (parent == null) {
            return null;
        }
        
        // Check current node
        String localName = parent.getName();
        if (localName != null && localName.equalsIgnoreCase(nodeName)) {
            return parent;
        }
        
        // Check children
        if (parent.getChildElements() != null) {
            for (Dom.XmlNode child : parent.getChildElements()) {
                Dom.XmlNode found = findNodeByName(child, nodeName);
                if (found != null) {
                    return found;
                }
            }
        }
        
        return null;
    }
    
    /**
     * Get organisation ID from contact's employment endpoint
     * @param contactId Arlo contact ID
     * @return Organisation ID (e.g., "28") or null if not found
     */
    private static String getOrganisationIdFromEmployment(String contactId) {
        try {
            // Endpoint: /api/2012-02-01/auth/resources/contacts/{contactId}/employment
            String endpoint = ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/employment';
            
            System.debug('ArloContactSync: Fetching employment data from: ' + endpoint);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/xml');
            
            // Use Basic Authentication
            Blob authBlob = Blob.valueOf(arloUsername + ':' + arloPassword);
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
            req.setHeader('Authorization', authHeader);
            
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('ArloContactSync: Employment response status: ' + res.getStatusCode());
            
            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();
                System.debug('ArloContactSync: Employment response body: ' + responseBody);
                
                // Parse XML to extract ALL organisation links (contact may have multiple employments)
                // Look for: <Link rel="http://schemas.arlo.co/api/2012/02/auth/related/Organisation" ... href=".../organisations/{ID}/"/>
                Pattern orgPattern = Pattern.compile('/organisations/(\\d+)/');
                Matcher matcher = orgPattern.matcher(responseBody);
                
                List<String> orgIds = new List<String>();
                while (matcher.find()) {
                    String orgId = matcher.group(1);
                    orgIds.add(orgId);
                }
                
                if (orgIds.isEmpty()) {
                    System.debug('ArloContactSync: No organisation ID found in employment response');
                    return null;
                }
                
                System.debug('ArloContactSync: Found ' + orgIds.size() + ' organisation ID(s) in employment: ' + String.join(orgIds, ', '));
                
                // If multiple organisations, check if any match an expected Account
                // For now, return the first one (original behavior)
                // TODO: Could enhance to prefer organisation that matches existing Salesforce Account
                String selectedOrgId = orgIds[0];
                System.debug('ArloContactSync: Using organisation ID: ' + selectedOrgId + ' (first of ' + orgIds.size() + ' found)');
                
                if (orgIds.size() > 1) {
                    System.debug('ArloContactSync: WARNING - Contact has multiple employments. Using first organisation: ' + selectedOrgId);
                    System.debug('ArloContactSync: All organisation IDs: ' + String.join(orgIds, ', '));
                }
                
                return selectedOrgId;
            } else {
                System.debug('ArloContactSync: Error getting employment data. Status: ' + res.getStatusCode());
                return null; // Employment data is optional, don't throw error
            }
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error getting organisation ID from employment: ' + e.getMessage());
            return null; // Employment data is optional, don't throw error
        }
    }
    
    /**
     * Get all contacts from Arlo and sync to Salesforce
     * Gets all contact links from /resources/contacts/ and processes them one by one
     * Each contact is automatically assigned to the correct Account based on their CodePrimary
     * Usage in Developer Console:
     * ArloContactSync.syncAllContacts('lizzie.barnett@lifeeducation.org.nz', 'YellowArlo123!');
     * Or: ArloContactSync.syncAllContacts(null, null); // Uses Custom Settings
     * 
     * @param username Arlo username (optional - will use Custom Settings if null)
     * @param password Arlo password (optional - will use Custom Settings if null)
     */
    public static void syncAllContacts(String username, String password) {
        // Use Custom Settings if credentials not provided
        if (String.isBlank(username) || String.isBlank(password)) {
            loadCredentialsFromCustomSettings();
            username = arloUsername;
            password = arloPassword;
        } else {
            // Store provided credentials
            arloUsername = username;
            arloPassword = password;
        }
        
        Id logId = null;
        Integer totalProcessed = 0;
        Integer totalSuccessful = 0;
        Integer totalFailed = 0;
        
        try {
            System.debug('ArloContactSync: Starting sync for all contacts from organization 2774');
            
            // STEP 1: Get all contact links (HTTP callout - no DML yet)
            List<String> contactLinks = getAllContactLinks();
            System.debug('ArloContactSync: Found ' + contactLinks.size() + ' contact links');
            
            if (contactLinks.isEmpty()) {
                // Create log after callout (DML is OK now)
                createLogRecord('Organization Contacts Sync', 'Warning', null, '2774', 
                    'No contacts found in Arlo', ARLO_API_BASE_URL + '/resources/contacts/', null, 0, 0);
                return;
            }
            
            // STEP 2: Create log record (after getting links, before processing)
            logId = createLogRecord('Organization Contacts Sync', 'In Progress', null, '2774', 
                'Found ' + contactLinks.size() + ' contacts. Starting batch processing...', 
                ARLO_API_BASE_URL + '/resources/contacts/', null, contactLinks.size(), null);
            
            // STEP 3: Use Queueable to process contacts in batches (avoids 100 callout limit)
            // Note: Account will be determined automatically for each contact based on CodePrimary
            System.debug('ArloContactSync: Enqueueing Queueable job to process ' + contactLinks.size() + ' contacts in batches');
            ArloContactSyncQueueable queueable = new ArloContactSyncQueueable(
                contactLinks, null, logId, '2774', username, password
            );
            System.enqueueJob(queueable);
            
            System.debug('ArloContactSync: Queueable job enqueued. Processing will continue asynchronously.');
            
            // Note: Final log update will be done by Queueable when all batches complete
            System.debug('ArloContactSync: Queueable job started. Check log record for progress.');
            
            // Clear credentials after use
            arloUsername = null;
            arloPassword = null;
            
        } catch (Exception e) {
            // Clear credentials on error
            arloUsername = null;
            arloPassword = null;
            System.debug('ArloContactSync: Error syncing contacts from org 2774: ' + e.getMessage());
            System.debug('ArloContactSync: Stack trace: ' + e.getStackTraceString());
            
            // Update log with error
            if (logId != null) {
                updateLogRecord(logId, 'Error', 
                    'Sync failed: ' + e.getMessage() + '\nProcessed: ' + totalProcessed + ', Successful: ' + totalSuccessful + ', Failed: ' + totalFailed, 
                    null, totalProcessed, totalSuccessful);
            } else {
                createLogRecord('Organization Contacts Sync', 'Error', null, '2774', 
                    'Sync failed: ' + e.getMessage(), null, null, totalProcessed, totalSuccessful);
            }
            
            throw new ArloSyncException('Sync failed: ' + e.getMessage(), e);
        }
    }
    
    
    /**
     * Extract contact links from the collection XML response
     */
    private static List<String> extractContactLinksFromCollection(String xmlBody) {
        List<String> contactLinks = new List<String>();
        
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            
            Dom.XmlNode root = doc.getRootElement();
            System.debug('ArloContactSync: Collection root element: ' + root.getName());
            
            // Find all Link elements with href pointing to contacts
            findContactLinks(root, contactLinks);
            
            System.debug('ArloContactSync: Extracted ' + contactLinks.size() + ' contact links');
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error extracting contact links: ' + e.getMessage());
        }
        
        return contactLinks;
    }
    
    /**
     * Recursively find Link elements that point to contacts
     * Only includes links with rel="http://schemas.arlo.co/api/2012/02/auth/Contact" (actual contacts, not "next" or "self")
     */
    private static void findContactLinks(Dom.XmlNode node, List<String> contactLinks) {
        String nodeName = node.getName();
        
        // Check if this is a Link element
        if (nodeName == 'Link') {
            // Get the href and rel attributes
            String href = node.getAttributeValue('href', null);
            String rel = node.getAttributeValue('rel', null);
            
            // Only include links that are actual contacts (not "next" or "self")
            if (String.isNotBlank(href) && href.contains('/resources/contacts/') && 
                String.isNotBlank(rel) && rel.contains('Contact') && rel != 'next' && rel != 'self') {
                // This is a link to a contact
                contactLinks.add(href);
                System.debug('ArloContactSync: Found contact link: ' + href);
            }
        }
        
        // Recursively check child elements
        for (Dom.XmlNode child : node.getChildElements()) {
            findContactLinks(child, contactLinks);
        }
    }
    
    
    /**
     * Main method to sync contacts from Arlo to Salesforce with optional filtering
     * 
     * @param arloOrgId The ID of the organization in Arlo (e.g., "2774")
     * @param salesforceAccountName The name of the Account in Salesforce
     * @param contactNameFilter Optional: Filter by contact name (e.g., "Mel Kira") - null to sync all
     * @param maxContacts Optional: Maximum number of contacts to sync - null for all
     */
    private static void syncContactsFromArloWithFilters(String arloOrgId, String salesforceAccountName, String contactNameFilter, Integer maxContacts) {
        try {
            System.debug('ArloContactSync: Starting sync for Arlo Org ID: ' + arloOrgId + ' -> SF Account: ' + salesforceAccountName);
            
            // Verify credentials are set
            if (String.isBlank(arloUsername) || String.isBlank(arloPassword)) {
                throw new ArloSyncException('Arlo credentials not set. Use syncContactsFromArlo method with username and password.');
            }
            
            // Verify organization ID is provided
            if (String.isBlank(arloOrgId)) {
                throw new ArloSyncException('Arlo Organization ID is required');
            }
            
            // Get Salesforce Account
            Account sfAccount = getSalesforceAccount(salesforceAccountName);
            if (sfAccount == null) {
                throw new ArloSyncException('Salesforce Account not found: ' + salesforceAccountName);
            }
            
            // Get contacts from Arlo
            List<ArloContact> arloContacts = getArloContacts(arloOrgId);
            System.debug('ArloContactSync: Retrieved ' + arloContacts.size() + ' contacts from Arlo');
            
            if (arloContacts.isEmpty()) {
                System.debug('ArloContactSync: No contacts found in Arlo organization');
                return;
            }
            
            // Note: For testing, we're syncing ALL contacts from organization 2774
            // Filters are disabled to get all contacts
            System.debug('ArloContactSync: Processing all ' + arloContacts.size() + ' contacts from organization');
            
            // Create log record for organization sync
            Id logId = createLogRecord('Organization Contacts Sync', 'In Progress', null, arloOrgId, 
                'Starting sync for organization ' + arloOrgId, null, null, arloContacts.size(), null);
            
            // Sync contacts to Salesforce
            syncContactsToSalesforce(arloContacts, sfAccount.Id, logId);
            
            // Update log with final status
            updateLogRecord(logId, 'Success', 'Successfully synced ' + arloContacts.size() + ' contacts from organization ' + arloOrgId, 
                null, arloContacts.size(), arloContacts.size());
            
            System.debug('ArloContactSync: Sync completed successfully');
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error during sync: ' + e.getMessage());
            System.debug('ArloContactSync: Stack trace: ' + e.getStackTraceString());
            throw new ArloSyncException('Sync failed: ' + e.getMessage(), e);
        }
    }
    
    /**
     * Get Salesforce Account by name
     */
    /**
     * Get Salesforce Account by AccountNumber (Arlo Organisation ID)
     */
    private static Account getSalesforceAccountByNumber(String accountNumber) {
        if (String.isBlank(accountNumber)) {
            return null;
        }
        
        try {
            List<Account> accounts = [
                SELECT Id, Name, AccountNumber
                FROM Account
                WHERE AccountNumber = :accountNumber
                LIMIT 1
            ];
            
            if (!accounts.isEmpty()) {
                System.debug('ArloContactSync: Found Salesforce Account by AccountNumber ' + accountNumber + ': ' + accounts[0].Name);
                return accounts[0];
            } else {
                System.debug('ArloContactSync: No Salesforce Account found with AccountNumber: ' + accountNumber);
                return null;
            }
        } catch (Exception e) {
            System.debug('ArloContactSync: Error querying Account by AccountNumber: ' + e.getMessage());
            return null;
        }
    }
    
    private static Account getSalesforceAccount(String accountName) {
        List<Account> accounts = [
            SELECT Id, Name 
            FROM Account 
            WHERE Name = :accountName 
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }
    
    /**
     * Get contacts from Arlo organization using Basic Auth
     */
    private static List<ArloContact> getArloContacts(String orgId) {
        List<ArloContact> contacts = new List<ArloContact>();
        
        try {
            // Get contacts for the organization
            // Based on Arlo API documentation, try these endpoints:
            // 1. /api/2012-02-01/auth/resources/organisations/{orgId}/contacts/ (organization contacts)
            // 2. /api/2012-02-01/auth/resources/contacts/?$filter=OrganisationID eq {orgId} (filtered contacts)
            // 3. /api/2012-02-01/auth/resources/contacts/ (all contacts - fallback)
            List<String> possibleEndpoints = new List<String>{
                ARLO_API_BASE_URL + '/resources/organisations/' + orgId + '/contacts/',
                ARLO_API_BASE_URL + '/resources/organisations/' + orgId + '/contacts',
                ARLO_API_BASE_URL + '/resources/contacts/?$filter=OrganisationID eq ' + orgId,
                ARLO_API_BASE_URL + '/resources/contacts/?$filter=OrganisationID eq \'' + orgId + '\'',
                ARLO_API_BASE_URL + '/resources/contacts/'
            };
            
            for (String endpoint : possibleEndpoints) {
                try {
                    System.debug('ArloContactSync: Trying contacts endpoint: ' + endpoint);
                    contacts = tryGetContacts(endpoint, orgId);
                    if (!contacts.isEmpty()) {
                        System.debug('ArloContactSync: Successfully retrieved contacts from: ' + endpoint);
                        break;
                    }
                } catch (Exception e) {
                    System.debug('ArloContactSync: Endpoint failed: ' + e.getMessage());
                }
            }
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error getting Arlo contacts: ' + e.getMessage());
        }
        
        return contacts;
    }
    
    /**
     * Try to get contacts from a specific endpoint using Basic Auth
     */
    private static List<ArloContact> tryGetContacts(String endpoint, String orgId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/xml');
        
        // Use Basic Authentication
        Blob authBlob = Blob.valueOf(arloUsername + ':' + arloPassword);
        String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
        req.setHeader('Authorization', authHeader);
        
        req.setTimeout(30000);
            
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('ArloContactSync: Contacts response status: ' + res.getStatusCode());
        String responseBody = res.getBody();
        System.debug('ArloContactSync: Contacts response body length: ' + responseBody.length());
        System.debug('ArloContactSync: Contacts response body (first 1000 chars): ' + (responseBody.length() > 1000 ? responseBody.substring(0, 1000) : responseBody));
        if (responseBody.length() > 1000) {
            System.debug('ArloContactSync: Contacts response body (last 500 chars): ' + responseBody.substring(responseBody.length() - 500));
        }
        
        if (res.getStatusCode() == 200) {
            // Parse XML response
            List<ArloContact> contacts = parseContactsFromXml(responseBody, orgId);
            System.debug('ArloContactSync: Parsed ' + contacts.size() + ' contacts from XML');
            return contacts;
        } else {
            System.debug('ArloContactSync: Error getting contacts. Status: ' + res.getStatusCode() + ', Body: ' + responseBody);
            throw new ArloSyncException('Failed to get contacts. Status: ' + res.getStatusCode());
        }
    }
    
    
    /**
     * Parse contacts from XML response
     */
    private static List<ArloContact> parseContactsFromXml(String xmlBody, String orgId) {
        List<ArloContact> contacts = new List<ArloContact>();
        
        // Parse XML - this is a simplified parser
        // You may need to adjust based on actual Arlo API response structure
        // Using Dom.Document for better XML parsing
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            
            Dom.XmlNode root = doc.getRootElement();
            System.debug('ArloContactSync: XML root element: ' + root.getName());
            System.debug('ArloContactSync: XML root namespace: ' + root.getNamespace());
            
            // Arlo API returns different structures:
            // 1. Single contact: <Contact>...</Contact>
            // 2. Multiple contacts: <ContactCollection><Contact>...</Contact></ContactCollection>
            // 3. Or: <feed><entry><Contact>...</Contact></entry></feed>
            // 4. Or: Direct Contact elements as children of root
            
            String rootName = root.getName();
            System.debug('ArloContactSync: XML root element: ' + rootName);
            System.debug('ArloContactSync: Root namespace: ' + root.getNamespace());
            
            // Check if root is a Contact element (single contact response)
            if (rootName == 'Contact') {
                System.debug('ArloContactSync: Root is a Contact element (single contact)');
                ArloContact contact = parseContactNode(root);
                if (contact != null) {
                    contacts.add(contact);
                    System.debug('ArloContactSync: Found single contact');
                }
            } else {
                // Check if root has direct Contact children
                List<Dom.XmlNode> rootChildren = root.getChildElements();
                System.debug('ArloContactSync: Root has ' + (rootChildren != null ? rootChildren.size() : 0) + ' child elements');
                
                // Check first few child element names to understand structure
                if (rootChildren != null && !rootChildren.isEmpty()) {
                    Integer count = 0;
                    for (Dom.XmlNode child : rootChildren) {
                        if (count < 5) {
                            System.debug('ArloContactSync: Root child ' + count + ': ' + child.getName());
                            count++;
                        }
                    }
                }
                
                // Look for ContactCollection or similar container
                Dom.XmlNode contactContainer = null;
                
                if (rootName == 'ContactCollection' || rootName == 'ArrayOfContact' || rootName == 'Contacts' || rootName == 'feed') {
                    contactContainer = root;
                    System.debug('ArloContactSync: Root is a known container type');
                } else {
                    // Look for container in child elements
                    for (Dom.XmlNode child : root.getChildElements()) {
                        String childName = child.getName();
                        if (childName == 'ContactCollection' || childName == 'ArrayOfContact' || childName == 'Contacts' || childName == 'feed' || childName == 'entry') {
                            contactContainer = child;
                            System.debug('ArloContactSync: Found container: ' + childName);
                            break;
                        }
                    }
                }
                
                // If we found a container, use it; otherwise use root
                Dom.XmlNode searchNode = contactContainer != null ? contactContainer : root;
                
                System.debug('ArloContactSync: Searching for contacts in node: ' + searchNode.getName());
                System.debug('ArloContactSync: Number of child elements: ' + (searchNode.getChildElements() != null ? searchNode.getChildElements().size() : 0));
                
                // Recursively search for Contact elements
                findContactNodes(searchNode, contacts);
            }
            
            System.debug('ArloContactSync: Found ' + contacts.size() + ' contacts after parsing');
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error parsing XML: ' + e.getMessage());
            System.debug('ArloContactSync: Stack trace: ' + e.getStackTraceString());
        }
        
        return contacts;
    }
    
    /**
     * Recursively find Contact nodes in XML
     */
    private static void findContactNodes(Dom.XmlNode node, List<ArloContact> contacts) {
        String nodeName = node.getName();
        
        // Check if this is a Contact element
        if (nodeName == 'Contact' || nodeName == 'entry') {
            System.debug('ArloContactSync: Found Contact/entry node, parsing...');
            ArloContact contact = parseContactNode(node);
            if (contact != null) {
                contacts.add(contact);
                System.debug('ArloContactSync: Added contact: ' + (contact.firstName != null ? contact.firstName : '') + ' ' + (contact.lastName != null ? contact.lastName : ''));
            } else {
                System.debug('ArloContactSync: Contact node parsed but returned null');
            }
        } else {
            // Only log first few nodes to avoid too much debug output
            if (contacts.size() < 3) {
                System.debug('ArloContactSync: Checking node: ' + nodeName + ' (not a Contact element)');
            }
        }
        
        // Recursively check child elements
        List<Dom.XmlNode> childElements = node.getChildElements();
        if (childElements != null && !childElements.isEmpty()) {
            System.debug('ArloContactSync: Node ' + nodeName + ' has ' + childElements.size() + ' child elements');
            for (Dom.XmlNode child : childElements) {
                findContactNodes(child, contacts);
            }
        }
    }
    
    /**
     * Parse a single contact node from XML
     */
    private static ArloContact parseContactNode(Dom.XmlNode node) {
        ArloContact contact = new ArloContact();
        
        try {
            // Try different field name variations that Arlo might use
            for (Dom.XmlNode child : node.getChildElements()) {
                String nodeName = child.getName();
                String nodeValue = child.getText();
                
                // Handle namespaces - get local name if there's a namespace
                if (nodeName.contains(':')) {
                    nodeName = nodeName.substring(nodeName.indexOf(':') + 1);
                }
                
                // Check for Link elements to extract numeric Contact ID from href
                if (nodeName == 'Link') {
                    String href = child.getAttributeValue('href', null);
                    if (String.isNotBlank(href)) {
                        // Extract numeric Contact ID from link (e.g., /contacts/100/)
                        String numericId = extractContactIdFromLink(href);
                        if (String.isNotBlank(numericId)) {
                            contact.numericContactId = numericId;
                        }
                    }
                }
                
                // Map Arlo API field names to contact fields
                // Based on actual Arlo API response structure
                if (nodeName == 'UniqueIdentifier') {
                    // Use UniqueIdentifier as the UUID (for Arlo_Contact_UUID__c field)
                    contact.contactId = nodeValue;
                } else if (nodeName == 'ContactID' || nodeName == 'ContactId') {
                    // Store numeric ContactID (for appending to LastName)
                    if (String.isBlank(contact.numericContactId)) {
                        contact.numericContactId = nodeValue;
                    }
                    // Also use as backup UUID if UniqueIdentifier is not available
                    if (String.isBlank(contact.contactId)) {
                        contact.contactId = nodeValue;
                    }
                } else if (nodeName == 'FirstName' || nodeName == 'Firstname') {
                    contact.firstName = nodeValue;
                } else if (nodeName == 'LastName' || nodeName == 'Lastname' || nodeName == 'Surname') {
                    contact.lastName = nodeValue;
                } else if (nodeName == 'Email' || nodeName == 'EmailAddress') {
                    contact.email = nodeValue;
                } else if (nodeName == 'PhoneMobile' || nodeName == 'MobileNumber' || nodeName == 'Mobile') {
                    contact.mobile = nodeValue;
                } else if (nodeName == 'PhoneNumber' || nodeName == 'Phone' || nodeName == 'WorkPhone') {
                    contact.phone = nodeValue;
                } else if (nodeName == 'Position') {
                    contact.title = nodeValue;
                }
                // Add more field mappings as needed
            }
            
            // Debug what we found
            System.debug('ArloContactSync: Parsed contact - ID: ' + contact.contactId + ', Name: ' + contact.firstName + ' ' + contact.lastName + ', Email: ' + contact.email);
            
            // Only return contact if it has at least a name or email
            if (String.isNotBlank(contact.firstName) || String.isNotBlank(contact.lastName) || String.isNotBlank(contact.email)) {
                return contact;
            } else {
                System.debug('ArloContactSync: Contact node skipped - no name or email found');
            }
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error parsing contact node: ' + e.getMessage());
            System.debug('ArloContactSync: Stack trace: ' + e.getStackTraceString());
        }
        
        return null;
    }
    
    /**
     * Sync contacts to Salesforce
     * Appends "TEST" to first and last names for testing purposes
     * Uses CodePrimary to find the correct Account by AccountNumber for each contact
     * Only syncs contacts if an Account exists with matching AccountNumber
     * @param defaultAccountId Optional default Account ID (used only if CodePrimary lookup fails)
     * @param logId Optional log record ID to update
     * @return First contact ID that was created/updated (for single contact syncs)
     */
    private static Id syncContactsToSalesforce(List<ArloContact> arloContacts, Id defaultAccountId, Id logId) {
        List<Contact> contactsToUpsert = new List<Contact>();
        Set<String> arloContactIds = new Set<String>();
        Map<String, Id> orgIdToAccountIdMap = new Map<String, Id>(); // Cache for organisation ID -> Account ID
        
        // Collect Arlo Contact IDs and emails for matching
        for (ArloContact arloContact : arloContacts) {
            if (String.isNotBlank(arloContact.contactId)) {
                arloContactIds.add(arloContact.contactId);
            }
        }
        
        // Query existing contacts that have Arlo Contact UUID (without Account filter since Account may vary)
        Map<String, Contact> existingContactsMap = new Map<String, Contact>();
        Set<String> emailsToMatch = new Set<String>();
        for (ArloContact arloContact : arloContacts) {
            if (String.isNotBlank(arloContact.email)) {
                emailsToMatch.add(arloContact.email);
            }
        }
        
        // Query existing contacts by Arlo UUID and email (no Account filter)
        List<Contact> existingContacts = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, Title, Arlo_Contact_UUID__c, AccountId
            FROM Contact
            WHERE Arlo_Contact_UUID__c IN :arloContactIds OR Email IN :emailsToMatch
        ];
        for (Contact c : existingContacts) {
            if (String.isNotBlank(c.Arlo_Contact_UUID__c)) {
                existingContactsMap.put(c.Arlo_Contact_UUID__c, c);
            }
            // Also map by email for fallback matching
            if (String.isNotBlank(c.Email)) {
                if (!existingContactsMap.containsKey(c.Email)) {
                    existingContactsMap.put(c.Email, c);
                }
            }
        }
        
        // Create/update contacts
        for (ArloContact arloContact : arloContacts) {
            Contact sfContact;
            
            // Determine the correct Account ID for this contact
            Id accountId = null; // Will be determined by CodePrimary
            
            // If contact has CodePrimary, find Account by AccountNumber
            if (String.isNotBlank(arloContact.organisationCodePrimary)) {
                // Check cache first (using CodePrimary as key)
                if (orgIdToAccountIdMap.containsKey(arloContact.organisationCodePrimary)) {
                    accountId = orgIdToAccountIdMap.get(arloContact.organisationCodePrimary);
                } else {
                    // Query for Account by AccountNumber (CodePrimary)
                    Account orgAccount = getSalesforceAccountByNumber(arloContact.organisationCodePrimary);
                    if (orgAccount != null) {
                        accountId = orgAccount.Id;
                        orgIdToAccountIdMap.put(arloContact.organisationCodePrimary, accountId);
                        System.debug('ArloContactSync: Mapped CodePrimary ' + arloContact.organisationCodePrimary + ' to Account: ' + orgAccount.Name);
                    } else {
                        System.debug('ArloContactSync: No Account found for CodePrimary ' + arloContact.organisationCodePrimary);
                        // Skip this contact if no Account found (don't use default)
                        System.debug('ArloContactSync: Skipping contact - no Account found for CodePrimary: ' + arloContact.organisationCodePrimary);
                        continue; // Skip this contact
                    }
                }
            } else if (String.isNotBlank(arloContact.organisationId)) {
                // Fallback: if CodePrimary is missing but organisationId exists, try to fetch it
                System.debug('ArloContactSync: CodePrimary missing, fetching for organisation ' + arloContact.organisationId);
                String codePrimary = getOrganisationCodePrimary(arloContact.organisationId);
                if (String.isNotBlank(codePrimary)) {
                    arloContact.organisationCodePrimary = codePrimary;
                    // Retry with CodePrimary
                    if (orgIdToAccountIdMap.containsKey(codePrimary)) {
                        accountId = orgIdToAccountIdMap.get(codePrimary);
                    } else {
                        Account orgAccount = getSalesforceAccountByNumber(codePrimary);
                        if (orgAccount != null) {
                            accountId = orgAccount.Id;
                            orgIdToAccountIdMap.put(codePrimary, accountId);
                            System.debug('ArloContactSync: Mapped CodePrimary ' + codePrimary + ' to Account: ' + orgAccount.Name);
                        } else {
                            System.debug('ArloContactSync: No Account found for CodePrimary ' + codePrimary);
                            // Skip this contact if no Account found
                            System.debug('ArloContactSync: Skipping contact - no Account found for CodePrimary: ' + codePrimary);
                            continue; // Skip this contact
                        }
                    }
                } else {
                    System.debug('ArloContactSync: No CodePrimary found for organisation ' + arloContact.organisationId);
                    // Skip this contact if no CodePrimary found
                    System.debug('ArloContactSync: Skipping contact - no CodePrimary found');
                    continue; // Skip this contact
                }
            } else {
                System.debug('ArloContactSync: No organisation data found for contact');
                // Skip this contact if no organisation data
                System.debug('ArloContactSync: Skipping contact - no organisation data');
                continue; // Skip this contact
            }
            
            // If we still don't have an Account ID, skip this contact
            if (accountId == null) {
                System.debug('ArloContactSync: Skipping contact - no Account ID determined');
                continue;
            }
            
            // Check if contact already exists by Arlo UUID or email - if exists, skip (only insert new contacts)
            Boolean contactExists = false;
            if (String.isNotBlank(arloContact.contactId) && existingContactsMap.containsKey(arloContact.contactId)) {
                System.debug('ArloContactSync: Contact already exists with Arlo UUID: ' + arloContact.contactId + ', skipping (insert only mode)');
                contactExists = true;
            } else if (String.isNotBlank(arloContact.email) && existingContactsMap.containsKey(arloContact.email)) {
                System.debug('ArloContactSync: Contact already exists with email: ' + arloContact.email + ', skipping (insert only mode)');
                contactExists = true;
            }
            
            // Skip existing contacts - only create new ones
            if (contactExists) {
                continue;
            }
            
            // Create new contact (insert only - no updates)
            sfContact = new Contact();
            sfContact.AccountId = accountId;
            
            // Set contact fields
            if (String.isNotBlank(arloContact.firstName)) {
                sfContact.FirstName = arloContact.firstName;
            }
            if (String.isNotBlank(arloContact.lastName)) {
                sfContact.LastName = arloContact.lastName;
            } else {
                sfContact.LastName = 'Contact';
            }
            if (String.isNotBlank(arloContact.email)) {
                sfContact.Email = arloContact.email;
            }
            if (String.isNotBlank(arloContact.phone)) {
                sfContact.Phone = arloContact.phone;
            }
            if (String.isNotBlank(arloContact.mobile)) {
                sfContact.MobilePhone = arloContact.mobile;
            }
            if (String.isNotBlank(arloContact.title)) {
                sfContact.Title = arloContact.title;
            }
            // Set Arlo Contact UUID
            if (String.isNotBlank(arloContact.contactId)) {
                sfContact.Arlo_Contact_UUID__c = arloContact.contactId;
            }
            
            contactsToUpsert.add(sfContact);
            
            /* COMMENTED OUT - UPSERT LOGIC (Now using insert only)
            // Check if contact already exists by Arlo UUID or email
            if (String.isNotBlank(arloContact.contactId) && existingContactsMap.containsKey(arloContact.contactId)) {
                sfContact = existingContactsMap.get(arloContact.contactId);
            } else if (String.isNotBlank(arloContact.email) && existingContactsMap.containsKey(arloContact.email)) {
                sfContact = existingContactsMap.get(arloContact.email);
            }
            
            // Create new contact if not found
            if (sfContact == null) {
                sfContact = new Contact();
                sfContact.AccountId = accountId;
            } else {
                // Update Account if it changed
                if (sfContact.AccountId != accountId) {
                    sfContact.AccountId = accountId;
                    System.debug('ArloContactSync: Updating Account for contact ' + sfContact.Id + ' to ' + accountId);
                }
            }
            */
        }
        
        // Insert contacts (insert only - no updates)
        Integer successCount = 0;
        Integer failCount = 0;
        Id firstContactId = null;
        
        // Reset last insert count
        lastInsertCount = 0;
        
        if (!contactsToUpsert.isEmpty()) {
            try {
                insert contactsToUpsert; // Changed from upsert to insert
                successCount = contactsToUpsert.size();
                lastInsertCount = successCount; // Store for syncContactsToSalesforceStatic
                if (!contactsToUpsert.isEmpty()) {
                    firstContactId = contactsToUpsert[0].Id;
                }
                System.debug('ArloContactSync: Successfully inserted ' + successCount + ' new contacts to Salesforce');
            } catch (Exception e) {
                failCount = contactsToUpsert.size();
                lastInsertCount = 0; // Reset on error
                System.debug('ArloContactSync: Error inserting contacts: ' + e.getMessage());
                throw e;
            }
        }
        
        /* COMMENTED OUT - UPSERT METHOD (Now using insert only)
        // Upsert contacts
        Integer successCount = 0;
        Integer failCount = 0;
        Id firstContactId = null;
        
        if (!contactsToUpsert.isEmpty()) {
            try {
                upsert contactsToUpsert;
                successCount = contactsToUpsert.size();
                if (!contactsToUpsert.isEmpty()) {
                    firstContactId = contactsToUpsert[0].Id;
                }
                System.debug('ArloContactSync: Successfully synced ' + successCount + ' contacts to Salesforce');
            } catch (Exception e) {
                failCount = contactsToUpsert.size();
                System.debug('ArloContactSync: Error upserting contacts: ' + e.getMessage());
                throw e;
            }
        }
        */
        
        // Update log if provided
        if (logId != null && (successCount > 0 || failCount > 0)) {
            updateLogRecord(logId, null, null, null, successCount + failCount, successCount);
        }
        
        return firstContactId;
    }
    
    /**
     * Create a log record in Arlo_Integration_Log__c
     * Made public for use by Queueable class
     */
    public static Id createLogRecord(String operationType, String status, String arloContactId, String arloOrgId, String message, String apiEndpoint, String httpStatusCode, Integer recordsProcessed, Integer recordsSuccessful) {
        try {
            Arlo_Integration_Log__c log = new Arlo_Integration_Log__c();
            log.Operation_Type__c = operationType;
            log.Status__c = status;
            log.Arlo_Contact_ID__c = arloContactId;
            log.Arlo_Organization_ID__c = arloOrgId;
            log.Message__c = message;
            log.API_Endpoint__c = apiEndpoint;
            log.HTTP_Status_Code__c = httpStatusCode;
            log.Records_Processed__c = recordsProcessed;
            log.Records_Successful__c = recordsSuccessful;
            log.Records_Failed__c = (recordsProcessed != null && recordsSuccessful != null) ? (recordsProcessed - recordsSuccessful) : null;
            
            insert log;
            System.debug('ArloContactSync: Created log record: ' + log.Id);
            return log.Id;
        } catch (Exception e) {
            System.debug('ArloContactSync: Error creating log record: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Update a log record in Arlo_Integration_Log__c
     * Made public for use by Queueable class
     */
    public static void updateLogRecord(Id logId, String status, String message, Id salesforceContactId, Integer recordsProcessed, Integer recordsSuccessful) {
        if (logId == null) {
            return;
        }
        
        try {
            Arlo_Integration_Log__c log = new Arlo_Integration_Log__c(Id = logId);
            if (String.isNotBlank(status)) {
                log.Status__c = status;
            }
            if (String.isNotBlank(message)) {
                log.Message__c = message;
            }
            if (salesforceContactId != null) {
                log.Salesforce_Contact__c = salesforceContactId;
            }
            if (recordsProcessed != null) {
                log.Records_Processed__c = recordsProcessed;
            }
            if (recordsSuccessful != null) {
                log.Records_Successful__c = recordsSuccessful;
                if (recordsProcessed != null) {
                    log.Records_Failed__c = recordsProcessed - recordsSuccessful;
                }
            }
            
            update log;
            System.debug('ArloContactSync: Updated log record: ' + logId);
        } catch (Exception e) {
            System.debug('ArloContactSync: Error updating log record: ' + e.getMessage());
        }
    }
    
    
    /**
     * Overloaded method that accepts username and password
     * Usage in Developer Console:
     * ArloContactSync.syncContactsFromArlo('2774', 'Life Education Trust (NZ) National Office', 'lizzie.barnett@lifeeducation.org.nz', 'YellowArlo123!');
     * 
     * NOTE: This will sync ALL contacts from organization 2774 and append "TEST" to first and last names
     * NOTE: For production, use Named Credentials instead of passing credentials directly
     */
    public static void syncContactsFromArlo(String arloOrgId, String salesforceAccountName, String username, String password) {
        try {
            // Store credentials for Basic Auth
            arloUsername = username;
            arloPassword = password;
            
            // Call the main sync method (will sync ALL contacts, filters disabled)
            syncContactsFromArloWithFilters(arloOrgId, salesforceAccountName, null, null);
            
            // Clear credentials after use
            arloUsername = null;
            arloPassword = null;
        } catch (Exception e) {
            // Clear credentials on error
            arloUsername = null;
            arloPassword = null;
            System.debug('ArloContactSync: Error in sync with credentials: ' + e.getMessage());
            throw new ArloSyncException('Sync failed: ' + e.getMessage(), e);
        }
    }
    
    /**
     * Get all contact links from the contacts endpoint
     * Handles pagination by following "next" links
     */
    private static List<String> getAllContactLinks() {
        List<String> allContactLinks = new List<String>();
        String nextLink = ARLO_API_BASE_URL + '/resources/contacts/';
        Integer pageCount = 0;
        Integer maxPages = 100; // Safety limit to prevent infinite loops
        
        while (String.isNotBlank(nextLink) && pageCount < maxPages) {
            try {
                System.debug('ArloContactSync: Fetching contacts page ' + (pageCount + 1) + ' from: ' + nextLink);
                
                HttpRequest req = new HttpRequest();
                req.setEndpoint(nextLink);
                req.setMethod('GET');
                req.setHeader('Accept', 'application/xml');
                
                // Use Basic Authentication
                Blob authBlob = Blob.valueOf(arloUsername + ':' + arloPassword);
                String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
                req.setHeader('Authorization', authHeader);
                
                req.setTimeout(30000);
                
                Http http = new Http();
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() == 200) {
                    // Extract contact links from XML
                    List<String> pageLinks = extractContactLinksFromCollection(res.getBody());
                    allContactLinks.addAll(pageLinks);
                    System.debug('ArloContactSync: Found ' + pageLinks.size() + ' contacts on page ' + (pageCount + 1));
                    
                    // Check for "next" link for pagination
                    nextLink = extractNextLink(res.getBody());
                    if (String.isNotBlank(nextLink)) {
                        System.debug('ArloContactSync: Found next page link: ' + nextLink);
                        pageCount++;
                    } else {
                        System.debug('ArloContactSync: No more pages to fetch');
                        break;
                    }
                } else {
                    System.debug('ArloContactSync: Error fetching contacts page. Status: ' + res.getStatusCode());
                    break;
                }
            } catch (Exception e) {
                System.debug('ArloContactSync: Error fetching contacts page: ' + e.getMessage());
                break;
            }
        }
        
        System.debug('ArloContactSync: Total contact links found: ' + allContactLinks.size() + ' across ' + (pageCount + 1) + ' pages');
        return allContactLinks;
    }
    
    
    /**
     * Extract the "next" link for pagination
     */
    private static String extractNextLink(String xmlBody) {
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            
            Dom.XmlNode root = doc.getRootElement();
            
            // Find Link element with rel="next"
            for (Dom.XmlNode node : root.getChildElements()) {
                if (node.getName() == 'Link') {
                    String rel = node.getAttributeValue('rel', null);
                    if (rel == 'next') {
                        String href = node.getAttributeValue('href', null);
                        return href;
                    }
                }
            }
            
            // Recursively search child elements
            for (Dom.XmlNode child : root.getChildElements()) {
                String nextLink = findNextLinkRecursive(child);
                if (String.isNotBlank(nextLink)) {
                    return nextLink;
                }
            }
            
        } catch (Exception e) {
            System.debug('ArloContactSync: Error extracting next link: ' + e.getMessage());
        }
        
        return null;
    }
    
    /**
     * Recursively find Link element with rel="next"
     */
    private static String findNextLinkRecursive(Dom.XmlNode node) {
        if (node.getName() == 'Link') {
            String rel = node.getAttributeValue('rel', null);
            if (rel == 'next') {
                return node.getAttributeValue('href', null);
            }
        }
        
        for (Dom.XmlNode child : node.getChildElements()) {
            String nextLink = findNextLinkRecursive(child);
            if (String.isNotBlank(nextLink)) {
                return nextLink;
            }
        }
        
        return null;
    }
    
    
    
    /**
     * Inner class to represent Arlo Contact
     */
    public class ArloContact {
        public String contactId; // UUID/UniqueIdentifier (for Arlo_Contact_UUID__c field)
        public String numericContactId; // Numeric Contact ID from link (e.g., "100" from /contacts/100/)
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String mobile;
        public String title; // Position from Arlo (maps to Salesforce Title)
        public String organisationId; // Arlo Organisation ID (from employment endpoint)
        public String organisationCodePrimary; // CodePrimary from organisation endpoint (used to match AccountNumber)
        // Add more fields as needed
    }
    
    
    /**
     * Custom exception class
     */
    public class ArloSyncException extends Exception {}
}

