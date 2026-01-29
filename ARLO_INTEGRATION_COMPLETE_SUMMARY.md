# Arlo Integration System - Complete Process Summary

## Overview

The Arlo Integration System is a comprehensive Salesforce-Apex solution that synchronizes contact data from the Arlo API (https://lifeeducationtrust.arlo.co) to Salesforce. 

**Note**: The main process is **Event Registration Sync**, which syncs contacts from Arlo events/registrations and assigns them to campaigns. The separate "Contact Sync" process is only needed if you want to sync ALL contacts from Arlo (including those who haven't registered for events).

### Main Process: Event Registration Sync
- Syncs contacts who have registered for events
- Automatically assigns them to campaigns based on event names
- **This is the primary process you should use**

### Optional Process: Contact Sync
- Syncs ALL contacts from Arlo (regardless of event registration)
- Use this only if you need contacts who haven't registered for any events

---

## System Architecture

### Core Components

#### Apex Classes

1. **`ArloContactSync.cls`** (1,355 lines)
   - Main class for contact synchronization
   - Handles API calls, XML parsing, and Salesforce DML operations
   - Methods:
     - `syncSingleContact()`: Sync one contact by ID
     - `syncAllContacts()`: Sync all contacts with pagination
     - `getSingleArloContact()`: Fetch contact from Arlo API
     - `syncContactsToSalesforce()`: Upsert contacts to Salesforce
     - `getOrganisationIdFromEmployment()`: Get organisation ID
     - `getOrganisationCodePrimary()`: Get CodePrimary for Account matching

2. **`ArloContactSyncQueueable.cls`** (157 lines)
   - Queueable class for bulk processing
   - Processes contacts in batches to avoid governor limits
   - Chains jobs for large volumes

3. **`ArloEventRegistrationSync.cls`** (4,620 lines)
   - Syncs contacts from events and registrations using **Contact-First Approach**
   - Gets all contacts first, then processes their registrations
   - Filters events (only processes events containing "NHM")
   - Checks email consent for each registration
   - Creates contacts in Salesforce if they don't exist
   - Assigns contacts to campaigns based on event names
   - Handles deferred registrations when callout limits are reached

4. **`ArloContactRegistrationSyncQueueable.cls`**
   - Queueable class for contact/registration sync
   - Processes contacts in batches to avoid governor limits
   - Handles deferred registrations from previous batches
   - Chains jobs for large volumes

#### Custom Objects

**`Arlo_Integration_Log__c`**
- Tracks all integration operations
- Fields: Status, Operation Type, Contact IDs, Record counts, Error messages, API endpoints

---

## Main Process: Event Registration Sync

**This is the primary process you should use.** It syncs contacts from Arlo events/registrations and automatically assigns them to campaigns.

### Purpose
Synchronize contacts from Arlo events and registrations, then automatically assign them to campaigns based on event names.

### Step-by-Step Process (Contact-First Approach)

```
1. GET /resources/contacts/
   └─> Returns list of contact links (with pagination)
   
2. For each contact:
   ├─> GET /resources/contacts/{id}/
   │   └─> Check if Status = "Active"
   │   └─> If NOT Active → SKIP contact
   │
   ├─> GET /resources/contacts/{id}/
   │   └─> Get contact details (UUID, Email) for Salesforce matching
   │
   └─> GET /resources/contacts/{id}/registrations/
       └─> Get all registration links for contact
       
3. For each registration:
   ├─> GET /resources/registrations/{id}/
   │   └─> Extract Event ID from registration
   │
   ├─> GET /resources/events/{eventId}/
   │   └─> Get event details (Name, Code)
   │   └─> Check if event Name or Code contains "NHM"
   │   └─> If NO → SKIP registration (excludes CONF events)
   │
   └─> GET /resources/registrations/{id}/customfields
       └─> Check email consent field: imhappytobeemailedaboutlifeeducationtrustnews
       └─> If false or not found → SKIP registration
       
4. Find or Create Salesforce Contact
   ├─> Find by UUID or Email
   ├─> If NOT found:
   │   ├─> GET /resources/contacts/{id}/ (full details)
   │   ├─> GET /resources/contacts/{id}/employment
   │   ├─> GET /resources/organisations/{orgId}/
   │   │   └─> Get CodePrimary
   │   └─> Create contact in Salesforce with correct Account
   └─> If found → Use existing contact
   
5. Add Contact to Campaign
   └─> Map event name to campaign name
   └─> Create CampaignMember record
   └─> Same logic as Contact Sync
   
6. Assign to Campaign
   ├─> Map event name to campaign using keywords:
   │   ├─> "Anxiety" → "NHM - Anxiety"
   │   ├─> "Digital wellbeing" → "NHM - Digital wellbeing"
   │   ├─> "Self-care" / "Selfcare" → "NHM - Self-care"
   │   └─> "Neurodiversity" → "NHM - Neurodiversity"
   │
   ├─> Create CampaignMember record
   └─> Prevent duplicates (check if already member)
```

### Key Features

- **Contact-First Approach**: Gets all contacts first, then processes their registrations
- **Event Filtering**: Only processes events where Name or Code contains "NHM" (excludes CONF events)
- **Email Consent Validation**: Checks `imhappytobeemailedaboutlifeeducationtrustnews` field for each registration
- **Contact Creation**: Creates contacts in Salesforce if they don't exist (with correct Account based on employment)
- **Campaign Assignment**: Automatically adds contacts to campaigns based on event name keywords
- **Duplicate Prevention**: Checks if contact is already a campaign member before adding
- **Deferred Processing**: Tracks and retries unprocessed registrations when callout limits are reached
- **Bulk Processing**: Uses Queueable for large volumes (processes contacts in batches, tracks callouts)

### Usage

```apex
// Sync contacts from events and registrations
ArloEventRegistrationSync.syncContactsFromEvents(
    'lizzie.barnett@lifeeducation.org.nz',
    'YellowArlo123!'
);
```

---

## Data Transformations

### Contact Data Mapping

| Arlo Field | Salesforce Field | Transformation |
|------------|-----------------|----------------|
| `ContactID` (numeric) | - | Extracted from link, appended to LastName |
| `UniqueIdentifier` (UUID) | `Arlo_Contact_UUID__c` | Used for matching existing contacts |
| `FirstName` | `FirstName` | Direct mapping |
| `LastName` | `LastName` | **Appended with `[numericContactId]`** (e.g., "Smith [100]") |
| `Email` | `Email` | **Appended with `.invalid`** (e.g., "john@example.com.invalid") |
| `PhoneMobile` / `MobileNumber` | `MobilePhone` | Direct mapping |
| `PhoneNumber` | `Phone` | Direct mapping |

### Account Matching

| Arlo Field | Salesforce Field | Purpose |
|------------|-----------------|---------|
| Organisation `CodePrimary` | Account `AccountNumber` | Used to find correct Account for contact |

### Event-to-Campaign Mapping

| Event Name Contains | Campaign Name |
|---------------------|---------------|
| "Anxiety" | NHM - Anxiety |
| "Digital wellbeing" | NHM - Digital wellbeing |
| "Self-care" / "Selfcare" | NHM - Self-care |
| "Neurodiversity" | NHM - Neurodiversity |

---

## Authentication

**Method**: Basic Authentication

**Format**:
```
Authorization: Basic {base64(username:password)}
```

**Credentials**: Passed as method parameters (not stored in code)

**API Base URL**: `https://lifeeducationtrust.arlo.co/api/2012-02-01/auth`

---

## API Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/resources/contacts/` | GET | Get all contact links (pagination) |
| `/resources/contacts/{id}/` | GET | Get single contact details |
| `/resources/contacts/{id}/employment` | GET | Get contact employment (organisation ID) |
| `/resources/organisations/{id}/` | GET | Get organisation details (CodePrimary) |
| `/resources/events/` | GET | Get all event links (pagination) |
| `/resources/events/{id}/` | GET | Get single event details |
| `/resources/events/{id}/registrations` | GET | Get registrations for event |
| `/resources/registrations/{id}/` | GET | Get single registration details |

---

## Error Handling

### Common Scenarios

1. **Account Not Found**
   - **Cause**: Contact's organisation `CodePrimary` doesn't match any Account `AccountNumber`
   - **Action**: Contact is skipped, warning logged in `Arlo_Integration_Log__c`
   - **Result**: Process continues with next contact

2. **CodePrimary Not Found**
   - **Cause**: Organisation doesn't have a `CodePrimary` value
   - **Action**: Contact is skipped, warning logged
   - **Result**: Process continues

3. **Campaign Not Found**
   - **Cause**: Campaign with expected name doesn't exist
   - **Action**: Campaign assignment skipped, warning logged
   - **Result**: Contact is still synced, just not added to campaign

4. **Duplicate Prevention**
   - **Cause**: Contact already exists or is already a campaign member
   - **Action**: Duplicate prevented, no error
   - **Result**: Existing record is updated (for contacts) or skipped (for campaign members)

---

## Logging

All operations are logged in `Arlo_Integration_Log__c` with:

- **Operation Type**: Single Contact Sync, Organization Contacts Sync, Event Registration Sync, API Call
- **Status**: Success, Error, In Progress, Warning
- **Record Counts**: Processed, Successful, Failed
- **Details**: Arlo Contact ID, Organisation ID, Salesforce Contact lookup, Error messages
- **API Info**: Endpoint called, HTTP status code

### Log Record Example

```
Operation Type: Event Registration Sync
Status: Success
Records Processed: 50
Records Successful: 48
Records Failed: 2
Message: Successfully synced 48 contacts from events
```

---

## Governor Limits & Performance

### Limits Addressed

1. **Callout Limit (100 per transaction)**
   - **Solution**: Queueable classes process in batches
   - **Contact Sync**: Processes 50 contacts per batch
   - **Event Sync**: Processes 3 events per batch, dynamically calculates max registrations

2. **DML Limit (150 per transaction)**
   - **Solution**: Batch operations (upsert, insert)
   - **Strategy**: All callouts first, then all DML operations

3. **SOQL Limit (100 per transaction)**
   - **Solution**: Queries optimized, Account lookups cached

### Performance Optimizations

- **Account Caching**: Maps `CodePrimary` to `AccountId` to avoid repeated queries
- **Batch Processing**: Processes records in batches to stay within limits
- **Separate Callouts and DML**: Prevents "uncommitted work pending" errors

---

## Recent Enhancements

### 1. Contact ID in LastName
- **Purpose**: Easy identification of synced contacts in Postman/Arlo
- **Format**: `LastName [numericContactId]`
- **Example**: "Smith [100]"
- **Extraction**: From link (`/contacts/100/`), Link XML element, or ContactID field

### 2. Email with ".invalid" Suffix
- **Purpose**: Prevent accidental emails to synced contacts
- **Format**: `email.invalid`
- **Example**: "john@example.com.invalid"
- **Matching**: Updated to handle both original and ".invalid" emails

---

## Usage Examples

### Developer Console

**Primary Usage (Recommended)**:
```apex
// Sync contacts from events and assign to campaigns
ArloEventRegistrationSync.syncContactsFromEvents(
    'lizzie.barnett@lifeeducation.org.nz',
    'YellowArlo123!'
);
```

**Optional Usage (Only if you need all contacts)**:
```apex
// Sync all contacts (including those without event registrations)
ArloContactSync.syncAllContacts(
    'lizzie.barnett@lifeeducation.org.nz',
    'YellowArlo123!'
);

// Sync single contact
ArloContactSync.syncSingleContact(
    '107',  // Numeric Contact ID
    'lizzie.barnett@lifeeducation.org.nz',
    'YellowArlo123!'
);
```

---

## Data Flow Summary

### Main Process: Event Registration Sync Flow
```
Arlo API → Fetch Events → Filter (skip CONF) → Get Registrations → 
Fetch Contacts → Get Employment → Get Organisation → 
Find Account → Upsert Contact → Assign to Campaign → Log Result
```

### Optional Process: Contact Sync Flow
```
Arlo API → Fetch Contacts → Get Employment → Get Organisation → 
Find Account → Upsert Contact → Log Result
```

---

## Maintenance & Monitoring

### Regular Tasks

1. **Monitor Logs**: Review `Arlo_Integration_Log__c` for errors
2. **Verify Campaigns**: Ensure all required campaigns exist
3. **Check Accounts**: Verify Account `AccountNumber` values match Arlo `CodePrimary`
4. **Review Performance**: Monitor execution times and governor limit usage

### Troubleshooting

1. Check `Arlo_Integration_Log__c` records for error details
2. Review debug logs for detailed processing information
3. Verify Arlo API credentials and connectivity
4. Ensure required campaigns and accounts exist

---

## Key Takeaways

✅ **Main Process**: Event Registration Sync handles contact syncing + campaign assignment  
✅ **Optional Process**: Contact Sync only needed for contacts without event registrations  
✅ **Automatic**: Fully automated sync processes  
✅ **Intelligent**: Automatically matches Accounts and assigns Campaigns  
✅ **Robust**: Handles errors gracefully, continues processing  
✅ **Scalable**: Uses Queueable for large volumes  
✅ **Traceable**: Comprehensive logging for all operations  
✅ **Safe**: Email ".invalid" suffix prevents accidental emails  
✅ **Identifiable**: Contact ID in LastName for easy tracking  

---

**Last Updated**: 2025-01-XX  
**Version**: 2.0  
**Deployed To**: `lifeeducation@redux.nz.arlo` (Sandbox)

