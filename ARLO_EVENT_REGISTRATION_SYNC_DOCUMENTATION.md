# Arlo Event Registration Sync Documentation

## Overview

The Arlo Event Registration Sync system automatically synchronizes contacts from Arlo events and registrations to Salesforce. After syncing contacts, the system automatically adds them to appropriate Campaigns (Contact Groups) based on the event name, enabling targeted marketing and communication.

### Key Features

- **Event Processing**: Fetches all events from Arlo API with pagination support
- **Event Filtering**: Only processes events where Code does NOT start with 'CONF'
- **Registration Processing**: Retrieves all registrations for qualifying events
- **Contact Sync**: Syncs contacts to Salesforce if their Account exists
- **Campaign Assignment**: Automatically adds contacts to campaigns based on event name keywords
- **Duplicate Prevention**: Prevents duplicate campaign memberships
- **Comprehensive Logging**: Tracks all operations in `Arlo_Integration_Log__c`

## Architecture

### Components

#### 1. Apex Classes

**`ArloEventRegistrationSync`**
- Main class for event and registration synchronization
- Handles event fetching, filtering, registration processing, and campaign assignment
- Location: `metadata/unpackaged/classes/ArloEventRegistrationSync.cls`

**`ArloContactSync`** (Dependency)
- Provides contact fetching and syncing functionality
- Methods used:
  - `getSingleArloContactStatic()`: Fetches contact details from Arlo
  - `syncContactsToSalesforceStatic()`: Upserts contacts to Salesforce
- Location: `metadata/unpackaged/classes/ArloContactSync.cls`

#### 2. Custom Objects

**`Arlo_Integration_Log__c`**
- Tracks all sync operations
- Fields:
  - `Operation_Type__c`: Type of operation (e.g., "Event Registration Sync")
  - `Status__c`: Status (Success, Error, In Progress, Warning)
  - `Arlo_Contact_ID__c`: Arlo Contact ID
  - `Arlo_Organization_ID__c`: Arlo Organization ID
  - `Salesforce_Contact__c`: Lookup to Salesforce Contact
  - `Message__c`: Detailed message or error description
  - `Records_Processed__c`: Count of records processed
  - `Records_Successful__c`: Count of successful records
  - `Records_Failed__c`: Count of failed records
  - `API_Endpoint__c`: API endpoint called
  - `HTTP_Status_Code__c`: HTTP status code

#### 3. Standard Objects

**`Contact`**
- Standard Salesforce Contact object
- Custom field used: `Arlo_Contact_UUID__c` (stores Arlo Contact ID for matching)

**`Account`**
- Standard Salesforce Account object
- Field used: `AccountNumber` (matched against Arlo `CodePrimary`)

**`Campaign`**
- Standard Salesforce Campaign object (used as Contact Groups)
- Campaigns used:
  - `NHM - Anxiety`
  - `NHM - Digital wellbeing`
  - `NHM - Self-care`
  - `NHM - Neurodiversity`

**`CampaignMember`**
- Standard Salesforce CampaignMember object
- Links Contacts to Campaigns
- Status set to "Responded" for synced contacts

## How It Works

### Process Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Get All Event Links (with pagination)                    │
│    Endpoint: /resources/events/                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. For Each Event:                                           │
│    - Fetch event details                                     │
│    - Check if Code starts with 'CONF' → SKIP if yes         │
│    - If Code does NOT start with 'CONF' → continue           │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Get All Registrations for Event                           │
│    Endpoint: /resources/events/{eventId}/registrations       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. For Each Registration:                                   │
│    - Get contact ID from registration                        │
│    - Fetch contact details from Arlo                         │
│    - Get organisation CodePrimary                           │
│    - Check if Account exists in Salesforce                   │
│    - Store contact + event name in wrapper                   │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Sync All Contacts to Salesforce (DML)                     │
│    - Group contacts by Account                               │
│    - Upsert contacts using ArloContactSync                  │
│    - Match synced contacts back to event wrappers           │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Add Contacts to Campaigns (DML)                          │
│    - Map event name to campaign name (keyword matching)      │
│    - Check for existing campaign memberships                 │
│    - Create CampaignMember records                           │
└─────────────────────────────────────────────────────────────┘
```

### Detailed Steps

#### Step 1: Fetch All Events

The system calls the Arlo API endpoint `/resources/events/` to get a list of all events. The response contains links to individual events:

```xml
<Events>
    <Link rel="Event" href="https://.../resources/events/20/"/>
    <Link rel="Event" href="https://.../resources/events/21/"/>
    ...
    <Link rel="next" href="https://.../resources/events/?skip=100"/>
