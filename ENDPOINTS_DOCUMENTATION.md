# Arlo API Endpoints Used - Contact-First Sync Approach

**Base URL**: `https://lifeeducationtrust.arlo.co/api/2012-02-01/auth`

## Step-by-Step Endpoint Flow

### Step 1: Get All Contacts from Arlo (with pagination)

- **Endpoint**: `GET /resources/contacts/`
- **Purpose**: Get all contact links from Arlo (paginated)
- **Response**: XML with list of Link elements pointing to individual contacts
- **Example Links**:
  ```xml
  <Link rel="http://schemas.arlo.co/api/2012/02/auth/Contact" type="application/xml" title="Contact" href="https://lifeeducationtrust.arlo.co/api/2012-02-01/auth/resources/contacts/11/"/>
  <Link rel="http://schemas.arlo.co/api/2012/02/auth/Contact" type="application/xml" title="Contact" href="https://lifeeducationtrust.arlo.co/api/2012-02-01/auth/resources/contacts/12/"/>
  ```
- **Pagination**: Follow `<Link rel="next" href="..."/>` to get next page

### Step 2: For Each Contact Link - Get Contact Details and Check Status

- **Endpoint**: `GET /resources/contacts/{numericContactId}`
- **Example**: `GET /resources/contacts/300`
- **Purpose**: Get contact details and check if Status = "Active"
- **Response**: XML with contact information including `<Status>Active</Status>`
- **Action**: If Status ≠ "Active", **SKIP** this contact and continue to next

---

### Step 3: Get All Registrations for Active Contact

- **Endpoint**: `GET /resources/contacts/{numericContactId}/registrations/`
- **Example**: `GET /resources/contacts/300/registrations/`
- **Purpose**: Get all event registrations for this specific contact
- **Response**: XML with list of Registration Resource elements
- **Extract**: List of registration links/IDs (e.g., `/resources/registrations/337/`)

---

### Step 4: For Each Registration - Process in Order

**4a. Get Registration Details**
- **Endpoint**: `GET /resources/registrations/{registrationId}`
- **Example**: `GET /resources/registrations/337`
- **Purpose**: Get the event ID that this registration belongs to
- **Response**: XML with registration details including event link
- **Extract**: Event ID from `<Link rel="...Event..." href=".../events/{eventId}"/>`

**4b. Get Event Details and Check if Event Contains "NHM"**
- **Endpoint**: `GET /resources/events/{eventId}`
- **Example**: `GET /resources/events/16`
- **Purpose**: Get event name, code, and details
- **Response**: XML with event information
- **Extract**: 
  - Event `Name` (e.g., "Nurturing Healthy Minds - Anxiety")
  - Event `Code` (e.g., "NHM-ANX-2024")
- **Action**: If event Name or Code does NOT contain "NHM", **SKIP** this registration (only process NHM events, excludes CONF events)

**4c. Check Email Consent** (only if event contains "NHM")
- **Endpoint**: `GET /resources/registrations/{registrationId}/customfields`
- **Example**: `GET /resources/registrations/337/customfields`
- **Purpose**: Check if `imhappytobeemailedaboutlifeeducationtrustnews` custom field is `true`
- **Response**: XML with custom fields (structure may vary)
  ```xml
  <Field>
      <Name>imhappytobeemailedaboutlifeeducationtrustnews</Name>
      <Value>
          <Boolean>true</Boolean>
      </Value>
  </Field>
  ```
- **Parsing**: Uses DOM parsing with regex fallback to handle various XML structures and whitespace
- **Action**: If `false` or not found, **SKIP** this registration and continue to next

---

### Step 5: Match Contact to Salesforce and Add to Campaign

After processing all registrations (all callouts complete):

**5a. Find or Create Salesforce Contact**
- **Action**: Find Salesforce contact by matching UUID or Email from Arlo contact
- **If contact exists**: Use existing contact
- **If contact does NOT exist**: 
  - Fetch full contact details (contact + employment + organisation) - 3 callouts
  - Get `CodePrimary` from organisation
  - Match to Salesforce Account by `AccountNumber`
  - Create contact in Salesforce with correct Account
