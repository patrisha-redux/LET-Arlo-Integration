/**
 * ArloTestDataFactory
 *
 * Provides test data factory methods for Arlo integration tests.
 * Creates mock XML responses and test Salesforce records.
 *
 * @author Test Framework
 * @version 1.0
 */
@isTest
public class ArloTestDataFactory {

    // Arlo API namespace constants
    public static final String ARLO_NAMESPACE = 'http://schemas.arlo.co/api/2012/02/auth';
    public static final String ARLO_API_BASE_URL = 'https://lifeeducationtrust.arlo.co/api/2012-02-01/auth';

    /**
     * Creates mock XML for a collection of contacts
     * @param count Number of contacts to include in the collection
     * @return String XML representing a ContactCollection
     */
    public static String createMockContactsXml(Integer count) {
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<ContactCollection xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <Link rel="self" href="' + ARLO_API_BASE_URL + '/resources/contacts/"/>\n';

        for (Integer i = 1; i <= count; i++) {
            String contactId = String.valueOf(100 + i);
            xml += '  <Link rel="' + ARLO_NAMESPACE + '/Contact" ';
            xml += 'href="' + ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/" ';
            xml += 'title="Test Contact ' + i + '"/>\n';
        }

        // Add pagination link if more than 50 contacts
        if (count > 50) {
            xml += '  <Link rel="next" href="' + ARLO_API_BASE_URL + '/resources/contacts/?skip=50"/>\n';
        }

        xml += '</ContactCollection>';
        return xml;
    }

    /**
     * Creates mock XML for a collection of registrations
     * @param count Number of registrations to include
     * @return String XML representing a RegistrationCollection
     */
    public static String createMockRegistrationsXml(Integer count) {
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<RegistrationCollection xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <Link rel="self" href="' + ARLO_API_BASE_URL + '/resources/registrations/"/>\n';

        for (Integer i = 1; i <= count; i++) {
            String registrationId = String.valueOf(1000 + i);
            String eventId = String.valueOf(500 + i);
            String contactId = String.valueOf(100 + i);

            xml += '  <Registration>\n';
            xml += '    <RegistrationID>' + registrationId + '</RegistrationID>\n';
            xml += '    <UniqueIdentifier>reg-uuid-' + registrationId + '</UniqueIdentifier>\n';
            xml += '    <Status>Approved</Status>\n';
            xml += '    <Link rel="' + ARLO_NAMESPACE + '/related/Event" ';
            xml += 'href="' + ARLO_API_BASE_URL + '/resources/events/' + eventId + '/" ';
            xml += 'title="NHM Test Event ' + i + '"/>\n';
            xml += '    <Link rel="' + ARLO_NAMESPACE + '/related/Contact" ';
            xml += 'href="' + ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/" ';
            xml += 'title="Test Contact ' + i + '"/>\n';
            xml += '  </Registration>\n';
        }

        xml += '</RegistrationCollection>';
        return xml;
    }

    /**
     * Creates mock XML for a single event
     * @param eventId The event ID
     * @param code The event code (e.g., "NHM-2024-001")
     * @param name The event name
     * @return String XML representing an Event
     */
    public static String createMockEventXml(String eventId, String code, String name) {
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<Event xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <EventID>' + eventId + '</EventID>\n';
        xml += '  <UniqueIdentifier>event-uuid-' + eventId + '</UniqueIdentifier>\n';
        xml += '  <Code>' + code + '</Code>\n';
        xml += '  <Name>' + name + '</Name>\n';
        xml += '  <Status>Active</Status>\n';
        xml += '  <StartDateTime>2024-06-15T09:00:00Z</StartDateTime>\n';
        xml += '  <EndDateTime>2024-06-15T17:00:00Z</EndDateTime>\n';
        xml += '  <TimeZone>Pacific/Auckland</TimeZone>\n';
        xml += '  <Location>\n';
        xml += '    <Name>Auckland Training Centre</Name>\n';
        xml += '    <City>Auckland</City>\n';
        xml += '    <Country>New Zealand</Country>\n';
        xml += '  </Location>\n';
        xml += '  <Link rel="self" href="' + ARLO_API_BASE_URL + '/resources/events/' + eventId + '/"/>\n';
        xml += '  <Link rel="' + ARLO_NAMESPACE + '/related/Registrations" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/events/' + eventId + '/registrations/"/>\n';
        xml += '</Event>';
        return xml;
    }

