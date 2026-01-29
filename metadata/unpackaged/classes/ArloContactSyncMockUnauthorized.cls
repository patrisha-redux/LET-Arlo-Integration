/**
 * Mock HTTP callout for 401 Unauthorized response
 */
@IsTest
global class ArloContactSyncMockUnauthorized implements HttpCalloutMock {
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(401);
        res.setBody('{"Code":"Unauthorized","Message":"Invalid credentials"}');
        return res;
    }
}


