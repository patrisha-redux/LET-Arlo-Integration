# Arlo Integration Setup Instructions

## 1. Custom Settings Configuration

### Arlo Credentials Custom Setting

The integration now uses a Hierarchy Custom Setting to store Arlo API credentials.

**Setup Steps:**
1. Go to **Setup** → **Custom Settings**
2. Find **Arlo Credentials** (or create it if it doesn't exist)
3. Click **Manage** → **New** (or edit the default org-level record)
4. Enter the following:
   - **Username**: `lizzie.barnett@lifeeducation.org.nz`
   - **Password**: `YellowArlo123!`
5. Click **Save**

**Note**: The Custom Setting is a Hierarchy type, so you can set org-level defaults or user/profile-specific values.

---

## 2. Email Notifications

Email notifications are automatically sent when:
- The sync encounters an error (Status = "Error")
- The sync completes with failures (Status = "Warning" or "Error")

**Recipients:**
- `patrisha@redux.nz`
- `lifeeducation@redux.nz`

**Email Content:**
- Error details
- Processed/Successful/Failed counts
- Link to the Arlo Integration Log record

---

## 3. Scheduled Job Setup

The integration can be scheduled to run automatically at 1 AM daily.

### To Schedule the Job:

**Option 1: Via Developer Console**
```apex
// Schedule the job to run daily at 1 AM
ArloEventRegistrationSyncScheduled scheduler = new ArloEventRegistrationSyncScheduled();
String cronExpression = '0 0 1 * * ?'; // 1 AM daily
System.schedule('Arlo Event Registration Sync - Daily', cronExpression, scheduler);
```

**Option 2: Via Setup UI**
1. Go to **Setup** → **Apex Classes**
2. Find **ArloEventRegistrationSyncScheduled**
3. Click **Schedule Apex**
4. Fill in:
   - **Job Name**: `Arlo Event Registration Sync - Daily`
   - **Frequency**: `Daily`
   - **Start Time**: `1:00 AM`
   - **End Date**: (optional)
5. Click **Save**

### CRON Expression Breakdown:
- `0 0 1 * * ?` = Every day at 1:00 AM
- Format: `Seconds Minutes Hours Day_of_month Month Day_of_week Year(optional)`

### To View Scheduled Jobs:
- Go to **Setup** → **Scheduled Jobs** (or **Apex Jobs**)

### To Unschedule:
- Go to **Setup** → **Scheduled Jobs**
- Find the job and click **Delete**

---

## 4. Usage

### Manual Execution (with Custom Settings):
```apex
// Uses credentials from Custom Settings
ArloEventRegistrationSync.syncContactsFromEvents(null, null);
```

### Manual Execution (with explicit credentials):
```apex
// Override Custom Settings with explicit credentials
ArloEventRegistrationSync.syncContactsFromEvents('username@example.com', 'password123');
```

### Contact Sync (with Custom Settings):
```apex
// Uses credentials from Custom Settings
ArloContactSync.syncAllContacts(null, null);
```

### Quick Test in Developer Console:
1. Open **Developer Console** → **Debug** → **Execute Anonymous**
2. Paste and run:
```apex
ArloEventRegistrationSync.syncContactsFromEvents(null, null);
```
3. Check **Arlo Integration Logs** tab for results
4. Check **Contacts** tab for synced contacts

---

## 5. Monitoring

### Check Logs:
- Go to **Arlo Integration Logs** tab
- Filter by:
  - **Operation Type**: "Event Registration Sync"
  - **Status**: "Success", "Error", "Warning", "In Progress"

### Check Scheduled Jobs:
- Go to **Setup** → **Scheduled Jobs**
- Look for "Arlo Event Registration Sync - Daily"

### Check Email Notifications:
- Monitor `patrisha@redux.nz` and `lifeeducation@redux.nz` inboxes
- Emails are sent when errors occur or when sync completes with failures

---

## 6. Troubleshooting

### Custom Settings Not Found:
- Error: "Arlo Credentials not configured"
- **Solution**: Create and populate the Arlo_Credentials__c Custom Setting (see section 1)

### Scheduled Job Not Running:
- Check **Setup** → **Scheduled Jobs** to verify the job is scheduled
- Check debug logs for errors
- Verify Custom Settings are configured

### Email Notifications Not Received:
- Check email deliverability settings in Salesforce
- Verify email addresses are correct
- Check spam/junk folders

---

**Last Updated**: 2025-01-XX  
**Version**: 2.0

