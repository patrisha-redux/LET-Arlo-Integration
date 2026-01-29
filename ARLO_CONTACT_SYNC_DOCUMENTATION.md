# Arlo Contact Sync Documentation

## Overview

The Arlo Contact Sync system automatically synchronizes contacts from the Arlo API to Salesforce. It fetches contact information from Arlo, determines the correct Salesforce Account based on the organisation's CodePrimary, and creates or updates Contact records in Salesforce.

## Key Features

- **Automatic Account Assignment**: Contacts are automatically assigned to the correct Salesforce Account based on their organisation's CodePrimary (mapped to AccountNumber)
- **Upsert Logic**: Existing contacts are updated, new contacts are created
- **Bulk Processing**: Handles large volumes of contacts using Queueable Apex to avoid governor limits
- **Custom Metadata Filtering**: Only syncs contacts whose AccountNumber is in the allowed list (Custom Metadata Type)
- **Comprehensive Logging**: All sync operations are logged in `Arlo_Integration_Log__c` custom object
- **Error Handling**: Gracefully handles missing data without stopping execution

## Architecture

### Components

1. **ArloContactSync.cls**: Main Apex class containing all sync logic
2. **ArloContactSyncQueueable.cls**: Queueable class for batch processing (handles 100+ callout limit)
3. **Arlo_Integration_Log__c**: Custom object for logging sync operations
4. **Arlo_Organisation__mdt**: Custom Metadata Type for allowed Account Numbers

### Data Flow

```
1. Fetch contact from Arlo API
   ↓
2. Fetch employment data to get Organisation ID
   ↓
3. Fetch organisation details to get CodePrimary
   ↓
4. Check if CodePrimary is in Custom Metadata (allowed list)
   ↓
5. Find Salesforce Account by AccountNumber = CodePrimary
   ↓
6. Upsert Contact to Salesforce
```

## Setup Requirements

### 1. Custom Metadata Type: Arlo_Organisation__mdt

Create a Custom Metadata Type with the following field:
- **Field Name**: `Account_Number__c`
- **Type**: Text
- **Length**: 50 (or as needed)

**Purpose**: This Custom Metadata Type acts as a whitelist. Only contacts whose parent Account's AccountNumber matches a value in this Custom Metadata will be synced.

**How to Use**:
1. Go to Setup → Custom Metadata Types
2. Create records in `Arlo_Organisation__mdt`
3. For each Account you want to allow syncing, add a record with the `Account_Number__c` field set to the Account's AccountNumber

### 2. Custom Object: Arlo_Integration_Log__c

The following fields are required:
- `Status__c` (Picklist): Success, Error, In Progress, Warning
- `Operation_Type__c` (Picklist): Single Contact Sync, Organization Contacts Sync, API Call
- `Arlo_Contact_ID__c` (Text): Arlo Contact ID
- `Arlo_Organization_ID__c` (Text): Arlo Organisation ID
- `Salesforce_Contact__c` (Lookup to Contact): Related Salesforce Contact
- `Message__c` (Long Text Area): Detailed message or error description
- `Records_Processed__c` (Number): Count of records processed
- `Records_Successful__c` (Number): Count of successful records
- `Records_Failed__c` (Number): Count of failed records
- `API_Endpoint__c` (Text): API endpoint called
- `HTTP_Status_Code__c` (Text): HTTP response status code

### 3. Custom Field on Contact

- `Arlo_Contact_UUID__c` (Text): Stores the Arlo Contact Unique Identifier for matching

### 4. Account Setup

Ensure that Salesforce Accounts have the `AccountNumber` field populated with the Arlo organisation's CodePrimary value.

## Usage

### Single Contact Sync

Sync a single contact by Arlo Contact ID:

```apex
ArloContactSync.syncSingleContact(
    '100',  // Arlo Contact ID
    'lizzie.barnett@lifeeducation.org.nz',  // Arlo username
    'YellowArlo123!'  // Arlo password
);
```

**What it does**:
1. Fetches contact 100 from Arlo
2. Gets employment data to find organisation ID
3. Gets organisation details to find CodePrimary
4. Finds Salesforce Account by AccountNumber = CodePrimary
5. Creates/updates the contact in Salesforce

### Bulk Contact Sync

Sync all contacts from Arlo:

```apex
ArloContactSync.syncAllContacts(
    'lizzie.barnett@lifeeducation.org.nz',  // Arlo username
    'YellowArlo123!'  // Arlo password
);
```

**What it does**:
1. Fetches all contact links from Arlo API
2. Processes contacts in batches of 50 (using Queueable)
3. For each contact:
   - Fetches contact details
   - Gets organisation CodePrimary
   - Checks if AccountNumber is in Custom Metadata
   - Finds Salesforce Account
   - Syncs contact
4. Continues processing even if some contacts fail

## How It Works

### Contact Matching

Contacts are matched using:
1. **Primary**: `Arlo_Contact_UUID__c` field (Arlo Contact Unique Identifier)
2. **Fallback**: `Email` field

