# Arlo Sync System - Components Summary

## Overview

This document provides a quick reference of all components used in the Arlo synchronization system, including both Contact Sync and Event Registration Sync functionality.

## System Components

### Apex Classes

#### 1. ArloContactSync.cls
**Purpose**: Core class for syncing contacts from Arlo to Salesforce

**Key Methods**:
- `syncSingleContact()`: Sync a single contact by Arlo Contact ID
- `syncAllContacts()`: Sync all contacts from Arlo (with pagination)
- `getSingleArloContactStatic()`: Fetch contact details from Arlo API
- `syncContactsToSalesforceStatic()`: Upsert contacts to Salesforce
- `getOrganisationIdFromEmployment()`: Get organisation ID from contact employment
- `getOrganisationCodePrimary()`: Get CodePrimary from organisation
- `getSalesforceAccountByNumber()`: Find Salesforce Account by AccountNumber

**Dependencies**: None

**Location**: `metadata/unpackaged/classes/ArloContactSync.cls`

---

#### 2. ArloContactSyncQueueable.cls
**Purpose**: Queueable class for bulk processing contacts to avoid governor limits

**Key Features**:
- Processes contacts in batches
- Chains jobs to handle large volumes
- Tracks progress across chained jobs
- Updates log records with progress

**Dependencies**: `ArloContactSync.cls`

**Location**: `metadata/unpackaged/classes/ArloContactSyncQueueable.cls`

---

#### 3. ArloEventRegistrationSync.cls
**Purpose**: Syncs contacts from Arlo events and registrations using **Contact-First Approach**, then adds them to campaigns

**Key Methods**:
- `syncContactsFromEvents()`: Main entry point - gets all contacts, then processes their registrations
- `getAllContactLinksStatic()`: Fetch all contact links with pagination
- `getContactRegistrationsStatic()`: Get all registrations for a contact
- `getEventIdFromRegistrationStatic()`: Extract event ID from registration
- `getEventDetailsStatic()`: Get details of a single event (checks if contains "NHM")
- `checkRegistrationEmailConsentStatic()`: Check email consent for a registration
- `getCampaignNameForEvent()`: Map event name to campaign name
- `addContactsToCampaignsStatic()`: Add contacts to campaigns based on event names
- `processContactsBatch()`: Process contacts in batches with deferred registration handling

**Key Features**:
- **Contact-First Flow**: Gets all contacts, then processes their registrations
- **NHM Event Filtering**: Only processes events containing "NHM" (excludes CONF events)
- **Email Consent Checking**: Validates consent for each registration
- **Contact Creation**: Creates contacts in Salesforce if they don't exist
- **Deferred Processing**: Tracks and retries unprocessed registrations when callout limits are reached

**Dependencies**: `ArloContactSync.cls`

**Location**: `metadata/unpackaged/classes/ArloEventRegistrationSync.cls`

---

#### 4. ArloContactRegistrationSyncQueueable.cls
**Purpose**: Queueable class for contact/registration sync batch processing

**Key Features**:
- Processes contacts in batches to avoid governor limits
- Handles deferred registrations from previous batches
- Chains jobs for large volumes
- Tracks progress across chained jobs

**Dependencies**: `ArloEventRegistrationSync.cls`

**Location**: `metadata/unpackaged/classes/ArloContactRegistrationSyncQueueable.cls`

---

### Custom Objects

#### 1. Arlo_Integration_Log__c
**Purpose**: Tracks all Arlo integration operations

**Fields**:
- `Log_Name__c` (Auto Number): Unique log identifier
- `Operation_Type__c` (Picklist): Type of operation
  - Values: "Single Contact Sync", "Organization Contacts Sync", "API Call", "Event Registration Sync"
- `Status__c` (Picklist): Operation status
  - Values: "Success", "Error", "In Progress", "Warning"
