/**
 * ArloEventRegistrationSyncQueueable
 * 
 * Queueable class to process Arlo events and registrations in batches to avoid governor limits.
 * Processes events, registrations, and contacts in chunks, chaining jobs as needed.
 * 
 * @author System Generated
 * @version 1.0
 */
public class ArloEventRegistrationSyncQueueable implements Queueable, Database.AllowsCallouts {
    
    // Event links to process
    private List<String> eventLinks;
    
    // Credentials for Basic Auth
    private String username;
    private String password;
    
    // Progress tracking
    private Integer startIndex;
    private Integer batchSize;
    
    // Counters (static to persist across chained jobs)
    private static Map<String, Integer> progressMap = new Map<String, Integer>();
    private static String PROGRESS_KEY = 'event_sync_progress';
    private static String SUCCESS_KEY = 'event_sync_success';
    private static String FAILED_KEY = 'event_sync_failed';
    
    // Failure reasons (static to persist across chained jobs)
    private static Map<String, Integer> cumulativeFailureReasons = new Map<String, Integer>();
    
    // Log ID (static to persist across chained jobs)
    private static Id logId = null;
    
    /**
     * Constructor for initial job
     */
    public ArloEventRegistrationSyncQueueable(List<String> eventLinks, String username, String password, Id logId) {
        this.eventLinks = eventLinks;
        this.username = username;
        this.password = password;
        this.startIndex = 0;
        this.batchSize = 3; // Process 3 events per batch to stay under callout limit (each event can have many registrations)
        ArloEventRegistrationSyncQueueable.logId = logId;
        
        // Initialize progress tracking
        if (!progressMap.containsKey(PROGRESS_KEY)) {
            progressMap.put(PROGRESS_KEY, 0);
        }
        if (!progressMap.containsKey(SUCCESS_KEY)) {
            progressMap.put(SUCCESS_KEY, 0);
        }
        if (!progressMap.containsKey(FAILED_KEY)) {
            progressMap.put(FAILED_KEY, 0);
        }
        // Initialize cumulative failure reasons map
        if (cumulativeFailureReasons == null || cumulativeFailureReasons.isEmpty()) {
            cumulativeFailureReasons = new Map<String, Integer>();
        }
    }
    
    /**
     * Constructor for chained jobs
     */
    public ArloEventRegistrationSyncQueueable(List<String> eventLinks, String username, String password, Integer startIndex) {
        this.eventLinks = eventLinks;
        this.username = username;
        this.password = password;
        this.startIndex = startIndex;
        this.batchSize = 3; // Process 3 events per batch to stay under callout limit
        // Note: logId is static, so it should persist from the initial job
        // But we'll verify it's still set
        System.debug('ArloEventRegistrationSyncQueueable: Chained job constructor - logId is: ' + ArloEventRegistrationSyncQueueable.logId);
    }
    
