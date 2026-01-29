/**
 * Test class for ArloContactSync
 * 
 * Comprehensive test coverage including positive and negative test scenarios
 * 
 * @author System Generated
 * @version 1.0
 */
@IsTest
private class ArloContactSyncTest {
    
    // Test credentials
    private static final String TEST_USERNAME = 'test@example.com';
    private static final String TEST_PASSWORD = 'testpassword';
    private static final String TEST_CONTACT_ID = '100';
    private static final String TEST_ORG_ID = '28';
    private static final String TEST_CODE_PRIMARY = '1234';
    
    /**
     * Setup test data
     */
    @TestSetup
    static void setupTestData() {
        // Create test Account with AccountNumber matching CodePrimary
        Account testAccount = new Account(
            Name = 'Test Account',
            AccountNumber = TEST_CODE_PRIMARY
        );
        insert testAccount;
        
        // Create Custom Setting for credentials
        Arlo_Credentials__c credentials = new Arlo_Credentials__c(
            Name = 'Default',
            Username__c = TEST_USERNAME,
            Password__c = TEST_PASSWORD
        );
        insert credentials;
    }
    
    /**
     * TC-AC-001: Successful Single Contact Sync
     * Positive test case
     */
    @IsTest
    static void testSuccessfulSingleContactSync() {
        // Get test Account
        Account testAccount = [SELECT Id, AccountNumber FROM Account WHERE AccountNumber = :TEST_CODE_PRIMARY LIMIT 1];
        
        // Set mock callout
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockSuccess());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify contact was created
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, MobilePhone, Arlo_Contact_UUID__c, AccountId
            FROM Contact
            WHERE Arlo_Contact_UUID__c = 'test-uuid-123'
        ];
        
        System.assertEquals(1, contacts.size(), 'Contact should be created');
        System.assertEquals('John', contacts[0].FirstName, 'FirstName should match');
        System.assertEquals('Doe', contacts[0].LastName, 'LastName should match');
        System.assertEquals('john.doe@example.com', contacts[0].Email, 'Email should match');
        System.assertEquals(testAccount.Id, contacts[0].AccountId, 'Account should be linked');
        
        // Verify log record was created
        List<Arlo_Integration_Log__c> logs = [
            SELECT Id, Status__c, Operation_Type__c, Arlo_Contact_ID__c
            FROM Arlo_Integration_Log__c
            WHERE Arlo_Contact_ID__c = :TEST_CONTACT_ID
        ];
        
        System.assert(!logs.isEmpty(), 'Log record should be created');
        System.assertEquals('Success', logs[0].Status__c, 'Log status should be Success');
    }
    
    /**
     * TC-AC-101: Invalid Credentials
     * Negative test case
     */
    @IsTest
    static void testInvalidCredentials() {
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockUnauthorized());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, 'invalid', 'invalid');
            System.assert(false, 'Should have thrown exception');
        } catch (ArloContactSync.ArloSyncException e) {
            System.assert(e.getMessage().contains('401') || e.getMessage().contains('Unauthorized'), 
                'Exception should mention authentication failure');
        }
        Test.stopTest();
    }
    
    /**
     * TC-AC-102: Missing Custom Settings
     * Negative test case
     */
    @IsTest
    static void testMissingCustomSettings() {
        // Delete Custom Setting
        delete [SELECT Id FROM Arlo_Credentials__c LIMIT 1];
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, null, null);
            System.assert(false, 'Should have thrown exception');
        } catch (ArloContactSync.ArloSyncException e) {
            System.assert(e.getMessage().contains('Credentials not configured'), 
                'Exception should mention missing credentials');
        }
        Test.stopTest();
    }
    
    /**
     * TC-AC-103: Contact Not Found in Arlo
     * Negative test case
     */
    @IsTest
    static void testContactNotFound() {
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockNotFound());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact('99999', TEST_USERNAME, TEST_PASSWORD);
            System.assert(false, 'Should have thrown exception');
        } catch (ArloContactSync.ArloSyncException e) {
            System.assert(e.getMessage().contains('not found'), 
                'Exception should mention contact not found');
        }
        Test.stopTest();
        
        // Verify log record was created with error
        List<Arlo_Integration_Log__c> logs = [
            SELECT Id, Status__c
            FROM Arlo_Integration_Log__c
            WHERE Arlo_Contact_ID__c = '99999'
        ];
        
        System.assert(!logs.isEmpty(), 'Log record should be created');
        System.assertEquals('Error', logs[0].Status__c, 'Log status should be Error');
    }
    
    /**
     * TC-AC-104: Organisation Without CodePrimary
     * Negative test case - should skip contact gracefully
     */
    @IsTest
    static void testOrganisationWithoutCodePrimary() {
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockNoCodePrimary());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
            // Should not throw exception - contact is skipped
        } catch (Exception e) {
            // If exception is thrown, it should be handled gracefully
            System.debug('Exception caught (expected): ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify contact was NOT created
        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE Arlo_Contact_UUID__c = 'test-uuid-123'
        ];
        
        System.assertEquals(0, contacts.size(), 'Contact should NOT be created when CodePrimary is missing');
    }
    
    /**
     * TC-AC-105: Account Not Found in Salesforce
     * Negative test case - should skip contact gracefully
     */
    @IsTest
    static void testAccountNotFound() {
        // Delete test Account
        delete [SELECT Id FROM Account WHERE AccountNumber = :TEST_CODE_PRIMARY LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockSuccess());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
            // Should not throw exception - contact is skipped
        } catch (Exception e) {
            // If exception is thrown, it should be handled gracefully
            System.debug('Exception caught (expected): ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify contact was NOT created
        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE Arlo_Contact_UUID__c = 'test-uuid-123'
        ];
        
        System.assertEquals(0, contacts.size(), 'Contact should NOT be created when Account is not found');
    }
    
    /**
     * TC-AC-106: Missing Employment Data
     * Negative test case
     */
    @IsTest
    static void testMissingEmploymentData() {
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockNoEmployment());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
            System.assert(false, 'Should have thrown exception');
        } catch (ArloContactSync.ArloSyncException e) {
            System.assert(e.getMessage().contains('organisation ID') || e.getMessage().contains('Employment'), 
                'Exception should mention missing employment data');
        }
        Test.stopTest();
    }
    
    /**
     * TC-AC-107: HTTP Error - 500 Internal Server Error
     * Negative test case
     */
    @IsTest
    static void testHttpServerError() {
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockServerError());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
            System.assert(false, 'Should have thrown exception');
        } catch (ArloContactSync.ArloSyncException e) {
            System.assert(e.getMessage().contains('500') || e.getMessage().contains('Status'), 
                'Exception should mention HTTP status code');
        }
        Test.stopTest();
    }
    
    /**
     * TC-AC-108: Invalid XML Response
     * Negative test case
     */
    @IsTest
    static void testInvalidXmlResponse() {
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockInvalidXml());
        
        Test.startTest();
        try {
            ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
            // May or may not throw exception depending on XML parsing
        } catch (Exception e) {
            // Exception is expected
            System.debug('Exception caught (expected): ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    /**
     * TC-AC-111: Duplicate Contact Prevention
     * Positive test case - should update existing contact
     */
    @IsTest
    static void testDuplicateContactPrevention() {
        Account testAccount = [SELECT Id FROM Account WHERE AccountNumber = :TEST_CODE_PRIMARY LIMIT 1];
        
        // Create existing contact
        Contact existingContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'john.doe@example.com',
            Arlo_Contact_UUID__c = 'test-uuid-123',
            AccountId = testAccount.Id
        );
        insert existingContact;
        
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockSuccess());
        
        Test.startTest();
        ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
        Test.stopTest();
        
        // Verify only one contact exists and it was updated
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Arlo_Contact_UUID__c
            FROM Contact
            WHERE Arlo_Contact_UUID__c = 'test-uuid-123'
        ];
        
        System.assertEquals(1, contacts.size(), 'Should have only one contact');
        System.assertEquals('John', contacts[0].FirstName, 'FirstName should be updated');
        System.assertEquals('Doe', contacts[0].LastName, 'LastName should be updated');
    }
    
    /**
     * TC-AC-004: Contact with Missing Optional Fields
     * Positive test case
     */
    @IsTest
    static void testContactWithMissingOptionalFields() {
        Account testAccount = [SELECT Id FROM Account WHERE AccountNumber = :TEST_CODE_PRIMARY LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockMinimalFields());
        
        Test.startTest();
        ArloContactSync.syncSingleContact(TEST_CONTACT_ID, TEST_USERNAME, TEST_PASSWORD);
        Test.stopTest();
        
        // Verify contact was created with required fields only
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, MobilePhone
            FROM Contact
            WHERE Arlo_Contact_UUID__c = 'test-uuid-123'
        ];
        
        System.assertEquals(1, contacts.size(), 'Contact should be created');
        System.assertNotEquals(null, contacts[0].FirstName, 'FirstName should be set');
        System.assertNotEquals(null, contacts[0].LastName, 'LastName should be set');
        // MobilePhone may be null (optional field)
    }
    
    /**
     * Test syncAllContacts method
     */
    @IsTest
    static void testSyncAllContacts() {
        Account testAccount = [SELECT Id FROM Account WHERE AccountNumber = :TEST_CODE_PRIMARY LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new ArloContactSyncMockBulkSuccess());
        
        Test.startTest();
        ArloContactSync.syncAllContacts(TEST_USERNAME, TEST_PASSWORD);
        Test.stopTest();
        
        // Verify contacts were created
        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE AccountId = :testAccount.Id
        ];
        
        System.assert(contacts.size() > 0, 'Contacts should be created');
    }
}


