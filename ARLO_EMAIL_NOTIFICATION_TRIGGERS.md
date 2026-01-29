# Arlo Integration Email Notification Triggers

## Overview
Email notifications are sent to **`patrisha@redux.nz`** when errors occur during the Arlo Event Registration Sync process.

## Email Notification Recipient
- **To:** `patrisha@redux.nz`

---

## When Email Notifications ARE Sent

### 1. **Exceptions During Sync Execution**
**Location:** `ArloEventRegistrationSyncQueueable.execute()` (catch block, line 697)

**Triggered When:**
- Any unhandled exception occurs during batch processing
- Examples:
  - HTTP callout failures (network errors, timeouts)
  - XML parsing errors
  - DML exceptions (validation rules, required fields)
  - Governor limit exceptions (too many SOQL queries, DML statements, etc.)
  - Null pointer exceptions
  - Any other runtime exceptions

**Email Content:**
- Error message
- Stack trace
- Processed/Inserted counts (if available)
- Link to log record (if available)

---

### 2. **Sync Completes with Actual Failures**
**Location:** `ArloEventRegistrationSyncQueueable.execute()` (final batch completion, line 666-669)

**Triggered When:**
- Sync completes successfully but has **actual failure reasons**
- Condition: `cumulativeFailed > 0 AND allFailureReasons is NOT empty`

**What Counts as "Actual Failures":**
- HTTP errors (404, 500, etc.)
- Invalid XML responses
- Missing required fields causing DML errors
- Validation rule failures
- Duplicate detection errors
- Any other errors that prevent contact insertion

**Email Content:**
- Summary: "Sync completed with X failures"
- Processed/Inserted/Failed counts
- Failure reasons breakdown (from `Failure_Reasons__c` field)
- Link to log record

---

### 3. **Initial Queueable Failures**
**Location:** `ArloSyncInitialQueueable.execute()` (catch block, line 75)

**Triggered When:**
- Exception occurs while fetching event links
- Exception occurs while creating initial log record
- Exception occurs while enqueueing the main processing Queueable

**Examples:**
- Cannot fetch events from Arlo API
- Invalid credentials
- Network connectivity issues
- Exception during log record creation

**Email Content:**
- Error message: "Initial sync failed: {error message}"
- No log record details (logId is null)

---

### 4. **Scheduled Job Failures**
**Location:** `ArloEventRegistrationSyncScheduled.execute()` (catch block, line 45-63)

**Triggered When:**
- Exception occurs in the scheduled job execution
- Examples:
  - Custom Settings not configured (missing `Arlo_Credentials__c`)
  - Exception while enqueueing `ArloSyncInitialQueueable`
  - Any other exception in scheduled context

**Email Content:**
- Subject: "Arlo Event Registration Sync - Scheduled Job Error"
- Error message
- Full stack trace
- Scheduled time
- Note to check Arlo Integration Log records

---

## When Email Notifications are NOT Sent

### 1. **Expected Filtering/Skips**
These are **NOT** counted as failures and **DO NOT** trigger email notifications:

- ✅ **CONF Events Skipped**
  - Events with Code starting with 'CONF' are intentionally skipped
  - No email notification sent

- ✅ **Missing Email Consent**
  - Registrations where `imhappytobeemailedaboutlifeeducationtrustnews` = false
  - Expected behavior - no email notification

- ✅ **No CodePrimary Found**
  - Organisation exists in Arlo but doesn't have CodePrimary
  - Contact is skipped gracefully
  - Logged as debug message only
  - **NOT counted as failure**

- ✅ **No Matching Salesforce Account**
  - CodePrimary exists but no Account with matching AccountNumber
  - Contact is skipped gracefully
  - Logged as debug message only
  - **NOT counted as failure**

- ✅ **Duplicate Contacts**
  - Contact already exists (matched by UUID or Email)
  - Contact is updated, not inserted
  - Not counted as failure

---

## Email Notification Logic Flow

