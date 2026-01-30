/**
 * ArloEventRegistrationSync
 * 
 * Syncs contacts from Arlo events and registrations to Salesforce.
 * Only processes events where Code does NOT start with 'CONF'.
 * For each registration, fetches the contact and syncs to Salesforce if their Account exists.
 * 
 * Usage in Developer Console:
 * // Note: Credentials should be configured in Arlo_Credentials__c Custom Setting
 * ArloEventRegistrationSync.syncContactsFromEvents(null, null); // Uses Custom Settings
 * // Or provide credentials: ArloEventRegistrationSync.syncContactsFromEvents('username', 'password');
 * 
 * @author System Generated
 * @version 1.0
 */
public with sharing class ArloEventRegistrationSync {
    
    // Arlo API Configuration - reference ArloApiClient for single source of truth
    public static final String ARLO_API_BASE_URL = ArloApiClient.BASE_URL;
    
    // Store credentials for Basic Auth (for backward compatibility)
    @TestVisible
    private static String arloUsername = null;
    @TestVisible
    private static String arloPassword = null;

    /**
     * Build and send an authenticated HTTP request to the Arlo API
     * @param endpoint The full URL endpoint to call
     * @param username The Arlo username for Basic Auth
     * @param password The Arlo password for Basic Auth
     * @return HttpResponse from the API call
     */
    @TestVisible
    private static HttpResponse makeArloRequest(String endpoint, String username, String password) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/xml');
        Blob authBlob = Blob.valueOf(username + ':' + password);
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(authBlob));
        req.setTimeout(30000);
        return new Http().send(req);
    }

    /**
     * Sync all contacts from events and registrations
     * CONTACT-FIRST APPROACH:
     * 1. GET all contacts -> /resources/contacts/
     * 2. For each contact, get registrations -> /resources/contacts/{id}/registrations
     * 3. For each registration, get the event from registration response -> /resources/events/{id}/
     * 4. If event contains "NHM" (not CONF), get customfields -> /resources/registrations/{id}/customfields
     * 5. Check consent - if true, sync/create contact in SF and add to campaign; if false, skip
     * 
     * Uses credentials from Custom Settings if username/password not provided
     * Usage in Developer Console:
     * // Note: Credentials should be configured in Arlo_Credentials__c Custom Setting
     * ArloEventRegistrationSync.syncContactsFromEvents(null, null); // Uses Custom Settings
     * // Or provide credentials: ArloEventRegistrationSync.syncContactsFromEvents('username', 'password');
     */
    public static void syncContactsFromEvents(String username, String password) {
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
        
        try {
            System.debug('ArloEventRegistrationSync: Starting CONTACT-FIRST sync approach');
            System.debug('ArloEventRegistrationSync: Step 1: Get all contacts from Arlo');
            System.debug('ArloEventRegistrationSync: Step 2: Enqueue Queueable job to process contacts in batches');
            
            // STEP 1: Get all contact links from Arlo (with pagination)
            System.debug('ArloEventRegistrationSync: Getting all contact links from Arlo...');
            List<String> allContactLinks = getAllContactLinksStatic(username, password);
            System.debug('ArloEventRegistrationSync: Found ' + allContactLinks.size() + ' contact links');
            
            if (allContactLinks.isEmpty()) {
                System.debug('ArloEventRegistrationSync: NO CONTACT LINKS FOUND');
                createLogRecord('Event Registration Sync', 'Warning', null, null, 
                    'No contacts found in Arlo', ARLO_API_BASE_URL + '/resources/contacts/', null, 0, 0);
                return;
            }
            
            // STEP 2: Create initial log record
            Id logId = createLogRecord('Event Registration Sync', 'In Progress', null, null, 
                'Found ' + allContactLinks.size() + ' contacts. Starting batch processing...', 
                ARLO_API_BASE_URL + '/resources/contacts/', null, allContactLinks.size(), null);
            
            // STEP 3: Use batch class for processing
            System.debug('ArloEventRegistrationSync: Starting batch job to process ' + allContactLinks.size() + ' contacts');
            ArloRegistrationSyncBatch batch = new ArloRegistrationSyncBatch(username, password);
            Id jobId = Database.executeBatch(batch, 5);
            System.debug('ArloEventRegistrationSync: Batch job started. Job ID: ' + jobId);
            
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error starting sync: ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            throw new ArloSyncException('Sync failed: ' + e.getMessage(), e);
        }
    }

    // ==================== HELPER METHODS FOR processContactsBatch ====================

    /**
     * Parse deferred contact entries from previous batch
     * @param deferredContactIds List of strings in format "contactId:regId1,regId2"
     * @return Map of contactId to Set of registrationIds that need processing
     */
    @TestVisible
    private static Map<String, Set<String>> parseDeferredContactEntries(List<String> deferredContactIds) {
        Map<String, Set<String>> contactsWithUnprocessedRegistrations = new Map<String, Set<String>>();

        if (deferredContactIds == null || deferredContactIds.isEmpty()) {
            return contactsWithUnprocessedRegistrations;
        }

        for (String deferredEntry : deferredContactIds) {
            if (String.isNotBlank(deferredEntry) && deferredEntry.contains(':')) {
                String[] parts = deferredEntry.split(':', 2);
                if (parts.size() == 2) {
                    String contactId = parts[0].trim();
                    String[] regIds = parts[1].split(',');
                    Set<String> regIdSet = new Set<String>();
                    for (String regId : regIds) {
                        if (String.isNotBlank(regId)) {
                            regIdSet.add(regId.trim());
                        }
                    }
                    if (!regIdSet.isEmpty()) {
                        contactsWithUnprocessedRegistrations.put(contactId, regIdSet);
                        System.debug('ArloEventRegistrationSync: Loaded deferred contact ' + contactId + ' with ' + regIdSet.size() + ' unprocessed registration(s): ' + regIdSet);
                    }
                }
            }
        }

        return contactsWithUnprocessedRegistrations;
    }

    /**
     * Process a single registration and determine if it should be synced
     * @param registrationId The Arlo registration ID
     * @param username Arlo API username
     * @param password Arlo API password
     * @param calloutCount Current callout count (will be incremented)
     * @return RegistrationProcessingResult with eventData if successful, null if should skip
     */
    @TestVisible
    private static RegistrationProcessingResult processRegistration(String registrationId, String username, String password, Integer calloutCount) {
        RegistrationProcessingResult result = new RegistrationProcessingResult(calloutCount);

        // Get event ID from registration
        result.calloutCount++;
        String eventId = getEventIdFromRegistrationStatic(registrationId, username, password);
        if (String.isBlank(eventId)) {
            return result;
        }

        // Get event details
        result.calloutCount++;
        EventData eventData = getEventDetailsStatic(eventId, username, password);
        if (eventData == null) {
            return result;
        }

        // Check if event contains NHM
        if (!isNhmEvent(eventData)) {
            return result;
        }

        // Check email consent
        result.calloutCount++;
        Boolean hasEmailConsent = checkRegistrationEmailConsentStatic(registrationId, username, password);
        if (!hasEmailConsent) {
            return result;
        }

        // All checks passed
        result.eventData = eventData;
        result.shouldProcess = true;
        return result;
    }

    /**
     * Check if an event is an NHM event (contains "NHM" in name or code)
     * @param eventData The event data to check
     * @return true if the event contains NHM
     */
    @TestVisible
    private static Boolean isNhmEvent(EventData eventData) {
        if (eventData == null) {
            return false;
        }
        if (String.isNotBlank(eventData.name) && eventData.name.contains('NHM')) {
            return true;
        }
        if (String.isNotBlank(eventData.code) && eventData.code.contains('NHM')) {
            return true;
        }
        return false;
    }

    /**
     * Find registrations that weren't processed (for tracking unprocessed work)
     * @param allRegistrations All registration IDs for a contact
     * @param processedRegistrations Registration IDs that were processed
     * @return Set of registration IDs that still need processing
     */
    @TestVisible
    private static Set<String> findUnprocessedRegistrations(Set<String> allRegistrations, Set<String> processedRegistrations) {
        Set<String> unprocessed = new Set<String>();
        for (String regId : allRegistrations) {
            if (!processedRegistrations.contains(regId)) {
                unprocessed.add(regId);
            }
        }
        return unprocessed;
    }

    /**
     * Build reverse lookup maps from arloContactMap (numericId -> ArloContact)
     * to find numeric IDs from UUID or email
     * @param arloContactMap Map of numericId to ArloContact
     * @return ReverseMapsResult with uuidToNumericId and emailToNumericId maps
     */
    @TestVisible
    private static ReverseMapsResult buildReverseMaps(Map<String, ArloModels.ArloContact> arloContactMap) {
        ReverseMapsResult result = new ReverseMapsResult();

        for (String numericId : arloContactMap.keySet()) {
            ArloModels.ArloContact ac = arloContactMap.get(numericId);
            if (ac != null) {
                if (String.isNotBlank(ac.contactId)) {
                    result.uuidToNumericId.put(ac.contactId.trim().toLowerCase(), numericId);
                }
                if (String.isNotBlank(ac.email)) {
                    result.emailToNumericId.put(ac.email.toLowerCase().trim(), numericId);
                }
            }
        }

        return result;
    }

    /**
     * Find ContactEventWrappers that don't have matching Salesforce contacts
     * Public static for reuse by ArloRegistrationSyncBatch
     * @param contactEventList List of all contact-event wrappers
     * @param syncedContactMap Map of Salesforce contacts that were found
     * @return List of wrappers that need to have contacts created
     */
    public static List<ContactEventWrapper> findUnmatchedWrappers(
        List<ContactEventWrapper> contactEventList,
        Map<Id, Contact> syncedContactMap
    ) {
        List<ContactEventWrapper> unmatchedWrappers = new List<ContactEventWrapper>();
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

        for (ContactEventWrapper wrapper : contactEventList) {
            if (wrapper.contact != null) {
                String wrapperUuid = wrapper.contact.contactId != null ? wrapper.contact.contactId.trim().toLowerCase() : '';
                String wrapperEmail = wrapper.contact.email != null ? wrapper.contact.email.toLowerCase().trim() : '';

                Boolean isMatched = (String.isNotBlank(wrapperUuid) && matchedUuids.contains(wrapperUuid)) ||
                                   (String.isNotBlank(wrapperEmail) && matchedEmails.contains(wrapperEmail));

                if (!isMatched) {
                    unmatchedWrappers.add(wrapper);
                }
            }
        }

        return unmatchedWrappers;
    }

    /**
     * Create contacts in Salesforce for unmatched wrappers
     * @param unmatchedWrappers List of ContactEventWrappers without matching SF contacts
     * @param arloContactMap Map of numericId to ArloContact
     * @param syncedContactMap Map to add newly created contacts to
     * @param username Arlo API username
     * @param password Arlo API password
     * @param calloutCount Current callout count
     * @param maxCallouts Maximum allowed callouts
     * @return Updated callout count after contact creation
     */
    @TestVisible
    private static Integer createContactsInSalesforce(
        List<ContactEventWrapper> unmatchedWrappers,
        Map<String, ArloModels.ArloContact> arloContactMap,
        Map<Id, Contact> syncedContactMap,
        String username,
        String password,
        Integer calloutCount,
        Integer maxCallouts
    ) {
        if (unmatchedWrappers.isEmpty()) {
            return calloutCount;
        }

        System.debug('ArloEventRegistrationSync: Found ' + unmatchedWrappers.size() + ' unmatched contact(s) - will create in Salesforce');

        // Build reverse maps to find numeric IDs from UUID/Email
        ReverseMapsResult reverseMaps = buildReverseMaps(arloContactMap);

        // Map unmatched wrappers to their numeric IDs
        Map<String, ContactEventWrapper> numericIdToWrapper = new Map<String, ContactEventWrapper>();
        for (ContactEventWrapper wrapper : unmatchedWrappers) {
            String numericId = null;
            if (wrapper.contact != null) {
                String wrapperUuid = wrapper.contact.contactId != null ? wrapper.contact.contactId.trim().toLowerCase() : '';
                String wrapperEmail = wrapper.contact.email != null ? wrapper.contact.email.toLowerCase().trim() : '';

                if (String.isNotBlank(wrapperUuid) && reverseMaps.uuidToNumericId.containsKey(wrapperUuid)) {
                    numericId = reverseMaps.uuidToNumericId.get(wrapperUuid);
                } else if (String.isNotBlank(wrapperEmail) && reverseMaps.emailToNumericId.containsKey(wrapperEmail)) {
                    numericId = reverseMaps.emailToNumericId.get(wrapperEmail);
                }

                if (String.isNotBlank(numericId) && !numericIdToWrapper.containsKey(numericId)) {
                    numericIdToWrapper.put(numericId, wrapper);
                }
            }
        }

        // Calculate how many contacts we can create with available callouts
        Integer availableCallouts = maxCallouts - calloutCount;
        System.debug('ArloEventRegistrationSync: ===== CONTACT CREATION PHASE =====');
        System.debug('ArloEventRegistrationSync: Available callouts for contact creation: ' + availableCallouts + ' (need ' + (numericIdToWrapper.size() * 3) + ' for all ' + numericIdToWrapper.size() + ' contacts)');
        System.debug('ArloEventRegistrationSync: Unmatched contacts to create: ' + numericIdToWrapper.size());

        // Each contact needs 3 callouts (contact + employment + org)
        Integer contactsToCreateCount = 0;
        if (availableCallouts >= 6) {
            // Reserve 3 callouts for safety, use the rest for contact creation
            contactsToCreateCount = (availableCallouts - 3) / 3;
            if (contactsToCreateCount > numericIdToWrapper.size()) {
                contactsToCreateCount = numericIdToWrapper.size();
            }
        }

        if (contactsToCreateCount == 0) {
            System.debug('ArloEventRegistrationSync: WARNING: Not enough callout budget to create contacts (available: ' + availableCallouts + ')');
            System.debug('ArloEventRegistrationSync: ' + numericIdToWrapper.size() + ' contact(s) with valid registrations will NOT be created in this batch');
            System.debug('ArloEventRegistrationSync: These contacts will be created in the next full sync run');
            System.debug('ArloEventRegistrationSync: RECOMMENDATION: Run the full sync again to create these contacts');
            return calloutCount;
        } else if (contactsToCreateCount < numericIdToWrapper.size()) {
            System.debug('ArloEventRegistrationSync: Limited callout budget - will create ' + contactsToCreateCount + ' of ' + numericIdToWrapper.size() + ' unmatched contact(s) in this batch');
            System.debug('ArloEventRegistrationSync: Remaining ' + (numericIdToWrapper.size() - contactsToCreateCount) + ' contact(s) will be created in next batch or next full sync');

            // Limit to contacts we can create now
            List<String> numericIdsToProcess = new List<String>(numericIdToWrapper.keySet());
            for (Integer i = contactsToCreateCount; i < numericIdsToProcess.size(); i++) {
                numericIdToWrapper.remove(numericIdsToProcess[i]);
            }
        } else {
            System.debug('ArloEventRegistrationSync: Sufficient callout budget - will create all ' + numericIdToWrapper.size() + ' unmatched contact(s)');
        }

        // Fetch full contact details for unmatched contacts
        List<ArloModels.ArloContact> contactsToCreate = new List<ArloModels.ArloContact>();

        for (String numericContactId : numericIdToWrapper.keySet()) {
            Integer remainingCallouts = maxCallouts - calloutCount;
            if (remainingCallouts < 5) {
                System.debug('ArloEventRegistrationSync: Reached callout limit - stopping contact creation (remaining: ' + remainingCallouts + ')');
                System.debug('ArloEventRegistrationSync: Will create remaining contacts in next batch');
                break;
            }

            System.debug('ArloEventRegistrationSync: Fetching full contact details for ID ' + numericContactId + ' to create in Salesforce (callout count: ' + calloutCount + ', remaining: ' + remainingCallouts + ')');
            ArloModels.ArloContact fullContact = ArloContactSync.getSingleArloContactStatic(numericContactId, username, password);
            calloutCount += 3; // getSingleArloContactStatic makes 3 callouts

            if (fullContact != null && String.isNotBlank(fullContact.organisationCodePrimary)) {
                contactsToCreate.add(fullContact);
                System.debug('ArloEventRegistrationSync: Contact ' + numericContactId + ' will be created with Account CodePrimary: ' + fullContact.organisationCodePrimary);
            } else {
                System.debug('ArloEventRegistrationSync: Cannot create contact ' + numericContactId + ' - no organisation CodePrimary found');
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
                Account sfAccount = getSalesforceAccountByNumberStatic(codePrimary);
                if (sfAccount != null) {
                    List<ArloModels.ArloContact> accountContacts = contactsByAccount.get(codePrimary);
                    System.debug('ArloEventRegistrationSync: Creating ' + accountContacts.size() + ' contact(s) for Account: ' + sfAccount.Name);
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

                    System.debug('ArloEventRegistrationSync: Successfully created ' + newlyCreatedContacts.size() + ' contact(s)');
                } else {
                    System.debug('ArloEventRegistrationSync: Cannot create contacts - Account not found for CodePrimary: ' + codePrimary);
                }
            }
        }

        return calloutCount;
    }

    // ==================== END HELPER METHODS ====================

    /**
     * Process contacts in batch (for use by Queueable)
     * CONTACT-FIRST FLOW:
     * 1. For each contact, get registrations
     * 2. For each registration, get the event from registration response
     * 3. If event contains "NHM" (not CONF), get customfields and check consent
     * 4. If consent is true, sync/create contact in SF and add to campaign; if false, skip
     */
    public static void processContactsBatch(List<String> contactLinks, String username, String password, Id logId, Integer startIndex) {
        processContactsBatch(contactLinks, username, password, logId, startIndex, new List<String>());
    }
    
    /**
     * Process contacts in batch (for use by Queueable) - with deferred contacts parameter (ignored in current flow)
     */
    public static void processContactsBatch(List<String> contactLinks, String username, String password, Id logId, Integer startIndex, List<String> deferredContactIds) {
        Integer totalProcessed = 0;
        Integer totalSuccessful = 0;
        Integer totalFailed = 0;
        Integer contactsProcessed = 0;
        Integer activeContactsProcessed = 0;

        // STEP 2: Process each contact - check Status = Active, get registrations
        List<ContactEventWrapper> contactEventList = new List<ContactEventWrapper>();
        Map<String, ArloModels.ArloContact> arloContactMap = new Map<String, ArloModels.ArloContact>();
        Integer calloutCount = 0;
        Integer maxCallouts = 95; // Leave some room for DML operations

        // Parse deferred contacts from previous batch using helper method
        Map<String, Set<String>> contactsWithUnprocessedRegistrations = parseDeferredContactEntries(deferredContactIds);

        try {
            // First, process any deferred contacts (contacts with unprocessed registrations from previous batch)
            Set<String> deferredContactIdsToProcess = contactsWithUnprocessedRegistrations.keySet();
            if (!deferredContactIdsToProcess.isEmpty()) {
                System.debug('ArloEventRegistrationSync: Processing ' + deferredContactIdsToProcess.size() + ' deferred contact(s) with unprocessed registrations first');
                for (String deferredContactId : deferredContactIdsToProcess) {
                    if (calloutCount >= maxCallouts - 10) {
                        System.debug('ArloEventRegistrationSync: Reached callout limit while processing deferred contacts - will retry remaining in next batch');
                        break;
                    }

                    try {
                        // Get contact details (we need UUID/Email for matching)
                        calloutCount++;
                        ArloModels.ArloContact arloContact = getContactUuidAndEmailOnly(deferredContactId, username, password);
                        if (arloContact == null || (String.isBlank(arloContact.contactId) && String.isBlank(arloContact.email))) {
                            System.debug('ArloEventRegistrationSync: Could not get contact UUID/Email for deferred contact ID: ' + deferredContactId);
                            contactsWithUnprocessedRegistrations.remove(deferredContactId);
                            continue;
                        }
                        arloContactMap.put(deferredContactId, arloContact);

                        Set<String> unprocessedRegIds = contactsWithUnprocessedRegistrations.get(deferredContactId);
                        System.debug('ArloEventRegistrationSync: Processing deferred contact ' + deferredContactId + ' with ' + unprocessedRegIds.size() + ' unprocessed registration(s)');

                        // Process each unprocessed registration using helper method
                        Set<String> processedRegIds = new Set<String>();
                        for (String registrationId : unprocessedRegIds) {
                            if (calloutCount >= maxCallouts - 5) {
                                System.debug('ArloEventRegistrationSync: Reached callout limit while processing deferred registrations - will retry remaining');
                                break;
                            }

                            RegistrationProcessingResult regResult = processRegistration(registrationId, username, password, calloutCount);
                            calloutCount = regResult.calloutCount;

                            if (regResult.shouldProcess && regResult.eventData != null) {
                                ContactEventWrapper wrapper = new ContactEventWrapper();
                                wrapper.contact = arloContact;
                                wrapper.eventName = regResult.eventData.name;
                                wrapper.eventCode = regResult.eventData.code;
                                contactEventList.add(wrapper);
                                totalProcessed++;
                                System.debug('ArloEventRegistrationSync: Processed deferred registration ' + registrationId + ' for contact ' + deferredContactId);
                            }
                            processedRegIds.add(registrationId);
                        }

                        // Update unprocessed list using helper method
                        Set<String> stillUnprocessed = findUnprocessedRegistrations(unprocessedRegIds, processedRegIds);

                        if (stillUnprocessed.isEmpty()) {
                            contactsWithUnprocessedRegistrations.remove(deferredContactId);
                            System.debug('ArloEventRegistrationSync: Completed all deferred registrations for contact ' + deferredContactId);
                        } else {
                            contactsWithUnprocessedRegistrations.put(deferredContactId, stillUnprocessed);
                            System.debug('ArloEventRegistrationSync: Contact ' + deferredContactId + ' still has ' + stillUnprocessed.size() + ' unprocessed registration(s) - will retry');
                        }

                    } catch (Exception e) {
                        System.debug('ArloEventRegistrationSync: Error processing deferred contact ' + deferredContactId + ': ' + e.getMessage());
                        System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                    }
                }
            }

            // Process contacts in batch starting from startIndex
            Integer endIndex = startIndex;
            for (Integer i = startIndex; i < contactLinks.size() && calloutCount < maxCallouts; i++) {
                String contactLink = contactLinks[i];
                endIndex = i + 1;
                if (calloutCount >= maxCallouts) {
                    System.debug('ArloEventRegistrationSync: Reached callout limit. Processed ' + contactsProcessed + ' contacts (' + activeContactsProcessed + ' active). Found ' + contactEventList.size() + ' contact-event pairs.');
                    break;
                }
                
                try {
                    // Extract numeric contact ID from link (e.g., /contacts/300/ -> 300)
                    String numericContactId = extractContactIdFromLink(contactLink);
                    if (String.isBlank(numericContactId)) {
                        System.debug('ArloEventRegistrationSync: Could not extract contact ID from link: ' + contactLink);
                        continue;
                    }

                    // Skip if this contact was already processed as a deferred contact
                    if (contactsWithUnprocessedRegistrations.containsKey(numericContactId)) {
                        System.debug('ArloEventRegistrationSync: Contact ' + numericContactId + ' is in deferred list - skipping');
                        continue;
                    }

                    contactsProcessed++;

                    // Get contact details and check Status = "Active"
                    calloutCount++;
                    String contactStatus = getContactStatusStatic(numericContactId, username, password);

                    if (String.isBlank(contactStatus) || contactStatus != 'Active') {
                        continue;
                    }

                    activeContactsProcessed++;

                    // Get contact details (UUID, Email) for Salesforce matching
                    calloutCount++;
                    ArloModels.ArloContact arloContact = getContactUuidAndEmailOnly(numericContactId, username, password);
                    if (arloContact == null || (String.isBlank(arloContact.contactId) && String.isBlank(arloContact.email))) {
                        System.debug('ArloEventRegistrationSync: Could not get contact UUID/Email for ID: ' + numericContactId);
                        continue;
                    }
                    arloContactMap.put(numericContactId, arloContact);

                    // Get registrations for this contact
                    calloutCount++;
                    Set<String> registrationIds = getContactRegistrationsStatic(numericContactId, username, password);

                    if (registrationIds.isEmpty()) {
                        continue;
                    }

                    // Determine which registrations to process
                    Set<String> registrationsToProcess = new Set<String>(registrationIds);
                    if (contactsWithUnprocessedRegistrations.containsKey(numericContactId)) {
                        Set<String> unprocessed = contactsWithUnprocessedRegistrations.get(numericContactId);
                        registrationsToProcess.clear();
                        for (String regId : unprocessed) {
                            if (registrationIds.contains(regId)) {
                                registrationsToProcess.add(regId);
                            }
                        }
                        System.debug('ArloEventRegistrationSync: Contact ' + numericContactId + ' has ' + unprocessed.size() + ' unprocessed registration(s) from previous batch');
                        contactsWithUnprocessedRegistrations.remove(numericContactId);

                        if (registrationsToProcess.isEmpty()) {
                            continue;
                        }
                    }

                    // Process each registration using helper method
                    Set<String> processedRegistrationIds = new Set<String>();
                    for (String registrationId : registrationsToProcess) {
                        Integer remainingCallouts = maxCallouts - calloutCount;
                        if (remainingCallouts < 5) {
                            System.debug('ArloEventRegistrationSync: Approaching callout limit (remaining: ' + remainingCallouts + ') - stopping registration processing');
                            Set<String> unprocessed = findUnprocessedRegistrations(registrationsToProcess, processedRegistrationIds);
                            if (!unprocessed.isEmpty()) {
                                contactsWithUnprocessedRegistrations.put(numericContactId, unprocessed);
                                System.debug('ArloEventRegistrationSync: Contact ' + numericContactId + ' has ' + unprocessed.size() + ' unprocessed registration(s) - will retry in next batch');
                            }
                            break;
                        }

                        RegistrationProcessingResult regResult = processRegistration(registrationId, username, password, calloutCount);
                        calloutCount = regResult.calloutCount;

                        if (regResult.shouldProcess && regResult.eventData != null) {
                            ContactEventWrapper wrapper = new ContactEventWrapper();
                            wrapper.contact = arloContact;
                            wrapper.eventName = regResult.eventData.name;
                            wrapper.eventCode = regResult.eventData.code;
                            contactEventList.add(wrapper);
                            totalProcessed++;
                        }
                        processedRegistrationIds.add(registrationId);
                    }

                    // Check if all registrations were processed
                    Set<String> unprocessed = findUnprocessedRegistrations(registrationsToProcess, processedRegistrationIds);
                    if (!unprocessed.isEmpty()) {
                        contactsWithUnprocessedRegistrations.put(numericContactId, unprocessed);
                        System.debug('ArloEventRegistrationSync: Contact ' + numericContactId + ' has ' + unprocessed.size() + ' unprocessed registration(s) - will retry in next batch');
                    }

                } catch (Exception e) {
                    totalFailed++;
                    System.debug('ArloEventRegistrationSync: Error processing contact link ' + contactLink + ': ' + e.getMessage());
                    System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                }
            }
            
            // STEP 4: NOW DO ALL DML OPERATIONS (after all callouts are complete)
            if (!contactEventList.isEmpty()) {
                System.debug('ArloEventRegistrationSync: Adding ' + contactEventList.size() + ' contact-event pairs to campaigns');

                try {
                    // Find Salesforce contacts for each Arlo contact
                    Map<Id, Contact> syncedContactMap = findSalesforceContactsForArloContacts(contactEventList, arloContactMap);

                    // Find unmatched contacts that need to be created
                    List<ContactEventWrapper> unmatchedWrappers = findUnmatchedWrappers(contactEventList, syncedContactMap);

                    // Create missing contacts using helper method
                    if (!unmatchedWrappers.isEmpty()) {
                        calloutCount = createContactsInSalesforce(
                            unmatchedWrappers,
                            arloContactMap,
                            syncedContactMap,
                            username,
                            password,
                            calloutCount,
                            maxCallouts
                        );
                    }

                    // Add all contacts (existing + newly created) to campaigns
                    System.debug('ArloEventRegistrationSync: ===== STARTING CAMPAIGN ASSIGNMENT =====');
                    System.debug('ArloEventRegistrationSync: Contact-event pairs to process: ' + contactEventList.size());
                    System.debug('ArloEventRegistrationSync: Salesforce contacts available: ' + syncedContactMap.size());
                    addContactsToCampaignsStatic(contactEventList, syncedContactMap);
                    System.debug('ArloEventRegistrationSync: ===== CAMPAIGN ASSIGNMENT COMPLETE =====');
                    totalSuccessful = contactEventList.size();
                } catch (Exception e) {
                    System.debug('ArloEventRegistrationSync: Error adding contacts to campaigns: ' + e.getMessage());
                    System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                    totalFailed += contactEventList.size();
                }
            }
            
            // Update log with batch status
            if (logId != null) {
                // Get previous totals from log
                Integer prevProcessed = 0;
                Integer prevSuccessful = 0;
                Integer prevFailed = 0;
                try {
                    Arlo_Integration_Log__c log = [SELECT Records_Processed__c, Records_Successful__c, Records_Failed__c 
                                                    FROM Arlo_Integration_Log__c WHERE Id = :logId LIMIT 1];
                    if (log.Records_Processed__c != null) prevProcessed = Integer.valueOf(log.Records_Processed__c);
                    if (log.Records_Successful__c != null) prevSuccessful = Integer.valueOf(log.Records_Successful__c);
                    if (log.Records_Failed__c != null) prevFailed = Integer.valueOf(log.Records_Failed__c);
                } catch (Exception e) {
                    System.debug('ArloEventRegistrationSync: Could not get previous totals for log ID ' + logId + ': ' + e.getMessage());
                    System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                }

                Integer cumulativeProcessed = prevProcessed + totalProcessed;
                Integer cumulativeSuccessful = prevSuccessful + totalSuccessful;
                Integer cumulativeFailed = prevFailed + totalFailed;
                
                String batchMessage = 'Batch ' + (startIndex / 20 + 1) + ': Processed ' + contactsProcessed + ' contacts (' + activeContactsProcessed + ' active). Found ' + totalProcessed + ' contact-event pairs. Processed contacts ' + startIndex + ' to ' + (endIndex - 1) + '.';
                
                // Check if there are more contacts to process OR if there are contacts with unprocessed registrations
                if (endIndex < contactLinks.size() || !contactsWithUnprocessedRegistrations.isEmpty()) {
                    // More contacts to process or contacts with unprocessed registrations - chain next job
                    String chainMessage = batchMessage;
                    if (!contactsWithUnprocessedRegistrations.isEmpty()) {
                        chainMessage += ' ' + contactsWithUnprocessedRegistrations.size() + ' contact(s) with unprocessed registrations will be retried.';
                        System.debug('ArloEventRegistrationSync: Contacts with unprocessed registrations: ' + contactsWithUnprocessedRegistrations.keySet());
                        for (String contactId : contactsWithUnprocessedRegistrations.keySet()) {
                            Set<String> regIds = contactsWithUnprocessedRegistrations.get(contactId);
                            System.debug('ArloEventRegistrationSync:   - Contact ' + contactId + ': ' + regIds.size() + ' unprocessed registration(s): ' + regIds);
                        }
                    }
                    chainMessage += ' Chaining next batch...';
                    updateLogRecordStatic(logId, 'In Progress', chainMessage, null, cumulativeProcessed, cumulativeSuccessful);
                    System.debug('ArloEventRegistrationSync: Chaining next batch for contacts ' + endIndex + ' to ' + contactLinks.size());
                    
                    // Pass unprocessed registrations to next batch via deferredContactIds
                    // Format: "contactId:regId1,regId2|contactId2:regId3,regId4"
                    List<String> deferredContacts = new List<String>();
                    for (String contactId : contactsWithUnprocessedRegistrations.keySet()) {
                        Set<String> regIds = contactsWithUnprocessedRegistrations.get(contactId);
                        String deferredEntry = contactId + ':' + String.join(new List<String>(regIds), ',');
                        deferredContacts.add(deferredEntry);
                        System.debug('ArloEventRegistrationSync: Deferring contact ' + contactId + ' with ' + regIds.size() + ' unprocessed registration(s)');
                    }
                    
                    // Note: For full sync use ArloRegistrationSyncBatch
                    System.debug('ArloEventRegistrationSync: Additional processing needed - use batch class instead');
                    updateLogRecordStatic(logId, 'Completed with Errors',
                        'Partial processing completed. Use ArloRegistrationSyncBatch for full sync.',
                        null, cumulativeProcessed, cumulativeSuccessful);
                } else {
                    // All contacts processed and no unprocessed registrations
                    String finalMessage = 'Completed! Processed ' + contactsProcessed + ' contacts (' + activeContactsProcessed + ' active) in final batch. Total: ' + cumulativeProcessed + ' contact-event pairs. Successfully added ' + cumulativeSuccessful + ' to campaigns. Failed: ' + cumulativeFailed;
                    updateLogRecordStatic(logId, 'Success', finalMessage, null, cumulativeProcessed, cumulativeSuccessful);
                    System.debug('ArloEventRegistrationSync: ===== FINAL SYNC SUMMARY =====');
                    System.debug('ArloEventRegistrationSync: Total Contact Links: ' + contactLinks.size());
                    System.debug('ArloEventRegistrationSync: Total Contact-Event Pairs: ' + cumulativeProcessed);
                    System.debug('ArloEventRegistrationSync: Successfully Added to Campaigns: ' + cumulativeSuccessful);
                    System.debug('ArloEventRegistrationSync: Failed: ' + cumulativeFailed);
                    System.debug('ArloEventRegistrationSync: ==========================');
                }
            }
            
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error processing batch: ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            
            // Update log with error
            String errorMessage = 'Batch failed: ' + e.getMessage() + '\nProcessed in batch: ' + totalProcessed + ', Successful: ' + totalSuccessful + ', Failed: ' + totalFailed;
            if (logId != null) {
                updateLogRecordStatic(logId, 'Error', errorMessage, null, totalProcessed, totalSuccessful);
                sendErrorNotification(logId, errorMessage);
            }
        }
    }
    
    /**
     * Get all event links from the events endpoint
     * Handles pagination by following "next" links
     */
    @TestVisible
    private static List<String> getAllEventLinks() {
        return getAllEventLinksStatic(arloUsername, arloPassword);
    }
    
    public static List<String> getAllEventLinksStatic(String username, String password) {
        // Store credentials temporarily
        String originalUsername = arloUsername;
        String originalPassword = arloPassword;
        arloUsername = username;
        arloPassword = password;
        
        try {
            return getAllEventLinksInternal();
        } finally {
            // Restore original credentials
            arloUsername = originalUsername;
            arloPassword = originalPassword;
        }
    }

    @TestVisible
    private static List<String> getAllEventLinksInternal() {
        List<String> allEventLinks = new List<String>();
        String nextLink = ARLO_API_BASE_URL + '/resources/events/';
        Integer pageCount = 0;
        Integer maxPages = 100; // Safety limit to prevent infinite loops
        
        // Verify credentials are set
        if (String.isBlank(arloUsername) || String.isBlank(arloPassword)) {
            System.debug('ArloEventRegistrationSync: ERROR - Credentials not set when calling getAllEventLinks()');
            System.debug('ArloEventRegistrationSync: arloUsername is blank: ' + String.isBlank(arloUsername));
            System.debug('ArloEventRegistrationSync: arloPassword is blank: ' + String.isBlank(arloPassword));
            return allEventLinks; // Return empty list
        }
        
        System.debug('ArloEventRegistrationSync: getAllEventLinks() - Using credentials. Username: ' + arloUsername);
        
        while (String.isNotBlank(nextLink) && pageCount < maxPages) {
            try {
                HttpResponse res = makeArloRequest(nextLink, arloUsername, arloPassword);

                if (res.getStatusCode() == 200) {
                    String responseBody = res.getBody();
                    System.debug('ArloEventRegistrationSync: Events API response body length: ' + responseBody.length());
                    System.debug('ArloEventRegistrationSync: Events API response body (first 500 chars): ' + (responseBody.length() > 500 ? responseBody.substring(0, 500) : responseBody));
                    
                    // Extract event links from XML
                    List<String> pageLinks = extractEventLinksFromCollection(responseBody);
                    allEventLinks.addAll(pageLinks);
                    System.debug('ArloEventRegistrationSync: Found ' + pageLinks.size() + ' events on page ' + (pageCount + 1));
                    
                    // Check for "next" link for pagination
                    nextLink = extractNextLink(responseBody);
                    if (String.isNotBlank(nextLink)) {
                        System.debug('ArloEventRegistrationSync: Found next page link: ' + nextLink);
                        pageCount++;
                    } else {
                        System.debug('ArloEventRegistrationSync: No more pages to fetch');
                        break;
                    }
                } else {
                    System.debug('ArloEventRegistrationSync: Error fetching events page. Status: ' + res.getStatusCode());
                    System.debug('ArloEventRegistrationSync: Response body: ' + res.getBody());
                    break;
                }
            } catch (Exception e) {
                System.debug('ArloEventRegistrationSync: Error fetching events page at ' + nextLink + ': ' + e.getMessage());
                System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                break;
            }
        }

        System.debug('ArloEventRegistrationSync: Total event links found: ' + allEventLinks.size() + ' across ' + (pageCount + 1) + ' pages');
        return allEventLinks;
    }
    
    /**
     * Get credentials from Custom Settings (public for use by Queueable)
     */
    public static void loadCredentialsFromCustomSettings() {
        Arlo_Credentials__c credentials = Arlo_Credentials__c.getOrgDefaults();
        if (credentials != null && String.isNotBlank(credentials.Username__c) && String.isNotBlank(credentials.Password__c)) {
            arloUsername = credentials.Username__c;
            arloPassword = credentials.Password__c;
            System.debug('ArloEventRegistrationSync: Loaded credentials from Custom Settings');
        } else {
            throw new ArloSyncException('Arlo Credentials not configured. Please set up Arlo_Credentials__c Custom Setting with Username__c and Password__c.');
        }
    }
    
    /**
     * Extract event links from XML response
     */
    @TestVisible
    private static List<String> extractEventLinksFromCollection(String xmlBody) {
        List<String> eventLinks = new List<String>();
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            
            Dom.XmlNode root = doc.getRootElement();
            findEventLinksRecursive(root, eventLinks);
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error extracting event links: ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: XML body length: ' + (xmlBody != null ? String.valueOf(xmlBody.length()) : 'null'));
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return eventLinks;
    }
    
    /**
     * Recursively find Event Link elements
     */
    @TestVisible
    private static void findEventLinksRecursive(Dom.XmlNode node, List<String> eventLinks) {
        if (node.getName() == 'Link') {
            String rel = node.getAttributeValue('rel', null);
            if (rel != null && rel.contains('Event') && rel != 'next') {
                String href = node.getAttributeValue('href', null);
                if (String.isNotBlank(href)) {
                    eventLinks.add(href);
                }
            }
        }
        
        for (Dom.XmlNode child : node.getChildElements()) {
            findEventLinksRecursive(child, eventLinks);
        }
    }
    
    /**
     * Extract event ID from link
     */
    public static String extractEventIdFromLink(String eventLink) {
        return ArloXmlParser.extractIdFromUrl(eventLink, 'events');
    }
    
    /**
     * Get all contact links from Arlo (with pagination)
     * Returns list of contact links (e.g., /resources/contacts/300/)
     */
    public static List<String> getAllContactLinksStatic(String username, String password) {
        List<String> allContactLinks = new List<String>();
        String nextLink = ARLO_API_BASE_URL + '/resources/contacts/';
        Integer pageCount = 0;
        Integer maxPages = 100; // Safety limit to prevent infinite loops

        while (String.isNotBlank(nextLink) && pageCount < maxPages) {
            try {
                HttpResponse res = makeArloRequest(nextLink, username, password);

                if (res.getStatusCode() == 200) {
                    String responseBody = res.getBody();

                    // Extract contact links from XML
                    List<String> pageLinks = extractContactLinksFromCollection(responseBody);
                    allContactLinks.addAll(pageLinks);
                    System.debug('ArloEventRegistrationSync: Found ' + pageLinks.size() + ' contacts on page ' + (pageCount + 1));

                    // Check for "next" link for pagination using ArloXmlParser
                    nextLink = ArloXmlParser.extractNextLink(responseBody);
                    if (String.isNotBlank(nextLink)) {
                        System.debug('ArloEventRegistrationSync: Found next page link: ' + nextLink);
                        pageCount++;
                    } else {
                        System.debug('ArloEventRegistrationSync: No more pages to fetch');
                        break;
                    }
                } else {
                    System.debug('ArloEventRegistrationSync: Error fetching contacts page. Status: ' + res.getStatusCode());
                    System.debug('ArloEventRegistrationSync: Response body: ' + res.getBody());
                    break;
                }
            } catch (Exception e) {
                System.debug('ArloEventRegistrationSync: Error fetching contacts page at ' + nextLink + ': ' + e.getMessage());
                System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                break;
            }
        }

        System.debug('ArloEventRegistrationSync: Total contact links found: ' + allContactLinks.size() + ' across ' + (pageCount + 1) + ' pages');
        return allContactLinks;
    }
    
    /**
     * Extract contact links from XML response
     * Public static for reuse by ArloRegistrationSyncBatch
     */
    public static List<String> extractContactLinksFromCollection(String xmlBody) {
        List<String> contactLinks = new List<String>();
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            
            Dom.XmlNode root = doc.getRootElement();
            findContactLinksRecursive(root, contactLinks);
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error extracting contact links: ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: XML body length: ' + (xmlBody != null ? String.valueOf(xmlBody.length()) : 'null'));
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return contactLinks;
    }

    /**
     * Recursively find Contact Link elements
     * Public static for reuse by ArloRegistrationSyncBatch
     */
    public static void findContactLinksRecursive(Dom.XmlNode node, List<String> contactLinks) {
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
     * Extract contact ID from link (e.g., /contacts/300/ -> 300)
     * Public static for reuse by ArloRegistrationSyncBatch
     */
    public static String extractContactIdFromLink(String contactLink) {
        return ArloXmlParser.extractIdFromUrl(contactLink, 'contacts');
    }
    
    /**
     * Get contact UUID and Email only (skips employment/org lookups to save callouts)
     * Assumes organization is a school and exists in Salesforce
     * Public static for reuse by ArloRegistrationSyncBatch
     */
    public static ArloModels.ArloContact getContactUuidAndEmailOnly(String numericContactId, String username, String password) {
        try {
            String endpoint = ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId;
            HttpResponse res = makeArloRequest(endpoint, username, password);

            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();

                // Parse only UUID and Email from XML using ArloXmlParser
                ArloModels.ArloContact contact = new ArloModels.ArloContact();
                contact.numericContactId = numericContactId;

                // Extract UniqueIdentifier (UUID)
                contact.contactId = ArloXmlParser.extractElementValue(responseBody, 'UniqueIdentifier');

                // Extract Email
                contact.email = ArloXmlParser.extractElementValue(responseBody, 'Email');

                // If no UniqueIdentifier found, try ContactID as fallback
                if (String.isBlank(contact.contactId)) {
                    contact.contactId = ArloXmlParser.extractElementValue(responseBody, 'ContactID');
                }

                return contact;
            } else {
                System.debug('ArloEventRegistrationSync: Error getting contact UUID/Email for ID ' + numericContactId + '. Status: ' + res.getStatusCode());
                System.debug('ArloEventRegistrationSync: Response body: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting contact UUID/Email for ID ' + numericContactId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }

    /**
     * Get contact status from Arlo (returns "Active", "Inactive", etc.)
     * Public static for reuse by ArloRegistrationSyncBatch
     */
    public static String getContactStatusStatic(String numericContactId, String username, String password) {
        try {
            String endpoint = ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId;
            HttpResponse res = makeArloRequest(endpoint, username, password);

            if (res.getStatusCode() == 200) {
                return ArloXmlParser.extractElementValue(res.getBody(), 'Status');
            } else {
                System.debug('ArloEventRegistrationSync: Error getting contact status for ID ' + numericContactId + '. Status: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting contact status for ID ' + numericContactId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }
    
    /**
     * Find Salesforce contacts for Arlo contacts by matching UUID or Email
     * Public static for reuse by ArloRegistrationSyncBatch
     */
    public static Map<Id, Contact> findSalesforceContactsForArloContacts(
        List<ContactEventWrapper> contactEventList,
        Map<String, ArloModels.ArloContact> arloContactMap
    ) {
        Map<Id, Contact> syncedContactMap = new Map<Id, Contact>();
        
        // Collect all UUIDs and Emails from Arlo contacts
        Set<String> arloUuids = new Set<String>();
        Set<String> arloEmails = new Set<String>();
        
        for (ContactEventWrapper wrapper : contactEventList) {
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
        for (ContactEventWrapper wrapper : contactEventList) {
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
        
        System.debug('ArloEventRegistrationSync: Matched ' + syncedContactMap.size() + ' Salesforce contacts from ' + contactEventList.size() + ' Arlo contact-event pairs');
        
        // Debug: Log unmatched contacts
        if (syncedContactMap.size() < contactEventList.size()) {
            System.debug('ArloEventRegistrationSync: WARNING: Some Arlo contacts were not matched to Salesforce contacts');
            for (ContactEventWrapper wrapper : contactEventList) {
                if (wrapper.contact != null) {
                    Boolean found = false;
                    for (Contact c : syncedContactMap.values()) {
                        String wrapperUuid = wrapper.contact.contactId != null ? wrapper.contact.contactId.trim().toLowerCase() : '';
                        String wrapperEmail = wrapper.contact.email != null ? wrapper.contact.email.toLowerCase().trim() : '';
                        String contactUuid = c.Arlo_Contact_UUID__c != null ? c.Arlo_Contact_UUID__c.trim().toLowerCase() : '';
                        String contactEmail = c.Email != null ? c.Email.toLowerCase().trim() : '';
                        
                        if ((String.isNotBlank(wrapperUuid) && wrapperUuid == contactUuid) ||
                            (String.isNotBlank(wrapperEmail) && wrapperEmail == contactEmail)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        System.debug('ArloEventRegistrationSync:   Unmatched Arlo contact - UUID: "' + wrapper.contact.contactId + '", Email: "' + wrapper.contact.email + '", Event: ' + wrapper.eventName);
                    }
                }
            }
        }
        
        return syncedContactMap;
    }
    
    /**
     * Get event details from Arlo API (uses static credentials)
     */
    @TestVisible
    private static EventData getEventDetails(String eventId) {
        return getEventDetailsStatic(eventId, arloUsername, arloPassword);
    }
    
    /**
     * Get event details from Arlo API (with credentials parameter)
     */
    public static EventData getEventDetailsStatic(String eventId, String username, String password) {
        try {
            String endpoint = ARLO_API_BASE_URL + '/resources/events/' + eventId;
            HttpResponse res = makeArloRequest(endpoint, username, password);

            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();

                // Parse XML using ArloXmlParser
                EventData eventData = new EventData();
                eventData.eventId = eventId;
                eventData.code = ArloXmlParser.extractElementValue(responseBody, 'Code');
                eventData.name = ArloXmlParser.extractElementValue(responseBody, 'Name');

                return eventData;
            } else {
                System.debug('ArloEventRegistrationSync: Error getting event details for event ID ' + eventId + '. Status: ' + res.getStatusCode());
                return null;
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting event details for event ID ' + eventId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }
    
    /**
     * Get registration links for an event (uses static credentials)
     */
    @TestVisible
    private static List<String> getRegistrationLinks(String eventId) {
        return getRegistrationLinksStatic(eventId, arloUsername, arloPassword);
    }
    
    /**
     * Get registration links for an event (with credentials parameter)
     * Handles pagination to get all registrations
     */
    public static List<String> getRegistrationLinksStatic(String eventId, String username, String password) {
        List<String> allRegistrationLinks = new List<String>();
        String nextLink = ARLO_API_BASE_URL + '/resources/events/' + eventId + '/registrations';
        Integer pageCount = 0;
        Integer maxPages = 100; // Safety limit to prevent infinite loops

        while (String.isNotBlank(nextLink) && pageCount < maxPages) {
            try {
                HttpResponse res = makeArloRequest(nextLink, username, password);

                if (res.getStatusCode() == 200) {
                    String responseBody = res.getBody();

                    // Parse XML to extract registration links using ArloXmlParser
                    List<String> pageLinks = ArloXmlParser.extractResourceLinks(responseBody, 'registrations');
                    allRegistrationLinks.addAll(pageLinks);
                    System.debug('ArloEventRegistrationSync: Found ' + pageLinks.size() + ' registrations on page ' + (pageCount + 1) + ' for event ' + eventId);

                    // Check for "next" link for pagination
                    nextLink = ArloXmlParser.extractNextLink(responseBody);
                    if (String.isNotBlank(nextLink)) {
                        System.debug('ArloEventRegistrationSync: Found next page link for event ' + eventId + ' registrations: ' + nextLink);
                        pageCount++;
                    } else {
                        System.debug('ArloEventRegistrationSync: No more registration pages for event ' + eventId);
                        break;
                    }
                } else {
                    System.debug('ArloEventRegistrationSync: Error getting registrations for event ' + eventId + '. Status: ' + res.getStatusCode());
                    break;
                }
            } catch (Exception e) {
                System.debug('ArloEventRegistrationSync: Error getting registrations for event ' + eventId + ': ' + e.getMessage());
                System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                break;
            }
        }

        System.debug('ArloEventRegistrationSync: Total registration links found for event ' + eventId + ': ' + allRegistrationLinks.size() + ' across ' + (pageCount + 1) + ' pages');
        return allRegistrationLinks;
    }
    
    /**
     * Extract registration ID from link
     */
    public static String extractRegistrationIdFromLink(String registrationLink) {
        return ArloXmlParser.extractIdFromUrl(registrationLink, 'registrations');
    }
    
    /**
     * Check if registration has email consent (uses static credentials)
     */
    @TestVisible
    private static Boolean checkRegistrationEmailConsent(String registrationId) {
        return checkRegistrationEmailConsentStatic(registrationId, arloUsername, arloPassword);
    }
    
    /**
     * Check if registration has email consent (with credentials parameter)
     * Checks the custom field 'imhappytobeemailedaboutlifeeducationtrustnews' for Boolean value true
     */
    public static Boolean checkRegistrationEmailConsentStatic(String registrationId, String username, String password) {
        try {
            String endpoint = ARLO_API_BASE_URL + '/resources/registrations/' + registrationId + '/customfields';
            HttpResponse res = makeArloRequest(endpoint, username, password);

            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();

                // Parse XML to find the field 'imhappytobeemailedaboutlifeeducationtrustnews'
                try {
                    Dom.Document doc = new Dom.Document();
                    doc.load(responseBody);
                    Dom.XmlNode root = doc.getRootElement();

                    // Recursively search for Field elements
                    Boolean result = findEmailConsentField(root);
                    // If result is null (field not found), return false; otherwise return the boolean value
                    return (result != null && result == true);

                } catch (Exception e) {
                    // XML parsing failed - try regex as fallback
                    System.debug('ArloEventRegistrationSync: XML parsing failed for registration ' + registrationId + ', trying regex fallback: ' + e.getMessage());
                    return checkEmailConsentWithRegex(responseBody);
                }
            } else {
                System.debug('ArloEventRegistrationSync: Error getting custom fields for registration ' + registrationId + '. Status: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting custom fields for registration ' + registrationId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return false; // Default to false if we can't determine
    }
    
    /**
     * Recursively find the email consent field in XML
     * Handles various XML structures and whitespace variations
     */
    @TestVisible
    private static Boolean findEmailConsentField(Dom.XmlNode node) {
        String nodeName = node.getName();

        // Handle namespaces in node name
        if (nodeName.contains(':')) {
            nodeName = nodeName.substring(nodeName.indexOf(':') + 1);
        }

        // Check if this is a Field element
        if (nodeName == 'Field') {
            String fieldName = null;
            Boolean fieldValue = false;
            Boolean hasBooleanValue = false;

            // Look for Name and Value elements
            for (Dom.XmlNode child : node.getChildElements()) {
                String childName = child.getName();

                // Handle namespaces
                if (childName.contains(':')) {
                    childName = childName.substring(childName.indexOf(':') + 1);
                }

                if (childName == 'Name') {
                    String nameText = child.getText();
                    if (nameText != null) {
                        fieldName = nameText.trim();
                    }
                } else if (childName == 'Value') {
                    // Check if Value directly contains text
                    String valueText = child.getText();
                    if (valueText != null && valueText.trim() != '') {
                        String trimmedValue = valueText.trim().toLowerCase();
                        if (trimmedValue == 'true' || trimmedValue == 'false') {
                            fieldValue = (trimmedValue == 'true');
                            hasBooleanValue = true;
                        }
                    }

                    // Also check child elements for Boolean
                    for (Dom.XmlNode valueChild : child.getChildElements()) {
                        String valueChildName = valueChild.getName();
                        if (valueChildName.contains(':')) {
                            valueChildName = valueChildName.substring(valueChildName.indexOf(':') + 1);
                        }
                        if (valueChildName == 'Boolean') {
                            String boolText = valueChild.getText();
                            if (boolText != null) {
                                fieldValue = (boolText.trim().toLowerCase() == 'true');
                                hasBooleanValue = true;
                            }
                        }
                    }
                }
            }

            // Check if this is the field we're looking for (case-insensitive)
            if (fieldName != null && fieldName.equalsIgnoreCase('imhappytobeemailedaboutlifeeducationtrustnews')) {
                return hasBooleanValue ? fieldValue : false;
            }
        }

        // Recursively search child elements
        for (Dom.XmlNode child : node.getChildElements()) {
            Boolean result = findEmailConsentField(child);
            if (result != null) {
                return result;
            }
        }

        return null;
    }
    
    /**
     * Fallback method to check email consent using regex
     * Handles various XML structures with whitespace and newlines
     */
    @TestVisible
    private static Boolean checkEmailConsentWithRegex(String xmlBody) {
        try {
            // Pattern 1: Standard structure with Boolean element
            Pattern pattern1 = Pattern.compile('(?i)<Name>\\s*imhappytobeemailedaboutlifeeducationtrustnews\\s*</Name>\\s*<Value>\\s*<Boolean>\\s*(true|false)\\s*</Boolean>');
            Matcher matcher1 = pattern1.matcher(xmlBody);
            if (matcher1.find()) {
                String boolValue = matcher1.group(1);
                return (boolValue != null && boolValue.trim().toLowerCase() == 'true');
            }

            // Pattern 2: Value contains text directly (no Boolean element)
            Pattern pattern2 = Pattern.compile('(?i)<Name>\\s*imhappytobeemailedaboutlifeeducationtrustnews\\s*</Name>\\s*<Value>\\s*(true|false)\\s*</Value>');
            Matcher matcher2 = pattern2.matcher(xmlBody);
            if (matcher2.find()) {
                String boolValue = matcher2.group(1);
                return (boolValue != null && boolValue.trim().toLowerCase() == 'true');
            }

            // Pattern 3: More flexible - allows any whitespace/newlines between elements
            Pattern pattern3 = Pattern.compile('(?i)<Name>\\s*imhappytobeemailedaboutlifeeducationtrustnews\\s*</Name>[\\s\\S]*?<Value>[\\s\\S]*?<Boolean>\\s*(true|false)\\s*</Boolean>');
            Matcher matcher3 = pattern3.matcher(xmlBody);
            if (matcher3.find()) {
                String boolValue = matcher3.group(1);
                return (boolValue != null && boolValue.trim().toLowerCase() == 'true');
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error in regex check for email consent: ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return false;
    }
    
    /**
     * Get contact ID from registration (uses static credentials)
     */
    @TestVisible
    private static String getContactIdFromRegistration(String registrationId) {
        return getContactIdFromRegistrationStatic(registrationId, arloUsername, arloPassword);
    }
    
    /**
     * Get contact ID from registration (with credentials parameter)
     */
    public static String getContactIdFromRegistrationStatic(String registrationId, String username, String password) {
        try {
            String endpoint = ARLO_API_BASE_URL + '/resources/registrations/' + registrationId;
            HttpResponse res = makeArloRequest(endpoint, username, password);

            if (res.getStatusCode() == 200) {
                // Extract contact ID from registration XML using ArloXmlParser
                return ArloXmlParser.extractIdFromLinkByRel(res.getBody(), 'Contact', 'contacts');
            } else {
                System.debug('ArloEventRegistrationSync: Error getting registration details for registration ' + registrationId + '. Status: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting registration details for registration ' + registrationId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }

    /**
     * Get event ID from a registration
     */
    public static String getEventIdFromRegistrationStatic(String registrationId, String username, String password) {
        try {
            String endpoint = ARLO_API_BASE_URL + '/resources/registrations/' + registrationId;
            HttpResponse res = makeArloRequest(endpoint, username, password);

            if (res.getStatusCode() == 200) {
                // Extract event ID from registration XML using ArloXmlParser
                return ArloXmlParser.extractIdFromLinkByRel(res.getBody(), 'Event', 'events');
            } else {
                System.debug('ArloEventRegistrationSync: Error getting registration details for registration ' + registrationId + '. Status: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting event ID from registration ' + registrationId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }
    
    /**
     * Get organisation CodePrimary from organisation endpoint (uses static credentials)
     */
    @TestVisible
    private static String getOrganisationCodePrimary(String organisationId) {
        return getOrganisationCodePrimaryStatic(organisationId, arloUsername, arloPassword);
    }
    
    /**
     * Get organisation CodePrimary from organisation endpoint (with credentials parameter)
     */
    public static String getOrganisationCodePrimaryStatic(String organisationId, String username, String password) {
        try {
            String endpoint = ARLO_API_BASE_URL + '/resources/organisations/' + organisationId;
            HttpResponse res = makeArloRequest(endpoint, username, password);

            if (res.getStatusCode() == 200) {
                // Use ArloXmlParser to parse organisation details
                ArloModels.ArloOrganisation org = ArloXmlParser.parseOrganisationDetails(res.getBody());
                if (org != null && String.isNotBlank(org.codePrimary)) {
                    return org.codePrimary;
                }
            } else {
                System.debug('ArloEventRegistrationSync: Error getting organisation data for organisation ID ' + organisationId + '. Status: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting CodePrimary for organisation ID ' + organisationId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }
    
    /**
     * Helper method to collect all node names for debugging
     */
    @TestVisible
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
    @TestVisible
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
     * Get Salesforce Account by AccountNumber
     */
    public static Account getSalesforceAccountByNumberStatic(String accountNumber) {
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
            
            return accounts.isEmpty() ? null : accounts[0];
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error querying Account for AccountNumber ' + accountNumber + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }

    /**
     * Extract the "next" link for pagination
     */
    @TestVisible
    private static String extractNextLink(String xmlBody) {
        return ArloXmlParser.extractNextLink(xmlBody);
    }

    /**
     * Create a log record
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
            return log.Id;
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error creating log record for operation ' + operationType + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }

    /**
     * Send email notification when sync fails (public for Queueable)
     */
    public static void sendErrorNotificationStatic(Id logId, String errorMessage) {
        sendErrorNotification(logId, errorMessage);
    }
    
    /**
     * Send email notification when sync fails
     */
    @TestVisible
    private static void sendErrorNotification(Id logId, String errorMessage) {
        try {
            List<String> toAddresses = new List<String>{ 'patrisha@redux.nz', 'lifeeducation@redux.nz' };
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('Arlo Event Registration Sync - Error Notification');
            
            String emailBody = 'The Arlo Event Registration Sync has encountered an error.\n\n';
            emailBody += 'Error Details:\n';
            emailBody += errorMessage + '\n\n';
            
            if (logId != null) {
                // Get log record to include failure reasons
                try {
                    List<Arlo_Integration_Log__c> logRecords = [
                        SELECT Id, Status__c, Records_Processed__c, Records_Successful__c, 
                               Records_Failed__c, Failure_Reasons__c
                        FROM Arlo_Integration_Log__c 
                        WHERE Id = :logId
                        LIMIT 1
                    ];
                    
                    if (!logRecords.isEmpty()) {
                        Arlo_Integration_Log__c log = logRecords[0];
                        emailBody += 'Sync Summary:\n';
                        emailBody += '- Processed: ' + (log.Records_Processed__c != null ? String.valueOf(log.Records_Processed__c) : '0') + '\n';
                        emailBody += '- Successful: ' + (log.Records_Successful__c != null ? String.valueOf(log.Records_Successful__c) : '0') + '\n';
                        emailBody += '- Failed: ' + (log.Records_Failed__c != null ? String.valueOf(log.Records_Failed__c) : '0') + '\n\n';
                        
                        if (String.isNotBlank(log.Failure_Reasons__c)) {
                            emailBody += 'Failure Reasons:\n';
                            emailBody += log.Failure_Reasons__c + '\n\n';
                        }
                    }
                } catch (Exception queryEx) {
                    System.debug('ArloEventRegistrationSync: Error querying log record for email notification, log ID ' + logId + ': ' + queryEx.getMessage());
                }

                // Get org URL for log record link
                String orgUrl = '';
                try {
                    // Use Site.getBaseUrl() or construct from current request
                    orgUrl = System.URL.getOrgDomainUrl().toExternalForm();
                } catch (Exception urlEx) {
                    // Fallback - just include the log ID (expected in some contexts)
                    System.debug('ArloEventRegistrationSync: Could not get org URL, using placeholder: ' + urlEx.getMessage());
                    orgUrl = '[Your Salesforce Org URL]';
                }
                emailBody += 'Log Record ID: ' + logId + '\n';
                emailBody += 'View in Salesforce: ' + orgUrl + '/' + logId + '\n\n';
            }
            
            emailBody += 'Please review the Arlo Integration Log records for more details.\n\n';
            emailBody += 'This is an automated message from the Arlo Integration System.';
            
            mail.setPlainTextBody(emailBody);
            
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
            System.debug('ArloEventRegistrationSync: Error notification email sent to ' + toAddresses);
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error sending notification email: ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            // Don't throw - email failure shouldn't stop the process
        }
    }

    /**
     * Update a log record
     */
    public static void updateLogRecordStatic(Id logId, String status, String message, Id salesforceContactId, Integer recordsProcessed, Integer recordsSuccessful) {
        updateLogRecordStatic(logId, status, message, salesforceContactId, recordsProcessed, recordsSuccessful, null);
    }
    
    public static void updateLogRecordStatic(Id logId, String status, String message, Id salesforceContactId, Integer recordsProcessed, Integer recordsSuccessful, String failureReasons) {
        if (logId == null) {
            System.debug('ArloEventRegistrationSync: Cannot update log - logId is null');
            return;
        }
        
        try {
            System.debug('ArloEventRegistrationSync: Updating log record ' + logId + ' with status: ' + status);
            
            // First, verify the log record exists
            List<Arlo_Integration_Log__c> existingLogs = [
                SELECT Id, Status__c, Records_Processed__c, Records_Successful__c 
                FROM Arlo_Integration_Log__c 
                WHERE Id = :logId 
                LIMIT 1
            ];
            
            if (existingLogs.isEmpty()) {
                System.debug('ArloEventRegistrationSync: ERROR - Log record ' + logId + ' does not exist!');
                return;
            }
            
            System.debug('ArloEventRegistrationSync: Found log record. Current Status: ' + existingLogs[0].Status__c);
            
            Arlo_Integration_Log__c log = new Arlo_Integration_Log__c(Id = logId);
            if (String.isNotBlank(status)) {
                log.Status__c = status;
                System.debug('ArloEventRegistrationSync: Setting Status__c to: ' + status);
            }
            if (String.isNotBlank(failureReasons)) {
                log.Failure_Reasons__c = failureReasons;
                System.debug('ArloEventRegistrationSync: Setting Failure_Reasons__c');
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
                // Only set Records_Failed__c if there are actual failure reasons
                // If failureReasons is empty/null, it means all "failures" were CodePrimary-related skips (not real failures)
                if (String.isNotBlank(failureReasons)) {
                    // Calculate failed count from failure reasons (count occurrences)
                    Integer failedCount = 0;
                    if (String.isNotBlank(failureReasons)) {
                        String[] lines = failureReasons.split('\n');
                        for (String line : lines) {
                            if (String.isNotBlank(line) && line.contains(': ')) {
                                String[] parts = line.split(': ', 2);
                                if (parts.size() == 2) {
                                    try {
                                        Integer count = Integer.valueOf(parts[1].trim());
                                        failedCount += count;
                                    } catch (Exception e) {
                                        // Parsing error for failure count - skip this line (expected for non-numeric values)
                                        System.debug(LoggingLevel.FINE, 'ArloEventRegistrationSync: Could not parse failure count from line: ' + line);
                                    }
                                }
                            }
                        }
                    }
                    log.Records_Failed__c = failedCount > 0 ? failedCount : 0;
                } else {
                    // No failure reasons = no actual failures (only CodePrimary-related skips)
                    log.Records_Failed__c = 0;
                }
            }
            
            System.debug('ArloEventRegistrationSync: About to update log record. Status: ' + log.Status__c + ', Processed: ' + log.Records_Processed__c + ', Successful: ' + log.Records_Successful__c);
            
            // Use Database.update with allOrNone=false to get partial success results
            Database.SaveResult result = Database.update(log, false);
            if (result.isSuccess()) {
                System.debug('ArloEventRegistrationSync: Successfully updated log record ' + logId);
            } else {
                System.debug('ArloEventRegistrationSync: ERROR - Failed to update log record ' + logId);
                for (Database.Error error : result.getErrors()) {
                    System.debug('ArloEventRegistrationSync: Error: ' + error.getMessage() + ' (Fields: ' + error.getFields() + ')');
                }
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Exception updating log record ' + logId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            System.debug('ArloEventRegistrationSync: Error type: ' + e.getTypeName());
        }
    }
    
    /**
     * Map event name to campaign name
     * Checks event name for keywords and maps to corresponding campaign
     * Delegates to EventCampaignMapper for the actual mapping
     */
    @TestVisible
    private static String getCampaignNameForEvent(String eventName) {
        String campaignName = EventCampaignMapper.getCampaignNameForEvent(eventName);
        if (campaignName != null) {
            System.debug('ArloEventRegistrationSync: Mapped event "' + eventName + '" -> ' + campaignName);
        } else {
            System.debug('ArloEventRegistrationSync: No campaign match for event "' + eventName + '"');
        }
        return campaignName;
    }
    
    /**
     * Public method to test event name mapping (for debugging)
     * Usage: ArloEventRegistrationSync.testEventNameMapping('Nurturing Healthy Minds - Neurodiversity');
     * Delegates to SyncDiagnostics
     */
    public static String testEventNameMapping(String eventName) {
        return SyncDiagnostics.testEventNameMapping(eventName);
    }
    
    /**
     * Add contacts to campaigns based on event names
     */
    public static void addContactsToCampaignsStatic(List<ContactEventWrapper> contactEventList, Map<Id, Contact> syncedContactMap) {
        System.debug('ArloEventRegistrationSync: ===== addContactsToCampaignsStatic START =====');
        System.debug('ArloEventRegistrationSync: Input - contactEventList size: ' + contactEventList.size() + ', syncedContactMap size: ' + syncedContactMap.size());

        // Delegate to CampaignMemberManager for campaign member creation
        CampaignMemberManager.AddMembersResult result = CampaignMemberManager.addContactsToCampaigns(
            contactEventList,
            syncedContactMap
        );

        // Log results
        System.debug('ArloEventRegistrationSync: Campaign member operation completed:');
        System.debug('ArloEventRegistrationSync:   - Total processed: ' + result.totalProcessed);
        System.debug('ArloEventRegistrationSync:   - Members added: ' + result.membersAdded);
        System.debug('ArloEventRegistrationSync:   - Already members: ' + result.alreadyMembers);
        System.debug('ArloEventRegistrationSync:   - No campaign match: ' + result.noCampaignMatch);
        System.debug('ArloEventRegistrationSync:   - Campaign not found: ' + result.campaignNotFound);

        // Check for critical errors (DML failures) vs informational errors
        // Throw exception only for insert failures to maintain backward compatibility
        if (!result.errors.isEmpty()) {
            for (String error : result.errors) {
                System.debug('ArloEventRegistrationSync: Error: ' + error);
                // Only throw for actual insert failures, not for informational messages
                if (error.startsWith('Error inserting campaign members:')) {
                    throw new CampaignMemberException(error);
                }
            }
        }

        System.debug('ArloEventRegistrationSync: ===== addContactsToCampaignsStatic END =====');
    }

    /**
     * Exception class for campaign member operations
     */
    public class CampaignMemberException extends Exception {}
    
    /**
     * Get Salesforce Account by AccountNumber (uses existing method)
     */
    @TestVisible
    private static Account getSalesforceAccountByNumber(String accountNumber) {
        return getSalesforceAccountByNumberStatic(accountNumber);
    }
    
    /**
     * Helper method to get contact IDs from ArloContact list
     */
    public static Set<String> getContactIds(List<ArloModels.ArloContact> contacts) {
        Set<String> ids = new Set<String>();
        for (ArloModels.ArloContact contact : contacts) {
            if (String.isNotBlank(contact.contactId)) {
                ids.add(contact.contactId);
            }
        }
        return ids;
    }
    
    /**
     * Helper method to get contact emails from ArloContact list
     */
    public static Set<String> getContactEmails(List<ArloModels.ArloContact> contacts) {
        Set<String> emails = new Set<String>();
        for (ArloModels.ArloContact contact : contacts) {
            if (String.isNotBlank(contact.email)) {
                emails.add(contact.email);
            }
        }
        return emails;
    }
    
    /**
     * Inner class to represent Event data
     */
    public class EventData {
        public String eventId;
        public String code;
        public String name;
    }

    /**
     * Inner class to wrap contact with event information
     */
    public class ContactEventWrapper {
        public ArloModels.ArloContact contact;
        public String eventName;
        public String eventCode;
    }

    /**
     * Inner class to hold reverse lookup maps for contact matching
     */
    public class ReverseMapsResult {
        public Map<String, String> uuidToNumericId;
        public Map<String, String> emailToNumericId;

        public ReverseMapsResult() {
            this.uuidToNumericId = new Map<String, String>();
            this.emailToNumericId = new Map<String, String>();
        }
    }

    /**
     * Inner class to wrap registration processing result
     */
    public class RegistrationProcessingResult {
        public EventData eventData;
        public Integer calloutCount;
        public Boolean shouldProcess;

        public RegistrationProcessingResult(Integer calloutCount) {
            this.calloutCount = calloutCount;
            this.shouldProcess = false;
            this.eventData = null;
        }
    }
    
    /**
     * Debug method to check the registrations endpoint response for a contact
     * Usage: ArloEventRegistrationSync.debugContactRegistrationsEndpoint('1944');
     * Delegates to SyncDiagnostics
     */
    public static void debugContactRegistrationsEndpoint(String numericContactId) {
        SyncDiagnostics.debugContactRegistrationsEndpoint(numericContactId);
    }
    
    /**
     * Diagnose which campaigns a contact should be in based on their Arlo registrations
     * This method uses the contact's numeric ID to get registrations directly
     * Usage: 
     *   - By numeric contact ID: ArloEventRegistrationSync.diagnoseContactCampaigns('1944');
     *   - By UUID: ArloEventRegistrationSync.diagnoseContactCampaigns('9b4c8fc8-eff0-4c04-a7b3-535fe95a23ff');
     *   - By email: ArloEventRegistrationSync.diagnoseContactCampaigns('kavanagha@hautapu.school.nz');
     */
    public static void diagnoseContactCampaigns(String contactIdentifier) {
        System.debug('=== DIAGNOSING CONTACT CAMPAIGNS ===');
        System.debug('Contact Identifier: ' + contactIdentifier);
        System.debug('This will check Arlo registrations and determine which campaigns the contact should be in\n');
        
        // Load credentials
        try {
            loadCredentialsFromCustomSettings();
        } catch (Exception e) {
            System.debug('❌ ERROR: Could not load credentials: ' + e.getMessage());
            return;
        }
        
        String arloUsername = ArloEventRegistrationSync.arloUsername;
        String arloPassword = ArloEventRegistrationSync.arloPassword;
        
        // Determine if contactIdentifier is a numeric ID, UUID, or email
        String arloNumericContactId = null;
        Boolean isNumericId = Pattern.matches('^\\d+$', contactIdentifier);
        Set<String> currentCampaignNames = new Set<String>(); // Initialize for both paths
        
        if (isNumericId) {
            // Direct numeric contact ID provided
            arloNumericContactId = contactIdentifier;
            System.debug('✓ Using numeric contact ID directly: ' + arloNumericContactId);
            
            // Still need to find contact in Salesforce to check campaign memberships
            // Get contact details from Arlo first to find email/UUID
            try {
                ArloModels.ArloContact arloContact = ArloContactSync.getSingleArloContactStatic(arloNumericContactId, arloUsername, arloPassword);
                if (arloContact != null && (String.isNotBlank(arloContact.email) || String.isNotBlank(arloContact.contactId))) {
                    // Find contact in Salesforce
                    List<Contact> contacts = [
                        SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name
                        FROM Contact
                        WHERE (Arlo_Contact_UUID__c != null AND Arlo_Contact_UUID__c = :arloContact.contactId)
                           OR (Email != null AND Email = :arloContact.email)
                        LIMIT 1
                    ];
                    
                    if (!contacts.isEmpty()) {
                        Contact sfContact = contacts[0];
                        System.debug('✓ Contact found in Salesforce:');
                        System.debug('   ID: ' + sfContact.Id);
                        System.debug('   Name: ' + sfContact.FirstName + ' ' + sfContact.LastName);
                        System.debug('   Email: "' + sfContact.Email + '"');
                        System.debug('   UUID: "' + sfContact.Arlo_Contact_UUID__c + '"');
                        
                        // Check current campaign memberships
                        List<CampaignMember> currentMembers = [
                            SELECT Campaign.Name, Status, CampaignId
                            FROM CampaignMember
                            WHERE ContactId = :sfContact.Id AND Campaign.Name LIKE 'NHM - %'
                        ];
                        
                        if (currentMembers.isEmpty()) {
                            System.debug('⚠️  Contact is NOT in any NHM campaigns');
                        } else {
                            System.debug('✓ Contact is currently in ' + currentMembers.size() + ' NHM campaign(s):');
                            for (CampaignMember cm : currentMembers) {
                                System.debug('   - ' + cm.Campaign.Name + ' (Status: ' + cm.Status + ')');
                                currentCampaignNames.add(cm.Campaign.Name);
                            }
                        }
                    } else {
                        System.debug('⚠️  Contact not found in Salesforce (may not be synced yet)');
                    }
                }
            } catch (Exception e) {
                System.debug('⚠️  Could not get contact details from Arlo: ' + e.getMessage());
            }
        } else {
            // Need to find contact in Salesforce first, then get numeric ID
            // STEP 1: Find contact in Salesforce
            System.debug('=== STEP 1: Finding Contact in Salesforce ===');
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name, Account.AccountNumber
                FROM Contact
                WHERE Arlo_Contact_UUID__c = :contactIdentifier OR Email = :contactIdentifier
                LIMIT 1
            ];
            
            if (contacts.isEmpty()) {
                System.debug('❌ Contact not found in Salesforce');
                System.debug('   Searched for: ' + contactIdentifier);
                return;
            }
            
            Contact sfContact = contacts[0];
            System.debug('✓ Contact found:');
            System.debug('   ID: ' + sfContact.Id);
            System.debug('   Name: ' + sfContact.FirstName + ' ' + sfContact.LastName);
            System.debug('   Email: "' + sfContact.Email + '"');
            System.debug('   UUID: "' + sfContact.Arlo_Contact_UUID__c + '"');
            System.debug('   Account: ' + (sfContact.Account != null ? sfContact.Account.Name : 'None'));
            
            // Check current campaign memberships
            System.debug('\n=== STEP 2: Current Campaign Memberships ===');
                        List<CampaignMember> currentMembers = [
                            SELECT Campaign.Name, Status, CampaignId
                            FROM CampaignMember
                            WHERE ContactId = :sfContact.Id AND Campaign.Name LIKE 'NHM - %'
                        ];
                        
                        if (currentMembers.isEmpty()) {
                System.debug('⚠️  Contact is NOT in any NHM campaigns');
            } else {
                System.debug('✓ Contact is currently in ' + currentMembers.size() + ' NHM campaign(s):');
                for (CampaignMember cm : currentMembers) {
                    System.debug('   - ' + cm.Campaign.Name + ' (Status: ' + cm.Status + ')');
                    currentCampaignNames.add(cm.Campaign.Name);
                }
            }
            
            // Try to get numeric contact ID from Arlo using UUID
            String targetContactUuid = sfContact.Arlo_Contact_UUID__c != null ? sfContact.Arlo_Contact_UUID__c.trim() : '';
            if (String.isNotBlank(targetContactUuid)) {
                System.debug('\n=== STEP 3: Getting Numeric Contact ID from Arlo ===');
                System.debug('Searching for contact by UUID: ' + targetContactUuid);
                // Use the same search logic as before, but simplified
                // For now, we'll skip this and go directly to registrations if we have the numeric ID
                // The user can provide the numeric ID directly
            }
        }
        
        // STEP 3/4: Get contact's registrations directly from Arlo using numeric ID
        if (String.isBlank(arloNumericContactId)) {
            System.debug('❌ Could not determine numeric contact ID. Cannot proceed.');
            return;
        }
        
        System.debug('\n=== STEP ' + (isNumericId ? '1' : '4') + ': Getting Contact Registrations from Arlo ===');
        System.debug('Using direct contact registrations endpoint: /resources/contacts/' + arloNumericContactId + '/registrations/');
        
        List<Map<String, String>> foundRegistrations = new List<Map<String, String>>();
        
        if (String.isNotBlank(arloNumericContactId)) {
            // Get registrations directly from contact endpoint
            try {
                String registrationsEndpoint = ARLO_API_BASE_URL + '/resources/contacts/' + arloNumericContactId + '/registrations/';
                HttpResponse res = makeArloRequest(registrationsEndpoint, arloUsername, arloPassword);

                if (res.getStatusCode() == 200) {
                    String responseBody = res.getBody();
                    System.debug('✓ Successfully retrieved registrations from Arlo');
                    
                    // Parse registration links from the response
                    // Look for Link elements with rel="self" that point to registrations (these are the actual registration resources)
                    // Also look for Resource elements with type="Registration"
                    // Extract registration IDs using ArloXmlParser
                    Set<String> registrationIds = ArloXmlParser.extractResourceIds(responseBody, 'registrations');
                    System.debug('Total unique registration IDs found: ' + registrationIds.size());
                    if (registrationIds.size() > 10) {
                        System.debug('⚠️  WARNING: Found ' + registrationIds.size() + ' registrations, which seems high. This might include pagination or related resource links.');
                    }
                    
                    // Process each registration
                    Integer registrationNumber = 0;
                    for (String registrationId : registrationIds) {
                        registrationNumber++;
                        System.debug('\n--- Processing Registration #' + registrationNumber + ' (ID: ' + registrationId + ') ---');
                        
                        try {
                            // Step 1: Check email consent
                            System.debug('Step 1: Checking email consent...');
                            Boolean hasEmailConsent = checkRegistrationEmailConsentStatic(registrationId, arloUsername, arloPassword);
                            if (!hasEmailConsent) {
                                System.debug('  ❌ Registration ' + registrationId + ': No email consent - SKIPPING');
                                continue;
                            }
                            System.debug('  ✓ Registration ' + registrationId + ': Has email consent');
                            
                            // Step 2: Get event ID from registration
                            System.debug('Step 2: Getting event from registration...');
                            String eventId = getEventIdFromRegistrationStatic(registrationId, arloUsername, arloPassword);
                            if (String.isBlank(eventId)) {
                                System.debug('  ❌ Registration ' + registrationId + ': No event found - SKIPPING');
                                continue;
                            }
                            System.debug('  ✓ Found event ID: ' + eventId);
                            
                            // Step 3: Get event details
                            System.debug('Step 3: Getting event details...');
                            EventData eventData = getEventDetailsStatic(eventId, arloUsername, arloPassword);
                            if (eventData == null) {
                                System.debug('  ❌ Registration ' + registrationId + ': Could not get event details - SKIPPING');
                                continue;
                            }
                            System.debug('  ✓ Event Name: ' + eventData.name);
                            System.debug('  ✓ Event Code: ' + (eventData.code != null ? eventData.code : 'N/A'));
                            
                            // Step 4: Skip CONF events
                            if (eventData.code != null && eventData.code.startsWith('CONF')) {
                                System.debug('  ⚠️  Registration ' + registrationId + ': CONF event - SKIPPING');
                                continue;
                            }
                            
                            // Step 5: Determine campaign
                            System.debug('Step 4: Determining campaign from event name...');
                            String campaignName = getCampaignNameForEvent(eventData.name);
                            if (String.isBlank(campaignName)) {
                                System.debug('  ⚠️  Registration ' + registrationId + ': Event "' + eventData.name + '" does not match any campaign keywords - SKIPPING');
                                continue;
                            }
                            System.debug('  ✓ Campaign: ' + campaignName);
                            
                            // Add to found registrations
                            Map<String, String> regInfo = new Map<String, String>();
                            regInfo.put('eventName', eventData.name);
                            regInfo.put('eventCode', eventData.code != null ? eventData.code : '');
                            regInfo.put('registrationId', registrationId);
                            regInfo.put('hasEmailConsent', 'true');
                            regInfo.put('campaignName', campaignName);
                            foundRegistrations.add(regInfo);
                            
                            System.debug('✓ Registration #' + registrationNumber + ' processed successfully:');
                            System.debug('   Event: ' + eventData.name);
                            System.debug('   Event Code: ' + (eventData.code != null ? eventData.code : 'N/A'));
                            System.debug('   Registration ID: ' + registrationId);
                            System.debug('   Email Consent: true');
                            System.debug('   → Should be in campaign: ' + campaignName);
                            
                        } catch (Exception e) {
                            System.debug('❌ Error processing registration ' + registrationId + ': ' + e.getMessage());
                            System.debug('Stack trace: ' + e.getStackTraceString());
                        }
                    }
                } else {
                    System.debug('❌ Error getting registrations. Status: ' + res.getStatusCode());
                    System.debug('   Response: ' + res.getBody());
                }
            } catch (Exception e) {
                System.debug('❌ Error calling registrations endpoint: ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
            }
        } else {
            System.debug('⚠️  Could not determine numeric contact ID. Cannot use direct registrations endpoint.');
            System.debug('   Falling back to event search method...');
            // Fallback to the old method if we can't get numeric ID
            // (Keep the old code as fallback)
        }
        
        System.debug('\n=== Summary of Search ===');
        System.debug('Registrations found for this contact: ' + foundRegistrations.size());
        
        // STEP 4: Determine which campaigns contact should be in
        System.debug('\n=== STEP 4: Expected Campaign Assignments ===');
        
        if (foundRegistrations.isEmpty()) {
            System.debug('❌ No registrations found for this contact with email consent');
            System.debug('   This could mean:');
            System.debug('   - Contact has no registrations in Arlo');
            System.debug('   - Contact\'s registrations don\'t have email consent');
            System.debug('   - Contact UUID/Email mismatch between Salesforce and Arlo');
            return;
        }
        
        Set<String> expectedCampaigns = new Set<String>();
        Map<String, List<String>> campaignToEvents = new Map<String, List<String>>();
        
        for (Map<String, String> reg : foundRegistrations) {
            // Campaign name is already determined during processing
            String campaignName = reg.get('campaignName');
            String eventName = reg.get('eventName');
            
            if (String.isNotBlank(campaignName)) {
                expectedCampaigns.add(campaignName);
                if (!campaignToEvents.containsKey(campaignName)) {
                    campaignToEvents.put(campaignName, new List<String>());
                }
                campaignToEvents.get(campaignName).add(eventName);
            } else {
                System.debug('⚠️  Event "' + eventName + '" does not match any campaign keywords');
            }
        }
        
        if (expectedCampaigns.isEmpty()) {
            System.debug('⚠️  No campaigns matched from the found registrations');
            System.debug('   Events found:');
            for (Map<String, String> reg : foundRegistrations) {
                System.debug('     - ' + reg.get('eventName'));
            }
            return;
        }
        
        System.debug('✓ Contact should be in ' + expectedCampaigns.size() + ' campaign(s):');
        for (String campaignName : expectedCampaigns) {
            System.debug('   - ' + campaignName);
            if (campaignToEvents.containsKey(campaignName)) {
                System.debug('     Based on events:');
                for (String eventName : campaignToEvents.get(campaignName)) {
                    System.debug('       • ' + eventName);
                }
            }
        }
        
        // STEP 5: Compare expected vs current
        System.debug('\n=== STEP 5: Comparison (Expected vs Current) ===');
        
        Set<String> missingCampaigns = new Set<String>();
        Set<String> extraCampaigns = new Set<String>();
        
        for (String expected : expectedCampaigns) {
            if (!currentCampaignNames.contains(expected)) {
                missingCampaigns.add(expected);
            }
        }
        
        for (String current : currentCampaignNames) {
            if (!expectedCampaigns.contains(current)) {
                extraCampaigns.add(current);
            }
        }
        
        if (missingCampaigns.isEmpty() && extraCampaigns.isEmpty()) {
            System.debug('✓ Contact is in all expected campaigns and no extra campaigns');
        } else {
            if (!missingCampaigns.isEmpty()) {
                System.debug('❌ MISSING Campaigns (' + missingCampaigns.size() + '):');
                for (String missing : missingCampaigns) {
                    System.debug('   - ' + missing);
                }
            }
            if (!extraCampaigns.isEmpty()) {
                System.debug('⚠️  EXTRA Campaigns (not expected based on current registrations):');
                for (String extra : extraCampaigns) {
                    System.debug('   - ' + extra);
                }
            }
        }
        
        // STEP 6: Verify campaigns exist in Salesforce
        System.debug('\n=== STEP 6: Verifying Campaigns Exist in Salesforce ===');
        List<Campaign> allExpectedCampaigns = [
            SELECT Id, Name
            FROM Campaign
            WHERE Name IN :expectedCampaigns
        ];
        
        Map<String, Id> campaignIdMap = new Map<String, Id>();
        for (Campaign camp : allExpectedCampaigns) {
            campaignIdMap.put(camp.Name, camp.Id);
            System.debug('✓ Campaign exists: ' + camp.Name + ' (ID: ' + camp.Id + ')');
        }
        
        Set<String> missingCampaignsInSF = new Set<String>();
        for (String expected : expectedCampaigns) {
            if (!campaignIdMap.containsKey(expected)) {
                missingCampaignsInSF.add(expected);
            }
        }
        
        if (!missingCampaignsInSF.isEmpty()) {
            System.debug('❌ Campaigns expected but NOT found in Salesforce:');
            for (String missing : missingCampaignsInSF) {
                System.debug('   - ' + missing);
            }
        }
        
        // STEP 7: Add contact to missing campaigns
        if (!missingCampaigns.isEmpty()) {
            System.debug('\n=== STEP 7: Adding Contact to Missing Campaigns ===');
            
            // Find contact in Salesforce if we haven't already
            Contact sfContact = null;
            if (!isNumericId) {
                // We already found it earlier
                List<Contact> contacts = [
                    SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c
                    FROM Contact
                    WHERE Arlo_Contact_UUID__c = :contactIdentifier OR Email = :contactIdentifier
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    sfContact = contacts[0];
                }
            } else {
                // For numeric ID, try to find contact by getting Arlo contact details first
                try {
                    ArloModels.ArloContact arloContact = ArloContactSync.getSingleArloContactStatic(arloNumericContactId, arloUsername, arloPassword);
                    if (arloContact != null && (String.isNotBlank(arloContact.email) || String.isNotBlank(arloContact.contactId))) {
                        List<Contact> contacts = [
                            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c
                            FROM Contact
                            WHERE (Arlo_Contact_UUID__c != null AND Arlo_Contact_UUID__c = :arloContact.contactId)
                               OR (Email != null AND Email = :arloContact.email)
                            LIMIT 1
                        ];
                        if (!contacts.isEmpty()) {
                            sfContact = contacts[0];
                        }
                    }
                } catch (Exception e) {
                    System.debug('⚠️  Could not get contact details from Arlo: ' + e.getMessage());
                }
            }
            
            if (sfContact == null) {
                System.debug('❌ Cannot add contact to campaigns - contact not found in Salesforce');
                System.debug('   The contact may need to be synced from Arlo first using ArloContactSync');
            } else {
                System.debug('✓ Found contact in Salesforce: ' + sfContact.Id + ' (' + sfContact.FirstName + ' ' + sfContact.LastName + ')');
                
                // Find campaigns that exist
                List<Campaign> missingCampaignRecords = [
                    SELECT Id, Name
                    FROM Campaign
                    WHERE Name IN :missingCampaigns
                ];
                
                Map<String, Id> campaignNameToId = new Map<String, Id>();
                for (Campaign camp : missingCampaignRecords) {
                    campaignNameToId.put(camp.Name, camp.Id);
                }
                
                // Check which campaigns exist
                Set<String> campaignsNotFound = new Set<String>();
                for (String campaignName : missingCampaigns) {
                    if (!campaignNameToId.containsKey(campaignName)) {
                        campaignsNotFound.add(campaignName);
                    }
                }
                
                if (!campaignsNotFound.isEmpty()) {
                    System.debug('⚠️  Campaigns not found in Salesforce:');
                    for (String notFound : campaignsNotFound) {
                        System.debug('   - ' + notFound);
                    }
                }
                
                // Create campaign members for campaigns that exist
                List<CampaignMember> membersToInsert = new List<CampaignMember>();
                Set<Id> existingCampaignIds = new Set<Id>();
                
                // Check for existing members to avoid duplicates
                if (!campaignNameToId.isEmpty()) {
                    List<CampaignMember> existingMembers = [
                        SELECT CampaignId
                        FROM CampaignMember
                        WHERE ContactId = :sfContact.Id AND CampaignId IN :campaignNameToId.values()
                    ];
                    
                    for (CampaignMember cm : existingMembers) {
                        existingCampaignIds.add(cm.CampaignId);
                    }
                    
                    for (String campaignName : missingCampaigns) {
                        if (campaignNameToId.containsKey(campaignName)) {
                            Id campaignId = campaignNameToId.get(campaignName);
                            if (!existingCampaignIds.contains(campaignId)) {
                                membersToInsert.add(new CampaignMember(
                                    ContactId = sfContact.Id,
                                    CampaignId = campaignId,
                                    Status = 'Responded'
                                ));
                                System.debug('✓ Will add contact to campaign: ' + campaignName);
                            } else {
                                System.debug('⚠️  Contact already a member of: ' + campaignName + ' (skipping)');
                            }
                        }
                    }
                }
                
                if (!membersToInsert.isEmpty()) {
                    try {
                        insert membersToInsert;
                        System.debug('✓ Successfully added contact to ' + membersToInsert.size() + ' campaign(s):');
                        for (CampaignMember cm : membersToInsert) {
                            String campaignName = '';
                            for (Campaign camp : missingCampaignRecords) {
                                if (camp.Id == cm.CampaignId) {
                                    campaignName = camp.Name;
                                    break;
                                }
                            }
                            System.debug('   - ' + campaignName);
                        }
                    } catch (Exception e) {
                        System.debug('❌ Error adding contact to campaigns: ' + e.getMessage());
                        System.debug('Stack trace: ' + e.getStackTraceString());
                    }
                } else {
                    System.debug('⚠️  No campaigns to add (all either missing or already members)');
                }
            }
        }
        
        System.debug('\n=== END DIAGNOSIS ===\n');
    }
    
    /**
     * Add contact to campaign by UUID/Email and event name (no API calls)
     * This is a simple wrapper that finds the contact and adds it to the campaign
     * Usage: ArloEventRegistrationSync.addContactToCampaignByEvent('9b4c8fc8-eff0-4c04-a7b3-535fe95a23ff', 'Nurturing Healthy Minds - Neurodiversity');
     * Delegates to CampaignMemberManager
     */
    public static Boolean addContactToCampaignByEvent(String contactUuidOrEmail, String eventName) {
        System.debug('=== ADDING CONTACT TO CAMPAIGN (NO API CALLS) ===');
        System.debug('Contact Identifier: ' + contactUuidOrEmail);
        System.debug('Event Name: ' + eventName);

        // Find contact
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c
            FROM Contact
            WHERE Arlo_Contact_UUID__c = :contactUuidOrEmail OR Email = :contactUuidOrEmail
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            System.debug('Contact not found');
            return false;
        }

        Contact c = contacts[0];
        System.debug('Contact found: ' + c.FirstName + ' ' + c.LastName + ' (ID: ' + c.Id + ')');

        // Delegate to CampaignMemberManager
        Boolean result = CampaignMemberManager.addContactToCampaignByEvent(c.Id, eventName);
        System.debug('=== END ===');
        return result;
    }

    /**
     * Manually add a contact to a campaign based on event name
     * Use this when a contact has email consent in Arlo but wasn't automatically added to a campaign
     * Usage in Developer Console:
     * ArloEventRegistrationSync.manuallyAddContactToCampaign('003XXXXXXXXXXXXXXX', 'Nurturing Healthy Minds - Anxiety');
     * Delegates to CampaignMemberManager
     *
     * @param contactId Salesforce Contact ID
     * @param eventName Event name (e.g., 'Nurturing Healthy Minds - Anxiety')
     * @return true if successfully added, false otherwise
     */
    public static Boolean manuallyAddContactToCampaign(Id contactId, String eventName) {
        System.debug('=== MANUAL CAMPAIGN ASSIGNMENT ===');
        System.debug('Contact ID: ' + contactId);
        System.debug('Event Name: ' + eventName);

        // Delegate to CampaignMemberManager
        Boolean result = CampaignMemberManager.addContactToCampaignByEvent(contactId, eventName);

        if (result) {
            String campaignName = EventCampaignMapper.getCampaignNameForEvent(eventName);
            System.debug('Successfully added contact to campaign "' + campaignName + '"');
        } else {
            System.debug('Failed to add contact to campaign');
        }

        System.debug('=== END MANUAL ASSIGNMENT ===');
        return result;
    }
    
    /**
     * Diagnostic method to check why a contact isn't being added to a campaign
     * Usage in Developer Console:
     * ArloEventRegistrationSync.diagnoseContactCampaignAssignment('contactIdOrEmail');
     * Delegates to SyncDiagnostics
     *
     * @param contactIdentifier Contact ID, Email, or Arlo Contact UUID
     */
    public static void diagnoseContactCampaignAssignment(String contactIdentifier) {
        SyncDiagnostics.diagnoseContactCampaignAssignment(contactIdentifier);
    }
    
    /**
     * Trace a specific contact through the sync process to identify failures
     * This simulates what happens during Event Registration Sync without actually syncing
     * Usage: ArloEventRegistrationSync.traceContactSync('9b4c8fc8-eff0-4c04-a7b3-535fe95a23ff');
     */
    public static void traceContactSync(String contactUuidOrEmail) {
        System.debug('=== TRACING CONTACT SYNC PROCESS ===');
        System.debug('Contact Identifier: ' + contactUuidOrEmail);
        System.debug('This will trace through the sync process to identify where it fails\n');
        
        // Load credentials
        try {
            loadCredentialsFromCustomSettings();
        } catch (Exception e) {
            System.debug('❌ ERROR: Could not load credentials: ' + e.getMessage());
            return;
        }
        
        // STEP 1: Find contact in Salesforce
        System.debug('=== STEP 1: Finding Contact in Salesforce ===');
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name, Account.AccountNumber
            FROM Contact
            WHERE Arlo_Contact_UUID__c = :contactUuidOrEmail OR Email = :contactUuidOrEmail
            LIMIT 1
        ];
        
        if (contacts.isEmpty()) {
            System.debug('❌ FAILURE: Contact not found in Salesforce');
            System.debug('   Searched for UUID or Email: ' + contactUuidOrEmail);
            return;
        }
        
        Contact sfContact = contacts[0];
        System.debug('✓ Contact found in Salesforce:');
        System.debug('   ID: ' + sfContact.Id);
        System.debug('   Name: ' + sfContact.FirstName + ' ' + sfContact.LastName);
        System.debug('   Email: "' + sfContact.Email + '"');
        System.debug('   UUID: "' + sfContact.Arlo_Contact_UUID__c + '"');
        System.debug('   Account: ' + (sfContact.Account != null ? sfContact.Account.Name : 'None'));
        System.debug('   Account Number: ' + (sfContact.Account != null ? sfContact.Account.AccountNumber : 'None'));
        
        // STEP 2: Check if contact is in any NHM campaigns
        System.debug('\n=== STEP 2: Checking Current Campaign Memberships ===');
        List<CampaignMember> members = [
            SELECT Campaign.Name, Status, CampaignId
            FROM CampaignMember
            WHERE ContactId = :sfContact.Id AND Campaign.Name LIKE 'NHM - %'
        ];
        
        if (members.isEmpty()) {
            System.debug('⚠️  Contact is NOT in any NHM campaigns');
        } else {
            System.debug('✓ Contact is in ' + members.size() + ' NHM campaign(s):');
            for (CampaignMember cm : members) {
                System.debug('   - ' + cm.Campaign.Name + ' (Status: ' + cm.Status + ')');
            }
        }
        
        // STEP 3: Check if campaigns exist
        System.debug('\n=== STEP 3: Verifying Campaigns Exist ===');
        List<Campaign> campaigns = [
            SELECT Id, Name
            FROM Campaign
            WHERE Name IN ('NHM - Anxiety', 'NHM - Digital wellbeing', 'NHM - Self-care', 'NHM - Neurodiversity')
        ];
        
        if (campaigns.isEmpty()) {
            System.debug('❌ FAILURE: No NHM campaigns found in Salesforce!');
            return;
        }
        
        System.debug('✓ Found ' + campaigns.size() + ' NHM campaign(s):');
        Map<String, Id> campaignMap = new Map<String, Id>();
        for (Campaign camp : campaigns) {
            campaignMap.put(camp.Name, camp.Id);
            System.debug('   - ' + camp.Name + ' (ID: ' + camp.Id + ')');
        }
        
        // STEP 4: Simulate matching logic
        System.debug('\n=== STEP 4: Simulating Matching Logic ===');
        System.debug('When Event Registration Sync runs, it will:');
        System.debug('1. Process registrations from events');
        System.debug('2. For each registration with email consent = true:');
        System.debug('   a. Get contact from Arlo');
        System.debug('   b. Match to Salesforce contact by UUID or Email');
        System.debug('   c. Get event name');
        System.debug('   d. Map event name to campaign');
        System.debug('   e. Add to campaign');
        
        System.debug('\nExpected matching values:');
        String normalizedUuid = sfContact.Arlo_Contact_UUID__c != null ? sfContact.Arlo_Contact_UUID__c.trim() : '';
        String normalizedEmail = sfContact.Email != null ? sfContact.Email.toLowerCase().trim() : '';
        System.debug('   UUID (normalized): "' + normalizedUuid + '"');
        System.debug('   Email (normalized): "' + normalizedEmail + '"');
        
        System.debug('\n⚠️  To complete the trace, the sync needs to run and process registrations.');
        System.debug('   The contact will be matched if:');
        System.debug('   - Registration contact UUID matches: "' + normalizedUuid + '"');
        System.debug('   - OR Registration contact Email matches: "' + normalizedEmail + '"');
        System.debug('   - AND Event name contains: "Neurodiversity" (case-insensitive)');
        System.debug('   - AND Campaign "NHM - Neurodiversity" exists (✓ confirmed above)');
        
        // STEP 5: Check recent sync logs
        System.debug('\n=== STEP 5: Checking Recent Sync Logs ===');
        List<Arlo_Integration_Log__c> recentLogs = [
            SELECT Id, Operation_Type__c, Status__c, Records_Processed__c, Records_Successful__c, 
                   Message__c, CreatedDate
            FROM Arlo_Integration_Log__c
            WHERE Operation_Type__c = 'Event Registration Sync'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        
        if (recentLogs.isEmpty()) {
            System.debug('⚠️  No recent Event Registration Sync logs found');
        } else {
            System.debug('Found ' + recentLogs.size() + ' recent sync log(s):');
            for (Arlo_Integration_Log__c log : recentLogs) {
                System.debug('   - ' + log.Status__c + ' (' + log.CreatedDate + ')');
                System.debug('     Processed: ' + log.Records_Processed__c + ', Successful: ' + log.Records_Successful__c);
                if (String.isNotBlank(log.Message__c) && log.Message__c.length() < 200) {
                    System.debug('     Message: ' + log.Message__c);
                }
            }
        }
        
        System.debug('\n=== DIAGNOSIS SUMMARY ===');
        System.debug('Contact Status:');
        System.debug('  ✓ Found in Salesforce');
        System.debug('  ' + (members.isEmpty() ? '❌' : '✓') + ' In NHM Campaigns: ' + members.size());
        System.debug('  ✓ Campaigns exist');
        
        System.debug('\nPossible Failure Points:');
        System.debug('1. Event Registration Sync hasn\'t processed this contact\'s registration yet');
        System.debug('2. Registration email consent check returned false (even though you see it as true in Arlo)');
        System.debug('3. Contact UUID/Email mismatch between Arlo registration and Salesforce contact');
        System.debug('4. Event name doesn\'t contain "Neurodiversity" keyword');
        System.debug('5. Contact\'s Account (CodePrimary) doesn\'t match any Salesforce Account');
        
        System.debug('\n=== END TRACE ===\n');
    }
    
    /**
     * Sync a single contact's event registrations to campaigns
     * This processes only registrations for the specified contact, avoiding full sync logs
     * Usage: ArloEventRegistrationSync.syncSingleContact('9b4c8fc8-eff0-4c04-a7b3-535fe95a23ff');
     *        ArloEventRegistrationSync.syncSingleContact('kavanagha@hautapu.school.nz');
     */
    public static void syncSingleContact(String contactUuidOrEmail) {
        System.debug('=== SYNCING SINGLE CONTACT ===');
        System.debug('Contact Identifier: ' + contactUuidOrEmail);
        
        // Load credentials
        try {
            loadCredentialsFromCustomSettings();
        } catch (Exception e) {
            System.debug('❌ ERROR: Could not load credentials: ' + e.getMessage());
            return;
        }
        
        // Find contact in Salesforce
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name, Account.AccountNumber
            FROM Contact
            WHERE Arlo_Contact_UUID__c = :contactUuidOrEmail OR Email = :contactUuidOrEmail
            LIMIT 1
        ];
        
        if (contacts.isEmpty()) {
            System.debug('❌ Contact not found in Salesforce');
            return;
        }
        
        Contact sfContact = contacts[0];
        System.debug('✓ Contact found: ' + sfContact.FirstName + ' ' + sfContact.LastName);
        System.debug('  UUID: ' + sfContact.Arlo_Contact_UUID__c);
        System.debug('  Email: ' + sfContact.Email);
        System.debug('  Account: ' + (sfContact.Account != null ? sfContact.Account.Name : 'None'));
        
        // Get contact's numeric ID from Arlo (we need this to find registrations)
        // We'll search through events and registrations to find this contact
        String targetContactUuid = sfContact.Arlo_Contact_UUID__c;
        String targetContactEmail = sfContact.Email != null ? sfContact.Email.toLowerCase().trim() : '';
        
        System.debug('\n=== Searching for contact registrations in Arlo ===');
        
        // Get all events
        List<String> eventLinks = getAllEventLinks();
        System.debug('Found ' + eventLinks.size() + ' events');
        
        List<ContactEventWrapper> contactEventList = new List<ContactEventWrapper>();
        Integer eventsChecked = 0;
        Integer registrationsFound = 0;
        Integer calloutCount = 0;
        Integer maxCallouts = 95; // Leave room for other operations
        
        // Process each event (limit to avoid callout limit)
        for (String eventLink : eventLinks) {
            // Check callout limit
            if (calloutCount >= maxCallouts) {
                System.debug('⚠️  Reached callout limit (' + maxCallouts + '). Stopping search.');
                System.debug('   Events checked: ' + eventsChecked + ' of ' + eventLinks.size());
                break;
            }
            try {
                String eventId = extractEventIdFromLink(eventLink);
                if (String.isBlank(eventId)) {
                    continue;
                }
                
                // Get event details
                calloutCount++;
                EventData eventData = getEventDetailsStatic(eventId, arloUsername, arloPassword);
                if (eventData == null) {
                    continue;
                }
                
                // Skip CONF events
                if (eventData.code != null && eventData.code.startsWith('CONF')) {
                    continue;
                }
                
                eventsChecked++;
                
                // Get registrations for this event
                calloutCount++;
                List<String> registrationLinks = getRegistrationLinksStatic(eventId, arloUsername, arloPassword);
                
                // Process each registration
                for (String registrationLink : registrationLinks) {
                    try {
                        String registrationId = extractRegistrationIdFromLink(registrationLink);
                        if (String.isBlank(registrationId)) {
                            continue;
                        }
                        
                        // Check callout limit before processing registration
                        if (calloutCount >= maxCallouts) {
                            System.debug('⚠️  Reached callout limit. Stopping registration processing.');
                            break;
                        }
                        
                        // Check email consent
                        calloutCount++;
                        Boolean hasEmailConsent = checkRegistrationEmailConsentStatic(registrationId, arloUsername, arloPassword);
                        if (!hasEmailConsent) {
                            continue;
                        }
                        
                        // Get contact ID from registration
                        calloutCount++;
                        String contactId = getContactIdFromRegistrationStatic(registrationId, arloUsername, arloPassword);
                        if (String.isBlank(contactId)) {
                            continue;
                        }
                        
                        // Get contact details
                        calloutCount++;
                        ArloModels.ArloContact contact = ArloContactSync.getSingleArloContactStatic(contactId, arloUsername, arloPassword);
                        if (contact == null) {
                            continue;
                        }
                        
                        // Check if this is our target contact
                        String contactUuid = contact.contactId != null ? contact.contactId.trim() : '';
                        String contactEmail = contact.email != null ? contact.email.toLowerCase().trim() : '';
                        
                        Boolean isTargetContact = false;
                        if (String.isNotBlank(targetContactUuid) && contactUuid == targetContactUuid) {
                            isTargetContact = true;
                        } else if (String.isNotBlank(targetContactEmail) && contactEmail == targetContactEmail) {
                            isTargetContact = true;
                        }
                        
                        if (!isTargetContact) {
                            continue; // Skip - not our target contact
                        }
                        
                        registrationsFound++;
                        System.debug('✓ Found registration for target contact:');
                        System.debug('  Event: ' + eventData.name);
                        System.debug('  Registration ID: ' + registrationId);
                        System.debug('  Contact UUID: ' + contactUuid);
                        System.debug('  Contact Email: ' + contactEmail);
                        
                        // Get organisation CodePrimary
                        if (String.isBlank(contact.organisationCodePrimary) && String.isNotBlank(contact.organisationId)) {
                            if (calloutCount >= maxCallouts) {
                                System.debug('  ⚠️  Reached callout limit before getting CodePrimary');
                                break;
                            }
                            calloutCount++;
                            String codePrimary = getOrganisationCodePrimaryStatic(contact.organisationId, arloUsername, arloPassword);
                            if (String.isNotBlank(codePrimary)) {
                                contact.organisationCodePrimary = codePrimary;
                            }
                        }
                        
                        // Check if Account exists
                        if (String.isNotBlank(contact.organisationCodePrimary)) {
                            Account sfAccount = getSalesforceAccountByNumber(contact.organisationCodePrimary);
                            if (sfAccount != null) {
                                ContactEventWrapper wrapper = new ContactEventWrapper();
                                wrapper.contact = contact;
                                wrapper.eventName = eventData.name;
                                wrapper.eventCode = eventData.code;
                                contactEventList.add(wrapper);
                                System.debug('  ✓ Added to sync list (Account: ' + sfAccount.Name + ')');
                                
                                // Stop searching once we find the registration - we only need one
                                System.debug('  ✓ Found target contact registration - stopping search');
                                break;
                            } else {
                                System.debug('  ✗ Account not found for CodePrimary: ' + contact.organisationCodePrimary);
                            }
                        } else {
                            System.debug('  ✗ No CodePrimary found');
                        }
                        
                        // If we found the registration, break out of registration loop
                        if (!contactEventList.isEmpty()) {
                            break;
                        }
                        
                    } catch (Exception e) {
                        System.debug('ArloEventRegistrationSync: Error processing registration in syncSingleContact: ' + e.getMessage());
                        System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                    }

                    // If we found the registration, break out of registration loop
                    if (!contactEventList.isEmpty()) {
                        break;
                    }
                }
                
                // If we found the registration, break out of event loop
                if (!contactEventList.isEmpty()) {
                    break;
                }
                
            } catch (Exception e) {
                System.debug('ArloEventRegistrationSync: Error processing event in syncSingleContact: ' + e.getMessage());
                System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            }

            // If we found the registration, break out of event loop
            if (!contactEventList.isEmpty()) {
                break;
            }
        }
        
        System.debug('\n=== Summary ===');
        System.debug('Events checked: ' + eventsChecked + ' of ' + eventLinks.size());
        System.debug('Callouts used: ' + calloutCount + ' of ' + maxCallouts);
        System.debug('Registrations found for contact: ' + registrationsFound);
        System.debug('Registrations to sync: ' + contactEventList.size());
        
        if (calloutCount >= maxCallouts && contactEventList.isEmpty()) {
            System.debug('\n⚠️  WARNING: Reached callout limit before finding contact registrations.');
            System.debug('   Consider using manuallyAddContactToCampaign() instead, or run full sync.');
        }
        
        if (contactEventList.isEmpty()) {
            System.debug('\n❌ No registrations found for this contact with email consent');
            return;
        }
        
        // Sync contact and add to campaigns
        System.debug('\n=== Syncing contact and adding to campaigns ===');
        
        // Group by Account
        Map<Id, List<ArloModels.ArloContact>> contactsByAccount = new Map<Id, List<ArloModels.ArloContact>>();
        Map<ArloModels.ArloContact, ContactEventWrapper> contactToWrapperMap = new Map<ArloModels.ArloContact, ContactEventWrapper>();
        
        for (ContactEventWrapper wrapper : contactEventList) {
            Account acc = getSalesforceAccountByNumber(wrapper.contact.organisationCodePrimary);
            if (acc != null) {
                if (!contactsByAccount.containsKey(acc.Id)) {
                    contactsByAccount.put(acc.Id, new List<ArloModels.ArloContact>());
                }
                contactsByAccount.get(acc.Id).add(wrapper.contact);
                contactToWrapperMap.put(wrapper.contact, wrapper);
            }
        }
        
        // Sync contacts
        Map<Id, Contact> syncedContactMap = new Map<Id, Contact>();
        for (Id accountId : contactsByAccount.keySet()) {
            List<ArloModels.ArloContact> arloContacts = contactsByAccount.get(accountId);
            ArloContactSync.syncContactsToSalesforceStatic(arloContacts, accountId);
            
            // Query for synced contacts
            Set<String> contactIds = getContactIds(arloContacts);
            Set<String> contactEmails = getContactEmails(arloContacts);
            
            List<Contact> syncedContacts = [
                SELECT Id, Arlo_Contact_UUID__c, Email
                FROM Contact
                WHERE (Arlo_Contact_UUID__c IN :contactIds AND Arlo_Contact_UUID__c != null)
                   OR (Email IN :contactEmails AND Email != null)
            ];
            
            for (Contact c : syncedContacts) {
                syncedContactMap.put(c.Id, c);
            }
        }
        
        System.debug('Synced contacts found: ' + syncedContactMap.size());
        
        // Add to campaigns
        addContactsToCampaignsStatic(contactEventList, syncedContactMap);
        
        System.debug('\n=== SYNC COMPLETE ===');
    }
    
    /**
     * Fallback method: Process existing Salesforce contacts by directly querying their registrations
     * This ensures contacts like 1944 that weren't found through events are still processed
     */
    @TestVisible
    private static void processExistingContactsDirectly(String username, String password, Map<Id, Contact> alreadyProcessedContacts) {
        System.debug('ArloEventRegistrationSync: Processing existing contacts directly via registrations endpoint');
        
        // Get all contacts that have Arlo UUID or Email and are not already processed
        List<Contact> contactsToProcess = [
            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId
            FROM Contact
            WHERE (Arlo_Contact_UUID__c != null OR Email != null)
              AND Id NOT IN :alreadyProcessedContacts.keySet()
            LIMIT 200  // Process in batches to avoid hitting limits
        ];
        
        System.debug('ArloEventRegistrationSync: Found ' + contactsToProcess.size() + ' existing contacts to process directly');
        
        if (contactsToProcess.isEmpty()) {
            return;
        }
        
        List<ContactEventWrapper> additionalWrappers = new List<ContactEventWrapper>();
        Integer calloutCount = 0;
        Integer maxCallouts = 80; // Leave some room for other operations
        
        for (Contact contact : contactsToProcess) {
            if (calloutCount >= maxCallouts) {
                System.debug('ArloEventRegistrationSync: Reached callout limit in fallback processing. Processed ' + additionalWrappers.size() + ' additional contacts.');
                break;
            }
            
            try {
                // Try to get numeric contact ID from Arlo
                String numericContactId = null;
                
                // If we have UUID, try to search for it
                if (String.isNotBlank(contact.Arlo_Contact_UUID__c)) {
                    calloutCount++;
                    try {
                        // Search for contact by UUID
                        String searchEndpoint = ARLO_API_BASE_URL + '/resources/contacts/?UniqueIdentifier=' + EncodingUtil.urlEncode(contact.Arlo_Contact_UUID__c, 'UTF-8');
                        HttpResponse searchRes = makeArloRequest(searchEndpoint, username, password);

                        if (searchRes.getStatusCode() == 200) {
                            // Extract numeric contact ID from response using ArloXmlParser
                            numericContactId = ArloXmlParser.extractFirstContactIdFromSearch(searchRes.getBody());
                        }
                    } catch (Exception e) {
                        System.debug('ArloEventRegistrationSync: Error searching for contact by UUID ' + contact.Arlo_Contact_UUID__c + ': ' + e.getMessage());
                        System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                    }
                }

                // If we still don't have numeric ID, try email
                if (String.isBlank(numericContactId) && String.isNotBlank(contact.Email)) {
                    calloutCount++;
                    try {
                        String searchEndpoint = ARLO_API_BASE_URL + '/resources/contacts/?Email=' + EncodingUtil.urlEncode(contact.Email, 'UTF-8');
                        HttpResponse searchRes = makeArloRequest(searchEndpoint, username, password);

                        if (searchRes.getStatusCode() == 200) {
                            // Extract numeric contact ID from response using ArloXmlParser
                            numericContactId = ArloXmlParser.extractFirstContactIdFromSearch(searchRes.getBody());
                        }
                    } catch (Exception e) {
                        System.debug('ArloEventRegistrationSync: Error searching for contact by email ' + contact.Email + ': ' + e.getMessage());
                        System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
                    }
                }
                
                if (String.isBlank(numericContactId)) {
                    continue; // Can't find numeric ID, skip this contact
                }

                // Get registrations directly from contact endpoint
                calloutCount++;
                String registrationsEndpoint = ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId + '/registrations/';
                HttpResponse regRes = makeArloRequest(registrationsEndpoint, username, password);

                if (regRes.getStatusCode() == 200) {
                    // Parse registration IDs using ArloXmlParser
                    Set<String> registrationIds = ArloXmlParser.extractResourceIds(regRes.getBody(), 'registrations');

                    // Process each registration
                    for (String registrationId : registrationIds) {
                        if (calloutCount >= maxCallouts) {
                            break;
                        }
                        
                        // Check email consent
                        calloutCount++;
                        Boolean hasEmailConsent = checkRegistrationEmailConsentStatic(registrationId, username, password);
                        if (!hasEmailConsent) {
                            continue;
                        }
                        
                        // Get event ID from registration
                        calloutCount++;
                        String eventId = getEventIdFromRegistrationStatic(registrationId, username, password);
                        if (String.isBlank(eventId)) {
                            continue;
                        }
                        
                        // Get event details
                        calloutCount++;
                        EventData eventData = getEventDetailsStatic(eventId, username, password);
                        if (eventData == null) {
                            continue;
                        }
                        
                        // Skip CONF events
                        if (String.isNotBlank(eventData.code) && eventData.code.startsWith('CONF')) {
                            continue;
                        }
                        
                        // Get contact details
                        calloutCount++;
                        ArloModels.ArloContact arloContact = ArloContactSync.getSingleArloContactStatic(numericContactId, username, password);
                        if (arloContact == null) {
                            continue;
                        }
                        
                        // Check if Account exists
                        if (String.isBlank(arloContact.organisationCodePrimary) && String.isNotBlank(arloContact.organisationId)) {
                            calloutCount++;
                            String codePrimary = getOrganisationCodePrimary(arloContact.organisationId);
                            if (String.isNotBlank(codePrimary)) {
                                arloContact.organisationCodePrimary = codePrimary;
                            }
                        }
                        
                        if (String.isNotBlank(arloContact.organisationCodePrimary)) {
                            Account sfAccount = getSalesforceAccountByNumber(arloContact.organisationCodePrimary);
                            if (sfAccount != null) {
                                // Create wrapper
                                ContactEventWrapper wrapper = new ContactEventWrapper();
                                wrapper.contact = arloContact;
                                wrapper.eventName = eventData.name;
                                wrapper.eventCode = eventData.code;
                                additionalWrappers.add(wrapper);
                            }
                        }
                    }
                }
            } catch (Exception e) {
                System.debug('ArloEventRegistrationSync: Error processing contact ' + contact.Id + ' in fallback: ' + e.getMessage());
                System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
            }
        }

        // If we found additional contacts, process them
        if (!additionalWrappers.isEmpty()) {
            System.debug('ArloEventRegistrationSync: Fallback found ' + additionalWrappers.size() + ' additional contact-event pairs');
            
            // Add to synced contact map if not already there
            Set<String> contactUuids = new Set<String>();
            Set<String> contactEmails = new Set<String>();
            for (ContactEventWrapper wrapper : additionalWrappers) {
                if (String.isNotBlank(wrapper.contact.contactId)) {
                    contactUuids.add(wrapper.contact.contactId.trim());
                }
                if (String.isNotBlank(wrapper.contact.email)) {
                    contactEmails.add(wrapper.contact.email.toLowerCase().trim());
                }
            }
            
            List<Contact> additionalContacts = [
                SELECT Id, Arlo_Contact_UUID__c, Email
                FROM Contact
                WHERE (Arlo_Contact_UUID__c IN :contactUuids AND Arlo_Contact_UUID__c != null)
                   OR (Email IN :contactEmails AND Email != null)
            ];
            
            for (Contact c : additionalContacts) {
                if (!alreadyProcessedContacts.containsKey(c.Id)) {
                    alreadyProcessedContacts.put(c.Id, c);
                }
            }
            
            // Add to campaigns
            addContactsToCampaignsStatic(additionalWrappers, alreadyProcessedContacts);
        }
    }
    
    /**
     * Get numeric contact ID by UUID
     */
    @TestVisible
    private static String getNumericContactIdByUuidStatic(String uuid, String username, String password) {
        try {
            String searchEndpoint = ARLO_API_BASE_URL + '/resources/contacts/?UniqueIdentifier=' + EncodingUtil.urlEncode(uuid, 'UTF-8');
            HttpResponse searchRes = makeArloRequest(searchEndpoint, username, password);

            if (searchRes.getStatusCode() == 200) {
                // Use ArloXmlParser to extract contact ID from search response
                return ArloXmlParser.extractFirstContactIdFromSearch(searchRes.getBody());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting numeric contact ID by UUID ' + uuid + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }

    /**
     * Get numeric contact ID by Email
     */
    @TestVisible
    private static String getNumericContactIdByEmailStatic(String email, String username, String password) {
        try {
            String searchEndpoint = ARLO_API_BASE_URL + '/resources/contacts/?Email=' + EncodingUtil.urlEncode(email, 'UTF-8');
            HttpResponse searchRes = makeArloRequest(searchEndpoint, username, password);

            if (searchRes.getStatusCode() == 200) {
                // Use ArloXmlParser to extract contact ID from search response
                return ArloXmlParser.extractFirstContactIdFromSearch(searchRes.getBody());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting numeric contact ID by email ' + email + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return null;
    }

    /**
     * Get all registrations for a contact
     * Public static for reuse by ArloRegistrationSyncBatch
     */
    public static Set<String> getContactRegistrationsStatic(String numericContactId, String username, String password) {
        Set<String> registrationIds = new Set<String>();
        try {
            String registrationsEndpoint = ARLO_API_BASE_URL + '/resources/contacts/' + numericContactId + '/registrations/';
            HttpResponse regRes = makeArloRequest(registrationsEndpoint, username, password);

            if (regRes.getStatusCode() == 200) {
                // Use ArloXmlParser to extract registration IDs
                registrationIds = ArloXmlParser.extractResourceIds(regRes.getBody(), 'registrations');
            } else {
                System.debug('ArloEventRegistrationSync: Error getting registrations for contact ' + numericContactId + '. Status: ' + regRes.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSync: Error getting contact registrations for contact ' + numericContactId + ': ' + e.getMessage());
            System.debug('ArloEventRegistrationSync: Stack trace: ' + e.getStackTraceString());
        }
        return registrationIds;
    }
    
    /**
     * Deep diagnostic for a specific contact - checks matching logic
     * Usage: ArloEventRegistrationSync.deepDiagnoseContact('kavanagha@hautapu.school.nz');
     * Delegates to SyncDiagnostics
     */
    public static void deepDiagnoseContact(String emailOrUuid) {
        SyncDiagnostics.deepDiagnoseContact(emailOrUuid);
    }

    /**
     * Quick check method for a specific contact by email or UUID
     * Usage: ArloEventRegistrationSync.quickCheckContact('kavanagha@hautapu.school.nz');
     * Delegates to SyncDiagnostics
     */
    public static void quickCheckContact(String emailOrUuid) {
        SyncDiagnostics.quickCheckContact(emailOrUuid);
    }
    
    /**
     * Diagnostic method to check why a contact is not being created in Salesforce
     * This method traces through the entire sync process for a specific contact
     * 
     * Usage:
     *   - By numeric contact ID: ArloEventRegistrationSync.diagnoseContactCreation('2192');
     *   - By UUID: ArloEventRegistrationSync.diagnoseContactCreation('9b4c8fc8-eff0-4c04-a7b3-535fe95a23ff');
     *   - By email: ArloEventRegistrationSync.diagnoseContactCreation('kavanagha@hautapu.school.nz');
     */
    public static void diagnoseContactCreation(String contactIdentifier) {
        System.debug('=== DIAGNOSING CONTACT CREATION ===');
        System.debug('Contact Identifier: ' + contactIdentifier);
        System.debug('This will trace why a contact is not being created in Salesforce\n');
        
        // Load credentials
        try {
            loadCredentialsFromCustomSettings();
        } catch (Exception e) {
            System.debug('❌ ERROR: Could not load credentials: ' + e.getMessage());
            return;
        }
        
        String arloUsername = ArloEventRegistrationSync.arloUsername;
        String arloPassword = ArloEventRegistrationSync.arloPassword;
        
        // Determine if contactIdentifier is a numeric ID, UUID, or email
        String arloNumericContactId = null;
        Boolean isNumericId = Pattern.matches('^\\d+$', contactIdentifier);
        
        if (isNumericId) {
            arloNumericContactId = contactIdentifier;
            System.debug('✓ Identified as numeric contact ID: ' + arloNumericContactId);
        } else {
            System.debug('⚠️  Not a numeric ID. Searching for contact in Arlo...');
            // Try to find numeric ID by UUID or email (this would require additional API calls)
            System.debug('   Note: To find numeric ID, you may need to search through contacts');
            System.debug('   For now, please use the numeric contact ID if available');
            return;
        }
        
        System.debug('\n=== STEP 1: Check Contact Status in Arlo ===');
        String contactStatus = getContactStatusStatic(arloNumericContactId, arloUsername, arloPassword);
        System.debug('Contact Status: ' + (contactStatus != null ? contactStatus : 'NULL (not found)'));
        
        if (String.isBlank(contactStatus)) {
            System.debug('❌ Contact not found in Arlo or error retrieving status');
            return;
        }
        
        if (contactStatus != 'Active') {
            System.debug('❌ REASON: Contact is NOT Active (Status: ' + contactStatus + ')');
            System.debug('   → Only Active contacts are processed in the sync');
            return;
        }
        System.debug('✓ Contact is Active');
        
        System.debug('\n=== STEP 2: Check Contact Details (UUID/Email) ===');
        ArloModels.ArloContact arloContact = getContactUuidAndEmailOnly(arloNumericContactId, arloUsername, arloPassword);
        if (arloContact == null) {
            System.debug('❌ Could not retrieve contact details from Arlo');
            return;
        }
        System.debug('✓ Contact Details:');
        System.debug('   UUID: ' + (arloContact.contactId != null ? arloContact.contactId : 'NULL'));
        System.debug('   Email: ' + (arloContact.email != null ? arloContact.email : 'NULL'));
        
        if (String.isBlank(arloContact.contactId) && String.isBlank(arloContact.email)) {
            System.debug('❌ REASON: Contact has no UUID or Email - cannot match to Salesforce');
            return;
        }
        
        System.debug('\n=== STEP 3: Check if Contact Already Exists in Salesforce ===');
        List<Contact> existingContacts = new List<Contact>();
        if (String.isNotBlank(arloContact.contactId)) {
            existingContacts = [
                SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name
                FROM Contact
                WHERE Arlo_Contact_UUID__c = :arloContact.contactId
                LIMIT 1
            ];
        }
        if (existingContacts.isEmpty() && String.isNotBlank(arloContact.email)) {
            existingContacts = [
                SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name
                FROM Contact
                WHERE Email = :arloContact.email
                LIMIT 1
            ];
        }
        
        if (!existingContacts.isEmpty()) {
            System.debug('✓ Contact ALREADY EXISTS in Salesforce:');
            System.debug('   Contact ID: ' + existingContacts[0].Id);
            System.debug('   Name: ' + existingContacts[0].FirstName + ' ' + existingContacts[0].LastName);
            System.debug('   Email: ' + existingContacts[0].Email);
            System.debug('   Account: ' + (existingContacts[0].Account != null ? existingContacts[0].Account.Name : 'None'));
            System.debug('   → Contact will not be created (already exists)');
            return;
        }
        System.debug('✓ Contact does NOT exist in Salesforce - should be created');
        
        System.debug('\n=== STEP 4: Check Registrations and Email Consent ===');
        Set<String> registrationIds = getContactRegistrationsStatic(arloNumericContactId, arloUsername, arloPassword);
        System.debug('Found ' + registrationIds.size() + ' registration(s)');
        
        if (registrationIds.isEmpty()) {
            System.debug('❌ REASON: Contact has NO registrations');
            System.debug('   → Contacts without registrations are not processed');
            return;
        }
        
        Integer registrationsWithConsent = 0;
        Integer registrationsWithoutConsent = 0;
        Integer confRegistrations = 0;
        
        for (String registrationId : registrationIds) {
            // Get event ID
            String eventId = getEventIdFromRegistrationStatic(registrationId, arloUsername, arloPassword);
            if (String.isBlank(eventId)) {
                continue;
            }
            
            // Get event details
            EventData eventData = getEventDetailsStatic(eventId, arloUsername, arloPassword);
            if (eventData == null) {
                continue;
            }
            
            // Check if CONF
            if (String.isNotBlank(eventData.code) && eventData.code.startsWith('CONF')) {
                confRegistrations++;
                continue;
            }
            
            // Check consent
            Boolean hasConsent = checkRegistrationEmailConsentStatic(registrationId, arloUsername, arloPassword);
            if (hasConsent) {
                registrationsWithConsent++;
                System.debug('   ✓ Registration ' + registrationId + ': Has consent, Event: ' + eventData.name);
            } else {
                registrationsWithoutConsent++;
                System.debug('   ✗ Registration ' + registrationId + ': NO consent, Event: ' + eventData.name);
            }
        }
        
        System.debug('\nRegistration Summary:');
        System.debug('   Total: ' + registrationIds.size());
        System.debug('   With Consent: ' + registrationsWithConsent);
        System.debug('   Without Consent: ' + registrationsWithoutConsent);
        System.debug('   CONF Events: ' + confRegistrations);
        
        if (registrationsWithConsent == 0) {
            System.debug('❌ REASON: Contact has NO registrations with email consent');
            System.debug('   → Only contacts with at least one registration with consent are processed');
            return;
        }
        System.debug('✓ Contact has ' + registrationsWithConsent + ' registration(s) with consent');
        
        System.debug('\n=== STEP 5: Check Employment/Organization Data ===');
        ArloModels.ArloContact fullContact = ArloContactSync.getSingleArloContactStatic(arloNumericContactId, arloUsername, arloPassword);
        if (fullContact == null) {
            System.debug('❌ Could not retrieve full contact details (including employment)');
            return;
        }
        
        System.debug('Organization CodePrimary: ' + (fullContact.organisationCodePrimary != null ? fullContact.organisationCodePrimary : 'NULL'));
        System.debug('Organization ID: ' + (fullContact.organisationId != null ? fullContact.organisationId : 'NULL'));
        
        if (String.isBlank(fullContact.organisationCodePrimary)) {
            System.debug('❌ REASON: Contact has NO organisation CodePrimary');
            System.debug('   → CodePrimary is required to find the Salesforce Account');
            System.debug('   → Contact cannot be created without a matching Account');
            return;
        }
        System.debug('✓ Contact has CodePrimary: ' + fullContact.organisationCodePrimary);
        
        System.debug('\n=== STEP 6: Check if Salesforce Account Exists ===');
        Account sfAccount = getSalesforceAccountByNumberStatic(fullContact.organisationCodePrimary);
        if (sfAccount == null) {
            System.debug('❌ REASON: Salesforce Account NOT FOUND for CodePrimary: ' + fullContact.organisationCodePrimary);
            System.debug('   → Contact cannot be created without a matching Account');
            System.debug('   → Please ensure an Account exists with AccountNumber = ' + fullContact.organisationCodePrimary);
            return;
        }
        System.debug('✓ Salesforce Account found:');
        System.debug('   Account ID: ' + sfAccount.Id);
        System.debug('   Account Name: ' + sfAccount.Name);
        System.debug('   Account Number: ' + sfAccount.AccountNumber);
        
        System.debug('\n=== STEP 7: Summary ===');
        System.debug('✓ Contact Status: Active');
        System.debug('✓ Contact has UUID/Email: ' + (String.isNotBlank(arloContact.contactId) ? 'UUID' : '') + 
                    (String.isNotBlank(arloContact.email) ? 'Email' : ''));
        System.debug('✓ Contact does NOT exist in Salesforce');
        System.debug('✓ Contact has ' + registrationsWithConsent + ' registration(s) with consent');
        System.debug('✓ Contact has CodePrimary: ' + fullContact.organisationCodePrimary);
        System.debug('✓ Salesforce Account exists: ' + sfAccount.Name);
        System.debug('\n✅ Contact SHOULD be created in Salesforce!');
        System.debug('   If it is not being created, possible reasons:');
        System.debug('   1. Callout limit reached before contact creation');
        System.debug('   2. DML error during contact creation (check debug logs for exceptions)');
        System.debug('   3. Contact creation deferred to next batch (check logs for "Deferring creation")');
        System.debug('\n=== END DIAGNOSIS ===\n');
    }
    
    /**
     * Trace a specific contact through the full sync process
     * This will add debug logging for a specific contact ID throughout the sync
     *
     * Usage: ArloEventRegistrationSync.traceContactInSync('2192');
     * Then run the full sync and check logs for messages containing this contact ID
     * Delegates to SyncDiagnostics
     */
    public static void traceContactInSync(String numericContactId) {
        SyncDiagnostics.traceContactInSync(numericContactId);
    }
    
    /**
     * Custom exception class
     */
    public class ArloSyncException extends Exception {}
}