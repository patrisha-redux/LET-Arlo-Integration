/**
 * ArloRegistrationSyncBatch
 *
 * Main batch class for Arlo to Salesforce sync.
 * Processes all Arlo contacts, checks registrations, and adds consenting contacts to campaigns.
 *
 * Flow:
 * 1. GET all contacts -> /resources/contacts/
 * 2. For each contact, get registrations -> /resources/contacts/{id}/registrations
 * 3. For each registration, get event -> /resources/events/{id}/
 * 4. If event contains NHM, check customfields for email consent
 * 5. If consent given, sync/create contact and add to campaign
 *
 * Usage:
 *   ArloRegistrationSyncBatch.startSync(null, null); // Uses Arlo_Credentials__c
 *   ArloSyncScheduler.scheduleDaily();               // Schedule for 2 AM daily
 *   ArloSyncScheduler.scheduleHourly();              // Schedule hourly
 *
 * @author Life Education
 * @date 2026
 */
public class ArloRegistrationSyncBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {

    // Credentials for Basic Auth
    private String username;
    private String password;

    // API Client for Arlo requests
    private ArloApiClient apiClient;

    // Log record ID
    private Id logId;

    // Stateful variables to track across batches
    private Integer totalProcessed = 0;
    private Integer totalSuccessful = 0;
    private Integer totalFailed = 0;
    private Integer totalContactsCreated = 0;
    private Integer totalContactLinks = 0;

    // Track which page we're on
    private Integer currentPage = 0;
    private String nextLink = null;

    // Track unprocessed contact links from current page (due to callout limits)
    private List<String> unprocessedContactLinks = new List<String>();

    // Constants
    private static final Integer RESERVED_CALLOUTS_FOR_CONTACT_CREATION = 15;

    /**
     * Constructor
     */
    public ArloRegistrationSyncBatch(String username, String password) {
        this.username = username;
        this.password = password;
        // Initialize API client if credentials provided
        if (String.isNotBlank(username) && String.isNotBlank(password)) {
            this.apiClient = new ArloApiClient(username, password);
        }
    }

    /**
     * Helper to check if we have enough callouts remaining
     */
    @TestVisible
    private Boolean hasCalloutsRemaining(Integer needed) {
        return ArloApiClient.hasCalloutsRemaining(needed);
    }
    
    /**
     * Start method - returns page numbers to process
     * NOTE: Cannot make callouts in start() method, so we return page numbers
     * Each page will be fetched in execute() method
     */
    public Iterable<Integer> start(Database.BatchableContext bc) {
        // Initialize API client if not already done (use custom settings)
        if (apiClient == null) {
            try {
                apiClient = ArloApiClient.fromCustomSettings();
                // Also set username/password for static method calls that still need them
                Arlo_Credentials__c credentials = Arlo_Credentials__c.getOrgDefaults();
                username = credentials.Username__c;
                password = credentials.Password__c;
            } catch (ArloApiClient.ArloApiException e) {
                throw new ArloEventRegistrationSync.ArloSyncException('Arlo Credentials not configured. Please set up Arlo_Credentials__c Custom Setting with Username__c and Password__c.');
            }
        }

        // Initialize nextLink for first page
        nextLink = ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/';

        // Create initial log record
        logId = ArloEventRegistrationSync.createLogRecord(
            'Event Registration Sync V2 (Batch)',
            'In Progress',
            null,
            null,
            'Starting batch job...',
            ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/',
            null,
            null,
            null
        );

        // Return a list of page numbers (we'll process pages one at a time)
        // Max 1000 pages (safety limit)
        List<Integer> pages = new List<Integer>();
        for (Integer i = 1; i <= 1000; i++) {
            pages.add(i);
        }
        return pages;
    }
    
