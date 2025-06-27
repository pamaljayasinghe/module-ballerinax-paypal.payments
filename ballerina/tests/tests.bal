// Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;
import ballerina/os;
import ballerina/http;
import ballerina/uuid;
import ballerina/time;

configurable string sandboxClientId = os:getEnv("PAYPAL_CLIENT_ID");
configurable string sandboxClientSecret = os:getEnv("PAYPAL_CLIENT_SECRET");
configurable boolean isLiveServer = false;
configurable string testOrderId = os:getEnv("PAYPAL_TEST_ORDER_ID");
configurable string testAuthId = os:getEnv("PAYPAL_TEST_AUTH_ID");
configurable string testCaptureId = os:getEnv("PAYPAL_TEST_CAPTURE_ID");
configurable string testRefundId = os:getEnv("PAYPAL_TEST_REFUND_ID");

const string SANDBOX_URL = "https://api-m.sandbox.paypal.com";
const string MOCK_URL = "http://localhost:9090";

string currentTestAuthId = "";
string currentTestCaptureId = "";
string currentTestRefundId = "";
string currentTestOrderId = "";

isolated function getPaypalServiceUrl() returns string => isLiveServer ? SANDBOX_URL : MOCK_URL;

Client paypal = test:mock(Client);

isolated function createOrderHttpClient() returns http:Client|error {
    string serviceUrl = getPaypalServiceUrl();
    http:OAuth2ClientCredentialsGrantConfig oauthConfig = {
        clientId: isLiveServer ? sandboxClientId : "test_client_id",
        clientSecret: isLiveServer ? sandboxClientSecret : "test_client_secret",
        tokenUrl: serviceUrl + "/v1/oauth2/token"
    };

    http:ClientConfiguration httpClientConfig = {
        auth: oauthConfig,
        timeout: 60
    };

    return new (serviceUrl, httpClientConfig);
}

isolated function createTestOrder() returns string|error {
    if !isLiveServer {
        return "mock_order_123";
    }

    string existingOrderId = testOrderId;
    if existingOrderId.length() > 0 {
        return existingOrderId;
    }

    http:Client orderClient = check createOrderHttpClient();

    record {|
        string intent;
        record {|
            record {|
                string currency_code;
                string value;
            |} amount;
            string description;
        |}[] purchase_units;
    |} orderPayload = {
        intent: "AUTHORIZE",
        purchase_units: [
            {
                amount: {
                    currency_code: "USD",
                    value: "100.00"
                },
                description: "Test order for Ballerina PayPal integration testing"
            }
        ]
    };

    http:Response orderResponse = check orderClient->post("/v2/checkout/orders", orderPayload, {
        "Content-Type": "application/json"
    });

    if orderResponse.statusCode == 200 || orderResponse.statusCode == 201 {
        json orderData = check orderResponse.getJsonPayload();
        string orderId = check orderData.id;
        return orderId;
    }

    json responseBody = check orderResponse.getJsonPayload();
    return error("Failed to create order: " + orderResponse.statusCode.toString() + " - " + responseBody.toString());
}

