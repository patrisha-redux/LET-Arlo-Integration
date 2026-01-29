# Arlo Integration Test Scenarios

## Overview
This document outlines comprehensive test scenarios for the Arlo-Salesforce integration, covering both positive (happy path) and negative (error handling) test cases.

## Test Classes
- `ArloContactSyncTest` - Tests for contact synchronization
- `ArloEventRegistrationSyncTest` - Tests for event registration synchronization
- `ArloSyncQueueableTest` - Tests for Queueable batch processing

---

## 1. ArloContactSync Test Scenarios

### Positive Test Cases

#### TC-AC-001: Successful Single Contact Sync
**Description:** Sync a single contact from Arlo to Salesforce successfully.

**Prerequisites:**
- Valid Arlo credentials configured
- Contact exists in Arlo with valid data
- Contact has employment data with valid organisation
- Organisation has CodePrimary
- Salesforce Account exists with matching AccountNumber

**Test Steps:**
1. Create test Account in Salesforce with AccountNumber matching CodePrimary
2. Mock HTTP response for contact endpoint (200 OK, valid XML)
3. Mock HTTP response for employment endpoint (200 OK, valid XML with organisation link)
4. Mock HTTP response for organisation endpoint (200 OK, valid XML with CodePrimary)
5. Call `ArloContactSync.syncSingleContact(contactId, username, password)`

**Expected Results:**
- Contact is created in Salesforce
- Contact fields are correctly mapped (FirstName, LastName, Email, Mobile, Arlo_Contact_UUID__c)
- Contact is linked to correct Account
- Log record created with Status = 'Success'
- No exceptions thrown

---

#### TC-AC-002: Successful Bulk Contact Sync
**Description:** Sync multiple contacts from Arlo to Salesforce successfully.

**Prerequisites:**
- Valid Arlo credentials configured
- Multiple contacts exist in Arlo
- All contacts have valid employment and organisation data
- Matching Salesforce Accounts exist

**Test Steps:**
1. Create test Accounts in Salesforce
2. Mock HTTP responses for contacts collection endpoint
3. Mock HTTP responses for individual contact endpoints
4. Mock HTTP responses for employment and organisation endpoints
5. Call `ArloContactSync.syncAllContacts(username, password)`

**Expected Results:**
- All contacts are created in Salesforce
- Log record shows correct count of processed and successful contacts
- No exceptions thrown

---

#### TC-AC-003: Contact Update (Upsert) - Existing Contact
**Description:** Sync a contact that already exists in Salesforce (by UUID or Email).

**Prerequisites:**
- Contact already exists in Salesforce with Arlo_Contact_UUID__c or Email
- Contact data in Arlo has been updated

**Test Steps:**
1. Create existing Contact in Salesforce
2. Mock HTTP responses for contact, employment, organisation
3. Call sync method

**Expected Results:**
- Existing contact is updated (not duplicated)
- Contact fields are updated with latest Arlo data
- Only one contact record exists

---

#### TC-AC-004: Contact with Missing Optional Fields
**Description:** Sync a contact that has some optional fields missing (e.g., no mobile phone).

**Prerequisites:**
- Contact exists in Arlo but missing some optional fields

**Test Steps:**
1. Mock HTTP response with contact missing optional fields
2. Call sync method

**Expected Results:**
- Contact is created successfully
- Required fields are populated
- Optional fields are null (not causing errors)

---

### Negative Test Cases

#### TC-AC-101: Invalid Credentials
**Description:** Attempt sync with invalid Arlo credentials.

**Test Steps:**
1. Call sync method with invalid username/password
2. Mock HTTP response with 401 Unauthorized

**Expected Results:**
- `ArloSyncException` is thrown with appropriate error message
- Log record created with Status = 'Error'
- No contacts are created

---

#### TC-AC-102: Missing Custom Settings
**Description:** Attempt sync without Custom Settings configured.

**Test Steps:**
1. Ensure `Arlo_Credentials__c` Custom Setting is not configured
2. Call sync method with null credentials

**Expected Results:**
- `ArloSyncException` is thrown: "Arlo Credentials not configured..."
- No contacts are created

---

#### TC-AC-103: Contact Not Found in Arlo
**Description:** Attempt to sync a contact that doesn't exist in Arlo.

**Test Steps:**
1. Call `syncSingleContact` with non-existent contact ID
2. Mock HTTP response with 404 Not Found

**Expected Results:**
- `ArloSyncException` is thrown: "Arlo Contact not found: {contactId}"
- Log record created with Status = 'Error'
- No contact is created

---

#### TC-AC-104: Organisation Without CodePrimary
**Description:** Sync contact from organisation that doesn't have CodePrimary.