    /**
     * Execute method - processes deferred contacts first, then fetches a new page if needed
     * Each batch has its own callout limit (100 callouts), ensuring contact creation can happen
     */
    public void execute(Database.BatchableContext bc, List<Integer> pageNumbers) {
        if (pageNumbers.isEmpty()) {
            return;
        }

        // Process each page in this batch
        for (Integer pageNumber : pageNumbers) {
            // Check if we should continue (if nextLink is null and no deferred contacts, we're done)
            if (String.isBlank(nextLink) && unprocessedContactLinks.isEmpty() && pageNumber > 1) {
                break;
            }

            currentPage = pageNumber;

            // Check callout limit before processing this page
            if (!hasCalloutsRemaining(20)) {
                break;
            }

            processPageInline(pageNumber);
        }

        // Update log after processing all pages in this batch
        updateLogAfterBatch();
    }
    
    /**
     * Process a single page of contacts
     */
    @TestVisible
    private void processPageInline(Integer pageNumber) {
        // First, process any unprocessed contacts from previous batch
        List<String> contactsToProcess = new List<String>();
        Boolean hasDeferredContacts = !unprocessedContactLinks.isEmpty();

        if (hasDeferredContacts) {
            contactsToProcess.addAll(unprocessedContactLinks);
            unprocessedContactLinks.clear();
        }

        // Fetch a new page if we don't have deferred contacts
        List<String> batchContactLinks = new List<String>();
        if (!hasDeferredContacts && String.isNotBlank(nextLink)) {
            batchContactLinks = fetchContactsPage();
            if (!batchContactLinks.isEmpty()) {
                contactsToProcess.addAll(batchContactLinks);
            }
        }

        if (contactsToProcess.isEmpty()) {
            return;
        }

        // Process contacts and collect results
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList = new List<ArloEventRegistrationSync.ContactEventWrapper>();
        Map<String, ArloModels.ArloContact> arloContactMap = new Map<String, ArloModels.ArloContact>();
        Integer batchProcessed = 0;
        Integer batchFailed = 0;

        // Process each contact
        for (Integer i = 0; i < contactsToProcess.size(); i++) {
            String contactLink = contactsToProcess[i];
            try {
                if (!hasCalloutsRemaining(10)) {
                    // Defer remaining contacts to next batch
                    for (Integer j = i; j < contactsToProcess.size(); j++) {
                        unprocessedContactLinks.add(contactsToProcess[j]);
                    }
                    break;
                }

                String numericContactId = extractContactIdFromLink(contactLink);
                if (String.isBlank(numericContactId)) {
                    continue;
                }

                // Process this contact
                Integer processed = processContact(numericContactId, contactEventList, arloContactMap);
                batchProcessed += processed;

            } catch (Exception e) {
                batchFailed++;
                System.debug('ArloRegistrationSyncBatch: Error processing contact ' + contactLink + ': ' + e.getMessage());
                System.debug('ArloRegistrationSyncBatch: Stack trace: ' + e.getStackTraceString());
            }
        }

        // If we had deferred contacts and finished them, fetch next page for next batch
        if (hasDeferredContacts && unprocessedContactLinks.isEmpty() && String.isNotBlank(nextLink)) {
            batchContactLinks = fetchContactsPage();
            if (!batchContactLinks.isEmpty()) {
                unprocessedContactLinks.addAll(batchContactLinks);
            }
        }

        // Process DML operations (after all callouts are complete)
        Integer batchSuccessful = 0;
        Integer batchContactsCreated = 0;
        if (!contactEventList.isEmpty()) {
            batchContactsCreated = assignContactsToCampaigns(contactEventList, arloContactMap);
            batchSuccessful = contactEventList.size();
        }

        // Update stateful variables
        totalProcessed += batchProcessed;
        totalSuccessful += batchSuccessful;
        totalFailed += batchFailed;
        totalContactsCreated += batchContactsCreated;
    }

    /**
     * Fetch a page of contacts from Arlo API
     */
    @TestVisible
    private List<String> fetchContactsPage() {
        List<String> contactLinks = new List<String>();
        try {
            String responseBody = apiClient.getXml(nextLink);

            if (responseBody != null) {
                contactLinks = extractContactLinksFromCollection(responseBody);
                totalContactLinks += contactLinks.size();

                // Check for "next" link for pagination using ArloXmlParser
                nextLink = ArloXmlParser.extractNextLink(responseBody);
            } else {
                System.debug('ArloRegistrationSyncBatch: Error fetching contacts page - null response from API');
                System.debug('ArloRegistrationSyncBatch: Endpoint attempted: ' + nextLink);
                nextLink = null;
            }
        } catch (Exception e) {
            System.debug('ArloRegistrationSyncBatch: Error fetching contact links: ' + e.getMessage());
            System.debug('ArloRegistrationSyncBatch: Endpoint: ' + nextLink);
            System.debug('ArloRegistrationSyncBatch: Stack trace: ' + e.getStackTraceString());
            nextLink = null;
        }
        return contactLinks;
    }

