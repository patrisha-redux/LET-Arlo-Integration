/**
 * Mock HTTP callout for 500 Internal Server Error
 */
@IsTest
global class ArloContactSyncMockServerError implements HttpCalloutMock {
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setBody('{"Code":"InternalServerError","Message":"Internal server error"}');
        return res;
    }
}