- **Endpoint**: `GET /resources/organisations/{organisationId}`
- **Example**: `GET /resources/organisations/1735`
- **Purpose**: Get the `CodePrimary` field from the organisation
- **Response**: XML with organisation details
- **Extract**: `CodePrimary` value (e.g., "1735")
- **Purpose**: Match to Salesforce Account by `AccountNumber`

**5b. Add Contact to Campaign**
- **Action**: Create `CampaignMember` records in Salesforce
- **Mapping**: 
  - Event Name → Campaign Name using `getCampaignNameForEvent()` method
  - Examples:
    - "Nurturing Healthy Minds - Anxiety" → "NHM - Anxiety"
    - "Nurturing Healthy Minds - Neurodiversity" → "NHM - Neurodiversity"
    - "Nurturing Healthy Minds - Digital wellbeing" → "NHM - Digital wellbeing"
    - "Nurturing Healthy Minds - Self-care" → "NHM - Self-care"

---

## Important Notes

### Callout Limit Handling
- **Max Callouts**: 95 per batch (reserves 5 for DML operations)
- **Reserved for Contact Creation**: 15 callouts (enough for ~5 contacts × 3 callouts each)
- **Deferred Processing**: If callout limits are reached:
  - Unprocessed registrations are tracked and deferred to next batch
  - Format: `"contactId:regId1,regId2|contactId2:regId3,regId4"`
  - Deferred contacts are processed first in the next batch

### Contact Creation Priority
- Contacts with valid registrations (NHM event + email consent) **MUST** be created
- System attempts to create contacts even with limited callouts
- If contacts can't be created due to callout limits, they will be created in the next full sync run

### Email Consent Parsing
- Handles various XML structures and whitespace variations
- Case-insensitive field name matching
- Checks both `<Value><Boolean>true</Boolean></Value>` and `<Value>true</Value>` structures
- Uses DOM parsing with regex fallback for robustness

---

## Summary

**Per Active Contact:**
1. **Callout 1**: Get contact details → Check Status = "Active"
2. **Callout 2**: Get contact details (UUID, Email) for Salesforce matching
3. **Callout 3**: Get contact's registrations
4. **For each registration** (could be multiple):
   - **Callout 4**: Get registration details → Extract event ID
   - **Callout 5**: Get event details → Check if event contains "NHM"
   - **Callout 6**: Get customfields → Check email consent (only if event contains "NHM")
5. **For unmatched contacts** (need creation):
   - **Callout 7-9**: Get full contact details (contact + employment + organisation) - 3 callouts per contact

**Total Callouts Per Active Contact**: 3 + (3 × number of registrations) + (3 × number of unmatched contacts)

**Example for Contact 300 (Active) with 2 registrations (both NHM with consent), contact doesn't exist:**
- 1 callout: Get contact → Status = "Active" ✓
- 1 callout: Get contact details → UUID and Email
- 1 callout: Get registrations → Find 2 registration IDs
- 2 callouts: Get registration details → Extract 2 event IDs
- 2 callouts: Get event details → Verify both contain "NHM"
- 2 callouts: Get customfields → Check consent for both (both true)
- 3 callouts: Get full contact details → Create contact in Salesforce
- **Total: ~12 callouts per active contact with 2 registrations (contact creation needed)**

---

## Endpoint Reference

| Step | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| 1 | GET | `/resources/contacts/` | Get all contact links (paginated) |
| 2 | GET | `/resources/contacts/{numericId}` | Get contact details and check Status = "Active" |
| 3 | GET | `/resources/contacts/{numericId}/registrations/` | Get all registrations for contact |
| 4a | GET | `/resources/registrations/{regId}` | Get registration details (extract event ID) |
| 4b | GET | `/resources/events/{eventId}` | Get event details (check if contains "NHM") |
| 4c | GET | `/resources/registrations/{regId}/customfields` | Check email consent (only for NHM events) |
| 5 | GET | `/resources/organisations/{orgId}` | Get CodePrimary for Account matching (contact creation) |