**Test Steps:**
1. Mock contact endpoint (200 OK)
2. Mock employment endpoint (200 OK, with organisation link)
3. Mock organisation endpoint (200 OK, but no CodePrimary in XML)

**Expected Results:**
- Contact is skipped (not synced)
- Warning logged: "No CodePrimary found for organisation {orgId}"
- No exception thrown (this is expected behavior)
- Log record shows contact was skipped

---

#### TC-AC-105: Account Not Found in Salesforce
**Description:** Sync contact where CodePrimary exists but no matching Salesforce Account.

**Test Steps:**
1. Mock all endpoints successfully
2. Organisation has CodePrimary = "1234"
3. No Salesforce Account with AccountNumber = "1234" exists

**Expected Results:**
- Contact is skipped (not synced)
- Warning logged: "Account not found for CodePrimary: 1234"
- No exception thrown (this is expected behavior)
- Log record shows contact was skipped

---

#### TC-AC-106: Missing Employment Data
**Description:** Sync contact that has no employment data in Arlo.

**Test Steps:**
1. Mock contact endpoint (200 OK)
2. Mock employment endpoint (404 Not Found or empty response)

**Expected Results:**
- `ArloSyncException` is thrown: "No organisation ID found for contact..."
- Log record created with Status = 'Error'
- No contact is created

---

#### TC-AC-107: HTTP Error - 500 Internal Server Error
**Description:** Arlo API returns server error.

**Test Steps:**
1. Mock HTTP response with 500 Internal Server Error

**Expected Results:**
- `ArloSyncException` is thrown with error details
- Log record created with Status = 'Error' and HTTP status code
- No contacts are created

---

#### TC-AC-108: Invalid XML Response
**Description:** Arlo API returns malformed XML.

**Test Steps:**
1. Mock HTTP response with 200 OK but invalid XML content

**Expected Results:**
- Exception is caught and handled gracefully
- Log record created with Status = 'Error'
- Error message indicates XML parsing issue

---

#### TC-AC-109: Missing Required Contact Fields
**Description:** Contact in Arlo is missing required fields (e.g., LastName).

**Test Steps:**
1. Mock contact endpoint with contact missing LastName
2. Attempt to sync

**Expected Results:**
- DML exception when inserting contact
- Exception is caught and logged
- Log record shows failure reason

---

#### TC-AC-110: Callout Timeout
**Description:** Arlo API call times out.

**Test Steps:**
1. Mock HTTP callout to timeout (simulate slow response)

**Expected Results:**
- `CalloutException` is thrown
- Exception is caught and logged
- Log record created with Status = 'Error'

---

#### TC-AC-111: Duplicate Contact Prevention
**Description:** Attempt to sync duplicate contact (same UUID or Email).

**Test Steps:**
1. Create existing Contact with Arlo_Contact_UUID__c = "test-uuid"
2. Attempt to sync another contact with same UUID

**Expected Results:**
- Existing contact is found and updated (not duplicated)
- Only one contact record exists

---

## 2. ArloEventRegistrationSync Test Scenarios

### Positive Test Cases

#### TC-AE-001: Successful Event Registration Sync
**Description:** Sync contacts from events and registrations successfully.

**Prerequisites:**
- Valid Arlo credentials
- Events exist in Arlo (not starting with 'CONF')
- Registrations exist with email consent = true
- Contacts have valid employment and organisation data
- Matching Salesforce Accounts exist

**Test Steps:**
1. Create test Accounts in Salesforce
2. Mock HTTP responses for:
   - Events collection endpoint
   - Individual event details
   - Event registrations
   - Registration custom fields (email consent = true)
   - Registration details (contact link)
   - Contact details
   - Employment data
   - Organisation data
3. Call `ArloEventRegistrationSync.syncContactsFromEvents(username, password)`

**Expected Results:**
- Contacts are synced to Salesforce
- Contacts are added to appropriate campaigns based on event name
- Log record shows correct counts
- No exceptions thrown

---

#### TC-AE-002: CONF Events Skipped
**Description:** Events with Code starting with 'CONF' are correctly skipped.

**Test Steps:**
1. Mock events collection with mix of CONF and non-CONF events
2. Call sync method

**Expected Results:**
- CONF events are skipped
- Only non-CONF events are processed
- Log shows correct count of skipped events

---

#### TC-AE-003: Email Consent Check - True
**Description:** Registration with email consent = true is processed.

**Test Steps:**
1. Mock registration custom fields with `imhappytobeemailedaboutlifeeducationtrustnews` = true
2. Call sync method

