/**
 * ArloContactSync
 *
 * Contact sync functionality for Arlo integration.
 * Provides methods to fetch/sync contacts from Arlo API to Salesforce.
 * Uses ArloApiClient for HTTP communication and ArloXmlParser for XML parsing.
 *
 * @author Life Education
 * @date 2026
 */
public class ArloContactSync {

    // ArloContact type alias - use ArloModels.ArloContact directly for new code

    /**
     * Fetch a single contact from Arlo by numeric ID
     * Uses ArloApiClient for HTTP communication and ArloXmlParser for parsing.
     */
    public static ArloModels.ArloContact getSingleArloContactStatic(String numericContactId, String username, String password) {
        if (String.isBlank(numericContactId)) {
            return null;
        }

        ArloApiClient client = new ArloApiClient(username, password);
        String endpoint = '/resources/contacts/' + numericContactId;
        String xmlBody = client.getXml(endpoint);

        if (String.isBlank(xmlBody)) {
            return null;
        }

        ArloModels.ArloContact contact = ArloXmlParser.parseContactDetails(xmlBody);

        // Extract organisation ID from employment link if available
        if (contact != null) {
            String orgLink = ArloXmlParser.extractLinkHref(xmlBody, 'employment');
            if (String.isNotBlank(orgLink)) {
                contact.organisationId = ArloXmlParser.extractIdFromUrl(orgLink, 'organisations');
            }
            // Also check for direct organisation link in href
            if (String.isBlank(contact.organisationId)) {
                Pattern orgPattern = Pattern.compile('href="[^"]*organisations/([^/"]+)/"');
                Matcher orgMatcher = orgPattern.matcher(xmlBody);
                if (orgMatcher.find()) {
                    contact.organisationId = orgMatcher.group(1);
                }
            }
        }

        return contact;
    }

    /**
     * Sync Arlo contacts to Salesforce under a specific account
     */
    public static void syncContactsToSalesforceStatic(List<ArloModels.ArloContact> arloContacts, Id accountId) {
        if (arloContacts == null || arloContacts.isEmpty() || accountId == null) {
            return;
        }

        // Collect UUIDs and emails for lookup
        Set<String> uuids = new Set<String>();
        Set<String> emails = new Set<String>();

        for (ArloModels.ArloContact ac : arloContacts) {
            if (String.isNotBlank(ac.contactId)) {
                uuids.add(ac.contactId);
            }
            if (String.isNotBlank(ac.email)) {
                emails.add(ac.email.toLowerCase());
            }
        }

        // Query existing contacts
        Map<String, Contact> existingByUuid = new Map<String, Contact>();
        Map<String, Contact> existingByEmail = new Map<String, Contact>();

        if (!uuids.isEmpty() || !emails.isEmpty()) {
            List<Contact> existing = [
                SELECT Id, FirstName, LastName, Email, Phone, Title, Arlo_Contact_UUID__c, AccountId
                FROM Contact
                WHERE (Arlo_Contact_UUID__c IN :uuids AND Arlo_Contact_UUID__c != null)
                   OR (Email IN :emails AND Email != null)
            ];

            for (Contact c : existing) {
                if (String.isNotBlank(c.Arlo_Contact_UUID__c)) {
                    existingByUuid.put(c.Arlo_Contact_UUID__c, c);
                }
                if (String.isNotBlank(c.Email)) {
                    existingByEmail.put(c.Email.toLowerCase(), c);
                }
            }
        }

        List<Contact> toInsert = new List<Contact>();
        List<Contact> toUpdate = new List<Contact>();

        for (ArloModels.ArloContact ac : arloContacts) {
            Contact existing = findExistingContact(ac, existingByUuid, existingByEmail);

            if (existing != null) {
                if (updateContactIfNeeded(existing, ac)) {
                    toUpdate.add(existing);
                }
            } else {
                toInsert.add(createNewContact(ac, accountId));
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
            System.debug('ArloContactSync: Created ' + toInsert.size() + ' contacts');
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
            System.debug('ArloContactSync: Updated ' + toUpdate.size() + ' contacts');
        }
    }

    /**
     * Find an existing contact by UUID or email
     */
    private static Contact findExistingContact(
        ArloModels.ArloContact ac,
        Map<String, Contact> existingByUuid,
        Map<String, Contact> existingByEmail
    ) {
        if (String.isNotBlank(ac.contactId) && existingByUuid.containsKey(ac.contactId)) {
            return existingByUuid.get(ac.contactId);
        }
        if (String.isNotBlank(ac.email) && existingByEmail.containsKey(ac.email.toLowerCase())) {
            return existingByEmail.get(ac.email.toLowerCase());
        }
        return null;
    }

    /**
     * Update existing contact with Arlo data if fields are blank
     * Returns true if contact was modified
     */
    private static Boolean updateContactIfNeeded(Contact existing, ArloModels.ArloContact ac) {
        Boolean needsUpdate = false;

        if (String.isBlank(existing.Arlo_Contact_UUID__c) && String.isNotBlank(ac.contactId)) {
            existing.Arlo_Contact_UUID__c = ac.contactId;
            needsUpdate = true;
        }
        if (String.isBlank(existing.Phone) && String.isNotBlank(ac.phone)) {
            existing.Phone = ac.phone;
            needsUpdate = true;
        }
        if (String.isBlank(existing.Title) && String.isNotBlank(ac.title)) {
            existing.Title = ac.title;
            needsUpdate = true;
        }

        return needsUpdate;
    }

    /**
     * Create a new Salesforce Contact from Arlo data
     */
    private static Contact createNewContact(ArloModels.ArloContact ac, Id accountId) {
        return new Contact(
            FirstName = ac.firstName,
            LastName = String.isNotBlank(ac.lastName) ? ac.lastName : 'Unknown',
            Email = ac.email,
            Phone = ac.phone,
            Title = ac.title,
            AccountId = accountId,
            Arlo_Contact_UUID__c = ac.contactId
        );
    }
}