    /**
     * Creates mock XML for a single contact
     * @param contactId The contact ID
     * @param firstName The contact's first name
     * @param lastName The contact's last name
     * @param email The contact's email address
     * @return String XML representing a Contact
     */
    public static String createMockContactXml(String contactId, String firstName, String lastName, String email) {
        String uuid = 'contact-uuid-' + contactId;
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<Contact xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <ContactID>' + contactId + '</ContactID>\n';
        xml += '  <UniqueIdentifier>' + uuid + '</UniqueIdentifier>\n';
        xml += '  <FirstName>' + firstName + '</FirstName>\n';
        xml += '  <LastName>' + lastName + '</LastName>\n';
        xml += '  <Email>' + email + '</Email>\n';
        xml += '  <PhoneMobile>+64 21 123 4567</PhoneMobile>\n';
        xml += '  <PhoneWork>+64 9 123 4567</PhoneWork>\n';
        xml += '  <Status>Active</Status>\n';
        xml += '  <CodePrimary>CP' + contactId + '</CodePrimary>\n';
        xml += '  <Link rel="self" href="' + ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/"/>\n';
        xml += '  <Link rel="' + ARLO_NAMESPACE + '/related/Employment" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/employment/"/>\n';
        xml += '  <Link rel="' + ARLO_NAMESPACE + '/related/Registrations" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/registrations/"/>\n';
        xml += '</Contact>';
        return xml;
    }

    /**
     * Creates mock XML for an organisation
     * @param orgId The organisation ID
     * @param codePrimary The primary code (used to match Salesforce Account.AccountNumber)
     * @param name The organisation name
     * @return String XML representing an Organisation
     */
    public static String createMockOrganisationXml(String orgId, String codePrimary, String name) {
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<Organisation xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <OrganisationID>' + orgId + '</OrganisationID>\n';
        xml += '  <UniqueIdentifier>org-uuid-' + orgId + '</UniqueIdentifier>\n';
        xml += '  <Name>' + name + '</Name>\n';
        xml += '  <CodePrimary>' + codePrimary + '</CodePrimary>\n';
        xml += '  <Status>Active</Status>\n';
        xml += '  <Address>\n';
        xml += '    <StreetLine1>123 Test Street</StreetLine1>\n';
        xml += '    <City>Auckland</City>\n';
        xml += '    <PostCode>1010</PostCode>\n';
        xml += '    <Country>New Zealand</Country>\n';
        xml += '  </Address>\n';
        xml += '  <Link rel="self" href="' + ARLO_API_BASE_URL + '/resources/organisations/' + orgId + '/"/>\n';
        xml += '  <Link rel="' + ARLO_NAMESPACE + '/related/Contacts" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/organisations/' + orgId + '/contacts/"/>\n';
        xml += '</Organisation>';
        return xml;
    }

    /**
     * Creates mock XML for custom fields with email consent
     * The batch class checks for field name: imhappytobeemailedaboutlifeeducationtrustnews
     * @param hasEmailConsent Whether email consent is granted
     * @return String XML representing CustomFields
     */
    public static String createMockCustomFieldsXml(Boolean hasEmailConsent) {
        String consentValue = hasEmailConsent ? 'true' : 'false';
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<CustomFields xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <CustomField>\n';
        xml += '    <FieldID>cf_le_email_consent</FieldID>\n';
        xml += '    <Name>imhappytobeemailedaboutlifeeducationtrustnews</Name>\n';
        xml += '    <Value>' + consentValue + '</Value>\n';
        xml += '  </CustomField>\n';
        xml += '  <CustomField>\n';
        xml += '    <FieldID>cf_dietary_requirements</FieldID>\n';
        xml += '    <Name>Dietary Requirements</Name>\n';
        xml += '    <Value>None</Value>\n';
        xml += '  </CustomField>\n';
        xml += '</CustomFields>';
        return xml;
    }

    /**
     * Creates and returns a test Account record
     * @param accountNumber The account number (maps to Arlo CodePrimary)
     * @param name The account name
     * @return Account The created Account record
     */
    public static Account createTestAccount(String accountNumber, String name) {
        Account acc = new Account(
            Name = name,
            AccountNumber = accountNumber,
            BillingStreet = '123 Test Street',
            BillingCity = 'Auckland',
            BillingPostalCode = '1010',
            BillingCountry = 'New Zealand'
        );
        insert acc;
        return acc;
    }

