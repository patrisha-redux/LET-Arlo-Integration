/**
 * ArloContactRegistrationSyncQueueable
 * 
 * Queueable class to process Arlo contacts and registrations in batches to avoid governor limits.
 * Processes contacts in chunks, chaining jobs as needed.
 * 
 * @author System Generated
 * @version 1.0
 */
public class ArloContactRegistrationSyncQueueable implements Queueable, Database.AllowsCallouts {
    
    // Contact links to process
    private List<String> contactLinks;
    
    // Credentials for Basic Auth
    private String username;
    private String password;
    
    // Progress tracking
    private Integer startIndex;
    private Id logId;
    
    // Deferred contacts to process (numeric IDs)
    private List<String> deferredContactIds;
    
    /**
     * Constructor
     */
    public ArloContactRegistrationSyncQueueable(List<String> contactLinks, String username, String password, Id logId, Integer startIndex) {
        this(contactLinks, username, password, logId, startIndex, new List<String>());
    }
    
    /**
     * Constructor with deferred contacts
     */
    public ArloContactRegistrationSyncQueueable(List<String> contactLinks, String username, String password, Id logId, Integer startIndex, List<String> deferredContactIds) {
        this.contactLinks = contactLinks;
        this.username = username;
        this.password = password;
        this.logId = logId;
        this.startIndex = startIndex;
        this.deferredContactIds = deferredContactIds != null ? deferredContactIds : new List<String>();
    }
    
    public void execute(QueueableContext context) {
        System.debug('ArloContactRegistrationSyncQueueable: ===== STARTING BATCH =====');
        System.debug('ArloContactRegistrationSyncQueueable: Starting batch processing from index ' + startIndex);
        System.debug('ArloContactRegistrationSyncQueueable: Total contact links: ' + contactLinks.size());
        // Note: deferredContactIds parameter is ignored in the new simplified flow
        // Call the method (deferredContactIds will be ignored)
        ArloEventRegistrationSync.processContactsBatch(contactLinks, username, password, logId, startIndex, deferredContactIds);
    }
}