**Expected Results:**
- Contact is synced to Salesforce
- Contact is added to campaign (if applicable)

---

#### TC-AE-004: Campaign Assignment - Anxiety Event
**Description:** Contact from "Anxiety" event is added to "NHM - Anxiety" campaign.

**Test Steps:**
1. Mock event with name containing "Anxiety"
2. Mock registration with email consent = true
3. Call sync method

**Expected Results:**
- Contact is synced
- Contact is added to "NHM - Anxiety" campaign
- No duplicate campaign members created

---

#### TC-AE-005: Campaign Assignment - Digital Wellbeing Event
**Description:** Contact from "Digital wellbeing" event is added to correct campaign.

**Test Steps:**
1. Mock event with name containing "Digital" and "Wellbeing" (separate words)
2. Call sync method

**Expected Results:**
- Contact is added to "NHM - Digital wellbeing" campaign

---

#### TC-AE-006: Multiple Registrations - Same Contact
**Description:** Same contact registered for multiple events.

**Test Steps:**
1. Mock multiple registrations for same contact (same UUID/Email)
2. Call sync method

**Expected Results:**
- Only one contact record is created/updated
- Contact is added to multiple campaigns (one per event)

---

#### TC-AE-007: Queueable Processing for Large Batches
**Description:** When more than 10 events, Queueable is used for batch processing.

**Test Steps:**
1. Mock events collection with 15 events
2. Call sync method

**Expected Results:**
- `ArloEventRegistrationSyncQueueable` is enqueued
- Log record created with Status = 'In Progress'
- Processing continues asynchronously

---

### Negative Test Cases

#### TC-AE-101: Email Consent Check - False
**Description:** Registration with email consent = false is skipped.

**Test Steps:**
1. Mock registration custom fields with `imhappytobeemailedaboutlifeeducationtrustnews` = false
2. Call sync method

**Expected Results:**
- Contact is NOT synced
- Registration is skipped
- Log shows registration was filtered out

---

#### TC-AE-102: Email Consent Check - Missing Field
**Description:** Registration custom fields don't contain email consent field.

**Test Steps:**
1. Mock registration custom fields without `imhappytobeemailedaboutlifeeducationtrustnews`
2. Call sync method

**Expected Results:**
- Contact is NOT synced (treated as consent = false)
- Registration is skipped

---

#### TC-AE-103: No Events Found
**Description:** Arlo API returns no events.

**Test Steps:**
1. Mock events collection endpoint with empty response
2. Call sync method

**Expected Results:**
- Log record created: "No events found"
- No contacts are synced
- No exception thrown (graceful handling)

---

#### TC-AE-104: Event Details Not Found
**Description:** Event link exists but event details endpoint returns 404.

**Test Steps:**
1. Mock events collection (returns event links)
2. Mock event details endpoint with 404

**Expected Results:**
- Event is skipped
- Error logged for that event
- Processing continues with other events

---

#### TC-AE-105: Registration Details Not Found
**Description:** Registration link exists but details endpoint returns 404.

**Test Steps:**
1. Mock event details (success)
2. Mock registrations collection (returns registration links)
3. Mock registration details endpoint with 404

**Expected Results:**
- Registration is skipped
- Error logged
- Processing continues

---

#### TC-AE-106: Campaign Not Found
**Description:** Event name matches campaign keyword but campaign doesn't exist in Salesforce.

**Test Steps:**
1. Mock event with name containing "Anxiety"
2. Ensure "NHM - Anxiety" campaign doesn't exist
3. Call sync method

