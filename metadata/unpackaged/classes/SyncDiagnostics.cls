/**
 * SyncDiagnostics
 *
 * Diagnostic and debugging utilities for the Arlo integration.
 * Provides methods to trace, diagnose, and debug contact sync issues.
 */
public with sharing class SyncDiagnostics {

    /**
     * Debug method to check the registrations endpoint response for a contact
     * Usage: SyncDiagnostics.debugContactRegistrationsEndpoint('1944');
     */
    public static void debugContactRegistrationsEndpoint(String numericContactId) {
        System.debug('=== DEBUGGING CONTACT REGISTRATIONS ENDPOINT ===');
        System.debug('Contact Numeric ID: ' + numericContactId);

        ArloSecureAuth auth;
        try {
            auth = ArloSecureAuth.getInstance();
        } catch (Exception e) {
            System.debug('ERROR: Could not load credentials: ' + e.getMessage());
            return;
        }

        try {
            String registrationsEndpoint = '/resources/contacts/' + numericContactId + '/registrations/';
            System.debug('Endpoint: ' + registrationsEndpoint);

            HttpResponse res = auth.get(registrationsEndpoint);

            System.debug('\n=== RESPONSE DETAILS ===');
            System.debug('Status Code: ' + res.getStatusCode());
            System.debug('Status: ' + res.getStatus());

            String responseBody = res.getBody();
            System.debug('Response Body Length: ' + responseBody.length());
            System.debug('\n=== FULL RESPONSE BODY ===');
            System.debug(responseBody);

            if (res.getStatusCode() == 200) {
                System.debug('\n=== PARSING RESPONSE ===');

                // Extract registration links
                Pattern regLinkPattern = Pattern.compile('<Link[^>]*href="([^"]*registrations/[^"]+)"');
                Matcher regMatcher = regLinkPattern.matcher(responseBody);

                List<String> registrationLinks = new List<String>();
                while (regMatcher.find()) {
                    registrationLinks.add(regMatcher.group(1));
                }

                System.debug('Found ' + registrationLinks.size() + ' registration link(s):');
                for (String link : registrationLinks) {
                    System.debug('  - ' + link);
                }

                // Extract registration IDs
                Pattern regIdPattern = Pattern.compile('/registrations/(\\d+)/');
                Set<String> registrationIds = new Set<String>();
                for (String link : registrationLinks) {
                    Matcher idMatcher = regIdPattern.matcher(link);
                    if (idMatcher.find()) {
                        registrationIds.add(idMatcher.group(1));
                    }
                }

                System.debug('\nExtracted Registration IDs: ' + registrationIds.size());
                for (String regId : registrationIds) {
                    System.debug('  - Registration ID: ' + regId);
                }

                // Extract event links
                Pattern eventLinkPattern = Pattern.compile('<Link[^>]*rel="[^"]*Event"[^>]*href="([^"]*events/[^"]+)"');
                Matcher eventMatcher = eventLinkPattern.matcher(responseBody);

                List<String> eventLinks = new List<String>();
                while (eventMatcher.find()) {
                    eventLinks.add(eventMatcher.group(1));
                }

                System.debug('\nFound ' + eventLinks.size() + ' event link(s):');
                for (String link : eventLinks) {
                    System.debug('  - ' + link);
                }

            } else {
                System.debug('Request failed with status: ' + res.getStatusCode());
            }

        } catch (Exception e) {
            System.debug('ERROR: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }

        System.debug('\n=== END DEBUG ===\n');
    }

    /**
     * Diagnose which campaigns a contact should be in based on their Arlo registrations
     * Usage:
     *   - By numeric contact ID: SyncDiagnostics.diagnoseContactCampaigns('1944');
     *   - By UUID: SyncDiagnostics.diagnoseContactCampaigns('9b4c8fc8-eff0-4c04-a7b3-535fe95a23ff');
     *   - By email: SyncDiagnostics.diagnoseContactCampaigns('user@example.com');
     */
    public static void diagnoseContactCampaigns(String contactIdentifier) {
        System.debug('=== DIAGNOSING CONTACT CAMPAIGNS ===');
        System.debug('Contact Identifier: ' + contactIdentifier);

        // Check if numeric ID
        Boolean isNumericId = Pattern.matches('^\\d+$', contactIdentifier);
        Set<String> currentCampaignNames = new Set<String>();

        if (isNumericId) {
            System.debug('Using numeric contact ID directly: ' + contactIdentifier);
            findSalesforceContactAndCampaigns(contactIdentifier, currentCampaignNames, true);
        } else {
            // Find contact in Salesforce
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name
                FROM Contact
                WHERE Arlo_Contact_UUID__c = :contactIdentifier OR Email = :contactIdentifier
                LIMIT 1
            ];

            if (contacts.isEmpty()) {
                System.debug('Contact not found in Salesforce');
                return;
            }

            Contact sfContact = contacts[0];
            System.debug('Contact found: ' + sfContact.FirstName + ' ' + sfContact.LastName);
            System.debug('  Email: ' + sfContact.Email);
            System.debug('  UUID: ' + sfContact.Arlo_Contact_UUID__c);

            // Get current campaign memberships
            List<CampaignMember> currentMembers = [
                SELECT Campaign.Name, Status
                FROM CampaignMember
                WHERE ContactId = :sfContact.Id AND Campaign.Name LIKE 'NHM - %'
            ];

            if (currentMembers.isEmpty()) {
                System.debug('Contact is NOT in any NHM campaigns');
            } else {
                System.debug('Contact is in ' + currentMembers.size() + ' NHM campaign(s):');
                for (CampaignMember cm : currentMembers) {
                    System.debug('  - ' + cm.Campaign.Name + ' (Status: ' + cm.Status + ')');
                    currentCampaignNames.add(cm.Campaign.Name);
                }
            }
        }

        System.debug('\n=== END DIAGNOSIS ===\n');
    }

    /**
     * Diagnostic method to check why a contact isn't being added to a campaign
     */
    public static void diagnoseContactCampaignAssignment(String contactIdentifier) {
        System.debug('=== DIAGNOSTIC: Contact Campaign Assignment ===');
        System.debug('Contact Identifier: ' + contactIdentifier);

        // Find the contact
        Contact contact = findContactByIdentifier(contactIdentifier);
        if (contact == null) {
            System.debug('ERROR: Contact not found');
            return;
        }

        System.debug('Contact found: ' + contact.Id);
        System.debug('  - Name: ' + contact.FirstName + ' ' + contact.LastName);
        System.debug('  - Email: ' + contact.Email);
        System.debug('  - Arlo UUID: ' + contact.Arlo_Contact_UUID__c);
        System.debug('  - Account: ' + (contact.Account != null ? contact.Account.Name : 'None'));

        // Check campaign memberships
        System.debug('\n=== Checking Campaign Memberships ===');
        List<String> campaigns = CampaignMemberManager.getContactNhmCampaigns(contact.Id);

        if (campaigns.isEmpty()) {
            System.debug('Contact is NOT a member of any NHM campaigns');
        } else {
            System.debug('Contact is a member of ' + campaigns.size() + ' NHM campaign(s):');
            for (String campaignName : campaigns) {
                System.debug('  - ' + campaignName);
            }
        }

        // Check available campaigns
        System.debug('\n=== Checking Available Campaigns ===');
        List<Campaign> availableCampaigns = EventCampaignMapper.getAllNhmCampaigns();

        if (availableCampaigns.isEmpty()) {
            System.debug('ERROR: No NHM campaigns found in Salesforce!');
        } else {
            System.debug('Found ' + availableCampaigns.size() + ' NHM campaign(s):');
            for (Campaign camp : availableCampaigns) {
                System.debug('  - ' + camp.Name + ' (ID: ' + camp.Id + ')');
            }
        }

        // Check matching info
        System.debug('\n=== Contact Matching Info ===');
        if (String.isBlank(contact.Arlo_Contact_UUID__c)) {
            System.debug('WARNING: Contact does not have Arlo_Contact_UUID__c set');
        } else {
            System.debug('Contact has Arlo UUID: ' + contact.Arlo_Contact_UUID__c);
        }

        if (String.isBlank(contact.Email)) {
            System.debug('WARNING: Contact does not have Email set');
        } else {
            System.debug('Contact has Email: ' + contact.Email);
        }

        System.debug('=== END DIAGNOSTIC ===\n');
    }

    /**
     * Trace a specific contact through the sync process
     */
    public static void traceContactSync(String contactUuidOrEmail) {
        System.debug('=== TRACING CONTACT SYNC PROCESS ===');
        System.debug('Contact Identifier: ' + contactUuidOrEmail);

        // Find contact in Salesforce
        Contact contact = findContactByIdentifier(contactUuidOrEmail);
        if (contact == null) {
            System.debug('Contact not found in Salesforce');
            return;
        }

        System.debug('Contact found in Salesforce:');
        System.debug('  ID: ' + contact.Id);
        System.debug('  Name: ' + contact.FirstName + ' ' + contact.LastName);
        System.debug('  Email: ' + contact.Email);
        System.debug('  UUID: ' + contact.Arlo_Contact_UUID__c);

        // Check current campaigns
        System.debug('\n=== Current Campaign Memberships ===');
        List<String> campaigns = CampaignMemberManager.getContactNhmCampaigns(contact.Id);

        if (campaigns.isEmpty()) {
            System.debug('Contact is NOT in any NHM campaigns');
        } else {
            System.debug('Contact is in ' + campaigns.size() + ' NHM campaign(s):');
            for (String campaignName : campaigns) {
                System.debug('  - ' + campaignName);
            }
        }

        // Check available campaigns
        System.debug('\n=== Verifying Campaigns Exist ===');
        List<Campaign> availableCampaigns = EventCampaignMapper.getAllNhmCampaigns();
        System.debug('Found ' + availableCampaigns.size() + ' NHM campaigns');

        // Check recent sync logs
        System.debug('\n=== Checking Recent Sync Logs ===');
        List<Arlo_Integration_Log__c> recentLogs = [
            SELECT Id, Operation_Type__c, Status__c, Records_Processed__c, Records_Successful__c,
                   Message__c, CreatedDate
            FROM Arlo_Integration_Log__c
            WHERE Operation_Type__c = 'Event Registration Sync'
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];

        if (recentLogs.isEmpty()) {
            System.debug('No recent Event Registration Sync logs found');
        } else {
            System.debug('Found ' + recentLogs.size() + ' recent sync log(s):');
            for (Arlo_Integration_Log__c log : recentLogs) {
                System.debug('  - ' + log.Status__c + ' (' + log.CreatedDate + ')');
                System.debug('    Processed: ' + log.Records_Processed__c + ', Successful: ' + log.Records_Successful__c);
            }
        }

        System.debug('\n=== END TRACE ===\n');
    }

    /**
     * Deep diagnostic for a specific contact - checks matching logic
     */
    public static void deepDiagnoseContact(String emailOrUuid) {
        System.debug('=== DEEP DIAGNOSTIC ===');
        System.debug('Checking: ' + emailOrUuid);

        Contact contact = findContactByIdentifier(emailOrUuid);
        if (contact == null) {
            System.debug('Contact not found in Salesforce');
            return;
        }

        System.debug('Contact found in Salesforce:');
        System.debug('  ID: ' + contact.Id);
        System.debug('  Name: ' + contact.FirstName + ' ' + contact.LastName);
        System.debug('  Email: "' + contact.Email + '" (length: ' + (contact.Email != null ? contact.Email.length() : 0) + ')');
        System.debug('  UUID: "' + contact.Arlo_Contact_UUID__c + '" (length: ' + (contact.Arlo_Contact_UUID__c != null ? contact.Arlo_Contact_UUID__c.length() : 0) + ')');
        System.debug('  Account: ' + (contact.Account != null ? contact.Account.Name : 'None'));

        // Normalized values
        String normalizedEmail = contact.Email != null ? contact.Email.toLowerCase().trim() : '';
        String normalizedUuid = contact.Arlo_Contact_UUID__c != null ? contact.Arlo_Contact_UUID__c.trim() : '';

        System.debug('\nNormalized values for matching:');
        System.debug('  Email (normalized): "' + normalizedEmail + '"');
        System.debug('  UUID (normalized): "' + normalizedUuid + '"');

        // Check campaign memberships
        List<String> campaigns = CampaignMemberManager.getContactNhmCampaigns(contact.Id);
        System.debug('\nCurrent Campaign Memberships: ' + campaigns.size());
        for (String campaignName : campaigns) {
            System.debug('  - ' + campaignName);
        }

        // Check available campaigns
        List<Campaign> availableCampaigns = EventCampaignMapper.getAllNhmCampaigns();
        System.debug('\nAvailable Campaigns: ' + availableCampaigns.size());
        for (Campaign camp : availableCampaigns) {
            System.debug('  - ' + camp.Name + ' (ID: ' + camp.Id + ')');
        }

        System.debug('=== END DEEP DIAGNOSTIC ===\n');
    }

    /**
     * Quick check method for a specific contact
     */
    public static void quickCheckContact(String emailOrUuid) {
        System.debug('=== QUICK CHECK ===');
        System.debug('Checking: ' + emailOrUuid);

        Contact contact = findContactByIdentifier(emailOrUuid);
        if (contact == null) {
            System.debug('Contact not found');
            return;
        }

        System.debug('Contact: ' + contact.FirstName + ' ' + contact.LastName);
        System.debug('  ID: ' + contact.Id);
        System.debug('  Email: ' + contact.Email);
        System.debug('  UUID: ' + contact.Arlo_Contact_UUID__c);
        System.debug('  Account: ' + (contact.Account != null ? contact.Account.Name : 'None'));

        List<String> campaigns = CampaignMemberManager.getContactNhmCampaigns(contact.Id);
        System.debug('\nCampaign Memberships: ' + campaigns.size());
        for (String campaignName : campaigns) {
            System.debug('  - ' + campaignName);
        }

        if (campaigns.isEmpty()) {
            System.debug('\nNot in any NHM campaigns');
            System.debug('Possible reasons:');
            System.debug('  1. Event Registration Sync hasn\'t run yet');
            System.debug('  2. Contact was synced via Contact Sync (not Event Registration Sync)');
            System.debug('  3. Event name doesn\'t match keywords');
            System.debug('  4. Registration email consent check failed');
        }

        System.debug('=== END QUICK CHECK ===\n');
    }

    /**
     * Diagnostic method to check why a contact is not being created in Salesforce
     */
    public static void diagnoseContactCreation(String contactIdentifier) {
        System.debug('=== DIAGNOSING CONTACT CREATION ===');
        System.debug('Contact Identifier: ' + contactIdentifier);

        Boolean isNumericId = Pattern.matches('^\\d+$', contactIdentifier);
        if (!isNumericId) {
            System.debug('Not a numeric ID. Please provide numeric contact ID.');
            return;
        }

        ArloSecureAuth auth;
        try {
            auth = ArloSecureAuth.getInstance();
        } catch (Exception e) {
            System.debug('ERROR: Could not load credentials: ' + e.getMessage());
            return;
        }

        // Get contact status
        System.debug('\n=== STEP 1: Check Contact Status in Arlo ===');
        String contactXml = auth.getXml('/resources/contacts/' + contactIdentifier);
        if (String.isBlank(contactXml)) {
            System.debug('Contact not found in Arlo or error retrieving');
            return;
        }

        ArloModels.ArloContact arloContact = ArloXmlParser.parseContactDetails(contactXml);
        if (arloContact == null) {
            System.debug('Could not parse contact details');
            return;
        }

        System.debug('Contact Status: ' + (arloContact.status != null ? arloContact.status : 'NULL'));
        if (arloContact.status != 'Active') {
            System.debug('REASON: Contact is NOT Active');
            return;
        }
        System.debug('Contact is Active');

        System.debug('\n=== STEP 2: Check Contact Details ===');
        System.debug('UUID: ' + (arloContact.contactId != null ? arloContact.contactId : 'NULL'));
        System.debug('Email: ' + (arloContact.email != null ? arloContact.email : 'NULL'));

        // Check if exists in Salesforce
        System.debug('\n=== STEP 3: Check if Exists in Salesforce ===');
        Contact sfContact = findContactByArloData(arloContact);
        if (sfContact != null) {
            System.debug('Contact ALREADY EXISTS in Salesforce:');
            System.debug('  Contact ID: ' + sfContact.Id);
            System.debug('  Name: ' + sfContact.FirstName + ' ' + sfContact.LastName);
            return;
        }
        System.debug('Contact does NOT exist in Salesforce - should be created');

        System.debug('\n=== END DIAGNOSIS ===\n');
    }

    /**
     * Trace a specific contact through the full sync process
     */
    public static void traceContactInSync(String numericContactId) {
        System.debug('=== TRACING CONTACT IN SYNC ===');
        System.debug('Contact Numeric ID: ' + numericContactId);
        System.debug('This contact will be traced through the full sync process');
        System.debug('Look for debug messages containing: "*** CONTACT ' + numericContactId + '"');
        System.debug('=== END TRACE SETUP ===\n');
    }

    /**
     * Test event name mapping
     */
    public static String testEventNameMapping(String eventName) {
        System.debug('=== TESTING EVENT NAME MAPPING ===');
        System.debug('Event Name: ' + eventName);
        String campaignName = EventCampaignMapper.getCampaignNameForEvent(eventName);
        System.debug('Result: ' + (campaignName != null ? campaignName : 'NO MATCH'));
        System.debug('=== END TEST ===\n');
        return campaignName;
    }

    // ==================== Helper Methods ====================

    /**
     * Find a contact by identifier (ID, Email, or UUID)
     */
    private static Contact findContactByIdentifier(String identifier) {
        if (String.isBlank(identifier)) {
            return null;
        }

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name
            FROM Contact
            WHERE Id = :identifier
               OR Email = :identifier
               OR Arlo_Contact_UUID__c = :identifier
            LIMIT 1
        ];

        return contacts.isEmpty() ? null : contacts[0];
    }

    /**
     * Find a Salesforce contact by Arlo contact data
     */
    private static Contact findContactByArloData(ArloModels.ArloContact arloContact) {
        if (arloContact == null) {
            return null;
        }

        List<Contact> contacts = new List<Contact>();

        if (String.isNotBlank(arloContact.contactId)) {
            contacts = [
                SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name
                FROM Contact
                WHERE Arlo_Contact_UUID__c = :arloContact.contactId
                LIMIT 1
            ];
        }

        if (contacts.isEmpty() && String.isNotBlank(arloContact.email)) {
            contacts = [
                SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c, AccountId, Account.Name
                FROM Contact
                WHERE Email = :arloContact.email
                LIMIT 1
            ];
        }

        return contacts.isEmpty() ? null : contacts[0];
    }

    /**
     * Helper to find SF contact and campaigns for numeric ID
     */
    private static void findSalesforceContactAndCampaigns(String numericContactId, Set<String> currentCampaignNames, Boolean isNumeric) {
        // Get contact from Arlo to find UUID/Email
        ArloSecureAuth auth;
        try {
            auth = ArloSecureAuth.getInstance();
        } catch (Exception e) {
            System.debug('Could not load credentials: ' + e.getMessage());
            return;
        }

        String contactXml = auth.getXml('/resources/contacts/' + numericContactId);
        if (String.isBlank(contactXml)) {
            return;
        }

        ArloModels.ArloContact arloContact = ArloXmlParser.parseContactDetails(contactXml);
        if (arloContact == null) {
            return;
        }

        Contact sfContact = findContactByArloData(arloContact);
        if (sfContact != null) {
            System.debug('Contact found in Salesforce:');
            System.debug('  ID: ' + sfContact.Id);
            System.debug('  Name: ' + sfContact.FirstName + ' ' + sfContact.LastName);

            List<CampaignMember> currentMembers = [
                SELECT Campaign.Name, Status
                FROM CampaignMember
                WHERE ContactId = :sfContact.Id AND Campaign.Name LIKE 'NHM - %'
            ];

            if (currentMembers.isEmpty()) {
                System.debug('Contact is NOT in any NHM campaigns');
            } else {
                System.debug('Contact is in ' + currentMembers.size() + ' NHM campaign(s):');
                for (CampaignMember cm : currentMembers) {
                    System.debug('  - ' + cm.Campaign.Name + ' (Status: ' + cm.Status + ')');
                    currentCampaignNames.add(cm.Campaign.Name);
                }
            }
        } else {
            System.debug('Contact not found in Salesforce (may not be synced yet)');
        }
    }
}