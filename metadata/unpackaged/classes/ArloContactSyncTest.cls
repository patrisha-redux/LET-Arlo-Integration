/**
 * ArloContactSyncTest
 *
 * Test class for ArloContactSync.
 *
 * @author Life Education
 * @date 2026
 */
@isTest
private class ArloContactSyncTest {

    /**
     * Mock HTTP callout for contact API
     */
    private class MockArloContactApi implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public MockArloContactApi(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/xml');
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    /**
     * Mock HTTP callout that throws an exception
     */
    private class MockArloContactApiThrowsError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated callout failure');
        }
    }

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test School', AccountNumber = 'TEST001');
        insert testAccount;
    }

    @isTest
    static void testArloContactClass() {
        ArloModels.ArloContact contact = new ArloModels.ArloContact();
        contact.contactId = 'uuid-123';
        contact.numericContactId = '456';
        contact.firstName = 'John';
        contact.lastName = 'Doe';
        contact.email = 'john@test.com';
        contact.phone = '021123456';
        contact.title = 'Teacher';
        contact.organisationId = 'org-789';
        contact.organisationCodePrimary = 'ORG001';
        contact.status = 'Active';

        System.assertEquals('uuid-123', contact.contactId);
        System.assertEquals('456', contact.numericContactId);
        System.assertEquals('John', contact.firstName);
        System.assertEquals('Doe', contact.lastName);
        System.assertEquals('john@test.com', contact.email);
        System.assertEquals('021123456', contact.phone);
        System.assertEquals('Teacher', contact.title);
        System.assertEquals('org-789', contact.organisationId);
        System.assertEquals('ORG001', contact.organisationCodePrimary);
        System.assertEquals('Active', contact.status);
    }

    @isTest
    static void testGetSingleArloContactStaticSuccess() {
        String xmlResponse = '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Contact xmlns="http://schemas.arlo.co/api/2012/02/auth/">' +
            '<UniqueIdentifier>uuid-test-123</UniqueIdentifier>' +
            '<FirstName>Jane</FirstName>' +
            '<LastName>Smith</LastName>' +
            '<Email>jane@test.com</Email>' +
            '<PhoneWork>09-1234567</PhoneWork>' +
            '<JobTitle>Principal</JobTitle>' +
            '<Status>Active</Status>' +
            '<Link rel="http://schemas.arlo.co/api/2012/02/auth/Employment" href="https://test.arlo.co/api/organisations/999/"/>' +
            '</Contact>';

        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(200, xmlResponse));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('123', 'user', 'pass');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a contact');
        System.assertEquals('uuid-test-123', result.contactId);
        System.assertEquals('Jane', result.firstName);
        System.assertEquals('Smith', result.lastName);
        System.assertEquals('jane@test.com', result.email);
        System.assertEquals('09-1234567', result.phone);
        System.assertEquals('Principal', result.title);
        System.assertEquals('Active', result.status);
    }

    @isTest
    static void testGetSingleArloContactStaticMobilePhone() {
        String xmlResponse = '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Contact xmlns="http://schemas.arlo.co/api/2012/02/auth/">' +
            '<UniqueIdentifier>uuid-456</UniqueIdentifier>' +
            '<FirstName>Bob</FirstName>' +
            '<LastName>Jones</LastName>' +
            '<Email>bob@test.com</Email>' +
            '<PhoneMobile>021-9876543</PhoneMobile>' +
            '<Status>Active</Status>' +
            '</Contact>';

        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(200, xmlResponse));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('456', 'user', 'pass');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('021-9876543', result.phone, 'Should use mobile phone when work phone is blank');
    }

    @isTest
    static void testGetSingleArloContactStaticBlankId() {
        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('', 'user', 'pass');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for blank ID');
    }

    @isTest
    static void testGetSingleArloContactStaticNullId() {
        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic(null, 'user', 'pass');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null ID');
    }

    @isTest
    static void testGetSingleArloContactStaticHttpError() {
        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(404, 'Not Found'));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('999', 'user', 'pass');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for HTTP error');
    }

    @isTest
    static void testSyncContactsToSalesforceStaticNewContact() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'new-uuid-001';
        ac.firstName = 'New';
        ac.lastName = 'Contact';
        ac.email = 'new@test.com';
        ac.phone = '021111222';
        ac.title = 'Teacher';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        List<Contact> created = [SELECT Id, FirstName, LastName, Email, Phone, Title, Arlo_Contact_UUID__c
                                  FROM Contact WHERE Arlo_Contact_UUID__c = 'new-uuid-001'];
        System.assertEquals(1, created.size(), 'Should create one contact');
        System.assertEquals('New', created[0].FirstName);
        System.assertEquals('Contact', created[0].LastName);
        System.assertEquals('new@test.com', created[0].Email);
    }

    @isTest
    static void testSyncContactsToSalesforceStaticUpdateExisting() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact without UUID
        Contact existingContact = new Contact(
            FirstName = 'Existing',
            LastName = 'Person',
            Email = 'existing@test.com',
            AccountId = testAccount.Id
        );
        insert existingContact;

        // Sync with matching email and new UUID
        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'update-uuid-002';
        ac.firstName = 'Existing';
        ac.lastName = 'Person';
        ac.email = 'existing@test.com';
        ac.phone = '021333444';
        ac.title = 'Principal';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact updated = [SELECT Id, Arlo_Contact_UUID__c, Phone, Title FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('update-uuid-002', updated.Arlo_Contact_UUID__c, 'Should update UUID');
        System.assertEquals('021333444', updated.Phone, 'Should update phone');
        System.assertEquals('Principal', updated.Title, 'Should update title');
    }

    @isTest
    static void testSyncContactsToSalesforceStaticMatchByUuid() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact with UUID
        Contact existingContact = new Contact(
            FirstName = 'UUID',
            LastName = 'Match',
            Email = 'uuid@test.com',
            Arlo_Contact_UUID__c = 'existing-uuid-003',
            AccountId = testAccount.Id
        );
        insert existingContact;

        // Sync with matching UUID but different email
        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'existing-uuid-003';
        ac.firstName = 'UUID';
        ac.lastName = 'Match';
        ac.email = 'different@test.com';
        ac.phone = '021555666';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        // Should not create duplicate, should update existing
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Arlo_Contact_UUID__c = 'existing-uuid-003'];
        System.assertEquals(1, contacts.size(), 'Should not create duplicate');
    }

    @isTest
    static void testSyncContactsToSalesforceStaticNullInputs() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        Test.startTest();
        // Test with null contacts list
        ArloContactSync.syncContactsToSalesforceStatic(null, testAccount.Id);
        // Test with empty list
        ArloContactSync.syncContactsToSalesforceStatic(new List<ArloModels.ArloContact>(), testAccount.Id);
        // Test with null account
        List<ArloModels.ArloContact> contacts = new List<ArloModels.ArloContact>();
        contacts.add(new ArloModels.ArloContact());
        ArloContactSync.syncContactsToSalesforceStatic(contacts, null);
        Test.stopTest();

        // Should not throw exceptions
        System.assert(true, 'Should handle null inputs gracefully');
    }

    @isTest
    static void testSyncContactsToSalesforceStaticMissingLastName() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'no-lastname-uuid';
        ac.firstName = 'NoLast';
        ac.lastName = null;  // Missing last name
        ac.email = 'nolast@test.com';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact created = [SELECT LastName FROM Contact WHERE Arlo_Contact_UUID__c = 'no-lastname-uuid'];
        System.assertEquals('Unknown', created.LastName, 'Should use "Unknown" for missing last name');
    }

    /**
     * Test getSingleArloContactStatic with empty XML response
     */
    @isTest
    static void testGetSingleArloContactStaticEmptyXml() {
        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(200, ''));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('123', 'user', 'pass');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for empty XML body');
    }

    /**
     * Test parsing XML with no matching elements
     * ArloXmlParser returns null when no meaningful contact data is found
     */
    @isTest
    static void testGetSingleArloContactStaticMinimalXml() {
        String xmlResponse = '<?xml version="1.0" encoding="UTF-8"?><Contact></Contact>';

        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(200, xmlResponse));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('123', 'user', 'pass');
        Test.stopTest();

        // ArloXmlParser returns null when no meaningful contact data is found
        System.assertEquals(null, result, 'Should return null when XML contains no contact data');
    }

    /**
     * Test sync with contact that has blank contactId but valid email
     */
    @isTest
    static void testSyncContactsBlankContactIdWithEmail() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = '';  // Blank UUID
        ac.firstName = 'NoUuid';
        ac.lastName = 'Person';
        ac.email = 'nouuid@test.com';
        ac.phone = '021999888';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        List<Contact> created = [SELECT Id, FirstName, LastName, Email FROM Contact WHERE Email = 'nouuid@test.com'];
        System.assertEquals(1, created.size(), 'Should create contact without UUID');
        System.assertEquals('NoUuid', created[0].FirstName);
    }

    /**
     * Test sync with contact that has blank email
     */
    @isTest
    static void testSyncContactsBlankEmail() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'no-email-uuid';
        ac.firstName = 'NoEmail';
        ac.lastName = 'User';
        ac.email = '';  // Blank email
        ac.phone = '021777666';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        List<Contact> created = [SELECT Id, FirstName, LastName FROM Contact WHERE Arlo_Contact_UUID__c = 'no-email-uuid'];
        System.assertEquals(1, created.size(), 'Should create contact without email');
    }

    /**
     * Test sync when existing contact already has phone and title (no update needed)
     */
    @isTest
    static void testSyncContactsNoUpdateNeeded() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact with all fields populated
        Contact existingContact = new Contact(
            FirstName = 'Complete',
            LastName = 'Contact',
            Email = 'complete@test.com',
            Phone = '021444555',
            Title = 'Manager',
            Arlo_Contact_UUID__c = 'complete-uuid',
            AccountId = testAccount.Id
        );
        insert existingContact;

        // Sync with same UUID - should not update since all fields present
        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'complete-uuid';
        ac.firstName = 'Complete';
        ac.lastName = 'Contact';
        ac.email = 'complete@test.com';
        ac.phone = '021999000';  // Different phone
        ac.title = 'Director';   // Different title
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact afterSync = [SELECT Phone, Title FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('021444555', afterSync.Phone, 'Phone should not be overwritten');
        System.assertEquals('Manager', afterSync.Title, 'Title should not be overwritten');
    }

    /**
     * Test sync matching by email with case variation
     */
    @isTest
    static void testSyncContactsEmailCaseInsensitive() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact with lowercase email
        Contact existingContact = new Contact(
            FirstName = 'Case',
            LastName = 'Test',
            Email = 'casetest@test.com',
            AccountId = testAccount.Id
        );
        insert existingContact;

        // Sync with uppercase email
        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'case-uuid';
        ac.firstName = 'Case';
        ac.lastName = 'Test';
        ac.email = 'CASETEST@TEST.COM';  // Uppercase
        ac.phone = '021888777';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact afterSync = [SELECT Arlo_Contact_UUID__c, Phone FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('case-uuid', afterSync.Arlo_Contact_UUID__c, 'Should match by email case-insensitively');
        System.assertEquals('021888777', afterSync.Phone, 'Should update phone');
    }

    /**
     * Test syncing multiple contacts at once
     */
    @isTest
    static void testSyncMultipleContacts() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();

        // First contact - new
        ArloModels.ArloContact ac1 = new ArloModels.ArloContact();
        ac1.contactId = 'multi-uuid-1';
        ac1.firstName = 'Multi';
        ac1.lastName = 'One';
        ac1.email = 'multi1@test.com';
        arloContacts.add(ac1);

        // Second contact - new
        ArloModels.ArloContact ac2 = new ArloModels.ArloContact();
        ac2.contactId = 'multi-uuid-2';
        ac2.firstName = 'Multi';
        ac2.lastName = 'Two';
        ac2.email = 'multi2@test.com';
        arloContacts.add(ac2);

        // Third contact - new
        ArloModels.ArloContact ac3 = new ArloModels.ArloContact();
        ac3.contactId = 'multi-uuid-3';
        ac3.firstName = 'Multi';
        ac3.lastName = 'Three';
        ac3.email = 'multi3@test.com';
        arloContacts.add(ac3);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        List<Contact> created = [SELECT Id FROM Contact WHERE Arlo_Contact_UUID__c LIKE 'multi-uuid-%'];
        System.assertEquals(3, created.size(), 'Should create all three contacts');
    }

    /**
     * Test sync with empty string lastName (vs null)
     */
    @isTest
    static void testSyncContactsEmptyStringLastName() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'empty-lastname-uuid';
        ac.firstName = 'EmptyLast';
        ac.lastName = '';  // Empty string
        ac.email = 'emptylast@test.com';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact created = [SELECT LastName FROM Contact WHERE Arlo_Contact_UUID__c = 'empty-lastname-uuid'];
        System.assertEquals('Unknown', created.LastName, 'Should use "Unknown" for empty last name');
    }

    /**
     * Test sync with contact having both null contactId and null email
     */
    @isTest
    static void testSyncContactsNullBothIdentifiers() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = null;
        ac.firstName = 'NoId';
        ac.lastName = 'NoEmail';
        ac.email = null;
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        List<Contact> created = [SELECT Id, FirstName, LastName FROM Contact WHERE FirstName = 'NoId' AND LastName = 'NoEmail'];
        System.assertEquals(1, created.size(), 'Should create contact without identifiers');
    }

    /**
     * Test sync updates existing contact matched by UUID - adding phone only
     */
    @isTest
    static void testSyncContactsUpdatePhoneOnly() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact with UUID and title but no phone
        Contact existingContact = new Contact(
            FirstName = 'PhoneOnly',
            LastName = 'Update',
            Email = 'phoneonly@test.com',
            Title = 'Existing Title',
            Arlo_Contact_UUID__c = 'phone-only-uuid',
            AccountId = testAccount.Id
        );
        insert existingContact;

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'phone-only-uuid';
        ac.firstName = 'PhoneOnly';
        ac.lastName = 'Update';
        ac.email = 'phoneonly@test.com';
        ac.phone = '021123123';
        ac.title = 'New Title';  // Should not update since existing has title
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact afterSync = [SELECT Phone, Title FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('021123123', afterSync.Phone, 'Should add phone');
        System.assertEquals('Existing Title', afterSync.Title, 'Should not overwrite existing title');
    }

    /**
     * Test sync updates existing contact matched by UUID - adding title only
     */
    @isTest
    static void testSyncContactsUpdateTitleOnly() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact with UUID and phone but no title
        Contact existingContact = new Contact(
            FirstName = 'TitleOnly',
            LastName = 'Update',
            Email = 'titleonly@test.com',
            Phone = '021456456',
            Arlo_Contact_UUID__c = 'title-only-uuid',
            AccountId = testAccount.Id
        );
        insert existingContact;

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'title-only-uuid';
        ac.firstName = 'TitleOnly';
        ac.lastName = 'Update';
        ac.email = 'titleonly@test.com';
        ac.phone = '021999999';  // Should not update since existing has phone
        ac.title = 'New Title';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact afterSync = [SELECT Phone, Title FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('021456456', afterSync.Phone, 'Should not overwrite existing phone');
        System.assertEquals('New Title', afterSync.Title, 'Should add title');
    }

    /**
     * Test HTTP 500 server error response
     */
    @isTest
    static void testGetSingleArloContactStaticServerError() {
        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(500, 'Internal Server Error'));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('123', 'user', 'pass');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for server error');
    }

    /**
     * Test HTTP 401 unauthorized response
     */
    @isTest
    static void testGetSingleArloContactStaticUnauthorized() {
        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(401, 'Unauthorized'));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('123', 'user', 'pass');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for unauthorized');
    }

    /**
     * Test parsing XML with organisation link in different format
     */
    @isTest
    static void testGetSingleArloContactWithOrgLink() {
        String xmlResponse = '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Contact xmlns="http://schemas.arlo.co/api/2012/02/auth/">' +
            '<UniqueIdentifier>org-uuid-123</UniqueIdentifier>' +
            '<FirstName>Org</FirstName>' +
            '<LastName>Test</LastName>' +
            '<Link rel="http://schemas.arlo.co/api/2012/02/auth/Employment" href="https://api.arlo.co/api/organisations/ORG12345/"/>' +
            '</Contact>';

        Test.setMock(HttpCalloutMock.class, new MockArloContactApi(200, xmlResponse));

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('123', 'user', 'pass');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('ORG12345', result.organisationId, 'Should extract organisation ID from link');
    }

    /**
     * Test sync with mix of inserts and updates
     */
    @isTest
    static void testSyncContactsMixedInsertUpdate() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create one existing contact
        Contact existingContact = new Contact(
            FirstName = 'Existing',
            LastName = 'Mixed',
            Email = 'existing.mixed@test.com',
            AccountId = testAccount.Id
        );
        insert existingContact;

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();

        // Existing contact to update
        ArloModels.ArloContact ac1 = new ArloModels.ArloContact();
        ac1.contactId = 'mixed-uuid-1';
        ac1.firstName = 'Existing';
        ac1.lastName = 'Mixed';
        ac1.email = 'existing.mixed@test.com';
        ac1.phone = '021111111';
        arloContacts.add(ac1);

        // New contact to insert
        ArloModels.ArloContact ac2 = new ArloModels.ArloContact();
        ac2.contactId = 'mixed-uuid-2';
        ac2.firstName = 'New';
        ac2.lastName = 'Mixed';
        ac2.email = 'new.mixed@test.com';
        arloContacts.add(ac2);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        // Verify existing was updated
        Contact afterUpdate = [SELECT Arlo_Contact_UUID__c, Phone FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('mixed-uuid-1', afterUpdate.Arlo_Contact_UUID__c, 'Should update existing with UUID');
        System.assertEquals('021111111', afterUpdate.Phone, 'Should update existing with phone');

        // Verify new was created
        List<Contact> newContact = [SELECT Id FROM Contact WHERE Arlo_Contact_UUID__c = 'mixed-uuid-2'];
        System.assertEquals(1, newContact.size(), 'Should create new contact');
    }

    /**
     * Test sync with contact that has whitespace-only lastName
     */
    @isTest
    static void testSyncContactsWhitespaceLastName() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'whitespace-uuid';
        ac.firstName = 'Whitespace';
        ac.lastName = '   ';  // Whitespace only
        ac.email = 'whitespace@test.com';
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact created = [SELECT LastName FROM Contact WHERE Arlo_Contact_UUID__c = 'whitespace-uuid'];
        System.assertEquals('Unknown', created.LastName, 'Should use "Unknown" for whitespace-only last name');
    }

    /**
     * Test sync when Arlo contact has null phone and title (no updates available)
     */
    @isTest
    static void testSyncContactsNoNewDataToUpdate() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact with UUID but no phone/title
        Contact existingContact = new Contact(
            FirstName = 'NoData',
            LastName = 'Update',
            Email = 'nodata@test.com',
            Arlo_Contact_UUID__c = 'no-data-uuid',
            AccountId = testAccount.Id
        );
        insert existingContact;

        // Sync with matching UUID but null phone/title
        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'no-data-uuid';
        ac.firstName = 'NoData';
        ac.lastName = 'Update';
        ac.email = 'nodata@test.com';
        ac.phone = null;
        ac.title = null;
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        // Should not throw exception, contact should remain unchanged
        Contact afterSync = [SELECT Phone, Title FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals(null, afterSync.Phone, 'Phone should remain null');
        System.assertEquals(null, afterSync.Title, 'Title should remain null');
    }

    /**
     * Test that existing contact matched by email gets UUID added
     */
    @isTest
    static void testSyncContactsAddUuidToExistingByEmail() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test School' LIMIT 1];

        // Create existing contact without UUID
        Contact existingContact = new Contact(
            FirstName = 'Add',
            LastName = 'Uuid',
            Email = 'adduuid@test.com',
            Phone = '021existing',
            Title = 'Existing Title',
            AccountId = testAccount.Id
        );
        insert existingContact;

        // Sync with email match and new UUID
        List<ArloModels.ArloContact> arloContacts = new List<ArloModels.ArloContact>();
        ArloModels.ArloContact ac = new ArloModels.ArloContact();
        ac.contactId = 'new-added-uuid';
        ac.firstName = 'Add';
        ac.lastName = 'Uuid';
        ac.email = 'adduuid@test.com';
        ac.phone = null;  // Don't update phone
        ac.title = null;  // Don't update title
        arloContacts.add(ac);

        Test.startTest();
        ArloContactSync.syncContactsToSalesforceStatic(arloContacts, testAccount.Id);
        Test.stopTest();

        Contact afterSync = [SELECT Arlo_Contact_UUID__c, Phone, Title FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('new-added-uuid', afterSync.Arlo_Contact_UUID__c, 'Should add UUID to existing contact');
        System.assertEquals('021existing', afterSync.Phone, 'Phone should remain unchanged');
        System.assertEquals('Existing Title', afterSync.Title, 'Title should remain unchanged');
    }

    /**
     * Test getSingleArloContactStatic when callout throws an exception
     */
    @isTest
    static void testGetSingleArloContactStaticCalloutException() {
        Test.setMock(HttpCalloutMock.class, new MockArloContactApiThrowsError());

        Test.startTest();
        ArloModels.ArloContact result = ArloContactSync.getSingleArloContactStatic('123', 'user', 'pass');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when callout throws exception');
    }
}