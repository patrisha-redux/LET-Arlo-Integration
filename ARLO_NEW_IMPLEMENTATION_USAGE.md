# Arlo New Implementation - Usage Guide

This document explains how to use the new refactored Arlo Integration implementation.

## Overview

The new implementation has been refactored with better separation of concerns:
- **ArloApiClient**: Centralized HTTP client for all Arlo API calls
- **ArloXmlParser**: XML parsing utility
- **ArloModels**: Data models
- **ArloRegistrationSyncBatch**: Main batch class for syncing
- **ArloSyncScheduler**: Scheduler for automated syncs

## How to Run the Sync

### Option 1: Run Immediately (Manual Execution)

**In Developer Console or Anonymous Apex:**

```apex
// Run full sync immediately (uses Custom Settings for credentials)
ArloRegistrationSyncBatch.startSync(null, null);
```

**Or with explicit credentials:**
```apex
ArloRegistrationSyncBatch.startSync('your-username', 'your-password');
```

### Option 2: Schedule Daily at 2 AM (Recommended for Production)

**In Developer Console or Anonymous Apex:**

```apex
// Schedule daily FULL sync at 2 AM
String jobId = ArloSyncScheduler.scheduleDaily();
System.debug('Scheduled daily sync. Job ID: ' + jobId);
```

This will:
- Run every day at 2 AM
- Perform a FULL sync (all contacts and registrations)
- Automatically start the batch job

### Option 3: Schedule Hourly (Delta Sync)

**In Developer Console or Anonymous Apex:**

```apex
// Schedule hourly DELTA sync (only recent changes)
String jobId = ArloSyncScheduler.scheduleHourly();
System.debug('Scheduled hourly sync. Job ID: ' + jobId);
```

This will:
- Run every hour at the top of the hour
- Perform a DELTA sync (only registrations modified since last sync)
- More efficient for frequent syncs

### Option 4: Run Immediately via Scheduler (For Testing)

**In Developer Console or Anonymous Apex:**

```apex
// Run immediately - full sync (runs in ~1 minute)
String jobId = ArloSyncScheduler.scheduleNow();
System.debug('Scheduled immediate sync. Job ID: ' + jobId);

// Or run immediately - delta sync
String jobId = ArloSyncScheduler.scheduleNow(true);
System.debug('Scheduled immediate delta sync. Job ID: ' + jobId);
```

## Managing Scheduled Jobs

### Check Scheduled Job Status

```apex
// Get status of all scheduled Arlo sync jobs
List<String> statusList = ArloSyncScheduler.getScheduledJobStatus();
for (String status : statusList) {
    System.debug(status);
}
```

### Unschedule All Jobs

```apex
// Remove all scheduled Arlo sync jobs
Integer abortedCount = ArloSyncScheduler.unschedule();
System.debug('Unscheduled ' + abortedCount + ' job(s)');
```

## Key Differences from Old Implementation

### New Implementation (Recommended)
- **Class**: `ArloRegistrationSyncBatch`
- **Scheduler**: `ArloSyncScheduler`
- **Batch Size**: 5 pages per execution
- **Architecture**: Better separation of concerns with dedicated classes for API, XML parsing, and models

### Old Implementation (Still Available)
- **V1**: `ArloEventRegistrationSync.syncContactsFromEvents()` (Queueable)
- **V2**: `ArloEventRegistrationSyncBatchV2.startSync()` (Batch)

## Batch Configuration

The new implementation processes **5 pages per batch execution** by default:
```apex
Database.executeBatch(batch, 5); // 5 pages per execution
```

This means:
- Faster processing (fewer batch executions)
- Each batch execution gets 100 callouts
- Processes up to 1000 pages total (safety limit)

## Monitoring

### Check Batch Job Status

Go to: **Setup → Apex Jobs** or use:
```apex
// Query for batch jobs
List<AsyncApexJob> jobs = [
    SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'ArloRegistrationSyncBatch'
    ORDER BY CreatedDate DESC
    LIMIT 10
];

for (AsyncApexJob job : jobs) {
    System.debug('Job: ' + job.Id + ' | Status: ' + job.Status + 
                 ' | Processed: ' + job.JobItemsProcessed + '/' + job.TotalJobItems);
}
```

### Check Log Records

The sync creates log records in `Arlo_Integration_Log__c`:
```apex
List<Arlo_Integration_Log__c> logs = [
    SELECT Id, Operation_Type__c, Status__c, Message__c, 
           Records_Processed__c, Records_Successful__c, CreatedDate
    FROM Arlo_Integration_Log__c
    WHERE Operation_Type__c LIKE '%Registration Sync%'
    ORDER BY CreatedDate DESC
    LIMIT 10
];

for (Arlo_Integration_Log__c log : logs) {
    System.debug('Log: ' + log.Id + ' | Status: ' + log.Status__c + 
                 ' | Message: ' + log.Message__c);
}
```

## Recommended Setup

For production, we recommend:

1. **Schedule Daily Full Sync at 2 AM:**
   ```apex
   ArloSyncScheduler.scheduleDaily();
   ```

2. **Optional: Schedule Hourly Delta Sync:**
   ```apex
   ArloSyncScheduler.scheduleHourly();
   ```

3. **Monitor via Log Records:**
   - Check `Arlo_Integration_Log__c` records
   - Review Apex Jobs in Setup

## Troubleshooting

### If sync doesn't start:
1. Check Arlo credentials in Custom Settings: `Arlo_Credentials__c`
2. Verify the batch job is not already running (check Apex Jobs)
3. Check debug logs for errors

### If contacts aren't being processed:
1. Check callout limits in debug logs
2. Verify contacts have registrations in Arlo
3. Check if events contain "NHM" in the name/code
4. Verify email consent is set to true

### If scheduled job doesn't run:
1. Check scheduled job status: `ArloSyncScheduler.getScheduledJobStatus()`
2. Verify the job is in "WAITING" state
3. Check NextFireTime to see when it will run next