If a contact exists with matching UUID or Email, it will be updated. Otherwise, a new contact is created.

### Account Assignment

1. Contact's employment data is fetched to get Organisation ID
2. Organisation details are fetched to get CodePrimary
3. CodePrimary is checked against Custom Metadata Type `Arlo_Organisation__mdt`
4. If allowed, Salesforce Account is found where `AccountNumber = CodePrimary`
5. Contact is assigned to that Account

### Field Mapping

| Arlo Field | Salesforce Field | Notes |
|------------|------------------|-------|
| UniqueIdentifier | Arlo_Contact_UUID__c | Used for matching |
| FirstName | FirstName | Appended with " TEST" |
| LastName | LastName | Appended with " TEST" |
| Email | Email | |
| PhoneMobile | MobilePhone | |
| PhoneNumber | Phone | |
| CodePrimary | AccountNumber (via Account lookup) | Used to find Account |

### Upsert Behavior

- **Existing Contacts**: Updated with latest data from Arlo
- **New Contacts**: Created with all fields populated
- **Account Changes**: If contact's Account changes, it's updated automatically

## Error Handling

### Missing CodePrimary

If CodePrimary is not found for an organisation:
- **Single Contact Sync**: Logs a warning and returns gracefully (does not throw exception)
- **Bulk Sync**: Skips the contact and continues processing others

### Missing Account

If Salesforce Account is not found for a CodePrimary:
- Contact is skipped
- Warning is logged
- Processing continues

### Not in Allowed List

If AccountNumber is not in Custom Metadata Type:
- Contact is skipped
- Debug message is logged
- Processing continues

### Missing Employment Data

If employment data is missing:
- Contact is skipped
- Error is logged
- Processing continues

## Logging

All sync operations are logged in `Arlo_Integration_Log__c`:

- **Status**: Success, Error, In Progress, Warning
- **Operation Type**: Single Contact Sync, Organization Contacts Sync, API Call
- **Details**: Contact ID, Organisation ID, messages, record counts
- **API Information**: Endpoint, HTTP status code

### Viewing Logs

1. Go to `Arlo Integration Logs` tab
2. Filter by Status or Operation Type
3. View detailed messages for troubleshooting

## Bulk Processing (Queueable)

For large syncs, the system uses `ArloContactSyncQueueable` to:
- Process contacts in batches of 50
- Stay under the 100 callout limit per transaction
- Chain batches automatically
- Track progress across all batches

## Testing

### Test Single Contact

```apex
// In Developer Console
ArloContactSync.syncSingleContact(
    '100',
    'your-username@example.com',
    'your-password'
);
```

### Test Bulk Sync

```apex
// In Developer Console
ArloContactSync.syncAllContacts(
    'your-username@example.com',
    'your-password'
);
```

**Note**: Bulk sync runs asynchronously. Check `Arlo_Integration_Log__c` records for progress.

## Troubleshooting

### No Contacts Syncing

1. Check Custom Metadata Type `Arlo_Organisation__mdt` has records
2. Verify Account Numbers in Custom Metadata match Account's AccountNumber field
3. Check logs for specific error messages

### Contacts Skipped

1. Check logs for "Skipping contact" messages
2. Verify CodePrimary exists in Arlo organisation data
3. Verify Account exists with matching AccountNumber
4. Verify AccountNumber is in Custom Metadata

### Missing CodePrimary Errors

- Check Arlo organisation data has CodePrimary field populated
- Some organisations may not have CodePrimary - these will be skipped

### Account Not Found

- Verify Account exists in Salesforce
- Verify Account's AccountNumber field matches CodePrimary
- Check AccountNumber field is populated

## API Endpoints Used

- `GET /api/2012-02-01/auth/resources/contacts/` - Get all contact links
- `GET /api/2012-02-01/auth/resources/contacts/{contactId}/` - Get single contact
- `GET /api/2012-02-01/auth/resources/contacts/{contactId}/employment` - Get employment data
- `GET /api/2012-02-01/auth/resources/organisations/{orgId}` - Get organisation details

## Authentication

The system uses Basic Authentication:
- Username: Arlo API username
- Password: Arlo API password
- Credentials are passed as parameters (not stored)

## Security Considerations

- Credentials are cleared after use
- No credentials are stored in the system
- All operations are logged for audit purposes
- Custom Metadata Type acts as a whitelist for security

## Limitations

- Maximum 100 HTTP callouts per transaction (handled by Queueable)
- Contacts without CodePrimary are skipped
- Contacts whose AccountNumber is not in Custom Metadata are skipped
- "TEST" is appended to FirstName and LastName (for testing purposes - can be removed)

## Future Enhancements

Potential improvements:
- Remove "TEST" suffix from names
- Add retry logic for failed API calls
- Add scheduling capability
- Add email notifications for sync completion
- Add dashboard for sync statistics

## Support

For issues or questions:
1. Check `Arlo_Integration_Log__c` records for error details
2. Review debug logs in Developer Console
3. Verify Custom Metadata Type configuration
4. Verify Account setup and AccountNumber values