    public void execute(QueueableContext context) {
        try {
            // Set credentials
            ArloContactSync.setCredentials(username, password);
            
            Integer processed = 0; // Count of registrations processed (may include duplicates)
            Integer successful = 0; // Will be set to unique contacts synced
            Integer failed = 0;
            Integer eventsProcessed = 0;
            Integer registrationsProcessed = 0;
            // Track unique contacts to get accurate count
            Set<String> uniqueContactIdsInBatch = new Set<String>();
            
            // Track skipped registrations for this batch
            Integer totalRegistrationsFound = 0;
            Integer eventsSkippedCONF = 0;
            Integer registrationsWithoutConsentTotal = 0;
            Integer registrationsSkippedNoAccountTotal = 0;
            Integer registrationsSkippedNoCodePrimaryTotal = 0;
            
            // Track failure reasons for this batch (will be merged into cumulative)
            Map<String, Integer> batchFailureReasons = new Map<String, Integer>();
            
            // Process batch of events with callout tracking
            Integer endIndex = startIndex;
            List<String> batchEventLinks = new List<String>();
            Integer calloutCount = 0;
            Integer maxCallouts = 85; // Leave buffer under 100 limit (reduced to account for all callouts)
            
            // Build batch while tracking callouts
            while (endIndex < eventLinks.size() && calloutCount < maxCallouts) {
                batchEventLinks.add(eventLinks[endIndex]);
                calloutCount += 2; // Reserve 2 callouts per event (event details + registrations list)
                endIndex++;
                
                // If we've added enough events, stop (each event will process its registrations)
                if (batchEventLinks.size() >= batchSize) {
                    break;
                }
            }
            
            System.debug('ArloEventRegistrationSyncQueueable: Processing events ' + startIndex + ' to ' + (endIndex - 1) + ' of ' + eventLinks.size() + ' (estimated callouts: ' + calloutCount + ')');
            
            // Process this batch of events (all HTTP callouts first)
            List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList = new List<ArloEventRegistrationSync.ContactEventWrapper>();
            Integer actualCalloutCount = 0;
            
            for (String eventLink : batchEventLinks) {
                // Check callout limit before processing each event
                if (actualCalloutCount >= maxCallouts) {
                    System.debug('ArloEventRegistrationSyncQueueable: Reached callout limit (' + actualCalloutCount + '). Stopping event processing.');
                    break;
                }
                try {
                    // Extract event ID from link
                    String eventId = ArloEventRegistrationSync.extractEventIdFromLink(eventLink);
                    if (String.isBlank(eventId)) {
                        System.debug('ArloEventRegistrationSyncQueueable: Could not extract event ID from link: ' + eventLink);
                        continue;
                    }
                    
                    // Get event details (1 callout)
                    ArloEventRegistrationSync.EventData eventData = ArloEventRegistrationSync.getEventDetailsStatic(eventId, username, password);
                    actualCalloutCount++;
                    if (eventData == null) {
                        System.debug('ArloEventRegistrationSyncQueueable: Could not fetch event details for ID: ' + eventId);
                        failed++;
                        continue;
                    }
                    
                    // Check if Code does NOT start with 'CONF' - skip if it does
                    if (String.isNotBlank(eventData.code) && eventData.code.startsWith('CONF')) {
                        System.debug('ArloEventRegistrationSyncQueueable: Skipping event ' + eventId + ' - Code starts with CONF: ' + eventData.code);
                        eventsSkippedCONF++;
                        continue;
                    }
                    
                    eventsProcessed++;
                    System.debug('ArloEventRegistrationSyncQueueable: Processing event ' + eventId + ' - Code: ' + eventData.code + ', Name: ' + eventData.name + ' (Callouts so far: ' + actualCalloutCount + ')');
                    
                    // Check callout limit before getting registrations
                    if (actualCalloutCount >= maxCallouts) {
                        System.debug('ArloEventRegistrationSyncQueueable: Reached callout limit before processing registrations for event ' + eventId);
                        break;
                    }
                    
                    // Get registrations for this event (1 callout)
                    List<String> registrationLinks = ArloEventRegistrationSync.getRegistrationLinksStatic(eventId, username, password);
                    actualCalloutCount++;
                    totalRegistrationsFound += registrationLinks.size(); // Track total registrations found
                    System.debug('ArloEventRegistrationSyncQueueable: Found ' + registrationLinks.size() + ' registrations for event ' + eventId + ' (Total so far: ' + totalRegistrationsFound + ', Callouts so far: ' + actualCalloutCount + ')');
                    
                    Integer registrationsWithConsent = 0;
                    Integer registrationsWithoutConsent = 0;
                    Integer registrationsSkippedNoAccount = 0;
                    Integer registrationsSkippedNoCodePrimary = 0;
                    
                    // Process each registration (but limit based on remaining callouts)
                    // Each registration needs: custom fields (1) + registration details (1) + contact (3: contact, employment, org) = 5 callouts
                    Integer maxRegistrationsToProcess = (maxCallouts - actualCalloutCount) / 5;
                    if (maxRegistrationsToProcess < 1) {
                        System.debug('ArloEventRegistrationSyncQueueable: Not enough callouts remaining to process registrations. Stopping.');
                        break;
                    }
                    
                    Integer registrationsProcessedForEvent = 0;
                    for (String registrationLink : registrationLinks) {
                        // Check callout limit before each registration
                        if (actualCalloutCount >= maxCallouts) {
                            System.debug('ArloEventRegistrationSyncQueueable: Reached callout limit. Stopping registration processing.');
                            break;
                        }
                        
                        if (registrationsProcessedForEvent >= maxRegistrationsToProcess) {
                            System.debug('ArloEventRegistrationSyncQueueable: Reached max registrations per event (' + maxRegistrationsToProcess + '). Remaining will be processed in next batch.');
                            break;
                        }
                        try {
                            // Extract registration ID from link
                            String registrationId = ArloEventRegistrationSync.extractRegistrationIdFromLink(registrationLink);
                            if (String.isBlank(registrationId)) {
                                System.debug('ArloEventRegistrationSyncQueueable: Could not extract registration ID from link: ' + registrationLink);
                                continue;
                            }
                            
                            // Check callout limit before checking custom fields (1 callout)
                            if (actualCalloutCount >= maxCallouts) {
                                System.debug('ArloEventRegistrationSyncQueueable: Reached callout limit before checking custom fields.');
                                break;
                            }
                            
                            // STEP 1: Check custom fields - only sync if email consent is true (1 callout)
                            Boolean hasEmailConsent = ArloEventRegistrationSync.checkRegistrationEmailConsentStatic(registrationId, username, password);
                            actualCalloutCount++;
                            if (!hasEmailConsent) {
                                registrationsWithoutConsent++;
                                System.debug('ArloEventRegistrationSyncQueueable: Skipping registration ' + registrationId + ' - email consent is false or not found (Total skipped for consent: ' + registrationsWithoutConsent + ')');
                                continue; // Skip this registration
                            }
                            
                            registrationsWithConsent++;
                            System.debug('ArloEventRegistrationSyncQueueable: Registration ' + registrationId + ' has email consent - proceeding with sync (Total with consent: ' + registrationsWithConsent + ')');
                            
                            // Check callout limit before getting registration details (1 callout)
                            if (actualCalloutCount >= maxCallouts) {
                                System.debug('ArloEventRegistrationSyncQueueable: Reached callout limit before getting registration details.');
                                break;
                            }
                            
                            // STEP 2: Get registration details to find contact (1 callout)
                            String contactId = ArloEventRegistrationSync.getContactIdFromRegistrationStatic(registrationId, username, password);
                            actualCalloutCount++;
                            if (String.isBlank(contactId)) {
                                System.debug('ArloEventRegistrationSyncQueueable: No contact found in registration ' + registrationId);
                                failed++;
                                String reason = 'No contact found in registration';
                                Integer currentCount = batchFailureReasons.containsKey(reason) ? batchFailureReasons.get(reason) : 0;
                                batchFailureReasons.put(reason, currentCount + 1);
                                continue;
                            }
                            
                            registrationsProcessed++;
                            registrationsProcessedForEvent++;
                            
                            // Check callout limit before getting contact (needs 3 callouts: contact, employment, org)
                            if (actualCalloutCount + 3 >= maxCallouts) {
                                System.debug('ArloEventRegistrationSyncQueueable: Not enough callouts remaining for contact ' + contactId + ' (need 3, have ' + (maxCallouts - actualCalloutCount) + ')');
                                break;
                            }
                            
                            // Get contact details (reuse existing method from ArloContactSync)
                            // This makes 3 callouts: contact (1) + employment (1) + organisation (1)
                            // This fetches the contact's employment information to get the CodePrimary for Account matching
                            ArloContactSync.ArloContact contact = ArloContactSync.getSingleArloContactStatic(contactId, username, password);
                            actualCalloutCount += 3; // Count all 3 callouts made by getSingleArloContactStatic
                            if (contact == null) {
                                System.debug('ArloEventRegistrationSyncQueueable: Could not fetch contact ' + contactId);
                                failed++;
                                String reason = 'Could not fetch contact from API';
                                Integer currentCount = batchFailureReasons.containsKey(reason) ? batchFailureReasons.get(reason) : 0;
                                batchFailureReasons.put(reason, currentCount + 1);
                                continue;
                            }
                            
                            // Note: getSingleArloContactStatic already fetches employment and CodePrimary,
                            // so we don't need to call getOrganisationCodePrimaryStatic again
                            
                            // Check if Account exists based on contact's employment (CodePrimary)
                            if (String.isNotBlank(contact.organisationCodePrimary)) {
                                Account sfAccount = ArloEventRegistrationSync.getSalesforceAccountByNumberStatic(contact.organisationCodePrimary);
                                if (sfAccount != null) {
                                    // Account exists - add contact with event info to sync list
                                    // NOTE: The contact will be CREATED in Salesforce if it doesn't exist,
                                    // or matched to existing contact by UUID/Email, then added to campaigns
                                    ArloEventRegistrationSync.ContactEventWrapper wrapper = new ArloEventRegistrationSync.ContactEventWrapper();
                                    wrapper.contact = contact;
                                    wrapper.eventName = eventData.name;
                                    wrapper.eventCode = eventData.code;
                                    contactEventList.add(wrapper);
                                    processed++; // Count registrations (may include same contact multiple times)
                                    
                                    // Track unique contacts
                                    if (String.isNotBlank(contact.contactId)) {
                                        uniqueContactIdsInBatch.add(contact.contactId);
                                    }
                                    
                                    System.debug('ArloEventRegistrationSyncQueueable: Added contact ' + contactId + ' to sync list (Account: ' + sfAccount.Name + ' [' + contact.organisationCodePrimary + '], Event: ' + eventData.name + ', Unique contacts so far: ' + uniqueContactIdsInBatch.size() + ')');
                                    System.debug('ArloEventRegistrationSyncQueueable: Contact will be created/updated in Salesforce with Account: ' + sfAccount.Name);
                                } else {
                                    registrationsSkippedNoAccount++;
                                    System.debug('ArloEventRegistrationSyncQueueable: Skipping contact ' + contactId + ' - Account not found for CodePrimary: ' + contact.organisationCodePrimary + ' (Total skipped - no account: ' + registrationsSkippedNoAccount + ') - This is CodePrimary-related, not counting as failure');
                                    // Don't count as failure or log in failure reasons - this is CodePrimary-related
                                    // Contacts from organizations where Account doesn't exist in Salesforce are simply skipped
                                }
                            } else {
                                registrationsSkippedNoCodePrimary++;
                                System.debug('ArloEventRegistrationSyncQueueable: Skipping contact ' + contactId + ' - No CodePrimary found for organization ' + (contact.organisationId != null ? contact.organisationId : 'unknown') + ' (Total skipped - no CodePrimary: ' + registrationsSkippedNoCodePrimary + ') - This is normal, many organizations do not have CodePrimary');
                                // Don't count as failure or log in failure reasons - this is expected behavior
                                // Contacts from organizations without CodePrimary are simply skipped
                            }
                            
                        } catch (Exception e) {
                            failed++;
                            String reason = 'Exception: ' + e.getMessage();
                            if (reason.length() > 100) {
                                reason = reason.substring(0, 100) + '...';
                            }
                            Integer currentCount = batchFailureReasons.containsKey(reason) ? batchFailureReasons.get(reason) : 0;
                            batchFailureReasons.put(reason, currentCount + 1);
                            System.debug('ArloEventRegistrationSyncQueueable: Error processing registration ' + registrationLink + ': ' + e.getMessage());
                        }
                    }
                    
                    // Accumulate skipped counts
                    registrationsWithoutConsentTotal += registrationsWithoutConsent;
                    registrationsSkippedNoAccountTotal += registrationsSkippedNoAccount;
                    registrationsSkippedNoCodePrimaryTotal += registrationsSkippedNoCodePrimary;
                    
                    // Log summary for this event
                    System.debug('ArloEventRegistrationSyncQueueable: Event ' + eventId + ' summary - Total registrations: ' + registrationLinks.size() + 
                        ', With consent: ' + registrationsWithConsent + 
                        ', Without consent: ' + registrationsWithoutConsent + 
                        ', Skipped (no Account): ' + registrationsSkippedNoAccount + 
                        ', Skipped (no CodePrimary): ' + registrationsSkippedNoCodePrimary + 
                        ', Added to sync list: ' + (registrationsWithConsent - registrationsSkippedNoAccount - registrationsSkippedNoCodePrimary));
                    
                } catch (Exception e) {
                    failed++;
                    String reason = 'Exception processing event: ' + e.getMessage();
                    if (reason.length() > 100) {
                        reason = reason.substring(0, 100) + '...';
                    }
                    Integer currentCount = batchFailureReasons.containsKey(reason) ? batchFailureReasons.get(reason) : 0;
                    batchFailureReasons.put(reason, currentCount + 1);
                    System.debug('ArloEventRegistrationSyncQueueable: Error processing event ' + eventLink + ': ' + e.getMessage());
                }
                
                // Break if we've hit callout limit
                if (actualCalloutCount >= maxCallouts) {
                    System.debug('ArloEventRegistrationSyncQueueable: Reached callout limit. Stopping event processing.');
                    break;
                }
            }
            
            System.debug('ArloEventRegistrationSyncQueueable: Completed batch. Total callouts used: ' + actualCalloutCount);
            
            // Now do all DML operations (after all callouts are complete)
            Map<Id, Contact> syncedContactMap = new Map<Id, Contact>();
            if (!contactEventList.isEmpty()) {
                System.debug('ArloEventRegistrationSyncQueueable: Syncing ' + contactEventList.size() + ' contacts to Salesforce');
                try {
                    // Group contacts by Account
                    Map<Id, List<ArloContactSync.ArloContact>> contactsByAccount = new Map<Id, List<ArloContactSync.ArloContact>>();
                    
                    for (ArloEventRegistrationSync.ContactEventWrapper wrapper : contactEventList) {
                        Account acc = ArloEventRegistrationSync.getSalesforceAccountByNumberStatic(wrapper.contact.organisationCodePrimary);
                        if (acc != null) {
                            if (!contactsByAccount.containsKey(acc.Id)) {
                                contactsByAccount.put(acc.Id, new List<ArloContactSync.ArloContact>());
                            }
                            contactsByAccount.get(acc.Id).add(wrapper.contact);
                        }
                    }
                    
                    // Sync contacts grouped by Account
                    // Track unique contacts to get accurate count (deduplicate by UUID or Email)
                    Set<String> uniqueContactIds = new Set<String>();
                    Set<String> uniqueEmails = new Set<String>();
                    Integer totalInserted = 0; // Track actual inserted count from sync method
                    
                    for (Id accountId : contactsByAccount.keySet()) {
                        List<ArloContactSync.ArloContact> contacts = contactsByAccount.get(accountId);
                        
                        // Track unique contacts for campaign assignment
                        Set<String> accountContactUuids = new Set<String>();
                        Set<String> accountContactEmails = new Set<String>();
                        for (ArloContactSync.ArloContact ac : contacts) {
                            if (String.isNotBlank(ac.contactId)) {
                                uniqueContactIds.add(ac.contactId);
                                accountContactUuids.add(ac.contactId);
                            }
                            if (String.isNotBlank(ac.email)) {
                                uniqueEmails.add(ac.email.toLowerCase().trim());
                                accountContactEmails.add(ac.email.toLowerCase().trim());
                            }
                        }
                        
                        System.debug('ArloEventRegistrationSyncQueueable: Syncing ' + contacts.size() + ' contact(s) for Account ' + accountId);
                        System.debug('ArloEventRegistrationSyncQueueable: Contact UUIDs: ' + accountContactUuids);
                        System.debug('ArloEventRegistrationSyncQueueable: Contact Emails: ' + accountContactEmails);
                        
                        // Sync contacts - this will CREATE contacts if they don't exist, or UPDATE if they do
                        // The method handles matching by UUID or Email and creates new contacts with the correct Account
                        Integer insertedCount = ArloContactSync.syncContactsToSalesforceStatic(contacts, accountId);
                        totalInserted += insertedCount;
                        System.debug('ArloEventRegistrationSyncQueueable: Inserted ' + insertedCount + ' new contact(s) for Account ' + accountId);
                        
                        // Get synced contact IDs for campaign assignment (both newly created and existing)
                        // Query by both UUID and Email to ensure we find all contacts
                        List<Contact> syncedContacts = new List<Contact>();
                        try {
                            Schema.SObjectType contactType = Schema.getGlobalDescribe().get('Contact');
                            Schema.DescribeSObjectResult contactDescribe = contactType.getDescribe();
                            Map<String, Schema.SObjectField> fieldMap = contactDescribe.fields.getMap();
                            
                            if (fieldMap.containsKey('Arlo_Contact_UUID__c')) {
                                // Query by UUID and Email
                                syncedContacts = [
                                    SELECT Id, Arlo_Contact_UUID__c, Email, AccountId
                                    FROM Contact
                                    WHERE (Arlo_Contact_UUID__c != null AND Arlo_Contact_UUID__c IN :accountContactUuids)
                                       OR (Email != null AND Email IN :accountContactEmails)
                                ];
                            } else {
                                // Query by Email only (UUID field doesn't exist)
                                syncedContacts = [
                                    SELECT Id, Email, AccountId
                                    FROM Contact
                                    WHERE Email != null AND Email IN :accountContactEmails
                                ];
                            }
                            
                            System.debug('ArloEventRegistrationSyncQueueable: Found ' + syncedContacts.size() + ' contact(s) in Salesforce (newly created or existing) for Account ' + accountId);
                            
                            // Verify contacts are associated with the correct Account
                            for (Contact c : syncedContacts) {
                                if (c.AccountId == accountId) {
                                    syncedContactMap.put(c.Id, c);
                                    System.debug('ArloEventRegistrationSyncQueueable: Added contact ' + c.Id + ' (UUID: ' + c.Arlo_Contact_UUID__c + ', Email: ' + c.Email + ') to syncedContactMap');
                                } else {
                                    System.debug('ArloEventRegistrationSyncQueueable: WARNING - Contact ' + c.Id + ' is not associated with Account ' + accountId + ' (current Account: ' + c.AccountId + ')');
                                }
                            }
                        } catch (Exception e) {
                            System.debug('ArloEventRegistrationSyncQueueable: Error querying synced contacts: ' + e.getMessage());
                            System.debug('ArloEventRegistrationSyncQueueable: Stack trace: ' + e.getStackTraceString());
                        }
                    }
                    
                    // Use the actual count of inserted contacts (after filtering out existing ones)
                    successful = totalInserted;
                    System.debug('ArloEventRegistrationSyncQueueable: Actually inserted ' + totalInserted + ' new contacts (Total registrations processed: ' + contactEventList.size() + ', Unique UUIDs in batch: ' + uniqueContactIds.size() + ', Synced contacts map size: ' + syncedContactMap.size() + ')');
                    System.debug('ArloEventRegistrationSyncQueueable: Note - "processed" counts registrations (may include duplicates), "successful" counts actual contacts inserted (new contacts only)');
                    
                    // Add contacts to campaigns
                    if (!syncedContactMap.isEmpty()) {
                        ArloEventRegistrationSync.addContactsToCampaignsStatic(contactEventList, syncedContactMap);
                    }
                    
                    System.debug('ArloEventRegistrationSyncQueueable: Successfully inserted ' + successful + ' contacts to Salesforce');
                } catch (Exception e) {
                    System.debug('ArloEventRegistrationSyncQueueable: Error syncing contacts: ' + e.getMessage());
                    failed += contactEventList.size();
                }
            }
            
            // Update progress (cumulative across batches)
            // Since static variables don't persist across chained jobs, we need to get totals from the log record
            Integer cumulativeProcessed = processed;
            Integer cumulativeSuccessful = successful;
            Integer cumulativeFailed = failed;
            
            // Try to get previous totals from the log record
            Id currentLogId = ArloEventRegistrationSyncQueueable.logId;
            if (currentLogId == null) {
                try {
                    List<Arlo_Integration_Log__c> recentLogs = [
                        SELECT Id, Records_Processed__c, Records_Successful__c, Records_Failed__c
                        FROM Arlo_Integration_Log__c 
                        WHERE Operation_Type__c = 'Event Registration Sync' 
                        AND Status__c = 'In Progress'
                        ORDER BY CreatedDate DESC 
                        LIMIT 1
                    ];
                    if (!recentLogs.isEmpty()) {
                        currentLogId = recentLogs[0].Id;
                        Integer prevProcessed = (Integer)recentLogs[0].Records_Processed__c;
                        Integer prevSuccessful = (Integer)recentLogs[0].Records_Successful__c;
                        Integer prevFailed = (Integer)recentLogs[0].Records_Failed__c;
                        cumulativeProcessed = (prevProcessed != null ? prevProcessed : 0) + processed;
                        cumulativeSuccessful = (prevSuccessful != null ? prevSuccessful : 0) + successful;
                        cumulativeFailed = (prevFailed != null ? prevFailed : 0) + failed;
                        System.debug('ArloEventRegistrationSyncQueueable: Found previous totals from log - Processed: ' + prevProcessed + ', Successful: ' + prevSuccessful + ', Failed: ' + prevFailed);
                    }
                } catch (Exception e) {
                    System.debug('ArloEventRegistrationSyncQueueable: Error getting previous totals: ' + e.getMessage());
                }
            } else {
                // Try to get from log record
                try {
                    List<Arlo_Integration_Log__c> logRecords = [
                        SELECT Id, Records_Processed__c, Records_Successful__c, Records_Failed__c
                        FROM Arlo_Integration_Log__c 
                        WHERE Id = :currentLogId
                        LIMIT 1
                    ];
                    if (!logRecords.isEmpty()) {
                        Integer prevProcessed = (Integer)logRecords[0].Records_Processed__c;
                        Integer prevSuccessful = (Integer)logRecords[0].Records_Successful__c;
                        Integer prevFailed = (Integer)logRecords[0].Records_Failed__c;
                        cumulativeProcessed = (prevProcessed != null ? prevProcessed : 0) + processed;
                        cumulativeSuccessful = (prevSuccessful != null ? prevSuccessful : 0) + successful;
                        cumulativeFailed = (prevFailed != null ? prevFailed : 0) + failed;
                        System.debug('ArloEventRegistrationSyncQueueable: Found previous totals from log record - Processed: ' + prevProcessed + ', Successful: ' + prevSuccessful + ', Failed: ' + prevFailed);
                    }
                } catch (Exception e) {
                    System.debug('ArloEventRegistrationSyncQueueable: Error querying log record: ' + e.getMessage());
                }
            }
            
            // Merge batch failure reasons into cumulative map
            for (String reason : batchFailureReasons.keySet()) {
                Integer batchCount = batchFailureReasons.get(reason);
                Integer cumulativeCount = cumulativeFailureReasons.containsKey(reason) ? cumulativeFailureReasons.get(reason) : 0;
                cumulativeFailureReasons.put(reason, cumulativeCount + batchCount);
            }
            
            System.debug('ArloEventRegistrationSyncQueueable: Batch complete - This batch: Processed: ' + processed + ', Successful: ' + successful + ', Failed: ' + failed);
            System.debug('ArloEventRegistrationSyncQueueable: Cumulative totals - Processed: ' + cumulativeProcessed + ', Successful: ' + cumulativeSuccessful + ', Failed: ' + cumulativeFailed);
            System.debug('ArloEventRegistrationSyncQueueable: This batch breakdown - Total registrations found: ' + totalRegistrationsFound + 
                ', Events skipped (CONF): ' + eventsSkippedCONF + 
                ', Registrations without consent: ' + registrationsWithoutConsentTotal + 
                ', Skipped (no Account): ' + registrationsSkippedNoAccountTotal + 
                ', Skipped (no CodePrimary): ' + registrationsSkippedNoCodePrimaryTotal);
            
            // Chain next job if more events to process
            if (endIndex < eventLinks.size()) {
                System.debug('ArloEventRegistrationSyncQueueable: Chaining next job for events ' + endIndex + ' to ' + eventLinks.size());
                // Update log with progress (but keep status as In Progress)
                if (currentLogId != null) {
                    System.debug('ArloEventRegistrationSyncQueueable: Updating log with cumulative totals before chaining');
                    String progressMessage = 'Processing events in batches... Registrations processed: ' + cumulativeProcessed + ', Contacts inserted: ' + cumulativeSuccessful;
                    // Only show Failed count if there are actual failure reasons in this batch (not CodePrimary-related skips)
                    if (cumulativeFailed > 0 && !batchFailureReasons.isEmpty()) {
                        progressMessage += ', Failed: ' + cumulativeFailed;
                    }
                    
                    // Build failure reasons string for separate field
                    // Always read existing failure reasons and preserve them, even if current batch has none
                    Map<String, Integer> accumulatedReasons = new Map<String, Integer>();
                    try {
                        List<Arlo_Integration_Log__c> existingLog = [
                            SELECT Failure_Reasons__c
                            FROM Arlo_Integration_Log__c 
                            WHERE Id = :currentLogId
                            LIMIT 1
                        ];
                        if (!existingLog.isEmpty() && String.isNotBlank(existingLog[0].Failure_Reasons__c)) {
                            String existingText = existingLog[0].Failure_Reasons__c;
                            String[] lines = existingText.split('\n');
                            for (String line : lines) {
                                if (String.isNotBlank(line) && line.contains(': ')) {
                                    String[] parts = line.split(': ', 2);
                                    if (parts.size() == 2) {
                                        String reason = parts[0].trim();
                                        try {
                                            Integer count = Integer.valueOf(parts[1].trim());
                                            accumulatedReasons.put(reason, count);
                                        } catch (Exception e) {
                                            // Ignore parsing errors
                                        }
                                    }
                                }
                            }
                        }
                    } catch (Exception e) {
                        System.debug('ArloEventRegistrationSyncQueueable: Error reading existing failure reasons: ' + e.getMessage());
                    }
                    
                    // Merge batch failure reasons (if any)
                    if (!batchFailureReasons.isEmpty()) {
                        for (String reason : batchFailureReasons.keySet()) {
                            Integer batchCount = batchFailureReasons.get(reason);
                            Integer existingCount = accumulatedReasons.containsKey(reason) ? accumulatedReasons.get(reason) : 0;
                            accumulatedReasons.put(reason, existingCount + batchCount);
                        }
                    }
                    
                    // Build text from accumulated reasons (preserve even if empty to maintain consistency)
                    String failureReasonsText = null;
                    if (!accumulatedReasons.isEmpty()) {
                        List<String> sortedReasons = new List<String>(accumulatedReasons.keySet());
                        sortedReasons.sort();
                        failureReasonsText = '';
                        for (String reason : sortedReasons) {
                            failureReasonsText += reason + ': ' + accumulatedReasons.get(reason) + '\n';
                        }
                    }
                    
                    ArloEventRegistrationSync.updateLogRecordStatic(currentLogId, 'In Progress', progressMessage, 
                        null, cumulativeProcessed, cumulativeSuccessful, failureReasonsText);
                }
                System.enqueueJob(new ArloEventRegistrationSyncQueueable(eventLinks, username, password, endIndex));
            } else {
                // All events processed - use the cumulative totals we calculated above
                Id finalLogId = currentLogId;
                if (finalLogId == null) {
                    finalLogId = ArloEventRegistrationSyncQueueable.logId;
                }
                
                if (finalLogId == null) {
                    try {
                        List<Arlo_Integration_Log__c> recentLogs = [
                            SELECT Id, Status__c, Records_Processed__c, Records_Successful__c, Records_Failed__c
                            FROM Arlo_Integration_Log__c 
                            WHERE Operation_Type__c = 'Event Registration Sync' 
                            AND Status__c = 'In Progress'
                            ORDER BY CreatedDate DESC 
                            LIMIT 1
                        ];
                        if (!recentLogs.isEmpty()) {
                            finalLogId = recentLogs[0].Id;
                            // Get the totals from the log and add this batch
                            Integer prevProcessed = (Integer)recentLogs[0].Records_Processed__c;
                            Integer prevSuccessful = (Integer)recentLogs[0].Records_Successful__c;
                            Integer prevFailed = (Integer)recentLogs[0].Records_Failed__c;
                            cumulativeProcessed = (prevProcessed != null ? prevProcessed : 0) + processed;
                            cumulativeSuccessful = (prevSuccessful != null ? prevSuccessful : 0) + successful;
                            cumulativeFailed = (prevFailed != null ? prevFailed : 0) + failed;
                            System.debug('ArloEventRegistrationSyncQueueable: Found log record and calculated final totals - Processed: ' + cumulativeProcessed + ', Successful: ' + cumulativeSuccessful + ', Failed: ' + cumulativeFailed);
                        }
                    } catch (Exception e) {
                        System.debug('ArloEventRegistrationSyncQueueable: Error finding log record: ' + e.getMessage());
                    }
                }
                
                System.debug('ArloEventRegistrationSyncQueueable: All events processed. Final totals - Processed: ' + cumulativeProcessed + ', Successful: ' + cumulativeSuccessful + ', Failed: ' + cumulativeFailed);
                System.debug('ArloEventRegistrationSyncQueueable: This batch - Processed: ' + processed + ', Successful: ' + successful + ', Failed: ' + failed);
                System.debug('ArloEventRegistrationSyncQueueable: Final logId: ' + finalLogId);
                
                if (finalLogId != null) {
                    System.debug('ArloEventRegistrationSyncQueueable: Calling updateLogRecordStatic with Success status and cumulative totals');
                    
                    // Get existing failure reasons from the Failure_Reasons__c field
                    Map<String, Integer> allFailureReasons = new Map<String, Integer>();
                    try {
                        List<Arlo_Integration_Log__c> existingLog = [
                            SELECT Failure_Reasons__c
                            FROM Arlo_Integration_Log__c 
                            WHERE Id = :finalLogId
                            LIMIT 1
                        ];
                        if (!existingLog.isEmpty() && String.isNotBlank(existingLog[0].Failure_Reasons__c)) {
                            // Parse failure reasons from Failure_Reasons__c field (format: "Reason: count\n")
                            String failureReasonsText = existingLog[0].Failure_Reasons__c;
                            String[] lines = failureReasonsText.split('\n');
                            for (String line : lines) {
                                if (String.isNotBlank(line) && line.contains(': ')) {
                                    String[] parts = line.split(': ', 2);
                                    if (parts.size() == 2) {
                                        String reason = parts[0].trim();
                                        try {
                                            Integer count = Integer.valueOf(parts[1].trim());
                                            allFailureReasons.put(reason, count);
                                        } catch (Exception e) {
                                            // Ignore parsing errors
                                        }
                                    }
                                }
                            }
                        }
                    } catch (Exception e) {
                        System.debug('ArloEventRegistrationSyncQueueable: Error parsing existing failure reasons: ' + e.getMessage());
                    }
                    
                    // Add this batch's failure reasons
                    for (String reason : batchFailureReasons.keySet()) {
                        Integer batchCount = batchFailureReasons.get(reason);
                        Integer existingCount = allFailureReasons.containsKey(reason) ? allFailureReasons.get(reason) : 0;
                        allFailureReasons.put(reason, existingCount + batchCount);
                    }
                    
                    // Build failure reasons text for separate field
                    String failureReasonsText = null;
                    if (cumulativeFailed > 0 && !allFailureReasons.isEmpty()) {
                        List<String> sortedReasons = new List<String>(allFailureReasons.keySet());
                        sortedReasons.sort();
                        failureReasonsText = '';
                        for (String reason : sortedReasons) {
                            failureReasonsText += reason + ': ' + allFailureReasons.get(reason) + '\n';
                        }
                    }
                    
                    // Log failure reasons to debug
                    System.debug('ArloEventRegistrationSyncQueueable: All failure reasons:');
                    if (!allFailureReasons.isEmpty()) {
                        for (String reason : allFailureReasons.keySet()) {
                            System.debug('  - ' + reason + ': ' + allFailureReasons.get(reason));
                        }
                    } else {
                        System.debug('  (empty)');
                    }
                    
                    // Build message - only show "Failed" if there are actual failure reasons (not CodePrimary-related skips)
                    String finalMessage = 'Completed processing all events. Total registrations processed: ' + cumulativeProcessed + ' (only registrations that passed all filters: email consent=true, CodePrimary exists, matching Account found)';
                    if (cumulativeSuccessful > 0) {
                        finalMessage += ', Total contacts inserted: ' + cumulativeSuccessful;
                    }
                    if (cumulativeFailed > 0 && !allFailureReasons.isEmpty()) {
                        // Only show failed count if there are actual failure reasons to display
                        finalMessage += ', Failed: ' + cumulativeFailed;
                    } else if (cumulativeFailed > 0 && allFailureReasons.isEmpty()) {
                        // If failed count exists but no failure reasons, it means all failures were CodePrimary-related skips
                        // Don't show them as failures in the message
                        System.debug('ArloEventRegistrationSyncQueueable: ' + cumulativeFailed + ' failures were CodePrimary-related and excluded from failure count');
                    }
                    finalMessage += '. Note: Many registrations are filtered out due to: CONF events (skipped), no email consent, no CodePrimary, or no matching Salesforce Account. Check debug logs for detailed breakdown per event.';
                    
                    // Determine final status - only mark as Warning if there are actual failure reasons (not just CodePrimary skips)
                    String finalStatus = (cumulativeFailed > 0 && !allFailureReasons.isEmpty()) ? 'Warning' : 'Success';
                    ArloEventRegistrationSync.updateLogRecordStatic(finalLogId, finalStatus, finalMessage, null, cumulativeProcessed, cumulativeSuccessful, failureReasonsText);
                    System.debug('ArloEventRegistrationSyncQueueable: updateLogRecordStatic call completed');
                    
                    // Send error notification only if there are actual failure reasons (not CodePrimary-related skips)
                    if (cumulativeFailed > 0 && !allFailureReasons.isEmpty()) {
                        ArloEventRegistrationSync.sendErrorNotificationStatic(finalLogId, 
                            'Sync completed with ' + cumulativeFailed + ' failures. Processed: ' + cumulativeProcessed + ', Inserted: ' + cumulativeSuccessful + ', Failed: ' + cumulativeFailed);
                    }
                } else {
                    System.debug('ArloEventRegistrationSyncQueueable: WARNING - logId is null, cannot update log status');
                }
                // Reset progress map, failure reasons, and logId
                progressMap.clear();
                cumulativeFailureReasons.clear();
                ArloEventRegistrationSyncQueueable.logId = null;
            }
            
            // Clear credentials
            ArloContactSync.clearCredentials();
            
        } catch (Exception e) {
            // Clear credentials on error
            ArloContactSync.clearCredentials();
            System.debug('ArloEventRegistrationSyncQueueable: Error in execute: ' + e.getMessage());
            System.debug('ArloEventRegistrationSyncQueueable: Stack trace: ' + e.getStackTraceString());
            
            // Update log with error
            Id errorLogId = ArloEventRegistrationSyncQueueable.logId;
            String errorMessage = 'Sync failed: ' + e.getMessage();
            if (errorLogId != null) {
                Integer finalProgress = progressMap.containsKey(PROGRESS_KEY) ? progressMap.get(PROGRESS_KEY) : 0;
                Integer finalSuccess = progressMap.containsKey(SUCCESS_KEY) ? progressMap.get(SUCCESS_KEY) : 0;
                errorMessage += '. Processed: ' + finalProgress + ', Inserted: ' + finalSuccess;
                ArloEventRegistrationSync.updateLogRecordStatic(errorLogId, 'Error', errorMessage, null, finalProgress, finalSuccess);
                // Send error notification
                ArloEventRegistrationSync.sendErrorNotificationStatic(errorLogId, errorMessage);
            } else {
                // Try to find the log record
                try {
                    List<Arlo_Integration_Log__c> recentLogs = [
                        SELECT Id, Status__c 
                        FROM Arlo_Integration_Log__c 
                        WHERE Operation_Type__c = 'Event Registration Sync' 
                        AND Status__c = 'In Progress'
                        ORDER BY CreatedDate DESC 
                        LIMIT 1
                    ];
                    if (!recentLogs.isEmpty()) {
                        ArloEventRegistrationSync.updateLogRecordStatic(recentLogs[0].Id, 'Error', 
                            'Sync failed: ' + e.getMessage(), null, 0, 0);
                    }
                } catch (Exception ex) {
                    System.debug('ArloEventRegistrationSyncQueueable: Error finding log record for error update: ' + ex.getMessage());
                }
            }
            
            // Reset progress map
            progressMap.clear();
        }
    }
}