    /**
     * Extract numeric contact ID from link
     * Delegates to ArloEventRegistrationSync for DRY compliance
     */
    @TestVisible
    private String extractContactIdFromLink(String contactLink) {
        return ArloEventRegistrationSync.extractContactIdFromLink(contactLink);
    }

    /**
     * Process a single contact - get details and registrations
     * Returns number of registrations processed
     */
    @TestVisible
    private Integer processContact(
        String numericContactId,
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList,
        Map<String, ArloModels.ArloContact> arloContactMap
    ) {
        if (!hasCalloutsRemaining(5)) {
            return 0;
        }

        // Fetch contact status (process ALL contacts regardless of status for historical data)
        fetchContactStatus(numericContactId);

        if (!hasCalloutsRemaining(5)) {
            return 0;
        }

        // Fetch contact UUID and Email for Salesforce matching
        ArloModels.ArloContact arloContact = fetchContactUuidAndEmail(numericContactId);
        if (arloContact == null || (String.isBlank(arloContact.contactId) && String.isBlank(arloContact.email))) {
            return 0;
        }
        arloContactMap.put(numericContactId, arloContact);

        if (!hasCalloutsRemaining(5)) {
            return 0;
        }

        // Fetch registrations for this contact
        Set<String> registrationIds = fetchContactRegistrations(numericContactId);
        if (registrationIds.isEmpty()) {
            return 0;
        }

        // Process each registration
        return processRegistrationsForContact(arloContact, registrationIds, contactEventList);
    }

    /**
     * Process registrations for a contact
     * Returns number of registrations processed with consent
     */
    @TestVisible
    private Integer processRegistrationsForContact(
        ArloModels.ArloContact arloContact,
        Set<String> registrationIds,
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList
    ) {
        Integer processed = 0;

        for (String registrationId : registrationIds) {
            // Check callout limit - reserve some for contact creation
            if (!hasCalloutsRemaining(RESERVED_CALLOUTS_FOR_CONTACT_CREATION + 5)) {
                break;
            }

            // Get event ID from registration
            String eventId = ArloEventRegistrationSync.getEventIdFromRegistrationStatic(registrationId, username, password);
            if (String.isBlank(eventId)) {
                continue;
            }

            if (!hasCalloutsRemaining(RESERVED_CALLOUTS_FOR_CONTACT_CREATION + 5)) {
                break;
            }

            // Get event details and check if event contains "NHM"
            ArloEventRegistrationSync.EventData eventData = ArloEventRegistrationSync.getEventDetailsStatic(eventId, username, password);
            if (eventData == null) {
                continue;
            }

            // Only process events that contain "NHM"
            Boolean eventContainsNHM = (String.isNotBlank(eventData.name) && eventData.name.contains('NHM')) ||
                                       (String.isNotBlank(eventData.code) && eventData.code.contains('NHM'));
            if (!eventContainsNHM) {
                continue;
            }

            if (!hasCalloutsRemaining(RESERVED_CALLOUTS_FOR_CONTACT_CREATION + 5)) {
                break;
            }

            // Check email consent
            Boolean hasEmailConsent = ArloEventRegistrationSync.checkRegistrationEmailConsentStatic(registrationId, username, password);
            if (!hasEmailConsent) {
                continue;
            }

            // Create wrapper for campaign assignment
            ArloEventRegistrationSync.ContactEventWrapper wrapper = new ArloEventRegistrationSync.ContactEventWrapper();
            wrapper.contact = arloContact;
            wrapper.eventName = eventData.name;
            wrapper.eventCode = eventData.code;
            contactEventList.add(wrapper);
            processed++;
        }

        return processed;
    }

