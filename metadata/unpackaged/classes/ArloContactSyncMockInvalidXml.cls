/**
 * Mock HTTP callout for invalid XML response
 */
@IsTest
global class ArloContactSyncMockInvalidXml implements HttpCalloutMock {
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('This is not valid XML <unclosed tag');
        return res;
    }
}


