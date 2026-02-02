# How to Run the Arlo Sync - Quick Reference

Based on the new implementation from `https://github.com/Life-Education-Trust/let-salesforce/`

## Quick Start - Run Immediately

**Open Developer Console → Debug → Execute Anonymous Window, then run:**

```apex
// Run the sync immediately (uses Custom Settings for credentials)
ArloRegistrationSyncBatch.startSync(null, null);
```

This will:
- Start a batch job that processes all Arlo contacts
- Process 5 pages per batch execution
- Handle callout limits automatically
- Create contacts and add them to campaigns

---

## Schedule Automated Syncs

### Option 1: Schedule Daily at 2 AM (Recommended for Production)

```apex
// Schedule daily FULL sync at 2 AM
String jobId = ArloSyncScheduler.scheduleDaily();
System.debug('Scheduled daily sync. Job ID: ' + jobId);
```

### Option 2: Schedule Hourly (Delta Sync - Only Recent Changes)

```apex
// Schedule hourly DELTA sync
String jobId = ArloSyncScheduler.scheduleHourly();
System.debug('Scheduled hourly sync. Job ID: ' + jobId);
```

### Option 3: Run Immediately via Scheduler (For Testing)

```apex
// Run immediately - full sync (runs in ~1 minute)
String jobId = ArloSyncScheduler.scheduleNow();
System.debug('Scheduled immediate sync. Job ID: ' + jobId);

// Or run immediately - delta sync
String jobId = ArloSyncScheduler.scheduleNow(true);
System.debug('Scheduled immediate delta sync. Job ID: ' + jobId);
```

---

## Check Scheduled Jobs

```apex
// Get status of all scheduled Arlo sync jobs
List<String> statusList = ArloSyncScheduler.getScheduledJobStatus();
for (String status : statusList) {
    System.debug(status);
}
```

---

## Unschedule All Jobs

```apex
// Remove all scheduled Arlo sync jobs
Integer abortedCount = ArloSyncScheduler.unschedule();
System.debug('Unscheduled ' + abortedCount + ' job(s)');
```

---

## Monitor the Sync

### Check Batch Job Status

Go to: **Setup → Apex Jobs** or run:

```apex
// Query for batch jobs
List<AsyncApexJob> jobs = [
    SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'ArloRegistrationSyncBatch'
    ORDER BY CreatedDate DESC
    LIMIT 10
];

for (AsyncApexJob job : jobs) {
    System.debug('Job: ' + job.Id + ' | Status: ' + job.Status + 
                 ' | Processed: ' + job.JobItemsProcessed + '/' + job.TotalJobItems +
                 ' | Errors: ' + job.NumberOfErrors);
}
```

### Check Log Records

```apex
// Query Arlo Integration Logs
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
                 ' | Processed: ' + log.Records_Processed__c + 
                 ' | Successful: ' + log.Records_Successful__c);
    System.debug('Message: ' + log.Message__c);
}
```

---

## Prerequisites

Before running the sync, ensure:

1. **Custom Settings are configured:**
   - Go to **Setup → Custom Settings**
   - Find **Arlo Credentials** (`Arlo_Credentials__c`)
   - Click **Manage** → **New** (or edit existing)
   - Enter:
     - **Username**: Your Arlo API username
     - **Password**: Your Arlo API password
   - Click **Save**

2. **Required Custom Fields exist:**
   - `Contact.Arlo_Contact_UUID__c` (Text)

3. **Campaigns exist:**
   - `NHM - Anxiety`
   - `NHM - Digital wellbeing`
   - `NHM - Self-care`
   - `NHM - Neurodiversity`

---

## New Implementation Classes

The new implementation includes:

- **ArloRegistrationSyncBatch**: Main batch class for syncing
- **ArloSyncScheduler**: Scheduler for automated syncs
- **ArloApiClient**: Centralized HTTP client
- **ArloXmlParser**: XML parsing utility
- **ArloModels**: Data models
- **CampaignMemberManager**: Campaign member management
- **EventCampaignMapper**: Event to campaign mapping
- **SyncDiagnostics**: Diagnostic utilities

---

## Troubleshooting

### If sync doesn't start:
1. Check Arlo credentials in Custom Settings
2. Verify the batch job is not already running
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

---

## Summary

**Most Common Use Case - Run Immediately:**
```apex
ArloRegistrationSyncBatch.startSync(null, null);
```

**Production Setup - Schedule Daily:**
```apex
ArloSyncScheduler.scheduleDaily();
```
