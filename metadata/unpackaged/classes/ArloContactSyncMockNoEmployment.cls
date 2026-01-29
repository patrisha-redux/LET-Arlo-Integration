/**
 * Mock HTTP callout for missing employment data
 */
@IsTest
global class ArloContactSyncMockNoEmployment implements HttpCalloutMock {
    
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
                '</Contact>');
        }
        // Employment endpoint - 404 or empty
        else if (endpoint.contains('/employment')) {
            res.setStatusCode(404);
            res.setBody('{"Code":"NotFound","Message":"Employment data not found"}');
        }
        else {
            res.setStatusCode(200);
            res.setBody('<?xml version="1.0" encoding="utf-8"?><Response>OK</Response>');
        }
        
        return res;
    }
}


