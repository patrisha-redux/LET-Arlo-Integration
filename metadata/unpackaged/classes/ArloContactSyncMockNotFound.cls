/**
 * Mock HTTP callout for 404 Not Found response
 */
@IsTest
global class ArloContactSyncMockNotFound implements HttpCalloutMock {
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(404);
        res.setBody('{"Code":"NotFound","Message":"Resource not found"}');
        return res;
    }
}