isolated function authorizeTestOrder(string orderId) returns string|error {
    if !isLiveServer {
        return "mock_auth_" + orderId;
    }

    string existingAuthId = testAuthId;
    if existingAuthId.length() > 0 {
        return existingAuthId;
    }

    http:Client orderClient = check createOrderHttpClient();

    record {|
        record {|
            record {|
                string number;
                string expiry;
                string security_code;
                string name;
                record {|
                    string address_line_1;
                    string admin_area_2;
                    string admin_area_1;
                    string postal_code;
                    string country_code;
                |} billing_address;
            |} card;
        |} payment_source;
    |} authorizePayload = {
        payment_source: {
            card: {
                number: "4111111111111111",
                expiry: "2029-08",
                security_code: "965",
                name: "John Doe",
                billing_address: {
                    address_line_1: "123 Main St",
                    admin_area_2: "San Jose",
                    admin_area_1: "CA",
                    postal_code: "95131",
                    country_code: "US"
                }
            }
        }
    };

    string requestId = uuid:createType1AsString();
    string authPath = "/v2/checkout/orders/" + orderId + "/authorize";

    http:Response authResponse = check orderClient->post(authPath, authorizePayload, {
        "Content-Type": "application/json",
        "PayPal-Request-Id": requestId
    });

    if authResponse.statusCode != 201 {
        json responseBody = check authResponse.getJsonPayload();
        return error("Failed to authorize order: " + authResponse.statusCode.toString() + " - " + responseBody.toString());
    }

    json authData = check authResponse.getJsonPayload();
    json[] purchaseUnitsArray = <json[]>check authData.purchase_units;
    json firstUnit = purchaseUnitsArray[0];
    json payments = check firstUnit.payments;
    json[] authArray = <json[]>check payments.authorizations;
    json firstAuth = authArray[0];
    string authId = check firstAuth.id;

    return authId;
}

isolated function handleReauthorizationError(error response) returns error? {
    if response !is http:ApplicationResponseError {
        return response;
    }
    
    http:ApplicationResponseError appError = <http:ApplicationResponseError>response;
    var detail = appError.detail();
    
    if detail.statusCode != 422 {
        return response;
    }
    
    json|error responseBody = <json>detail.body;
    if responseBody is error {
        return response;
    }
    
    json|error details = responseBody.details;
    if details is error || details !is json[] || details.length() == 0 {
        return response;
    }
    
    json|error issue = details[0].issue;
    if issue is error || issue !is string {
        return response;
    }
    
    if issue == "REAUTHORIZATION_TOO_SOON" || issue == "AUTHORIZATION_ALREADY_CAPTURED" {
        test:assertTrue(true, "Reauthorization correctly rejected: " + issue);
        return;
    }
    
    return response;
}

isolated function validateAuthorizationResponse(Authorization2 response) {
    test:assertTrue(response.id is string && response.id != "", "Reauthorization ID should be a non-empty string");
    test:assertTrue(response.status is string && response.status != "", "Reauthorization status should be a non-empty string");
}

@test:BeforeSuite
function beforeAllTests() returns error? {
    string serviceUrl = getPaypalServiceUrl();
    string paymentsServiceUrl = serviceUrl + "/v2/payments";
    
    http:OAuth2ClientCredentialsGrantConfig oauthConfig = {
        clientId: isLiveServer ? sandboxClientId : "test_client_id",
        clientSecret: isLiveServer ? sandboxClientSecret : "test_client_secret",
        tokenUrl: serviceUrl + "/v1/oauth2/token"
    };

    ConnectionConfig config = {
        auth: oauthConfig,
        timeout: 60
    };

    paypal = check new Client(config, paymentsServiceUrl);

    if !isLiveServer {
        currentTestOrderId = "mock_order_123";
        currentTestAuthId = "testAuthId123";
        currentTestCaptureId = "testCaptureId123";
        currentTestRefundId = "testRefundId123";
        return;
    }

    if sandboxClientId.length() == 0 || sandboxClientSecret.length() == 0 {
        return error("Missing sandbox credentials");
    }

    string existingAuthId = testAuthId;
    if existingAuthId.length() > 0 {
        currentTestAuthId = existingAuthId;
        currentTestCaptureId = testCaptureId;
        currentTestRefundId = testRefundId;
        return;
    }

    string orderId = check createTestOrder();
    currentTestOrderId = orderId;
    currentTestAuthId = check authorizeTestOrder(orderId);
    currentTestCaptureId = testCaptureId;
    currentTestRefundId = testRefundId;
}

@test:Config {
    groups: ["live_tests", "mock_tests"]
}
function testGetAuthorizationDetails() returns error? {
    Authorization2 response = check paypal->/authorizations/[currentTestAuthId];

    test:assertTrue(response.id is string && response.id != "", "Authorization ID should be a non-empty string");
    test:assertTrue(response.status is string && response.status != "", "Authorization status should be a non-empty string");
}

