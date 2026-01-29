/**
 * Queueable class to process Arlo contacts in batches
 * Handles the 100 callout limit by processing contacts in chunks
 */
public class ArloContactSyncQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<String> contactLinks;
    private Id accountId;
    private Id logId;
    private Integer batchSize = 50; // Process 50 contacts per transaction (stays under 100 callout limit)
    private Integer startIndex = 0;
    private Integer totalProcessed = 0;
    private Integer totalSuccessful = 0;
    private Integer totalFailed = 0;
    private String arloOrgId;
    private String username;
    private String password;
    
    // Static variables to track progress across queueable executions
    private static Map<Id, Integer> logProgressMap = new Map<Id, Integer>();
    private static Map<Id, Integer> logSuccessMap = new Map<Id, Integer>();
    private static Map<Id, Integer> logFailedMap = new Map<Id, Integer>();
    
    /**
     * Constructor for initial batch
     */
    public ArloContactSyncQueueable(List<String> contactLinks, Id accountId, Id logId, String arloOrgId, String username, String password) {
        this.contactLinks = contactLinks;
        this.accountId = accountId;
        this.logId = logId;
        this.arloOrgId = arloOrgId;
        this.username = username;
        this.password = password;
        this.startIndex = 0;
        
        // Initialize tracking maps
        if (logId != null) {
            logProgressMap.put(logId, 0);
            logSuccessMap.put(logId, 0);
            logFailedMap.put(logId, 0);
        }
    }
    
    /**
     * Constructor for subsequent batches (chained execution)
     */
    public ArloContactSyncQueueable(List<String> contactLinks, Id accountId, Id logId, String arloOrgId, String username, String password, Integer startIndex) {
        this.contactLinks = contactLinks;
        this.accountId = accountId;
        this.logId = logId;
        this.arloOrgId = arloOrgId;
        this.username = username;
        this.password = password;
        this.startIndex = startIndex;
    }
    
    public void execute(QueueableContext context) {
        // Set credentials
        ArloContactSync.setCredentials(username, password);
        
        try {
            // Calculate batch range
            Integer endIndex = Math.min(startIndex + batchSize, contactLinks.size());
            List<String> batchLinks = new List<String>();
            
            for (Integer i = startIndex; i < endIndex; i++) {
                batchLinks.add(contactLinks[i]);
            }
            
            System.debug('ArloContactSyncQueueable: Processing batch ' + (startIndex / batchSize + 1) + ' - Contacts ' + startIndex + ' to ' + (endIndex - 1) + ' of ' + contactLinks.size());
            
            // STEP 1: Fetch contacts in this batch (HTTP callouts)
            List<ArloContactSync.ArloContact> batchContacts = new List<ArloContactSync.ArloContact>();
            
            for (String contactLink : batchLinks) {
                try {
                    String contactId = ArloContactSync.extractContactIdFromLink(contactLink);
                    if (String.isBlank(contactId)) {
                        totalFailed++;
                        continue;
                    }
                    
                    ArloContactSync.ArloContact contact = ArloContactSync.getSingleArloContactStatic(contactId, username, password);
                    if (contact != null) {
                        batchContacts.add(contact);
                        totalProcessed++;
                    } else {
                        totalFailed++;
                    }
                } catch (Exception e) {
                    totalFailed++;
                    System.debug('ArloContactSyncQueueable: Error fetching contact: ' + e.getMessage());
                }
            }
            
            // STEP 2: Sync batch to Salesforce (DML)
            // Note: accountId can be null - each contact will find its own Account by CodePrimary
            if (!batchContacts.isEmpty()) {
                try {
                    ArloContactSync.syncContactsToSalesforceStatic(batchContacts, accountId);
                    totalSuccessful += batchContacts.size();
                    System.debug('ArloContactSyncQueueable: Successfully synced ' + batchContacts.size() + ' contacts in this batch');
                } catch (Exception e) {
                    totalFailed += batchContacts.size();
                    System.debug('ArloContactSyncQueueable: Error syncing batch: ' + e.getMessage());
                }
            }
            
            // Update tracking maps
            if (logId != null) {
                Integer currentProcessed = logProgressMap.get(logId) != null ? logProgressMap.get(logId) : 0;
                Integer currentSuccessful = logSuccessMap.get(logId) != null ? logSuccessMap.get(logId) : 0;
                Integer currentFailed = logFailedMap.get(logId) != null ? logFailedMap.get(logId) : 0;
                
                logProgressMap.put(logId, currentProcessed + totalProcessed);
                logSuccessMap.put(logId, currentSuccessful + totalSuccessful);
                logFailedMap.put(logId, currentFailed + totalFailed);
                
                // Update log record
                ArloContactSync.updateLogRecord(logId, 'In Progress', 
                    'Processed ' + logProgressMap.get(logId) + ' of ' + contactLinks.size() + ' contacts', 
                    null, logProgressMap.get(logId), logSuccessMap.get(logId));
            }
            
            // Check if there are more contacts to process
            if (endIndex < contactLinks.size()) {
                // Chain next batch
                System.debug('ArloContactSyncQueueable: Chaining next batch starting at index ' + endIndex);
                ArloContactSyncQueueable nextBatch = new ArloContactSyncQueueable(
                    contactLinks, accountId, logId, arloOrgId, username, password, endIndex
                );
                System.enqueueJob(nextBatch);
            } else {
                // All batches complete - finalize log
                System.debug('ArloContactSyncQueueable: All batches complete');
                if (logId != null) {
                    ArloContactSync.updateLogRecord(logId, 'Success', 
                        'Successfully synced ' + logSuccessMap.get(logId) + ' of ' + logProgressMap.get(logId) + ' contacts. Failed: ' + logFailedMap.get(logId), 
                        null, logProgressMap.get(logId), logSuccessMap.get(logId));
                }
            }
            
        } catch (Exception e) {
            System.debug('ArloContactSyncQueueable: Error in batch processing: ' + e.getMessage());
            if (logId != null) {
                ArloContactSync.updateLogRecord(logId, 'Error', 
                    'Batch processing failed: ' + e.getMessage(), 
                    null, logProgressMap.get(logId), logSuccessMap.get(logId));
            }
        } finally {
            // Clear credentials
            ArloContactSync.clearCredentials();
        }
    }
}

