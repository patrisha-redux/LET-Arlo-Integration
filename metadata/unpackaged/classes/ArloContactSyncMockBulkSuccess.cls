/**
 * Mock HTTP callout for bulk contact sync
 */
@IsTest
global class ArloContactSyncMockBulkSuccess implements HttpCalloutMock {
    
    private Integer callCount = 0;
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        String endpoint = req.getEndpoint();
        callCount++;
        
        // Contacts collection endpoint
        if (endpoint.contains('/resources/contacts/') && !endpoint.contains('/contacts/100/') && !endpoint.contains('/contacts/101/')) {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?>' +
                '<Contacts>' +
                '<Link rel="http://schemas.arlo.co/api/2012/02/auth/Contact" href="https://lifeeducationtrust.arlo.co/api/2012-02-01/auth/resources/contacts/100/"/>' +
                '<Link rel="http://schemas.arlo.co/api/2012/02/auth/Contact" href="https://lifeeducationtrust.arlo.co/api/2012-02-01/auth/resources/contacts/101/"/>' +
                '</Contacts>');
        }
        // Individual contact endpoints
        else if (endpoint.contains('/contacts/100/') && !endpoint.contains('/employment')) {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?>' +
                '<Contact>' +
                '<ContactID>100</ContactID>' +
                '<UniqueIdentifier>test-uuid-100</UniqueIdentifier>' +
                '<FirstName>John</FirstName>' +
                '<LastName>Doe</LastName>' +
                '<Email>john.doe@example.com</Email>' +
                '</Contact>');
        }
        else if (endpoint.contains('/contacts/101/') && !endpoint.contains('/employment')) {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?>' +
                '<Contact>' +
                '<ContactID>101</ContactID>' +
                '<UniqueIdentifier>test-uuid-101</UniqueIdentifier>' +
                '<FirstName>Jane</FirstName>' +
                '<LastName>Smith</LastName>' +
                '<Email>jane.smith@example.com</Email>' +
                '</Contact>');
        }
        // Employment endpoints
        else if (endpoint.contains('/employment')) {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?>' +
                '<Employment>' +
                '<Link rel="http://schemas.arlo.co/api/2012/02/auth/related/Organisation" href="https://lifeeducationtrust.arlo.co/api/2012-02-01/auth/resources/organisations/28/"/>' +
                '</Employment>');
        }
        // Organisation endpoint
        else if (endpoint.contains('/organisations/')) {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?>' +
                '<Organisation>' +
                '<OrganisationID>28</OrganisationID>' +
                '<CodePrimary>1234</CodePrimary>' +
                '<Name>Test Organisation</Name>' +
                '</Organisation>');
        }
        else {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?><Response>OK</Response>');
        }
        
        return res;
    }
}