    /**
     * Assign contacts to campaigns - handles DML phase
     * Returns number of contacts created
     */
    @TestVisible
    private Integer assignContactsToCampaigns(
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList,
        Map<String, ArloModels.ArloContact> arloContactMap
    ) {
        Integer contactsCreated = 0;

        try {
            // Find Salesforce contacts for each Arlo contact
            Map<Id, Contact> syncedContactMap = findSalesforceContacts(contactEventList, arloContactMap);

            // Find unmatched contacts that need to be created
            List<ArloEventRegistrationSync.ContactEventWrapper> unmatchedWrappers = findUnmatchedWrappers(contactEventList, syncedContactMap);

            // Create missing contacts
            if (!unmatchedWrappers.isEmpty()) {
                contactsCreated = createMissingContacts(unmatchedWrappers, arloContactMap, syncedContactMap);
            }

            // Add all contacts (existing + newly created) to campaigns
            if (!contactEventList.isEmpty() && !syncedContactMap.isEmpty()) {
                ArloEventRegistrationSync.addContactsToCampaignsStatic(contactEventList, syncedContactMap);
            }

        } catch (Exception e) {
            System.debug('ArloRegistrationSyncBatch: Error in campaign assignment: ' + e.getMessage());
            System.debug('ArloRegistrationSyncBatch: Contact-event pairs being processed: ' + contactEventList.size());
            System.debug('ArloRegistrationSyncBatch: Stack trace: ' + e.getStackTraceString());
        }

        return contactsCreated;
    }

    /**
     * Find wrappers that don't have matching Salesforce contacts
     * Delegates to ArloEventRegistrationSync for DRY compliance
     */
    @TestVisible
    private List<ArloEventRegistrationSync.ContactEventWrapper> findUnmatchedWrappers(
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList,
        Map<Id, Contact> syncedContactMap
    ) {
        return ArloEventRegistrationSync.findUnmatchedWrappers(contactEventList, syncedContactMap);
    }

