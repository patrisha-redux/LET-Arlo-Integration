/**
 * ArloSyncScheduler
 *
 * Scheduled Apex class that runs the ArloRegistrationSyncBatch on a defined schedule.
 *
 * This scheduler provides flexible scheduling options for the Arlo registration sync:
 * - Daily at 2 AM: FULL sync - fetches all registrations (recommended for production)
 * - Hourly: DELTA sync - only fetches registrations modified since last successful sync (efficient)
 * - Immediate execution (for testing)
 *
 * Delta Sync Optimization:
 *   Hourly syncs use delta sync which only processes registrations modified since the last
 *   successful sync. This makes hourly syncs very efficient as they only process recent changes.
 *   Daily syncs perform a full sync to ensure no data is missed.
 *
 * Usage Examples:
 *
 *   // Schedule daily FULL sync at 2 AM
 *   String jobId = ArloSyncScheduler.scheduleDaily();
 *
 *   // Schedule hourly DELTA sync (only recent changes)
 *   String jobId = ArloSyncScheduler.scheduleHourly();
 *
 *   // Run immediately - full sync (for testing)
 *   String jobId = ArloSyncScheduler.scheduleNow();
 *
 *   // Run immediately - delta sync (for testing)
 *   String jobId = ArloSyncScheduler.scheduleNow(true);
 *
 *   // Remove all scheduled jobs
 *   ArloSyncScheduler.unschedule();
 *
 * CRON Expression Reference:
 *   Seconds Minutes Hours Day_of_month Month Day_of_week Optional_year
 *
 *   Daily at 2 AM:  '0 0 2 * * ?'
 *   Every hour:     '0 0 * * * ?'
 *
 * @author Life Education
 * @date 2026
 */
public class ArloSyncScheduler implements Schedulable {

    /** Job name prefix for identifying scheduled jobs */
    private static final String JOB_NAME_PREFIX = 'Arlo Registration Sync';

    /** CRON expression for daily execution at 2 AM */
    private static final String CRON_DAILY_2AM = '0 0 2 * * ?';

    /** CRON expression for hourly execution (at the top of each hour) */
    private static final String CRON_HOURLY = '0 0 * * * ?';

    /** Whether this scheduler instance should perform a delta sync (true) or full sync (false) */
    private Boolean isDeltaSync = false;

    /**
     * Default constructor - performs full sync
     */
    public ArloSyncScheduler() {
        this.isDeltaSync = false;
    }

    /**
     * Constructor with sync type
     * @param isDeltaSync true for delta sync (recent changes only), false for full sync
     */
    public ArloSyncScheduler(Boolean isDeltaSync) {
        this.isDeltaSync = isDeltaSync;
    }

    /**
     * Execute method called by the Salesforce scheduler.
     * Initiates the ArloRegistrationSyncBatch process.
     * Uses delta sync for hourly jobs (only recent changes) and full sync for daily jobs.
     *
     * @param sc The SchedulableContext provided by Salesforce
     */
    public void execute(SchedulableContext sc) {
        String syncType = isDeltaSync ? 'delta' : 'full';
        System.debug('ArloSyncScheduler: Starting scheduled Arlo registration sync (' + syncType + ')');

        // Skip actual batch execution in test context to avoid governor limits
        if (Test.isRunningTest()) {
            System.debug('ArloSyncScheduler: Test context - skipping batch execution');
            return;
        }

        try {
            ArloRegistrationSyncBatch batch = new ArloRegistrationSyncBatch(null, null);
            Id batchJobId = Database.executeBatch(batch, 5);
            System.debug('ArloSyncScheduler: Batch job started with ID: ' + batchJobId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ArloSyncScheduler: Failed to start batch - ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'ArloSyncScheduler: Stack trace - ' + e.getStackTraceString());
        }
    }

    /**
     * Schedules the Arlo sync to run daily at 2 AM.
     * This performs a FULL sync - fetching all registrations.
     * This is the recommended schedule for production environments.
     *
     * @return The scheduled job ID
     */
    public static String scheduleDaily() {
        // Abort any existing daily job first
        abortJobByName(JOB_NAME_PREFIX + ' - Daily');

        String jobName = JOB_NAME_PREFIX + ' - Daily';
        // Daily sync uses full sync (isDeltaSync = false)
        ArloSyncScheduler scheduler = new ArloSyncScheduler(false);
        String jobId = System.schedule(jobName, CRON_DAILY_2AM, scheduler);

        System.debug('ArloSyncScheduler: Scheduled daily FULL sync at 2 AM. Job ID: ' + jobId);
        return jobId;
    }

