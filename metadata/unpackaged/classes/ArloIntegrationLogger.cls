/**
 * ArloIntegrationLogger
 *
 * Centralized logging to Arlo_Integration_Log__c custom object.
 * Provides real-time tracking of sync operations with detailed metrics.
 */
public with sharing class ArloIntegrationLogger {

    private Id logId;
    private String operationType;
    private DateTime startTime;
    private ArloModels.SyncResult result;

    /**
     * Start a new log entry
     */
    public ArloIntegrationLogger(String operationType) {
        this.operationType = operationType;
        this.startTime = DateTime.now();
        this.result = new ArloModels.SyncResult();
        createLogRecord();
    }

    /**
     * Create initial log record
     */
    private void createLogRecord() {
        Arlo_Integration_Log__c log = new Arlo_Integration_Log__c(
            Operation_Type__c = operationType,
            Status__c = 'In Progress',
            Message__c = 'Started at ' + startTime.format('yyyy-MM-dd HH:mm:ss'),
            Records_Processed__c = 0,
            Records_Successful__c = 0,
            Records_Failed__c = 0
        );
        insert log;
        this.logId = log.Id;
    }

    /**
     * Get the log record ID
     */
    public Id getLogId() {
        return logId;
    }

    /**
     * Update progress during sync
     */
    public void updateProgress(String message, Integer processed, Integer successful, Integer failed) {
        result.totalProcessed = processed;
        result.totalSuccessful = successful;
        result.totalFailed = failed;

        if (logId != null) {
            Arlo_Integration_Log__c log = new Arlo_Integration_Log__c(
                Id = logId,
                Status__c = 'In Progress',
                Message__c = truncateMessage(message),
                Records_Processed__c = processed,
                Records_Successful__c = successful,
                Records_Failed__c = failed
            );
            update log;
        }
    }

    /**
     * Update with batch progress
     */
    public void updateBatchProgress(Integer batchNumber, Integer totalBatches, Integer processed, Integer successful) {
        String message = 'Batch ' + batchNumber + '/' + totalBatches + ' complete. ' +
                        'Processed: ' + processed + ', Successful: ' + successful;
        updateProgress(message, processed, successful, result.totalFailed);
    }

    /**
     * Log an error
     */
    public void logError(String errorMessage) {
        result.errors.add(errorMessage);
        result.totalFailed++;
        System.debug('ArloIntegrationLogger ERROR: ' + errorMessage);
    }

    /**
     * Log success for contacts created
     */
    public void logContactsCreated(Integer count) {
        result.contactsCreated += count;
        result.totalSuccessful += count;
    }

    /**
     * Log success for campaign members added
     */
    public void logCampaignMembersAdded(Integer count) {
        result.campaignMembersAdded += count;
    }

    /**
     * Complete the log with success
     */
    public void complete() {
        complete('Success', buildSummaryMessage());
    }

    /**
     * Complete the log with custom status and message
     */
    public void complete(String status, String message) {
        if (logId != null) {
            Long durationMs = DateTime.now().getTime() - startTime.getTime();
            String durationStr = formatDuration(durationMs);

            String failureReasons = result.errors.isEmpty() ? null :
                String.join(result.errors, '\n').left(32000);

            Arlo_Integration_Log__c log = new Arlo_Integration_Log__c(
                Id = logId,
                Status__c = status,
                Message__c = truncateMessage(message + '\nDuration: ' + durationStr),
                Records_Processed__c = result.totalProcessed,
                Records_Successful__c = result.totalSuccessful,
                Records_Failed__c = result.totalFailed,
                Failure_Reasons__c = failureReasons
            );
            update log;
        }
    }

    /**
     * Complete with error
     */
    public void completeWithError(String errorMessage) {
        logError(errorMessage);
        complete('Error', errorMessage);
    }

    /**
     * Complete with error from exception
     */
    public void completeWithError(Exception e) {
        String errorMessage = e.getMessage() + '\nStack: ' + e.getStackTraceString();
        completeWithError(errorMessage);
    }

    /**
     * Get the sync result
     */
    public ArloModels.SyncResult getResult() {
        return result;
    }

    /**
     * Build summary message
     */
    private String buildSummaryMessage() {
        return 'Sync completed.\n' +
               'Total Processed: ' + result.totalProcessed + '\n' +
               'Successful: ' + result.totalSuccessful + '\n' +
               'Failed: ' + result.totalFailed + '\n' +
               'Contacts Created: ' + result.contactsCreated + '\n' +
               'Campaign Members Added: ' + result.campaignMembersAdded;
    }

    /**
     * Format duration in human readable format
     */
    private String formatDuration(Long milliseconds) {
        Long seconds = milliseconds / 1000;
        Long minutes = seconds / 60;
        seconds = Math.mod(seconds, 60);

        if (minutes > 0) {
            return minutes + 'm ' + seconds + 's';
        }
        return seconds + 's';
    }

    /**
     * Truncate message to fit in text field
     */
    private String truncateMessage(String message) {
        if (message != null && message.length() > 32000) {
            return message.left(32000);
        }
        return message;
    }

    /**
     * Static helper - create a quick log entry for simple operations
     */
    public static Id quickLog(String operationType, String status, String message) {
        Arlo_Integration_Log__c log = new Arlo_Integration_Log__c(
            Operation_Type__c = operationType,
            Status__c = status,
            Message__c = message != null ? message.left(32000) : null
        );
        insert log;
        return log.Id;
    }

    /**
     * Static helper - update existing log
     */
    public static void updateLog(Id logId, String status, String message,
                                  Integer processed, Integer successful, Integer failed) {
        if (logId != null) {
            Arlo_Integration_Log__c log = new Arlo_Integration_Log__c(
                Id = logId,
                Status__c = status,
                Message__c = message != null ? message.left(32000) : null,
                Records_Processed__c = processed,
                Records_Successful__c = successful,
                Records_Failed__c = failed
            );
            update log;
        }
    }
}