    /**
     * Create missing contacts in Salesforce
     * Returns number of contacts created
     */
    @TestVisible
    private Integer createMissingContacts(
        List<ArloEventRegistrationSync.ContactEventWrapper> unmatchedWrappers,
        Map<String, ArloModels.ArloContact> arloContactMap,
        Map<Id, Contact> syncedContactMap
    ) {
        Integer contactsCreated = 0;

        // Build lookup maps
        Map<String, String> uuidToNumericId = new Map<String, String>();
        Map<String, String> emailToNumericId = new Map<String, String>();

        for (String numericId : arloContactMap.keySet()) {
            ArloModels.ArloContact ac = arloContactMap.get(numericId);
            if (ac != null) {
                if (String.isNotBlank(ac.contactId)) {
                    uuidToNumericId.put(ac.contactId.trim().toLowerCase(), numericId);
                }
                if (String.isNotBlank(ac.email)) {
                    emailToNumericId.put(ac.email.toLowerCase().trim(), numericId);
                }
            }
        }

        // Map unmatched wrappers to numeric IDs
        Set<String> numericIdsToCreate = new Set<String>();
        for (ArloEventRegistrationSync.ContactEventWrapper wrapper : unmatchedWrappers) {
            if (wrapper.contact != null) {
                String wrapperUuid = wrapper.contact.contactId != null ? wrapper.contact.contactId.trim().toLowerCase() : '';
                String wrapperEmail = wrapper.contact.email != null ? wrapper.contact.email.toLowerCase().trim() : '';

                String numericId = null;
                if (String.isNotBlank(wrapperUuid) && uuidToNumericId.containsKey(wrapperUuid)) {
                    numericId = uuidToNumericId.get(wrapperUuid);
                } else if (String.isNotBlank(wrapperEmail) && emailToNumericId.containsKey(wrapperEmail)) {
                    numericId = emailToNumericId.get(wrapperEmail);
                }

                if (String.isNotBlank(numericId)) {
                    numericIdsToCreate.add(numericId);
                }
            }
        }

        // Fetch full contact details for unmatched contacts
        List<ArloModels.ArloContact> contactsToCreate = new List<ArloModels.ArloContact>();

        for (String numericContactId : numericIdsToCreate) {
            if (!hasCalloutsRemaining(5)) {
                break;
            }

            ArloModels.ArloContact fullContact = ArloContactSync.getSingleArloContactStatic(numericContactId, username, password);

            if (fullContact != null && String.isNotBlank(fullContact.organisationCodePrimary)) {
                contactsToCreate.add(fullContact);
            }
        }

        // Create contacts in Salesforce (grouped by Account)
        if (!contactsToCreate.isEmpty()) {
            Map<String, List<ArloModels.ArloContact>> contactsByAccount = new Map<String, List<ArloModels.ArloContact>>();

            for (ArloModels.ArloContact ac : contactsToCreate) {
                if (String.isNotBlank(ac.organisationCodePrimary)) {
                    if (!contactsByAccount.containsKey(ac.organisationCodePrimary)) {
                        contactsByAccount.put(ac.organisationCodePrimary, new List<ArloModels.ArloContact>());
                    }
                    contactsByAccount.get(ac.organisationCodePrimary).add(ac);
                }
            }

            // Create contacts for each Account
            for (String codePrimary : contactsByAccount.keySet()) {
                Account sfAccount = ArloEventRegistrationSync.getSalesforceAccountByNumberStatic(codePrimary);
                if (sfAccount != null) {
                    List<ArloModels.ArloContact> accountContacts = contactsByAccount.get(codePrimary);
                    ArloContactSync.syncContactsToSalesforceStatic(accountContacts, sfAccount.Id);

                    // Query for newly created contacts
                    Set<String> newContactUuids = new Set<String>();
                    Set<String> newContactEmails = new Set<String>();
                    for (ArloModels.ArloContact ac : accountContacts) {
                        if (String.isNotBlank(ac.contactId)) {
                            newContactUuids.add(ac.contactId);
                        }
                        if (String.isNotBlank(ac.email)) {
                            newContactEmails.add(ac.email);
                        }
                    }

                    List<Contact> newlyCreatedContacts = [
                        SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c
                        FROM Contact
                        WHERE (Arlo_Contact_UUID__c IN :newContactUuids AND Arlo_Contact_UUID__c != null)
                           OR (Email IN :newContactEmails AND Email != null)
                    ];

                    for (Contact c : newlyCreatedContacts) {
                        syncedContactMap.put(c.Id, c);
                    }

                    contactsCreated += newlyCreatedContacts.size();
                }
            }
        }

        return contactsCreated;
    }
    
    /**
     * Update log after processing all pages in this batch execution
     */
    @TestVisible
    private void updateLogAfterBatch() {
        // Update log with progress
        if (logId != null) {
            ArloEventRegistrationSync.updateLogRecordStatic(
                logId, 
                'In Progress', 
                'Page ' + currentPage + ' complete. Total contacts found: ' + totalContactLinks + ', Processed: ' + totalProcessed + ', Successful: ' + totalSuccessful + ', Created: ' + totalContactsCreated, 
                null, 
                totalProcessed, 
                totalSuccessful
            );
        }
    }
    
    /**
     * Finish method - updates log with final results
     */
    public void finish(Database.BatchableContext bc) {
        String finalMessage = 'Completed! Found ' + totalContactLinks + ' contacts. Processed ' + totalProcessed + ' contact-event pairs. Successfully added ' + totalSuccessful + ' to campaigns. Created ' + totalContactsCreated + ' new contacts. Failed: ' + totalFailed;

        if (logId != null) {
            ArloEventRegistrationSync.updateLogRecordStatic(
                logId,
                'Success',
                finalMessage,
                null,
                totalProcessed,
                totalSuccessful
            );
        }
    }
    