**Expected Results:**
- Contact is synced successfully
- Campaign assignment fails gracefully (logged but doesn't stop sync)
- No exception thrown

---

#### TC-AE-107: Callout Limit Exceeded
**Description:** Too many callouts in single transaction.

**Test Steps:**
1. Mock large number of events/registrations
2. Process synchronously (not using Queueable)

**Expected Results:**
- `LimitException` is thrown when limit reached
- Exception is caught and logged
- Log record shows partial processing

---

#### TC-AE-108: DML Error - Duplicate Campaign Member
**Description:** Attempt to add contact to campaign where they already exist.

**Test Steps:**
1. Create existing CampaignMember
2. Attempt to add same contact to same campaign

**Expected Results:**
- Duplicate is prevented (query before insert)
- No DML exception thrown
- Only one CampaignMember exists

---

#### TC-AE-109: Invalid Event Link Format
**Description:** Event link in collection has invalid format.

**Test Steps:**
1. Mock events collection with malformed event links
2. Call sync method

**Expected Results:**
- Invalid links are skipped
- Error logged for each invalid link
- Processing continues with valid links

---

#### TC-AE-110: Missing Event Code
**Description:** Event details don't contain Code field.

**Test Steps:**
1. Mock event details without Code field
2. Call sync method

**Expected Results:**
- Event is processed (assumed non-CONF if Code is missing)
- Or event is skipped with warning logged

---

## 3. Queueable Test Scenarios

### Positive Test Cases

#### TC-Q-001: Successful Queueable Chain
**Description:** Queueable processes batches and chains correctly.

**Test Steps:**
1. Enqueue Queueable with large batch
2. Mock HTTP responses for each batch

**Expected Results:**
- Each batch processes successfully
- Next batch is chained automatically
- Log record is updated after each batch
- Final log shows Status = 'Success' with correct totals

---

#### TC-Q-002: Progress Tracking Across Batches
**Description:** Cumulative progress is tracked correctly across chained jobs.

**Test Steps:**
1. Process multiple batches
2. Check log record after each batch

**Expected Results:**
- Log shows cumulative processed/successful/failed counts
- Counts are accurate across all batches

---

### Negative Test Cases

#### TC-Q-101: Queueable Failure Mid-Batch
**Description:** Queueable fails during batch processing.

**Test Steps:**
1. Enqueue Queueable
2. Mock HTTP error in middle of batch

**Expected Results:**
- Exception is caught and logged
- Log record updated with Status = 'Error'
- Partial progress is saved

---

#### TC-Q-102: Static Variable Reset
**Description:** Static variables reset between chained jobs (known Salesforce behavior).

**Test Steps:**
1. Process multiple batches
2. Verify logId is retrieved correctly in subsequent batches

**Expected Results:**
- Fallback mechanism queries for "In Progress" log record
- Log updates continue correctly
- No data loss

---

## 4. Integration Test Scenarios

### Positive Test Cases

#### TC-I-001: End-to-End Sync Flow
**Description:** Complete flow from events → registrations → contacts → campaigns.

**Test Steps:**
1. Set up all prerequisites
2. Run full sync
3. Verify all components

**Expected Results:**
- Events fetched
- Registrations processed
- Contacts synced
- Campaigns assigned
- Log records created
- All counts accurate

---

### Negative Test Cases

#### TC-I-101: Partial Failure Recovery
**Description:** Some contacts fail but others succeed.

**Test Steps:**
1. Mock mix of successful and failed operations
2. Run sync

**Expected Results:**
- Successful contacts are synced
- Failed contacts are logged
- Final log shows breakdown of success/failure
- Email notification sent if failures > 0

---

## 5. Edge Cases

### TC-EC-001: Empty Response Bodies
**Description:** API returns 200 OK but empty response body.

**Expected Results:**
- Graceful handling
- Appropriate error logged
- No crash

---

### TC-EC-002: Special Characters in Names
**Description:** Contact names contain special characters (apostrophes, hyphens, etc.).

**Expected Results:**
- Names are correctly stored
- No encoding issues
- XML parsing handles special characters

---

### TC-EC-003: Very Long Field Values
**Description:** Contact fields exceed Salesforce field length limits.

**Expected Results:**
- Values are truncated if necessary
- Or validation error is caught and logged

---

### TC-EC-004: Null Values in XML
**Description:** XML contains null or empty elements.

**Expected Results:**
- Null values handled gracefully
- Fields set to null in Salesforce (if allowed)

---

## Test Data Requirements

### Mock Data Needed:
1. **Arlo API Responses:**
   - Contact XML (single and collection)
   - Employment XML
   - Organisation XML
   - Event XML (single and collection)
   - Registration XML (single and collection)
   - Registration Custom Fields XML

2. **Salesforce Test Data:**
   - Accounts with various AccountNumbers
   - Existing Contacts (for update scenarios)
   - Campaigns (for campaign assignment)
   - Custom Settings (Arlo_Credentials__c)

3. **HTTP Mock Responses:**
   - 200 OK with valid XML
   - 401 Unauthorized
   - 404 Not Found
   - 500 Internal Server Error
   - Timeout scenarios

---

## Test Coverage Goals

- **Code Coverage:** Minimum 75% (target: 90%+)
- **Branch Coverage:** All critical paths tested
- **Exception Handling:** All catch blocks tested
- **Edge Cases:** All identified edge cases covered

---

## Notes

1. **Mock Framework:** Use `Test.setMock(HttpCalloutMock.class, mock)` for HTTP callouts
2. **Governor Limits:** Use `Test.startTest()` and `Test.stopTest()` appropriately
3. **Data Isolation:** Tests should not depend on existing org data
4. **Assertions:** Every test should have meaningful assertions
5. **Error Messages:** Verify error messages are user-friendly and actionable