@test:Config {
    groups: ["live_tests", "mock_tests"],
    dependsOn: [testGetAuthorizationDetails]
}
function testCaptureAuthorization() returns error? {
    CaptureRequest payload = {
        amount: {
            value: "50.00",
            currency_code: "USD"
        },
        note_to_payer: "Test capture from Ballerina automated testing"
    };

    Capture2 response = check paypal->/authorizations/[currentTestAuthId]/capture.post(payload);

    test:assertTrue(response.id is string && response.id != "", "Capture ID should be a non-empty string");
    test:assertTrue(response.status is string && response.status != "", "Capture status should be a non-empty string");

    string? responseId = response.id;
    if responseId is string {
        currentTestCaptureId = responseId;
    }
}

@test:Config {
    groups: ["live_tests", "mock_tests"],
    dependsOn: [testGetAuthorizationDetails]
}
function testReauthorizeAuthorization() returns error? {
    ReauthorizeRequest payload = {
        amount: {
            value: "75.00",
            currency_code: "USD"
        }
    };

    if isLiveServer {
        Authorization2|error response = paypal->/authorizations/[currentTestAuthId]/reauthorize.post(payload);
        
        if response is error {
            return handleReauthorizationError(response);
        }
        
        validateAuthorizationResponse(response);
        return;
    }

    Authorization2 response = check paypal->/authorizations/[currentTestAuthId]/reauthorize.post(payload);
    validateAuthorizationResponse(response);
}

@test:Config {
    groups: ["live_tests", "mock_tests"],
    dependsOn: [testGetAuthorizationDetails]
}
function testVoidAuthorization() returns error? {
    string voidAuthId = currentTestAuthId;

    if isLiveServer && testAuthId.length() == 0 {
        string newOrderId = check createTestOrder();
        voidAuthId = check authorizeTestOrder(newOrderId);
        time:Utc currentTime = time:utcNow();
        time:Utc delayUntil = time:utcAddSeconds(currentTime, 5);
        while time:utcNow() < delayUntil {
        }
    }

    Authorization2? response = check paypal->/authorizations/[voidAuthId]/void.post();

    if response is Authorization2 {
        test:assertTrue(response.id is string, "Void response should contain an ID");
    }
}

@test:Config {
    groups: ["live_tests", "mock_tests"],
    dependsOn: [testCaptureAuthorization]
}
function testGetCaptureDetails() returns error? {
    Capture2 response = check paypal->/captures/[currentTestCaptureId];

    test:assertTrue(response.id is string && response.id != "", "Capture ID should be a non-empty string");
    test:assertTrue(response.status is string && response.status != "", "Capture status should be a non-empty string");
    test:assertEquals(response.id, currentTestCaptureId, "Response ID should match the request ID");
}

@test:Config {
    groups: ["live_tests", "mock_tests"],
    dependsOn: [testGetCaptureDetails]
}
function testRefundCapture() returns error? {
    RefundRequest payload = {
        amount: {
            value: "25.00",
            currency_code: "USD"
        },
        note_to_payer: "Test partial refund from Ballerina automated testing"
    };

    Refund response = check paypal->/captures/[currentTestCaptureId]/refund.post(payload);

    test:assertTrue(response.id is string && response.id != "", "Refund ID should be a non-empty string");
    test:assertTrue(response.status is string && response.status != "", "Refund status should be a non-empty string");

    string? responseId = response.id;
    if responseId is string {
        currentTestRefundId = responseId;
    }
}

@test:Config {
    groups: ["live_tests", "mock_tests"],
    dependsOn: [testRefundCapture]
}
function testGetRefundDetails() returns error? {
    Refund response = check paypal->/refunds/[currentTestRefundId];

    test:assertTrue(response.id is string && response.id != "", "Refund ID should be a non-empty string");
    test:assertTrue(response.status is string && response.status != "", "Refund status should be a non-empty string");
    test:assertEquals(response.id, currentTestRefundId, "Response ID should match the request ID");
}