    /**
     * Creates and returns a test Contact record
     * @param accountId The parent Account Id
     * @param firstName The contact's first name
     * @param lastName The contact's last name
     * @param email The contact's email address
     * @param arloUuid The Arlo Contact UUID (stored in Arlo_Contact_UUID__c)
     * @return Contact The created Contact record
     */
    public static Contact createTestContact(Id accountId, String firstName, String lastName, String email, String arloUuid) {
        Contact con = new Contact(
            AccountId = accountId,
            FirstName = firstName,
            LastName = lastName,
            Email = email
        );

        // Only set Arlo_Contact_UUID__c if the field exists and value is provided
        if (String.isNotBlank(arloUuid)) {
            try {
                con.put('Arlo_Contact_UUID__c', arloUuid);
            } catch (Exception e) {
                // Field may not exist in test context - continue without it
                System.debug('ArloTestDataFactory: Arlo_Contact_UUID__c field not available: ' + e.getMessage());
            }
        }

        insert con;
        return con;
    }

    /**
     * Creates and returns a test Campaign record
     * @param name The campaign name
     * @return Campaign The created Campaign record
     */
    public static Campaign createTestCampaign(String name) {
        Campaign camp = new Campaign(
            Name = name,
            IsActive = true,
            Status = 'In Progress',
            Type = 'Event'
        );
        insert camp;
        return camp;
    }

    /**
     * Creates mock XML for employment data
     * Note: The rel attribute uses lowercase 'organisation' to match batch class parsing
     * @param contactId The contact ID
     * @param organisationId The organisation ID
     * @return String XML representing Employment
     */
    public static String createMockEmploymentXml(String contactId, String organisationId) {
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<EmploymentCollection xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <Employment>\n';
        xml += '    <EmploymentID>1</EmploymentID>\n';
        xml += '    <JobTitle>Teacher</JobTitle>\n';
        xml += '    <IsPrimary>true</IsPrimary>\n';
        xml += '    <OrganisationID>' + organisationId + '</OrganisationID>\n';
        xml += '    <Link rel="' + ARLO_NAMESPACE + '/related/organisation" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/organisations/' + organisationId + '/" ';
        xml += 'title="Test Organisation"/>\n';
        xml += '  </Employment>\n';
        xml += '</EmploymentCollection>';
        return xml;
    }

    /**
     * Creates mock XML for a single registration
     * @param registrationId The registration ID
     * @param eventId The event ID
     * @param contactId The contact ID
     * @return String XML representing a Registration
     */
    public static String createMockSingleRegistrationXml(String registrationId, String eventId, String contactId) {
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<Registration xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <RegistrationID>' + registrationId + '</RegistrationID>\n';
        xml += '  <UniqueIdentifier>reg-uuid-' + registrationId + '</UniqueIdentifier>\n';
        xml += '  <Status>Approved</Status>\n';
        xml += '  <Link rel="self" href="' + ARLO_API_BASE_URL + '/resources/registrations/' + registrationId + '/"/>\n';
        xml += '  <Link rel="' + ARLO_NAMESPACE + '/related/Event" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/events/' + eventId + '/"/>\n';
        xml += '  <Link rel="' + ARLO_NAMESPACE + '/related/Contact" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/"/>\n';
        xml += '  <Link rel="' + ARLO_NAMESPACE + '/related/CustomFields" ';
        xml += 'href="' + ARLO_API_BASE_URL + '/resources/registrations/' + registrationId + '/customfields/"/>\n';
        xml += '</Registration>';
        return xml;
    }

    /**
     * Creates mock XML for contact registrations collection
     * @param contactId The contact ID
     * @param registrationIds List of registration IDs
     * @return String XML representing a RegistrationCollection for a contact
     */
    public static String createMockContactRegistrationsXml(String contactId, List<String> registrationIds) {
        String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<RegistrationCollection xmlns="' + ARLO_NAMESPACE + '">\n';
        xml += '  <Link rel="self" href="' + ARLO_API_BASE_URL + '/resources/contacts/' + contactId + '/registrations/"/>\n';

        for (String regId : registrationIds) {
            xml += '  <Link rel="' + ARLO_NAMESPACE + '/Registration" ';
            xml += 'href="' + ARLO_API_BASE_URL + '/resources/registrations/' + regId + '/"/>\n';
        }

        xml += '</RegistrationCollection>';
        return xml;
    }
}