</Events>
```

The system handles pagination by following "next" links until all events are retrieved.

#### Step 2: Process Each Event

For each event link:
1. Extract event ID from the link
2. Fetch event details from `/resources/events/{eventId}/`
3. Extract `Code` and `Name` fields from the event XML
4. **Filter**: Skip events where `Code` starts with 'CONF'
5. Continue processing only qualifying events

#### Step 3: Get Registrations

For each qualifying event:
1. Call `/resources/events/{eventId}/registrations` to get registration links
2. Process each registration link

#### Step 4: Process Each Registration

For each registration:
1. Extract registration ID from link
2. Fetch registration details from `/resources/registrations/{registrationId}/`
3. Extract contact link from registration XML
4. Extract contact ID from contact link
5. Fetch contact details using `ArloContactSync.getSingleArloContactStatic()`
6. Get organisation `CodePrimary` from Arlo
7. Check if Salesforce Account exists with matching `AccountNumber`
8. If Account exists, store contact + event name in `ContactEventWrapper`

#### Step 5: Sync Contacts to Salesforce

1. Group contacts by Account to optimize DML operations
2. Call `ArloContactSync.syncContactsToSalesforceStatic()` to upsert contacts
3. Query synced contacts to get Salesforce Contact IDs
4. Map synced contacts back to their event wrappers using:
   - Primary: `Arlo_Contact_UUID__c` field
   - Fallback: Email address (case-insensitive)

#### Step 6: Add Contacts to Campaigns

1. Query campaigns: `NHM - Anxiety`, `NHM - Digital wellbeing`, `NHM - Self-care`, `NHM - Neurodiversity`
2. For each synced contact:
   - Find its event wrapper using Arlo Contact UUID or Email
   - Extract event name from wrapper
   - Map event name to campaign name using keyword matching
   - If match found, add to `contactToCampaignMap`
3. Check for existing CampaignMember records to avoid duplicates
4. Create new CampaignMember records with Status = "Responded"

## Event to Campaign Mapping

The system uses keyword matching to map event names to campaigns. The matching is case-insensitive and checks for the following keywords:

| Event Name Contains | Campaign Name |
|-------------------|---------------|
| "Anxiety" | NHM - Anxiety |
| "Digital wellbeing" or "Digital well-being" | NHM - Digital wellbeing |
| "Self-care" or "Selfcare" or "Self care" | NHM - Self-care |
| "Neurodiversity" or "Neuro-diversity" | NHM - Neurodiversity |

### Mapping Logic

The `getCampaignNameForEvent()` method:
1. Converts event name to uppercase
2. Checks for keywords in order of specificity
3. Returns the corresponding campaign name if a match is found
4. Returns `null` if no match is found

### Example

**Event Name**: "Nurturing Healthy Minds - Anxiety"
- Contains keyword: "ANXIETY"
- Mapped to: "NHM - Anxiety"
- Contact added to: "NHM - Anxiety" campaign

**Event Name**: "Digital Wellbeing Workshop"
- Contains keyword: "DIGITAL WELLBEING"
- Mapped to: "NHM - Digital wellbeing"
- Contact added to: "NHM - Digital wellbeing" campaign

## Usage

### Running the Sync

Execute the sync from the Developer Console:

```apex
ArloEventRegistrationSync.syncContactsFromEvents(
    'lizzie.barnett@lifeeducation.org.nz', 
    'YellowArlo123!'
);
```

### Parameters

- `username`: Arlo API username (Basic Authentication)
- `password`: Arlo API password (Basic Authentication)

### Expected Behavior

1. **Logging**: A log record is created in `Arlo_Integration_Log__c` with status "In Progress"
2. **Processing**: Events are fetched and processed
3. **Filtering**: Events with Code starting with 'CONF' are skipped
4. **Contact Sync**: Contacts are synced to Salesforce if their Account exists
5. **Campaign Assignment**: Contacts are added to appropriate campaigns based on event names
6. **Completion**: Log record is updated with final status and counts

## API Endpoints Used

### Arlo API Base URL
```
https://lifeeducationtrust.arlo.co/api/2012-02-01/auth
```

### Endpoints

1. **Get All Events** (with pagination)
   - `GET /resources/events/`
   - Returns: List of event links

2. **Get Event Details**
   - `GET /resources/events/{eventId}/`
   - Returns: Event details including `Code` and `Name`

3. **Get Event Registrations**
   - `GET /resources/events/{eventId}/registrations`
   - Returns: List of registration links

4. **Get Registration Details**
   - `GET /resources/registrations/{registrationId}/`
   - Returns: Registration details including contact link

5. **Get Contact Details** (via ArloContactSync)
   - `GET /resources/contacts/{contactId}/`
   - Returns: Contact details

6. **Get Contact Employment**
   - `GET /resources/contacts/{contactId}/employment`
   - Returns: Employment details including organisation ID

7. **Get Organisation Details**
   - `GET /resources/organisations/{organisationId}/`
   - Returns: Organisation details including `CodePrimary`

## Authentication

The system uses **Basic Authentication** for all Arlo API calls:
- Username and password are provided as method parameters
- Credentials are Base64 encoded and sent in the `Authorization` header
- Format: `Basic {base64(username:password)}`

## Error Handling

### Exception Handling

The system includes comprehensive error handling:

1. **Event Processing Errors**: Individual event processing errors are caught and logged, but don't stop the entire sync
2. **Registration Processing Errors**: Individual registration errors are caught and logged
3. **Contact Sync Errors**: Errors during contact sync are caught and logged
4. **Campaign Assignment Errors**: Campaign assignment errors are logged but don't stop the sync (non-critical)

### Error Logging

All errors are logged in `Arlo_Integration_Log__c` with:
- Status: "Error"
- Message: Detailed error description
- Records_Processed: Count of records processed before error
- Records_Successful: Count of successful records
- Records_Failed: Count of failed records

### Common Errors

1. **Account Not Found**: Contact's organisation `CodePrimary` doesn't match any Salesforce Account `AccountNumber`
   - Action: Contact is skipped, error logged
   
2. **CodePrimary Not Found**: Organisation doesn't have a `CodePrimary` value
   - Action: Contact is skipped, warning logged
   
3. **Campaign Not Found**: Campaign with expected name doesn't exist in Salesforce
   - Action: Campaign assignment is skipped, warning logged
   
4. **Duplicate Campaign Member**: Contact is already a member of the campaign
   - Action: Duplicate is prevented, no error

## Logging

### Log Record Creation

A log record is created at the start of the sync with:
- `Operation_Type__c`: "Event Registration Sync"
- `Status__c`: "In Progress"
- `API_Endpoint__c`: `/resources/events/`
- `Message__c`: Initial status message

### Log Record Updates

The log record is updated at the end of the sync with:
- `Status__c`: "Success" or "Error"
- `Message__c`: Final status message with counts
- `Records_Processed__c`: Total contacts processed
- `Records_Successful__c`: Total contacts successfully synced
- `Records_Failed__c`: Total contacts that failed

### Debug Logging

The system includes extensive debug logging:
- Event processing progress
- Registration processing progress
- Contact matching and syncing
- Campaign assignment
- Error details

## Data Flow

### Contact Data Mapping

| Arlo Field | Salesforce Field | Notes |
|-----------|------------------|-------|
| `ContactID` / `UniqueIdentifier` | `Arlo_Contact_UUID__c` | Used for matching |
| `FirstName` | `FirstName` | Direct mapping |
| `LastName` | `LastName` | Direct mapping |
| `Email` | `Email` | Direct mapping |
| `PhoneMobile` / `MobileNumber` | `Mobile` | Direct mapping |
| Organisation `CodePrimary` | Account `AccountNumber` | Used for Account lookup |

### Account Matching

1. Get contact's employment data from Arlo
2. Extract organisation ID from employment
3. Fetch organisation details to get `CodePrimary`
4. Query Salesforce Account where `AccountNumber = CodePrimary`
5. If Account found, use it as the contact's Account
6. If Account not found, skip the contact

## Limitations and Considerations

### Governor Limits

1. **Callout Limit**: 100 callouts per transaction
   - **Impact**: If processing many events/registrations, may hit limit
   - **Mitigation**: Consider implementing Queueable Apex for bulk processing

2. **DML Limit**: 150 DML statements per transaction
   - **Impact**: Large batches may hit limit
   - **Mitigation**: Batch operations are used where possible

3. **SOQL Limit**: 100 SOQL queries per transaction
   - **Impact**: Multiple queries for campaigns, contacts, accounts
   - **Mitigation**: Queries are optimized and cached where possible

### Data Considerations

1. **Event Filtering**: Only events where Code does NOT start with 'CONF' are processed
2. **Account Requirement**: Contacts are only synced if their Account exists in Salesforce
3. **Campaign Matching**: Event name must contain specific keywords to map to campaigns
4. **Duplicate Prevention**: Existing CampaignMembers are checked to prevent duplicates

### Performance Considerations

1. **Pagination**: Event fetching handles pagination automatically
2. **Batch Processing**: Contacts are grouped by Account for efficient DML
3. **Query Optimization**: Campaigns and existing members are queried once per sync

## Troubleshooting

### No Contacts Synced

**Possible Causes**:
1. All events have Code starting with 'CONF' (filtered out)
2. Contacts' Accounts don't exist in Salesforce
3. Organisation `CodePrimary` not found or doesn't match `AccountNumber`

**Solution**:
- Check log records for detailed messages
- Verify Account records exist with correct `AccountNumber` values
- Check Arlo organisation data for `CodePrimary` values

### Contacts Not Added to Campaigns

**Possible Causes**:
1. Event name doesn't contain matching keywords
2. Campaign doesn't exist in Salesforce
3. Contact couldn't be matched back to event wrapper

**Solution**:
- Check event names in Arlo
- Verify campaigns exist: `NHM - Anxiety`, `NHM - Digital wellbeing`, `NHM - Self-care`, `NHM - Neurodiversity`
- Check debug logs for matching details
- Verify `Arlo_Contact_UUID__c` field is populated on Contact records

### Sync Takes Too Long

**Possible Causes**:
1. Large number of events/registrations
2. Network latency with Arlo API
3. Approaching governor limits

**Solution**:
- Check log records for processing counts
- Consider implementing Queueable Apex for bulk processing
- Monitor debug logs for performance bottlenecks

## Future Enhancements

### Potential Improvements

1. **Queueable Implementation**: Process events/registrations in batches to avoid governor limits
2. **Scheduled Execution**: Automate sync on a schedule
3. **Enhanced Mapping**: Support additional event types and campaigns
4. **Error Notifications**: Send notifications for critical errors
5. **Retry Logic**: Automatic retry for failed operations
6. **Incremental Sync**: Only process new/updated events since last sync

## Related Documentation

- [Arlo Contact Sync Documentation](./ARLO_CONTACT_SYNC_DOCUMENTATION.md)
- [Arlo API Documentation](https://developer.arlo.co/doc/api/2012-02-01/auth/resources/integrationdata)

## Support

For issues or questions:
1. Check `Arlo_Integration_Log__c` records for error details
2. Review debug logs for detailed processing information
3. Verify Arlo API credentials and connectivity
4. Ensure required campaigns exist in Salesforce

---

**Last Updated**: 2025-01-XX  
**Version**: 1.0  
**Author**: System Generated