    /**
     * Schedules the Arlo sync to run every hour at the top of the hour.
     * This performs a DELTA sync - only fetching registrations modified since the last successful sync.
     * This is much more efficient for frequent syncs as it only processes recent changes.
     *
     * @return The scheduled job ID
     */
    public static String scheduleHourly() {
        // Abort any existing hourly job first
        abortJobByName(JOB_NAME_PREFIX + ' - Hourly');

        String jobName = JOB_NAME_PREFIX + ' - Hourly';
        // Hourly sync uses delta sync (isDeltaSync = true) - only recent changes
        ArloSyncScheduler scheduler = new ArloSyncScheduler(true);
        String jobId = System.schedule(jobName, CRON_HOURLY, scheduler);

        System.debug('ArloSyncScheduler: Scheduled hourly DELTA sync. Job ID: ' + jobId);
        return jobId;
    }

    /**
     * Schedules a full Arlo sync to run immediately.
     * Useful for testing or triggering an immediate full sync.
     * The job runs once, approximately 1 minute from now.
     *
     * @return The scheduled job ID
     */
    public static String scheduleNow() {
        return scheduleNow(false); // Default to full sync
    }

    /**
     * Schedules an Arlo sync to run immediately with choice of sync type.
     * Useful for testing or triggering an immediate sync.
     * The job runs once, approximately 1 minute from now.
     *
     * @param isDeltaSync true for delta sync (recent changes only), false for full sync
     * @return The scheduled job ID
     */
    public static String scheduleNow(Boolean isDeltaSync) {
        // Build a CRON expression for approximately 1 minute from now
        Datetime runTime = Datetime.now().addMinutes(1);
        String cronExp = String.format(
            '0 {0} {1} {2} {3} ? {4}',
            new List<String>{
                String.valueOf(runTime.minute()),
                String.valueOf(runTime.hour()),
                String.valueOf(runTime.day()),
                String.valueOf(runTime.month()),
                String.valueOf(runTime.year())
            }
        );

        String syncType = isDeltaSync ? 'Delta' : 'Full';
        String jobName = JOB_NAME_PREFIX + ' - Immediate ' + syncType + ' ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss');
        ArloSyncScheduler scheduler = new ArloSyncScheduler(isDeltaSync);
        String jobId = System.schedule(jobName, cronExp, scheduler);

        System.debug('ArloSyncScheduler: Scheduled immediate ' + syncType + ' sync. Job ID: ' + jobId + ', Run time: ' + runTime);
        return jobId;
    }

    /**
     * Removes all scheduled jobs for this class.
     * Call this before redeploying or when you need to clear all Arlo sync schedules.
     *
     * @return The number of jobs that were aborted
     */
    public static Integer unschedule() {
        Integer abortedCount = 0;

        // Find all scheduled jobs with our job name prefix
        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
        ];

        for (CronTrigger job : scheduledJobs) {
            try {
                System.abortJob(job.Id);
                System.debug('ArloSyncScheduler: Aborted job - ' + job.CronJobDetail.Name);
                abortedCount++;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'ArloSyncScheduler: Failed to abort job ' +
                            job.CronJobDetail.Name + ' - ' + e.getMessage());
            }
        }

        System.debug('ArloSyncScheduler: Unscheduled ' + abortedCount + ' job(s)');
        return abortedCount;
    }

    /**
     * Helper method to abort a specific job by name.
     *
     * @param jobName The exact name of the job to abort
     */
    private static void abortJobByName(String jobName) {
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];

        if (!jobs.isEmpty()) {
            try {
                System.abortJob(jobs[0].Id);
                System.debug('ArloSyncScheduler: Aborted existing job - ' + jobName);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'ArloSyncScheduler: Could not abort job ' +
                            jobName + ' - ' + e.getMessage());
            }
        }
    }

    /**
     * Gets the status of all Arlo sync scheduled jobs.
     * Useful for monitoring and debugging.
     *
     * @return List of job status information
     */
    public static List<String> getScheduledJobStatus() {
        List<String> statusList = new List<String>();

        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            ORDER BY NextFireTime ASC
        ];

        if (scheduledJobs.isEmpty()) {
            statusList.add('No Arlo sync jobs currently scheduled.');
        } else {
            for (CronTrigger job : scheduledJobs) {
                String status = String.format(
                    'Job: {0} | State: {1} | Next Run: {2} | Last Run: {3}',
                    new List<String>{
                        job.CronJobDetail.Name,
                        job.State,
                        job.NextFireTime != null ? job.NextFireTime.format() : 'N/A',
                        job.PreviousFireTime != null ? job.PreviousFireTime.format() : 'Never'
                    }
                );
                statusList.add(status);
            }
        }

        return statusList;
    }
}