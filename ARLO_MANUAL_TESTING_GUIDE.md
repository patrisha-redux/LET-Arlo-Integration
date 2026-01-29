# Arlo Integration - Manual Testing Guide

## Prerequisites

Before testing, ensure:
1. **Custom Settings are configured** (see Setup Instructions)
2. You have access to Developer Console
3. You have access to Arlo Integration Logs

---

## Step 1: Configure Custom Settings

1. Go to **Setup** → **Custom Settings**
2. Find **Arlo Credentials**
3. Click **Manage** → **New** (or edit existing org-level record)
4. Enter:
   - **Username**: `lizzie.barnett@lifeeducation.org.nz`
   - **Password**: `YellowArlo123!`
5. Click **Save**

---

## Step 2: Test Event Registration Sync

### Option A: Using Custom Settings (Recommended)

1. Open **Developer Console** (Setup → Developer Console)
2. Go to **Debug** → **Open Execute Anonymous Window**
3. Paste and execute:

```apex
// Test Event Registration Sync using Custom Settings
try {
    ArloEventRegistrationSync.syncContactsFromEvents(null, null);
    System.debug('Sync initiated successfully');
} catch (Exception e) {
    System.debug('Error: ' + e.getMessage());
    System.debug('Stack: ' + e.getStackTraceString());
}
```

### Option B: With Explicit Credentials (Override Custom Settings)

```apex
// Test with explicit credentials (overrides Custom Settings)
try {
    ArloEventRegistrationSync.syncContactsFromEvents(
        'lizzie.barnett@lifeeducation.org.nz', 
        'YellowArlo123!'
    );
    System.debug('Sync initiated successfully');
} catch (Exception e) {
    System.debug('Error: ' + e.getMessage());
    System.debug('Stack: ' + e.getStackTraceString());
}
```

---

## Step 3: Monitor the Sync

### Check Debug Logs

1. In Developer Console, go to **Logs** tab
2. Look for debug messages:
   - `ArloEventRegistrationSync: Starting sync...`
   - `ArloEventRegistrationSync: Found X events`
   - `ArloEventRegistrationSync: Processing event...`
   - `ArloEventRegistrationSync: Completed sync...`

### Check Arlo Integration Logs

1. Go to **Arlo Integration Logs** tab
2. Find the most recent log record
3. Check:
   - **Status**: Should be "Success", "In Progress", "Warning", or "Error"
   - **Operation Type**: "Event Registration Sync"
   - **Records Processed**: Number of registrations processed
   - **Records Successful**: Number of unique contacts synced
   - **Records Failed**: Number of failures
   - **Message**: Detailed status message

### Check Contacts

1. Go to **Contacts** tab
2. Filter or search for contacts with:
   - LastName contains `[` (to find contacts with Contact ID appended)
   - Email contains `.invalid`
3. Verify:
   - Contacts have Arlo Contact ID in LastName (e.g., "Smith [100]")
   - Emails have `.invalid` suffix
   - Contacts are assigned to correct Accounts

### Check Campaign Members

1. Go to **Campaigns** tab
2. Check these campaigns:
   - **NHM - Anxiety**
   - **NHM - Digital wellbeing**
   - **NHM - Self-care**
   - **NHM - Neurodiversity**
3. Verify:
   - Synced contacts are added as Campaign Members
   - Status is "Responded"

---

## Step 4: Verify Email Notifications

### Test Error Notification

To test email notifications, you can temporarily break the sync:

1. **Option 1**: Remove/clear Custom Settings
2. **Option 2**: Use invalid credentials
3. Run the sync
4. Check email inboxes:
   - `patrisha@redux.nz`
   - `lifeeducation@redux.nz`

### Expected Email Content:
- Subject: "Arlo Event Registration Sync - Error Notification"
- Error details
- Processed/Successful/Failed counts
- Link to log record

---

## Step 5: Test Scheduled Job

### Schedule the Job

1. In Developer Console, execute:

```apex
// Schedule the job to run daily at 1 AM
ArloEventRegistrationSyncScheduled scheduler = new ArloEventRegistrationSyncScheduled();
String cronExpression = '0 0 1 * * ?'; // 1 AM daily
String jobId = System.schedule('Arlo Event Registration Sync - Daily', cronExpression, scheduler);
System.debug('Scheduled job ID: ' + jobId);
```

### Verify Scheduled Job

1. Go to **Setup** → **Scheduled Jobs** (or **Apex Jobs**)
2. Look for: **"Arlo Event Registration Sync - Daily"**
3. Check:
   - **Status**: "Waiting" or "Processing"
   - **Next Scheduled Run**: Should show next 1 AM
   - **Frequency**: Daily

### Test Scheduled Job Immediately (Optional)

To test the scheduled job without waiting until 1 AM:

```apex
// Test the scheduled job immediately
ArloEventRegistrationSyncScheduled scheduler = new ArloEventRegistrationSyncScheduled();
SchedulableContext ctx = null; // Can be null for testing
scheduler.execute(ctx);
```

---

## Step 6: Test Single Contact Sync (Optional)

```apex
// Test syncing a single contact
try {
    ArloContactSync.syncSingleContact(
        '107',  // Arlo Contact ID
        null,   // Use Custom Settings
        null    // Use Custom Settings
    );
    System.debug('Single contact sync completed');
} catch (Exception e) {
    System.debug('Error: ' + e.getMessage());
}
```

---

## Expected Results

### Successful Sync:
- **Status**: "Success" or "Warning" (if some failed)
- **Records Processed**: Total registrations processed
- **Records Successful**: Unique contacts synced (should match Contact count)
- **Records Failed**: Contacts that couldn't be synced
- **Contacts Created/Updated**: Check Contacts tab
- **Campaign Members Added**: Check Campaigns

### Common Issues:

1. **"Arlo Credentials not configured"**
   - **Solution**: Set up Custom Settings (Step 1)

2. **"No events found"**
   - **Solution**: Check if events exist in Arlo API

3. **"Account not found"**
   - **Solution**: Verify Account `AccountNumber` matches Arlo `CodePrimary`

4. **"Email consent is false"**
   - **Expected**: Contacts without email consent are skipped (this is correct behavior)

---

## Quick Test Checklist

- [ ] Custom Settings configured
- [ ] Sync runs without errors
- [ ] Log record created with correct status
- [ ] Contacts created/updated in Salesforce
- [ ] Contact IDs appended to LastName
- [ ] Email has `.invalid` suffix
- [ ] Campaign Members added to correct campaigns
- [ ] Email notification sent on errors (if any)
- [ ] Scheduled job can be created

---

## Troubleshooting

### View Debug Logs:
1. **Setup** → **Debug Logs**
2. Filter by your user
3. Check for errors or warnings

### Check Integration Logs:
1. **Arlo Integration Logs** tab
2. Sort by **Created Date** (newest first)
3. Review **Status** and **Message** fields

### Verify Custom Settings:
```apex
// Check Custom Settings in Developer Console
Arlo_Credentials__c creds = Arlo_Credentials__c.getOrgDefaults();
System.debug('Username: ' + creds.Username__c);
System.debug('Password: ' + (creds.Password__c != null ? '***SET***' : 'NOT SET'));
```

---

**Last Updated**: 2025-01-XX  
**Version**: 1.0