- `Arlo_Contact_ID__c` (Text, 50): Arlo Contact ID
- `Arlo_Organization_ID__c` (Text, 50): Arlo Organization ID
- `Salesforce_Contact__c` (Lookup to Contact): Related Salesforce Contact
- `Message__c` (Long Text Area): Detailed message or error description
- `Records_Processed__c` (Number): Count of records processed
- `Records_Successful__c` (Number): Count of successful records
- `Records_Failed__c` (Number): Count of failed records
- `API_Endpoint__c` (Text, 255): API endpoint called
- `HTTP_Status_Code__c` (Text, 10): HTTP status code

**Location**: `metadata/unpackaged/objects/Arlo_Integration_Log__c/`

---

### Standard Objects Used

#### 1. Contact
**Purpose**: Stores synced contact information

**Custom Fields Used**:
- `Arlo_Contact_UUID__c`: Stores Arlo Contact ID for matching

**Standard Fields Used**:
- `FirstName`, `LastName`, `Email`, `Mobile`, `AccountId`

---

#### 2. Account
**Purpose**: Parent account for contacts

**Standard Fields Used**:
- `AccountNumber`: Matched against Arlo `CodePrimary`

---

#### 3. Campaign
**Purpose**: Contact Groups for event-based contacts

**Campaigns Used**:
- `NHM - Anxiety`
- `NHM - Digital wellbeing`
- `NHM - Self-care`
- `NHM - Neurodiversity`

---

#### 4. CampaignMember
**Purpose**: Links Contacts to Campaigns

**Fields Used**:
- `ContactId`: Reference to Contact
- `CampaignId`: Reference to Campaign
- `Status`: Set to "Responded" for synced contacts

---

## Data Flow Diagrams

### Contact Sync Flow

```
┌─────────────────────────────────────────────────────────┐
│ ArloContactSync.syncAllContacts()                        │
│ - Get all contact links from /resources/contacts/        │
│ - Handle pagination                                      │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ For each contact link:                                   │
│ - Call getSingleArloContactStatic()                      │
│   • Fetch contact details                                │
│   • Get employment → organisation ID                     │
│   • Get organisation → CodePrimary                       │
│   • Check if Account exists                              │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ ArloContactSyncQueueable (if > 100 contacts)            │
│ - Process in batches of 50                              │
│ - Chain jobs for remaining contacts                      │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ syncContactsToSalesforceStatic()                         │
│ - Upsert contacts to Salesforce                          │
│ - Match by Arlo_Contact_UUID__c or Email                │
└─────────────────────────────────────────────────────────┘
```

### Event Registration Sync Flow

```
┌─────────────────────────────────────────────────────────┐
│ ArloEventRegistrationSync.syncContactsFromEvents()      │
│ - Get all event links from /resources/events/            │
│ - Handle pagination                                      │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ For each event:                                          │
│ - Get event details                                      │
│ - Check if Code starts with 'CONF' → SKIP              │
│ - If Code does NOT start with 'CONF' → continue        │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ For each registration:                                   │
│ - Get contact ID from registration                       │
│ - Call getSingleArloContactStatic()                      │
│ - Store contact + event name in wrapper                 │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ syncContactsToSalesforceStatic()                         │
│ - Upsert contacts to Salesforce                          │
│ - Match synced contacts back to event wrappers          │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ addContactsToCampaigns()                                 │
│ - Map event name to campaign (keyword matching)          │
│ - Create CampaignMember records                         │
└─────────────────────────────────────────────────────────┘
```

## API Endpoints

### Arlo API Base URL
```
https://lifeeducationtrust.arlo.co/api/2012-02-01/auth
```

### Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/resources/contacts/` | GET | Get all contact links (with pagination) |
| `/resources/contacts/{id}/` | GET | Get single contact details |
| `/resources/contacts/{id}/employment` | GET | Get contact employment data |
| `/resources/organisations/{id}/` | GET | Get organisation details (CodePrimary) |
| `/resources/events/` | GET | Get all event links (with pagination) |
| `/resources/events/{id}/` | GET | Get single event details |
| `/resources/events/{id}/registrations` | GET | Get registrations for an event |
| `/resources/registrations/{id}/` | GET | Get single registration details |

## Authentication

**Method**: Basic Authentication

