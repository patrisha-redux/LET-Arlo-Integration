/**
 * Mock HTTP callout for successful Arlo API responses
 */
@IsTest
global class ArloContactSyncMockSuccess implements HttpCalloutMock {
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        String endpoint = req.getEndpoint();
        
        // Contact endpoint
        if (endpoint.contains('/contacts/') && !endpoint.contains('/employment') && !endpoint.contains('/organisations')) {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?>' +
                '<Contact>' +
                '<ContactID>100</ContactID>' +
                '<UniqueIdentifier>test-uuid-123</UniqueIdentifier>' +
                '<FirstName>John</FirstName>' +
                '<LastName>Doe</LastName>' +
                '<Email>john.doe@example.com</Email>' +
                '<PhoneMobile>+64212345678</PhoneMobile>' +
                '<Status>Active</Status>' +
                '</Contact>');
        }
        // Employment endpoint
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
        // Contacts collection endpoint
        else if (endpoint.contains('/contacts/') && !endpoint.contains('/resources/contacts/')) {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?>' +
                '<Contacts>' +
                '<Link rel="http://schemas.arlo.co/api/2012/02/auth/Contact" href="https://lifeeducationtrust.arlo.co/api/2012-02-01/auth/resources/contacts/100/"/>' +
                '<Link rel="http://schemas.arlo.co/api/2012/02/auth/Contact" href="https://lifeeducationtrust.arlo.co/api/2012-02-01/auth/resources/contacts/101/"/>' +
                '</Contacts>');
        }
        else {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?><Response>OK</Response>');
        }
        
        return res;
    }
}