```
┌─────────────────────────────────────────────────┐
│  Sync Process Starts                            │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │ Exception Occurs?   │
        └─────┬───────────┬───┘
              │ YES       │ NO
              ▼           ▼
    ┌─────────────────┐  ┌────────────────────────┐
    │ Send Email      │  │ Sync Completes         │
    │ (Any Exception) │  └────────┬───────────────┘
    └─────────────────┘           │
                                  ▼
                        ┌──────────────────────┐
                        │ Has Actual Failures? │
                        │ (cumulativeFailed > 0│
                        │  AND failureReasons  │
                        │  is NOT empty)       │
                        └─────┬────────────┬───┘
                              │ YES        │ NO
                              ▼            ▼
                    ┌─────────────────┐  ┌──────────────┐
                    │ Send Email      │  │ No Email     │
                    │ (With Failure   │  │ (Success)    │
                    │  Details)       │  └──────────────┘
                    └─────────────────┘
```

---

## Example Scenarios

### Scenario 1: Successful Sync with Filtering
- **Events Processed:** 132
- **Registrations:** 500
- **Filtered Out:**
  - 50 CONF events (skipped)
  - 200 no email consent (skipped)
  - 50 no CodePrimary (skipped)
  - 50 no matching Account (skipped)
- **Contacts Inserted:** 150
- **Actual Failures:** 0

**Result:** ✅ **NO EMAIL SENT** (all filtering is expected behavior)

---

### Scenario 2: Sync with HTTP Errors
- **Events Processed:** 132
- **Registrations:** 500
- **Contacts Inserted:** 400
- **Actual Failures:** 100
  - 50: HTTP 404 errors
  - 30: Invalid XML responses
  - 20: Validation rule failures

**Result:** ✅ **EMAIL SENT** with failure details

---

### Scenario 3: Exception During Processing
- **Events Processed:** 50
- **Exception:** `System.LimitException: Too many SOQL queries: 101`
- Processing stops

**Result:** ✅ **EMAIL SENT** immediately with exception details

---

### Scenario 4: Scheduled Job Credentials Missing
- **Scheduled Job Runs**
- **Custom Settings:** Not configured
- **Exception:** "Arlo Credentials not configured..."

**Result:** ✅ **EMAIL SENT** from scheduled job catch block

---

## Email Notification Content

### Subject Line
- `Arlo Event Registration Sync - Error Notification` (for sync errors)
- `Arlo Event Registration Sync - Scheduled Job Error` (for scheduled job errors)

### Email Body Includes:
1. **Error Details:**
   - Error message
   - Stack trace (for exceptions)

2. **Sync Summary** (if available):
   - Records Processed
   - Records Successful/Inserted
   - Records Failed

3. **Failure Reasons** (if available):
   - Breakdown from `Failure_Reasons__c` field
   - Example: "HTTP 404: 50, Invalid XML: 30, Validation Error: 20"

4. **Log Record Link:**
   - Log Record ID
   - Direct link to view in Salesforce

5. **Additional Notes:**
   - Reminder to check Arlo Integration Log records
   - Automated message disclaimer

---

## Important Notes

1. **Email Failure Handling:**
   - If email sending itself fails, it's logged to debug logs only
   - Email failure does NOT stop the sync process

2. **Multiple Email Scenarios:**
   - Exception during processing = immediate email
   - Failures at completion = email after all batches complete
   - Only one email per sync run (either exception OR completion failures, not both)

3. **Log Record Status:**
   - `Error` = Exception occurred
   - `Warning` = Sync completed with failures
   - `Success` = Sync completed successfully (no actual failures)

4. **Failure Reasons Tracking:**
   - Only "actual" failures are tracked in `Failure_Reasons__c`
   - CodePrimary-related skips are intentionally excluded
   - This prevents false positives in email notifications

---

## Testing Email Notifications

To test email notifications, you can:

1. **Simulate HTTP Error:**
   ```apex
   // In test class, use mock that returns 500 error
   Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockServerError());
   ```

2. **Simulate Exception:**
   ```apex
   // Force exception by passing invalid parameters
   ArloEventRegistrationSync.syncContactsFromEvents(null, null);
   // When Custom Settings not configured
   ```

3. **Simulate Validation Error:**
   - Create test data that violates validation rules
   - Sync will fail and trigger email

---

## Summary

**Email notifications are sent when:**
- ✅ Unhandled exceptions occur
- ✅ Sync completes with actual failures (not expected skips)
- ✅ Scheduled job fails

**Email notifications are NOT sent for:**
- ❌ Expected filtering (CONF events, no consent, no CodePrimary, no Account)
- ❌ Successful syncs
- ❌ Duplicate contact handling
- ❌ Normal processing flow


