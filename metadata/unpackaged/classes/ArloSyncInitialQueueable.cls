/**
 * ArloSyncInitialQueueable
 * 
 * Initial Queueable class to fetch event links and then enqueue the main processing Queueable.
 * This is needed because Scheduled Apex cannot make HTTP callouts directly.
 * 
 * @author System Generated
 * @version 1.0
 */
public class ArloSyncInitialQueueable implements Queueable, Database.AllowsCallouts {
    
    private String username;
    private String password;
    
    public ArloSyncInitialQueueable(String username, String password) {
        this.username = username;
        this.password = password;
    }
    
    public void execute(QueueableContext context) {
        try {
            System.debug('ArloSyncInitialQueueable: Starting initial event link fetch at ' + DateTime.now());
            System.debug('ArloSyncInitialQueueable: Username provided: ' + (String.isNotBlank(username) ? 'Yes' : 'No'));
            System.debug('ArloSyncInitialQueueable: Password provided: ' + (String.isNotBlank(password) ? 'Yes' : 'No'));
            
            // Set credentials for use by ArloContactSync methods
            ArloContactSync.setCredentials(username, password);
            System.debug('ArloSyncInitialQueueable: Credentials set for ArloContactSync');
            
            // Fetch all event links (this requires HTTP callout, which is allowed in Queueable)
            // getAllEventLinksStatic accepts credentials as parameters, so no need to load from Custom Settings
            System.debug('ArloSyncInitialQueueable: Calling getAllEventLinksStatic...');
            List<String> eventLinks = ArloEventRegistrationSync.getAllEventLinksStatic(username, password);
            System.debug('ArloSyncInitialQueueable: Found ' + eventLinks.size() + ' event links');
            
            if (eventLinks.isEmpty()) {
                // No events found - create log record
                ArloEventRegistrationSync.createLogRecord('Event Registration Sync', 'Warning', null, null, 
                    'No events found in Arlo', 
                    ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/events/', null, 0, 0);
                System.debug('ArloSyncInitialQueueable: No events found, created warning log');
                return;
            }
            
            // Create initial log record
            Id logId = ArloEventRegistrationSync.createLogRecord('Event Registration Sync', 'In Progress', null, null, 
                'Found ' + eventLinks.size() + ' events. Processing in batches via Queueable...', 
                ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/events/', null, 0, 0);
            
            // Enqueue the main processing Queueable
            System.enqueueJob(new ArloEventRegistrationSyncQueueable(eventLinks, username, password, logId));
            System.debug('ArloSyncInitialQueueable: Enqueued ArloEventRegistrationSyncQueueable with ' + eventLinks.size() + ' events');
            
            // Clear credentials
            ArloContactSync.clearCredentials();
            
        } catch (Exception e) {
            System.debug('ArloSyncInitialQueueable: Error: ' + e.getMessage());
            System.debug('ArloSyncInitialQueueable: Stack trace: ' + e.getStackTraceString());
            
            // Clear credentials on error
            ArloContactSync.clearCredentials();
            
            // Create error log
            try {
                ArloEventRegistrationSync.createLogRecord('Event Registration Sync', 'Error', null, null, 
                    'Initial sync failed: ' + e.getMessage(), 
                    ArloEventRegistrationSync.ARLO_API_BASE_URL + '/resources/events/', null, 0, 0);
            } catch (Exception logEx) {
                System.debug('ArloSyncInitialQueueable: Error creating log record: ' + logEx.getMessage());
            }
            
            // Send error notification
            try {
                ArloEventRegistrationSync.sendErrorNotificationStatic(null, 'Initial sync failed: ' + e.getMessage());
            } catch (Exception emailEx) {
                System.debug('ArloSyncInitialQueueable: Error sending notification: ' + emailEx.getMessage());
            }
        }
    }
}

