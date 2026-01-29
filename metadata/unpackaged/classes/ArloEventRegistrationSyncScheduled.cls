/**
 * ArloEventRegistrationSyncScheduled
 * 
 * Schedulable class to run Arlo Event Registration Sync daily at 1 AM
 * 
 * To schedule:
 * ArloEventRegistrationSyncScheduled scheduler = new ArloEventRegistrationSyncScheduled();
 * String cronExpression = '0 0 1 * * ?'; // 1 AM daily
 * System.schedule('Arlo Event Registration Sync - Daily', cronExpression, scheduler);
 * 
 * @author System Generated
 * @version 1.0
 */
public class ArloEventRegistrationSyncScheduled implements Schedulable {
    
    public void execute(SchedulableContext ctx) {
        try {
            System.debug('ArloEventRegistrationSyncScheduled: ========================================');
            System.debug('ArloEventRegistrationSyncScheduled: Starting scheduled sync at ' + DateTime.now());
            System.debug('ArloEventRegistrationSyncScheduled: CronTrigger ID: ' + (ctx != null ? ctx.getTriggerId() : 'null'));
            
            // Verify Custom Settings are configured before calling sync
            Arlo_Credentials__c creds = Arlo_Credentials__c.getOrgDefaults();
            if (creds == null || String.isBlank(creds.Username__c) || String.isBlank(creds.Password__c)) {
                String errorMsg = 'Arlo Credentials not configured in Custom Settings. Cannot run scheduled sync.';
                System.debug('ArloEventRegistrationSyncScheduled: ERROR - ' + errorMsg);
                throw new CalloutException(errorMsg);
            }
            
            System.debug('ArloEventRegistrationSyncScheduled: Custom Settings verified. Username: ' + creds.Username__c);
            System.debug('ArloEventRegistrationSyncScheduled: About to enqueue ArloSyncInitialQueueable...');
            
            // Scheduled Apex cannot make HTTP callouts, so enqueue a Queueable job
            // The Queueable will fetch event links and then enqueue the main processing Queueable
            Id queueableJobId = System.enqueueJob(new ArloSyncInitialQueueable(creds.Username__c, creds.Password__c));
            
            System.debug('ArloEventRegistrationSyncScheduled: Successfully enqueued ArloSyncInitialQueueable. Job ID: ' + queueableJobId);
            System.debug('ArloEventRegistrationSyncScheduled: Processing will continue asynchronously.');
            System.debug('ArloEventRegistrationSyncScheduled: ========================================');
        } catch (Exception e) {
            System.debug('ArloEventRegistrationSyncScheduled: Error in scheduled sync: ' + e.getMessage());
            System.debug('ArloEventRegistrationSyncScheduled: Stack trace: ' + e.getStackTraceString());
            
            // Send error notification
            try {
                List<String> toAddresses = new List<String>{ 'patrisha@redux.nz', 'lifeeducation@redux.nz' };
                
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(toAddresses);
                mail.setSubject('Arlo Event Registration Sync - Scheduled Job Error');
                
                String emailBody = 'The scheduled Arlo Event Registration Sync has encountered an error.\n\n';
                emailBody += 'Error Details:\n';
                emailBody += e.getMessage() + '\n\n';
                emailBody += 'Stack Trace:\n';
                emailBody += e.getStackTraceString() + '\n\n';
                emailBody += 'Scheduled Time: ' + DateTime.now() + '\n\n';
                emailBody += 'Please review the error and check the Arlo Integration Log records.\n\n';
                emailBody += 'This is an automated message from the Arlo Integration System.';
                
                mail.setPlainTextBody(emailBody);
                
                Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
            } catch (Exception emailEx) {
                System.debug('ArloEventRegistrationSyncScheduled: Error sending notification email: ' + emailEx.getMessage());
            }
        }
    }
}