**Format**: 
```
Authorization: Basic {base64(username:password)}
```

**Credentials**: Provided as method parameters (not stored in code)

## Key Data Mappings

### Arlo → Salesforce Contact

| Arlo Field | Salesforce Field | Notes |
|-----------|------------------|-------|
| `ContactID` / `UniqueIdentifier` | `Arlo_Contact_UUID__c` | Used for matching |
| `FirstName` | `FirstName` | Direct mapping |
| `LastName` | `LastName` | Direct mapping |
| `Email` | `Email` | Direct mapping |
| `PhoneMobile` / `MobileNumber` | `Mobile` | Direct mapping |

### Arlo → Salesforce Account

| Arlo Field | Salesforce Field | Notes |
|-----------|------------------|-------|
| Organisation `CodePrimary` | Account `AccountNumber` | Used for Account lookup |

### Event → Campaign Mapping

| Event Name Contains | Campaign Name |
|-------------------|---------------|
| "Anxiety" | NHM - Anxiety |
| "Digital wellbeing" | NHM - Digital wellbeing |
| "Self-care" / "Selfcare" | NHM - Self-care |
| "Neurodiversity" | NHM - Neurodiversity |

## Usage Examples

### Contact Sync

```apex
// Sync all contacts
ArloContactSync.syncAllContacts(
    'lizzie.barnett@lifeeducation.org.nz', 
    'YellowArlo123!'
);

// Sync single contact
ArloContactSync.syncSingleContact(
    '107',  // Arlo Contact ID
    'lizzie.barnett@lifeeducation.org.nz', 
    'YellowArlo123!'
);
```

### Event Registration Sync

```apex
// Sync contacts from events and registrations
ArloEventRegistrationSync.syncContactsFromEvents(
    'lizzie.barnett@lifeeducation.org.nz', 
    'YellowArlo123!'
);
```

## Error Handling

### Common Errors

1. **Account Not Found**
   - **Cause**: Contact's organisation `CodePrimary` doesn't match any Salesforce Account `AccountNumber`
   - **Action**: Contact is skipped, logged in `Arlo_Integration_Log__c`

2. **CodePrimary Not Found**
   - **Cause**: Organisation doesn't have a `CodePrimary` value
   - **Action**: Contact is skipped, warning logged

3. **Campaign Not Found**
   - **Cause**: Campaign with expected name doesn't exist
   - **Action**: Campaign assignment skipped, warning logged

4. **Duplicate Prevention**
   - **Cause**: Contact already exists or is already a campaign member
   - **Action**: Duplicate prevented, no error

## Logging

All operations are logged in `Arlo_Integration_Log__c` with:
- Operation type
- Status (Success, Error, In Progress, Warning)
- Record counts (Processed, Successful, Failed)
- Error messages
- API endpoints and HTTP status codes

## Governor Limits Considerations

### Callout Limit
- **Limit**: 100 callouts per transaction
- **Mitigation**: `ArloContactSyncQueueable` processes in batches

### DML Limit
- **Limit**: 150 DML statements per transaction
- **Mitigation**: Batch operations used where possible

### SOQL Limit
- **Limit**: 100 SOQL queries per transaction
- **Mitigation**: Queries optimized and cached

## Testing

### Test Classes

1. **ArloContactSyncTest** (if exists)
   - Tests contact sync functionality
   - Verifies Account matching
   - Tests error handling

2. **ArloEventRegistrationSyncTest** (if exists)
   - Tests event/registration sync
   - Verifies campaign assignment
   - Tests event filtering

## Related Documentation

- [Arlo Contact Sync Documentation](./ARLO_CONTACT_SYNC_DOCUMENTATION.md)
- [Arlo Event Registration Sync Documentation](./ARLO_EVENT_REGISTRATION_SYNC_DOCUMENTATION.md)
- [Arlo API Documentation](https://developer.arlo.co/doc/api/2012-02-01/auth/resources/integrationdata)

## Maintenance

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

**Last Updated**: 2025-01-XX  
**Version**: 1.0  
**Author**: System Generated


