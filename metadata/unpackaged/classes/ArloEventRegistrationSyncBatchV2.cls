/**
 * ArloEventRegistrationSyncBatchV2
 * 
 * Batch class version of Arlo Event Registration Sync
 * Uses Database.Batchable to ensure contact creation happens correctly
 * Each batch has its own callout limit, ensuring contacts are created even when processing many registrations
 * 
 * VERSION 2 - Batch Class Implementation
 * 
 * Flow:
 * 1. GET all contacts -> /resources/contacts/
 * 2. For each contact, get registrations -> /resources/contacts/{id}/registrations
 * 3. For each registration, get event -> /resources/events/{id}/
 * 4. If event contains NHM, get customfields -> /resources/registrations/{id}/customfields
 * 5. Check consent - if true, sync/create contact and add to campaign
 * 
 * @author System Generated
 * @version 2.0
 */
public class ArloEventRegistrationSyncBatchV2 implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
    
    // Credentials for Basic Auth
    private String username;
    private String password;
    
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
    
    /**
     * Constructor
     */
    public ArloEventRegistrationSyncBatchV2(String username, String password) {
        this.username = username;
        this.password = password;
    }
    
    /**
     * Start method - returns page numbers to process
     * NOTE: Cannot make callouts in start() method, so we return page numbers
     * Each page will be fetched in execute() method
     */
    public Iterable<Integer> start(Database.BatchableContext bc) {
        System.debug('ArloEventRegistrationSyncBatchV2: ===== STARTING BATCH JOB =====');
        
        // Use Custom Settings if credentials not provided
        if (String.isBlank(username) || String.isBlank(password)) {
            Arlo_Credentials__c credentials = Arlo_Credentials__c.getOrgDefaults();
            if (credentials != null && String.isNotBlank(credentials.Username__c) && String.isNotBlank(credentials.Password__c)) {
                username = credentials.Username__c;
                password = credentials.Password__c;
                System.debug('ArloEventRegistrationSyncBatchV2: Loaded credentials from Custom Settings');
            } else {
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
        // Start with page 1, and continue until no more pages
        // Increase to 200 pages to ensure we process all contacts
        List<Integer> pages = new List<Integer>();
        for (Integer i = 1; i <= 200; i++) { // Max 200 pages (safety limit)
            pages.add(i);
        }
        
        System.debug('ArloEventRegistrationSyncBatchV2: Will process up to 200 pages of contacts');
        return pages;
    }
    
    /**
     * Execute method - processes deferred contacts first, then fetches a new page if needed
     * Each batch has its own callout limit (100 callouts), ensuring contact creation can happen
     */
    public void execute(Database.BatchableContext bc, List<Integer> pageNumbers) {
        // Process only the first page number in this batch
        if (pageNumbers.isEmpty()) {
            System.debug('ArloEventRegistrationSyncBatchV2: No more pages to process');
            return;
        }
        
        Integer pageNumber = pageNumbers[0];
        currentPage = pageNumber;
        
        // First, process any unprocessed contacts from previous batch
        List<String> contactsToProcess = new List<String>();
        Boolean hasDeferredContacts = !unprocessedContactLinks.isEmpty();
        
        if (hasDeferredContacts) {
            System.debug('ArloEventRegistrationSyncBatchV2: ===== PROCESSING DEFERRED CONTACTS =====');
            System.debug('ArloEventRegistrationSyncBatchV2: Processing ' + unprocessedContactLinks.size() + ' deferred contact(s) from previous batch');
            contactsToProcess.addAll(unprocessedContactLinks);
            unprocessedContactLinks.clear(); // Clear after adding - will repopulate if needed
        }
        
        // Fetch a new page if we don't have deferred contacts (or if we finish processing them)
        // We'll check after processing if we need to fetch a new page
        List<String> batchContactLinks = new List<String>();
        if (!hasDeferredContacts && String.isNotBlank(nextLink)) {
            System.debug('ArloEventRegistrationSyncBatchV2: ===== FETCHING PAGE ' + pageNumber + ' =====');
            
            try {
                System.debug('ArloEventRegistrationSyncBatchV2: Fetching contact links from: ' + nextLink);
                
                HttpRequest req = new HttpRequest();
                req.setEndpoint(nextLink);
                req.setMethod('GET');
                req.setHeader('Accept', 'application/xml');
                
                Blob authBlob = Blob.valueOf(username + ':' + password);
                String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
                req.setHeader('Authorization', authHeader);
                req.setTimeout(30000);
                
                Http http = new Http();
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() == 200) {
                    String responseBody = res.getBody();
                    
                    // Extract contact links from XML
                    batchContactLinks = extractContactLinksFromCollection(responseBody);
                    totalContactLinks += batchContactLinks.size();
                    System.debug('ArloEventRegistrationSyncBatchV2: Found ' + batchContactLinks.size() + ' contact(s) on page ' + pageNumber + ' (total so far: ' + totalContactLinks + ')');
                    
                    // Check for "next" link for pagination
                    Pattern nextPattern = Pattern.compile('<Link[^>]*rel="next"[^>]*href="([^"]*)"');
                    Matcher nextMatcher = nextPattern.matcher(responseBody);
                    if (nextMatcher.find()) {
                        nextLink = nextMatcher.group(1);
                        System.debug('ArloEventRegistrationSyncBatchV2: Found next page link: ' + nextLink);
                    } else {
                        nextLink = null; // No more pages
                        System.debug('ArloEventRegistrationSyncBatchV2: No more pages to fetch');
                    }
                } else {
                    System.debug('ArloEventRegistrationSyncBatchV2: Error fetching contacts page. Status: ' + res.getStatusCode());
                    nextLink = null; // Stop processing
                }
            } catch (Exception e) {
                System.debug('ArloEventRegistrationSyncBatchV2: Error fetching contact links: ' + e.getMessage());
                nextLink = null; // Stop processing
            }
            
            if (!batchContactLinks.isEmpty()) {
                contactsToProcess.addAll(batchContactLinks);
            }
        } else if (hasDeferredContacts) {
            System.debug('ArloEventRegistrationSyncBatchV2: Skipping page fetch - processing deferred contacts first');
        } else if (String.isBlank(nextLink)) {
            System.debug('ArloEventRegistrationSyncBatchV2: No more pages to fetch (nextLink is blank)');
        }
        
        if (contactsToProcess.isEmpty()) {
            System.debug('ArloEventRegistrationSyncBatchV2: No contacts to process in this batch');
            return;
        }
        
        System.debug('ArloEventRegistrationSyncBatchV2: Processing ' + contactsToProcess.size() + ' total contact(s) (page ' + pageNumber + ' + deferred)');
        
        Integer batchProcessed = 0;
        Integer batchSuccessful = 0;
        Integer batchFailed = 0;
        Integer batchContactsCreated = 0;
        
        // Process each contact in this batch
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList = new List<ArloEventRegistrationSync.ContactEventWrapper>();
        Map<String, ArloContactSync.ArloContact> arloContactMap = new Map<String, ArloContactSync.ArloContact>();
        Integer maxCallouts = 100; // Batch limit
        Integer reservedForContactCreation = 15; // Reserve callouts for contact creation
        
        try {
            Integer processedCount = 0;
            for (String contactLink : contactsToProcess) {
                try {
                    // Check callout limit BEFORE processing this contact
                    Integer remainingCallouts = maxCallouts - Limits.getCallouts();
                    if (remainingCallouts < 10) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Approaching callout limit (' + remainingCallouts + ' remaining) - deferring remaining contacts');
                        // Add remaining contacts to unprocessed list
                        Integer currentIndex = contactsToProcess.indexOf(contactLink);
                        for (Integer i = currentIndex; i < contactsToProcess.size(); i++) {
                            unprocessedContactLinks.add(contactsToProcess[i]);
                        }
                        System.debug('ArloEventRegistrationSyncBatchV2: Deferred ' + unprocessedContactLinks.size() + ' contact(s) to next batch');
                        break;
                    }
                    
                    // Extract numeric contact ID from link
                    // Use regex to extract ID from link like /resources/contacts/300/
                    String numericContactId = null;
                    if (String.isNotBlank(contactLink)) {
                        Pattern idPattern = Pattern.compile('/contacts/(\\d+)/');
                        Matcher matcher = idPattern.matcher(contactLink);
                        if (matcher.find()) {
                            numericContactId = matcher.group(1);
                        }
                    }
                    
                    if (String.isBlank(numericContactId)) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Could not extract contact ID from link: ' + contactLink);
                        continue;
                    }
                    
                    // STEP 1: Get contact details and check Status = "Active"
                    remainingCallouts = maxCallouts - Limits.getCallouts();
                    if (remainingCallouts < 5) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Too few callouts remaining (' + remainingCallouts + ') - deferring remaining contacts');
                        // Add remaining contacts to unprocessed list
                        Integer currentIndex = contactsToProcess.indexOf(contactLink);
                        for (Integer i = currentIndex; i < contactsToProcess.size(); i++) {
                            unprocessedContactLinks.add(contactsToProcess[i]);
                        }
                        break;
                    }
                    String contactStatus = getContactStatus(numericContactId);
                    
                    if (String.isBlank(contactStatus) || contactStatus != 'Active') {
                        continue; // Skip non-Active contacts
                    }
                    
                    // STEP 2: Get contact details (UUID, Email) for Salesforce matching
                    remainingCallouts = maxCallouts - Limits.getCallouts();
                    if (remainingCallouts < 5) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Too few callouts remaining (' + remainingCallouts + ') - deferring remaining contacts');
                        // Add remaining contacts to unprocessed list
                        Integer currentIndex = contactsToProcess.indexOf(contactLink);
                        for (Integer i = currentIndex; i < contactsToProcess.size(); i++) {
                            unprocessedContactLinks.add(contactsToProcess[i]);
                        }
                        break;
                    }
                    ArloContactSync.ArloContact arloContact = getContactUuidAndEmail(numericContactId);
                    if (arloContact == null || (String.isBlank(arloContact.contactId) && String.isBlank(arloContact.email))) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Could not get contact UUID/Email for ID: ' + numericContactId);
                        continue;
                    }
                    arloContactMap.put(numericContactId, arloContact);
                    
                    // STEP 3: Get registrations for this contact
                    remainingCallouts = maxCallouts - Limits.getCallouts();
                    if (remainingCallouts < 5) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Too few callouts remaining (' + remainingCallouts + ') - deferring remaining contacts');
                        // Add remaining contacts to unprocessed list
                        Integer currentIndex = contactsToProcess.indexOf(contactLink);
                        for (Integer i = currentIndex; i < contactsToProcess.size(); i++) {
                            unprocessedContactLinks.add(contactsToProcess[i]);
                        }
                        break;
                    }
                    Set<String> registrationIds = getContactRegistrations(numericContactId);
                    
                    if (registrationIds.isEmpty()) {
                        continue;
                    }
                    
                    System.debug('ArloEventRegistrationSyncBatchV2: Contact ' + numericContactId + ' has ' + registrationIds.size() + ' registration(s)');
                    
                    // STEP 4: Process each registration
                    for (String registrationId : registrationIds) {
                        // Check callout limit - reserve some for contact creation
                        remainingCallouts = maxCallouts - Limits.getCallouts();
                        if (remainingCallouts < reservedForContactCreation + 5) {
                            System.debug('ArloEventRegistrationSyncBatchV2: Approaching callout limit (remaining: ' + remainingCallouts + ', reserved: ' + reservedForContactCreation + ' for contact creation) - stopping registration processing');
                            break;
                        }
                        
                        // STEP 4a: Get registration details (to get event ID)
                        String eventId = ArloEventRegistrationSync.getEventIdFromRegistrationStatic(registrationId, username, password);
                        if (String.isBlank(eventId)) {
                            continue;
                        }
                        
                        // Check callout limit again
                        remainingCallouts = maxCallouts - Limits.getCallouts();
                        if (remainingCallouts < reservedForContactCreation + 5) {
                            System.debug('ArloEventRegistrationSyncBatchV2: Approaching callout limit - stopping registration processing');
                            break;
                        }
                        
                        // STEP 4b: Get event details and check if event contains "NHM"
                        ArloEventRegistrationSync.EventData eventData = ArloEventRegistrationSync.getEventDetailsStatic(eventId, username, password);
                        if (eventData == null) {
                            continue;
                        }
                        
                        // Only process events that contain "NHM"
                        Boolean eventContainsNHM = false;
                        if (String.isNotBlank(eventData.name) && eventData.name.contains('NHM')) {
                            eventContainsNHM = true;
                        } else if (String.isNotBlank(eventData.code) && eventData.code.contains('NHM')) {
                            eventContainsNHM = true;
                        }
                        
                        if (!eventContainsNHM) {
                            continue;
                        }
                        
                        // Check callout limit again before consent check
                        remainingCallouts = maxCallouts - Limits.getCallouts();
                        if (remainingCallouts < reservedForContactCreation + 5) {
                            System.debug('ArloEventRegistrationSyncBatchV2: Approaching callout limit - stopping registration processing');
                            break;
                        }
                        
                        // STEP 4c: Check email consent
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
                        batchProcessed++;
                        
                        System.debug('ArloEventRegistrationSyncBatchV2: ✓ Contact ' + numericContactId + ' - Registration ' + registrationId + ' passed all checks (Event: ' + eventData.name + ')');
                    }
                    
                    processedCount++;
                    
                } catch (Exception e) {
                    batchFailed++;
                    System.debug('ArloEventRegistrationSyncBatchV2: Error processing contact link ' + contactLink + ': ' + e.getMessage());
                    System.debug('ArloEventRegistrationSyncBatchV2: Stack trace: ' + e.getStackTraceString());
                }
            }
            
            System.debug('ArloEventRegistrationSyncBatchV2: Processed ' + processedCount + ' of ' + contactsToProcess.size() + ' contact(s) in this batch');
            if (!unprocessedContactLinks.isEmpty()) {
                System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ ' + unprocessedContactLinks.size() + ' contact(s) deferred to next batch due to callout limits');
            } else if (hasDeferredContacts && String.isNotBlank(nextLink)) {
                // We finished processing deferred contacts, now fetch the next page
                System.debug('ArloEventRegistrationSyncBatchV2: Finished processing deferred contacts, fetching next page...');
                try {
                    HttpRequest req = new HttpRequest();
                    req.setEndpoint(nextLink);
                    req.setMethod('GET');
                    req.setHeader('Accept', 'application/xml');
                    
                    Blob authBlob = Blob.valueOf(username + ':' + password);
                    String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
                    req.setHeader('Authorization', authHeader);
                    req.setTimeout(30000);
                    
                    Http http = new Http();
                    HttpResponse res = http.send(req);
                    
                    if (res.getStatusCode() == 200) {
                        String responseBody = res.getBody();
                        batchContactLinks = extractContactLinksFromCollection(responseBody);
                        totalContactLinks += batchContactLinks.size();
                        System.debug('ArloEventRegistrationSyncBatchV2: Found ' + batchContactLinks.size() + ' contact(s) on next page (total so far: ' + totalContactLinks + ')');
                        
                        // Check for "next" link for pagination
                        Pattern nextPattern = Pattern.compile('<Link[^>]*rel="next"[^>]*href="([^"]*)"');
                        Matcher nextMatcher = nextPattern.matcher(responseBody);
                        if (nextMatcher.find()) {
                            nextLink = nextMatcher.group(1);
                            System.debug('ArloEventRegistrationSyncBatchV2: Found next page link: ' + nextLink);
                        } else {
                            nextLink = null;
                            System.debug('ArloEventRegistrationSyncBatchV2: No more pages to fetch');
                        }
                        
                        // Add new page contacts to unprocessed list for next batch
                        if (!batchContactLinks.isEmpty()) {
                            unprocessedContactLinks.addAll(batchContactLinks);
                            System.debug('ArloEventRegistrationSyncBatchV2: Added ' + batchContactLinks.size() + ' contact(s) from next page to deferred list');
                        }
                    }
                } catch (Exception e) {
                    System.debug('ArloEventRegistrationSyncBatchV2: Error fetching next page after deferred contacts: ' + e.getMessage());
                }
            }
            
            // STEP 5: NOW DO ALL DML OPERATIONS (after all callouts are complete)
            if (!contactEventList.isEmpty()) {
                System.debug('ArloEventRegistrationSyncBatchV2: Processing ' + contactEventList.size() + ' contact-event pairs');
                
                try {
                    // Find Salesforce contacts for each Arlo contact
                    System.debug('ArloEventRegistrationSyncBatchV2: ===== FINDING SALESFORCE CONTACTS =====');
                    System.debug('ArloEventRegistrationSyncBatchV2: contactEventList size: ' + contactEventList.size());
                    System.debug('ArloEventRegistrationSyncBatchV2: arloContactMap size: ' + arloContactMap.size());
                    Map<Id, Contact> syncedContactMap = findSalesforceContacts(contactEventList, arloContactMap);
                    System.debug('ArloEventRegistrationSyncBatchV2: Found ' + syncedContactMap.size() + ' Salesforce contact(s)');
                    
                    // STEP 5a: Create missing contacts in Salesforce
                    List<ArloEventRegistrationSync.ContactEventWrapper> unmatchedWrappers = new List<ArloEventRegistrationSync.ContactEventWrapper>();
                    Set<String> matchedUuids = new Set<String>();
                    Set<String> matchedEmails = new Set<String>();
                    
                    for (Contact c : syncedContactMap.values()) {
                        if (String.isNotBlank(c.Arlo_Contact_UUID__c)) {
                            matchedUuids.add(c.Arlo_Contact_UUID__c.trim().toLowerCase());
                        }
                        if (String.isNotBlank(c.Email)) {
                            matchedEmails.add(c.Email.toLowerCase().trim());
                        }
                    }
                    
                    // Find unmatched contacts (need to be created)
                    for (ArloEventRegistrationSync.ContactEventWrapper wrapper : contactEventList) {
                        if (wrapper.contact != null) {
                            Boolean isMatched = false;
                            String wrapperUuid = wrapper.contact.contactId != null ? wrapper.contact.contactId.trim().toLowerCase() : '';
                            String wrapperEmail = wrapper.contact.email != null ? wrapper.contact.email.toLowerCase().trim() : '';
                            
                            if ((String.isNotBlank(wrapperUuid) && matchedUuids.contains(wrapperUuid)) ||
                                (String.isNotBlank(wrapperEmail) && matchedEmails.contains(wrapperEmail))) {
                                isMatched = true;
                            }
                            
                            if (!isMatched) {
                                unmatchedWrappers.add(wrapper);
                            }
                        }
                    }
                    
                    // Create missing contacts
                    if (!unmatchedWrappers.isEmpty()) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ===== CONTACT CREATION PHASE =====');
                        System.debug('ArloEventRegistrationSyncBatchV2: Found ' + unmatchedWrappers.size() + ' unmatched contact(s) - will create in Salesforce');
                        
                        // Group by numeric contact ID to avoid duplicate fetches
                        Map<String, String> uuidToNumericId = new Map<String, String>();
                        Map<String, String> emailToNumericId = new Map<String, String>();
                        
                        for (String numericId : arloContactMap.keySet()) {
                            ArloContactSync.ArloContact ac = arloContactMap.get(numericId);
                            if (ac != null) {
                                if (String.isNotBlank(ac.contactId)) {
                                    uuidToNumericId.put(ac.contactId.trim().toLowerCase(), numericId);
                                }
                                if (String.isNotBlank(ac.email)) {
                                    emailToNumericId.put(ac.email.toLowerCase().trim(), numericId);
                                }
                            }
                        }
                        
                        Map<String, ArloEventRegistrationSync.ContactEventWrapper> numericIdToWrapper = new Map<String, ArloEventRegistrationSync.ContactEventWrapper>();
                        for (ArloEventRegistrationSync.ContactEventWrapper wrapper : unmatchedWrappers) {
                            String numericId = null;
                            if (wrapper.contact != null) {
                                String wrapperUuid = wrapper.contact.contactId != null ? wrapper.contact.contactId.trim().toLowerCase() : '';
                                String wrapperEmail = wrapper.contact.email != null ? wrapper.contact.email.toLowerCase().trim() : '';
                                
                                if (String.isNotBlank(wrapperUuid) && uuidToNumericId.containsKey(wrapperUuid)) {
                                    numericId = uuidToNumericId.get(wrapperUuid);
                                } else if (String.isNotBlank(wrapperEmail) && emailToNumericId.containsKey(wrapperEmail)) {
                                    numericId = emailToNumericId.get(wrapperEmail);
                                }
                                
                                if (String.isNotBlank(numericId) && !numericIdToWrapper.containsKey(numericId)) {
                                    numericIdToWrapper.put(numericId, wrapper);
                                }
                            }
                        }
                        
                        // Fetch full contact details (including employment) for unmatched contacts
                        // In Batch class, we have a fresh callout limit, so we can create contacts
                        List<ArloContactSync.ArloContact> contactsToCreate = new List<ArloContactSync.ArloContact>();
                        
                        for (String numericContactId : numericIdToWrapper.keySet()) {
                            // Check remaining callouts - ensure we have enough for contact creation (3 callouts per contact)
                            Integer remainingCallouts = maxCallouts - Limits.getCallouts();
                            if (remainingCallouts < 5) {
                                System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Low on callouts (' + remainingCallouts + ' remaining) - will create remaining contacts in next batch');
                                break;
                            }
                            
                            // Fetch full contact details with employment data (3 callouts: contact + employment + org)
                            System.debug('ArloEventRegistrationSyncBatchV2: Fetching full contact details for ID ' + numericContactId + ' to create in Salesforce');
                            ArloContactSync.ArloContact fullContact = ArloContactSync.getSingleArloContactStatic(numericContactId, username, password);
                            
                            if (fullContact != null && String.isNotBlank(fullContact.organisationCodePrimary)) {
                                contactsToCreate.add(fullContact);
                                System.debug('ArloEventRegistrationSyncBatchV2: ✓ Contact ' + numericContactId + ' will be created with Account CodePrimary: ' + fullContact.organisationCodePrimary);
                            } else {
                                System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Cannot create contact ' + numericContactId + ' - no organisation CodePrimary found');
                            }
                        }
                        
                        // Create contacts in Salesforce (grouped by Account)
                        if (!contactsToCreate.isEmpty()) {
                            Map<String, List<ArloContactSync.ArloContact>> contactsByAccount = new Map<String, List<ArloContactSync.ArloContact>>();
                            
                            for (ArloContactSync.ArloContact ac : contactsToCreate) {
                                if (String.isNotBlank(ac.organisationCodePrimary)) {
                                    if (!contactsByAccount.containsKey(ac.organisationCodePrimary)) {
                                        contactsByAccount.put(ac.organisationCodePrimary, new List<ArloContactSync.ArloContact>());
                                    }
                                    contactsByAccount.get(ac.organisationCodePrimary).add(ac);
                                }
                            }
                            
                            // Create contacts for each Account
                            for (String codePrimary : contactsByAccount.keySet()) {
                                Account sfAccount = ArloEventRegistrationSync.getSalesforceAccountByNumberStatic(codePrimary);
                                if (sfAccount != null) {
                                    List<ArloContactSync.ArloContact> accountContacts = contactsByAccount.get(codePrimary);
                                    System.debug('ArloEventRegistrationSyncBatchV2: Creating ' + accountContacts.size() + ' contact(s) for Account: ' + sfAccount.Name);
                                    ArloContactSync.syncContactsToSalesforceStatic(accountContacts, sfAccount.Id);
                                    
                                    // Query for newly created contacts
                                    Set<String> newContactUuids = new Set<String>();
                                    Set<String> newContactEmails = new Set<String>();
                                    for (ArloContactSync.ArloContact ac : accountContacts) {
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
                                    
                                    batchContactsCreated += newlyCreatedContacts.size();
                                    System.debug('ArloEventRegistrationSyncBatchV2: ✓ Successfully created ' + newlyCreatedContacts.size() + ' contact(s)');
                                } else {
                                    System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ Cannot create contacts - Account not found for CodePrimary: ' + codePrimary);
                                }
                            }
                        }
                    }
                    
                    // STEP 5b: Now add all contacts (existing + newly created) to campaigns
                    System.debug('ArloEventRegistrationSyncBatchV2: ===== CAMPAIGN ASSIGNMENT PHASE =====');
                    System.debug('ArloEventRegistrationSyncBatchV2: Contact-event pairs to process: ' + contactEventList.size());
                    System.debug('ArloEventRegistrationSyncBatchV2: Salesforce contacts available: ' + syncedContactMap.size());
                    
                    // Debug: Log wrapper details
                    for (ArloEventRegistrationSync.ContactEventWrapper wrapper : contactEventList) {
                        if (wrapper.contact != null) {
                            System.debug('ArloEventRegistrationSyncBatchV2: Wrapper - UUID: ' + wrapper.contact.contactId + ', Email: ' + wrapper.contact.email + ', Event: ' + wrapper.eventName);
                        }
                    }
                    
                    // Debug: Log synced contacts
                    for (Contact c : syncedContactMap.values()) {
                        System.debug('ArloEventRegistrationSyncBatchV2: Synced Contact - Id: ' + c.Id + ', UUID: ' + c.Arlo_Contact_UUID__c + ', Email: ' + c.Email);
                    }
                    
                    if (contactEventList.isEmpty()) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ No contact-event pairs to process for campaign assignment');
                    } else if (syncedContactMap.isEmpty()) {
                        System.debug('ArloEventRegistrationSyncBatchV2: ⚠️ No Salesforce contacts found to add to campaigns');
                    } else {
                        ArloEventRegistrationSync.addContactsToCampaignsStatic(contactEventList, syncedContactMap);
                        System.debug('ArloEventRegistrationSyncBatchV2: ===== CAMPAIGN ASSIGNMENT COMPLETE =====');
                    }
                    batchSuccessful = contactEventList.size();
                    
                } catch (Exception e) {
                    System.debug('ArloEventRegistrationSyncBatchV2: Error processing contacts: ' + e.getMessage());
                    System.debug('ArloEventRegistrationSyncBatchV2: Stack trace: ' + e.getStackTraceString());
                    batchFailed += contactEventList.size();
                }
            }
            
            // Update stateful variables
            totalProcessed += batchProcessed;
            totalSuccessful += batchSuccessful;
            totalFailed += batchFailed;
            totalContactsCreated += batchContactsCreated;
            
            System.debug('ArloEventRegistrationSyncBatchV2: Batch complete - Processed: ' + batchProcessed + ', Successful: ' + batchSuccessful + ', Failed: ' + batchFailed + ', Contacts Created: ' + batchContactsCreated);
            
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSyncBatchV2: Error in execute method: ' + e.getMessage());
            System.debug('ArloEventRegistrationSyncBatchV2: Stack trace: ' + e.getStackTraceString());
            totalFailed += batchContactLinks.size();
        }
        
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
        System.debug('ArloEventRegistrationSyncBatchV2: ===== BATCH JOB COMPLETE =====');
        System.debug('ArloEventRegistrationSyncBatchV2: Total Contact Links Found: ' + totalContactLinks);
        System.debug('ArloEventRegistrationSyncBatchV2: Total Processed: ' + totalProcessed);
        System.debug('ArloEventRegistrationSyncBatchV2: Total Successful: ' + totalSuccessful);
        System.debug('ArloEventRegistrationSyncBatchV2: Total Failed: ' + totalFailed);
        System.debug('ArloEventRegistrationSyncBatchV2: Total Contacts Created: ' + totalContactsCreated);
        
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
        
        System.debug('ArloEventRegistrationSyncBatchV2: ==========================');
    }
    
    /**
     * Helper method to get contact status
     */
    private String getContactStatus(String numericContactId) {
        try {
            String endpoint = ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/xml');
            
            Blob authBlob = Blob.valueOf(username + ':' + password);
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
            req.setHeader('Authorization', authHeader);
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();
                // Parse XML to find Status element
                Dom.Document doc = new Dom.Document();
                doc.load(responseBody);
                Dom.XmlNode root = doc.getRootElement();
                
                // Search for Status element
                for (Dom.XmlNode child : root.getChildElements()) {
                    if (child.getName() == 'Status') {
                        return child.getText();
                    }
                }
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSyncBatchV2: Error getting contact status: ' + e.getMessage());
        }
        return null;
    }
    
    /**
     * Helper method to get contact UUID and Email only (saves callouts)
     */
    private ArloContactSync.ArloContact getContactUuidAndEmail(String numericContactId) {
        try {
            String endpoint = ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/xml');
            
            Blob authBlob = Blob.valueOf(username + ':' + password);
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
            req.setHeader('Authorization', authHeader);
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();
                Dom.Document doc = new Dom.Document();
                doc.load(responseBody);
                Dom.XmlNode root = doc.getRootElement();
                
                ArloContactSync.ArloContact contact = new ArloContactSync.ArloContact();
                contact.numericContactId = numericContactId;
                
                // Extract UniqueIdentifier (UUID) and Email from XML using regex (like original method)
                // Extract UniqueIdentifier (UUID)
                Pattern uuidPattern = Pattern.compile('<UniqueIdentifier>([^<]+)</UniqueIdentifier>');
                Matcher uuidMatcher = uuidPattern.matcher(responseBody);
                if (uuidMatcher.find()) {
                    contact.contactId = uuidMatcher.group(1).trim();
                }
                
                // Extract Email
                Pattern emailPattern = Pattern.compile('<Email>([^<]+)</Email>');
                Matcher emailMatcher = emailPattern.matcher(responseBody);
                if (emailMatcher.find()) {
                    contact.email = emailMatcher.group(1).trim();
                }
                
                // If no UniqueIdentifier found, try ContactID as fallback
                if (String.isBlank(contact.contactId)) {
                    Pattern contactIdPattern = Pattern.compile('<ContactID>([^<]+)</ContactID>');
                    Matcher contactIdMatcher = contactIdPattern.matcher(responseBody);
                    if (contactIdMatcher.find()) {
                        contact.contactId = contactIdMatcher.group(1).trim();
                    }
                }
                
                return contact;
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSyncBatchV2: Error getting contact UUID/Email: ' + e.getMessage());
        }
        return null;
    }
    
    /**
     * Helper method to get contact registrations
     */
    private Set<String> getContactRegistrations(String numericContactId) {
        Set<String> registrationIds = new Set<String>();
        try {
            String registrationsEndpoint = ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId + '/registrations/';
            
            HttpRequest regReq = new HttpRequest();
            regReq.setEndpoint(registrationsEndpoint);
            regReq.setMethod('GET');
            regReq.setHeader('Accept', 'application/xml');
            Blob authBlob = Blob.valueOf(username + ':' + password);
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(authBlob);
            regReq.setHeader('Authorization', authHeader);
            regReq.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse regRes = http.send(regReq);
            
            if (regRes.getStatusCode() == 200) {
                String responseBody = regRes.getBody();
                
                // Parse registration IDs - Method 1: Resource elements with type="Registration"
                Pattern resourcePattern = Pattern.compile('<Resource[^>]*type="[^"]*Registration[^"]*"[^>]*>');
                Matcher resourceMatcher = resourcePattern.matcher(responseBody);
                while (resourceMatcher.find()) {
                    Integer resourceStart = resourceMatcher.start();
                    Integer searchEnd = Math.min(resourceStart + 500, responseBody.length());
                    String resourceSection = responseBody.substring(resourceStart, searchEnd);
                    Pattern linkPattern = Pattern.compile('<Link[^>]*rel="self"[^>]*href="[^"]*/registrations/(\\d+)/"');
                    Matcher linkMatcher = linkPattern.matcher(resourceSection);
                    if (linkMatcher.find()) {
                        String regId = linkMatcher.group(1);
                        registrationIds.add(regId);
                    }
                }
                
                // Method 2: Self links if no resources found
                if (registrationIds.isEmpty()) {
                    Pattern selfLinkPattern = Pattern.compile('<Link[^>]*rel="self"[^>]*href="[^"]*/registrations/(\\d+)/"');
                    Matcher selfMatcher = selfLinkPattern.matcher(responseBody);
                    while (selfMatcher.find()) {
                        String regId = selfMatcher.group(1);
                        registrationIds.add(regId);
                    }
                }
                
                // Method 3: Fallback - direct pattern matching
                if (registrationIds.isEmpty()) {
                    Pattern fallbackPattern = Pattern.compile('/registrations/(\\d+)/');
                    Matcher fallbackMatcher = fallbackPattern.matcher(responseBody);
                    while (fallbackMatcher.find()) {
                        String regId = fallbackMatcher.group(1);
                        registrationIds.add(regId);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSyncBatchV2: Error getting registrations: ' + e.getMessage());
        }
        return registrationIds;
    }
    
    /**
     * Helper method to find Salesforce contacts for Arlo contacts
     */
    private Map<Id, Contact> findSalesforceContacts(
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList,
        Map<String, ArloContactSync.ArloContact> arloContactMap
    ) {
        Map<Id, Contact> syncedContactMap = new Map<Id, Contact>();
        
        // Collect all UUIDs and Emails from Arlo contacts
        Set<String> arloUuids = new Set<String>();
        Set<String> arloEmails = new Set<String>();
        
        for (ArloEventRegistrationSync.ContactEventWrapper wrapper : contactEventList) {
            if (wrapper.contact != null) {
                if (String.isNotBlank(wrapper.contact.contactId)) {
                    arloUuids.add(wrapper.contact.contactId.trim());
                }
                if (String.isNotBlank(wrapper.contact.email)) {
                    arloEmails.add(wrapper.contact.email.toLowerCase().trim());
                }
            }
        }
        
        // Query Salesforce contacts
        List<Contact> salesforceContacts = [
            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c
            FROM Contact
            WHERE (Arlo_Contact_UUID__c != null AND Arlo_Contact_UUID__c IN :arloUuids)
               OR (Email != null AND Email IN :arloEmails)
        ];
        
        // Create maps for matching
        Map<String, Contact> uuidToContact = new Map<String, Contact>();
        Map<String, Contact> emailToContact = new Map<String, Contact>();
        
        for (Contact c : salesforceContacts) {
            if (String.isNotBlank(c.Arlo_Contact_UUID__c)) {
                uuidToContact.put(c.Arlo_Contact_UUID__c.trim().toLowerCase(), c);
            }
            if (String.isNotBlank(c.Email)) {
                emailToContact.put(c.Email.toLowerCase().trim(), c);
            }
        }
        
        // Match Arlo contacts to Salesforce contacts
        for (ArloEventRegistrationSync.ContactEventWrapper wrapper : contactEventList) {
            if (wrapper.contact != null) {
                Contact matchedContact = null;
                
                // Try UUID first
                if (String.isNotBlank(wrapper.contact.contactId)) {
                    matchedContact = uuidToContact.get(wrapper.contact.contactId.trim().toLowerCase());
                }
                
                // Try Email if UUID didn't match
                if (matchedContact == null && String.isNotBlank(wrapper.contact.email)) {
                    matchedContact = emailToContact.get(wrapper.contact.email.toLowerCase().trim());
                }
                
                if (matchedContact != null) {
                    syncedContactMap.put(matchedContact.Id, matchedContact);
                }
            }
        }
        
        System.debug('ArloEventRegistrationSyncBatchV2: Matched ' + syncedContactMap.size() + ' Salesforce contacts from ' + contactEventList.size() + ' Arlo contact-event pairs');
        
        return syncedContactMap;
    }
    
    /**
     * Extract contact links from XML response
     */
    private List<String> extractContactLinksFromCollection(String xmlBody) {
        List<String> contactLinks = new List<String>();
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            
            Dom.XmlNode root = doc.getRootElement();
            findContactLinksRecursive(root, contactLinks);
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSyncBatchV2: Error extracting contact links: ' + e.getMessage());
        }
        return contactLinks;
    }
    
    /**
     * Recursively find Contact Link elements
     */
    private void findContactLinksRecursive(Dom.XmlNode node, List<String> contactLinks) {
        if (node.getName() == 'Link') {
            String rel = node.getAttributeValue('rel', null);
            // Look for Link with rel containing "Contact" (e.g., "http://schemas.arlo.co/api/2012/02/auth/Contact")
            if (rel != null && rel.contains('Contact') && rel != 'next') {
                String href = node.getAttributeValue('href', null);
                if (String.isNotBlank(href)) {
                    contactLinks.add(href);
                }
            }
        }
        
        for (Dom.XmlNode child : node.getChildElements()) {
            findContactLinksRecursive(child, contactLinks);
        }
    }
    
    /**
     * Static method to start the batch job
     * Usage: ArloEventRegistrationSyncBatchV2.startSync(null, null); // Uses Custom Settings
     *        ArloEventRegistrationSyncBatchV2.startSync('username', 'password');
     */
    public static Id startSync(String username, String password) {
        ArloEventRegistrationSyncBatchV2 batch = new ArloEventRegistrationSyncBatchV2(username, password);
        // Process 1 page per batch execution to ensure we have full callout limit per page
        return Database.executeBatch(batch, 1);
    }
}