    /**
     * Fetch contact status from Arlo API
     * Uses instance apiClient for HTTP calls (saves callouts vs static methods)
     * @param numericContactId The numeric ID of the contact in Arlo
     * @return The status string (e.g., "Active", "Inactive") or null on error
     */
    @TestVisible
    private String fetchContactStatus(String numericContactId) {
        try {
            String endpoint = ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId;
            String responseBody = apiClient.getXml(endpoint);

            if (responseBody != null) {
                // Use ArloXmlParser to extract Status
                return ArloXmlParser.extractElementValue(responseBody, 'Status');
            }
        } catch (Exception e) {
            System.debug('ArloRegistrationSyncBatch: Error getting contact status for ID ' + numericContactId + ': ' + e.getMessage());
            System.debug('ArloRegistrationSyncBatch: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }

    /**
     * Fetch contact UUID and Email from Arlo API
     * Uses instance apiClient for HTTP calls (more efficient than static methods)
     * Only retrieves UUID and Email fields to minimize parsing overhead
     * @param numericContactId The numeric ID of the contact in Arlo
     * @return ArloContact with contactId (UUID) and email populated, or null on error
     */
    @TestVisible
    private ArloModels.ArloContact fetchContactUuidAndEmail(String numericContactId) {
        try {
            String endpoint = ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId;
            String responseBody = apiClient.getXml(endpoint);

            if (responseBody != null) {
                ArloModels.ArloContact contact = new ArloModels.ArloContact();
                contact.numericContactId = numericContactId;

                // Use ArloXmlParser to extract fields
                contact.contactId = ArloXmlParser.extractElementValue(responseBody, 'UniqueIdentifier');
                contact.email = ArloXmlParser.extractElementValue(responseBody, 'Email');

                // If no UniqueIdentifier found, try ContactID as fallback
                if (String.isBlank(contact.contactId)) {
                    contact.contactId = ArloXmlParser.extractElementValue(responseBody, 'ContactID');
                }

                return contact;
            }
        } catch (Exception e) {
            System.debug('ArloRegistrationSyncBatch: Error getting contact UUID/Email for ID ' + numericContactId + ': ' + e.getMessage());
            System.debug('ArloRegistrationSyncBatch: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }
    
    /**
     * Fetch registration IDs for a contact from Arlo API
     * Uses instance apiClient for HTTP calls (more efficient than static methods)
     * @param numericContactId The numeric ID of the contact in Arlo
     * @return Set of registration IDs for this contact, empty set on error
     */
    @TestVisible
    private Set<String> fetchContactRegistrations(String numericContactId) {
        Set<String> registrationIds = new Set<String>();
        try {
            String endpoint = ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId + '/registrations/';
            String responseBody = apiClient.getXml(endpoint);

            if (responseBody != null) {
                // Use ArloXmlParser to extract registration IDs
                registrationIds = ArloXmlParser.extractResourceIds(responseBody, 'registrations');
            }
        } catch (Exception e) {
            System.debug('ArloRegistrationSyncBatch: Error getting registrations for contact ID ' + numericContactId + ': ' + e.getMessage());
            System.debug('ArloRegistrationSyncBatch: Stack trace: ' + e.getStackTraceString());
        }
        return registrationIds;
    }
    
    /**
     * Helper method to find Salesforce contacts for Arlo contacts
     * Delegates to ArloEventRegistrationSync for DRY compliance
     */
    @TestVisible
    private Map<Id, Contact> findSalesforceContacts(
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList,
        Map<String, ArloModels.ArloContact> arloContactMap
    ) {
        return ArloEventRegistrationSync.findSalesforceContactsForArloContacts(contactEventList, arloContactMap);
    }
    
    /**
     * Extract contact links from XML response
     * Delegates to ArloEventRegistrationSync for DRY compliance
     */
    @TestVisible
    private List<String> extractContactLinksFromCollection(String xmlBody) {
        return ArloEventRegistrationSync.extractContactLinksFromCollection(xmlBody);
    }
    
    /**
     * Start the batch job
     * @param username Arlo API username (null to use Arlo_Credentials__c)
     * @param password Arlo API password (null to use Arlo_Credentials__c)
     * @return The batch job ID
     */
    public static Id startSync(String username, String password) {
        ArloRegistrationSyncBatch batch = new ArloRegistrationSyncBatch(username, password);
        return Database.executeBatch(batch, 5);
    }
}