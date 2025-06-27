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

import ballerina/http;
import ballerina/time;

const int PORT = 9090;

listener http:Listener httpListener = new(PORT);

service / on httpListener {
    
    resource function post v1/oauth2/token(@http:Payload string payload) returns json|http:InternalServerError {
        return {
            access_token: "mock_access_token_123456",
            token_type: "Bearer",
            expires_in: 3600,
            scope: "https://uri.paypal.com/services/payments/payment"
        };
    }
    
    resource function get v2/payments/authorizations/[string id]() returns Authorization2|error {
        LinkDescription[] links = [
            {
                href: "https://api-m.sandbox.paypal.com/v2/payments/authorizations/" + id,
                rel: "self",
                method: "GET"
            }
        ];

        Authorization2 auth = {
            status: "CREATED",
            id,
            amount: { 
                value: "100.00", 
                currency_code: "USD" 
            },
            links,
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow())
        };

        return auth;
    }
    
    resource function post v2/payments/authorizations/[string id]/capture(@http:Payload CaptureRequest requestBody) returns Capture2|error {
        string captureId = "testCaptureId123";
        Money amount = { value: "50.00", currency_code: "USD" };
        
        Money? reqAmount = requestBody.amount;
        if reqAmount is Money {
            amount = reqAmount;
        }

        LinkDescription[] links = [
            {
                href: "https://api-m.sandbox.paypal.com/v2/payments/captures/" + captureId,
                rel: "self",
                method: "GET"
            }
        ];

        boolean finalCapture = false;
        if requestBody.final_capture is boolean {
            finalCapture = requestBody.final_capture;
        }

        Capture2 capture = {
            status: "COMPLETED",
            id: captureId,
            amount,
            final_capture: finalCapture,
            links,
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow())
        };

        return capture;
    }
    
    resource function post v2/payments/authorizations/[string id]/reauthorize(@http:Payload ReauthorizeRequest requestBody) returns Authorization2|error {
        string reauthId = id + "_reauth_123";
        Money amount = { value: "75.00", currency_code: "USD" };
        
        Money? reqAmount = requestBody.amount;
        if reqAmount is Money {
            amount = reqAmount;
        }

        LinkDescription[] links = [
            {
                href: "https://api-m.sandbox.paypal.com/v2/payments/authorizations/" + reauthId,
                rel: "self",
                method: "GET"
            }
        ];

        Authorization2 reauth = {
            status: "CREATED",
            id: reauthId,
            amount,
            links,
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow())
        };

        return reauth;
    }
    
    resource function post v2/payments/authorizations/[string id]/void() returns Authorization2|error? {
        Authorization2 voidedAuth = {
            status: "VOIDED",
            id,
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow())
        };

        return voidedAuth;
    }
    
    resource function get v2/payments/captures/[string id]() returns Capture2|error {
        LinkDescription[] links = [
            {
                href: "https://api-m.sandbox.paypal.com/v2/payments/captures/" + id,
                rel: "self",
                method: "GET"
            }
        ];

        Capture2 capture = {
            status: "COMPLETED",
            id,
            amount: { 
                value: "50.00", 
                currency_code: "USD" 
            },
            final_capture: false,
            links,
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow())
        };

        return capture;
    }
    
    resource function post v2/payments/captures/[string id]/refund(@http:Payload RefundRequest requestBody) returns Refund|error {
        string refundId = "testRefundId123";
        Money amount = { value: "25.00", currency_code: "USD" };
        
        Money? reqAmount = requestBody.amount;
        if reqAmount is Money {
            amount = reqAmount;
        }

        LinkDescription[] links = [
            {
                href: "https://api-m.sandbox.paypal.com/v2/payments/refunds/" + refundId,
                rel: "self",
                method: "GET"
            }
        ];

        Refund refund = {
            status: "COMPLETED",
            id: refundId,
            amount,
            custom_id: requestBody.custom_id,
            invoice_id: requestBody.invoice_id,
            note_to_payer: requestBody.note_to_payer,
            links,
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow())
        };

        return refund;
    }
    
    resource function get v2/payments/refunds/[string id]() returns Refund|error {
        LinkDescription[] links = [
            {
                href: "https://api-m.sandbox.paypal.com/v2/payments/refunds/" + id,
                rel: "self",
                method: "GET"
            }
        ];

        Refund refund = {
            status: "COMPLETED",
            id,
            amount: { 
                value: "25.00", 
                currency_code: "USD" 
            },
            links,
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow())
        };

        return refund;
    }
    
    resource function post v2/checkout/orders(@http:Payload json requestBody) returns json|http:Response {
        string orderId = "mock_order_123";
        return {
            id: orderId,
            status: "CREATED",
            intent: "AUTHORIZE",
            purchase_units: [
                {
                    reference_id: "default",
                    amount: {
                        currency_code: "USD",
                        value: "100.00"
                    },
                    description: "Test order for Ballerina PayPal integration testing"
                }
            ],
            create_time: time:utcToString(time:utcNow()),
            update_time: time:utcToString(time:utcNow()),
            links: [
                {
                    href: "https://api-m.sandbox.paypal.com/v2/checkout/orders/" + orderId,
                    rel: "self",
                    method: "GET"
                }
            ]
        };
    }
    
    resource function post v2/checkout/orders/[string id]/authorize(@http:Payload json requestBody) returns json|http:Response {
        json|error paymentSource = requestBody.payment_source;
        
        if paymentSource is json {
            json|error card = paymentSource.card;
            
            if card is json {
                json|error cardNumber = card.number;
                
                if cardNumber is json {
                    string cardNumberStr = cardNumber.toString();
                    if cardNumberStr != "4111111111111111" {
                        return createValidationErrorResponse();
                    }
                }
            }
        }
        
        string authId = "testAuthId123";
        
        return {
            id,
            status: "COMPLETED",
            purchase_units: [
                {
                    reference_id: "default",
                    payments: {
                        authorizations: [
                            {
                                id: authId,
                                status: "CREATED",
                                amount: {
                                    currency_code: "USD",
                                    value: "100.00"
                                },
                                create_time: time:utcToString(time:utcNow()),
                                update_time: time:utcToString(time:utcNow()),
                                links: [
                                    {
                                        href: "https://api-m.sandbox.paypal.com/v2/payments/authorizations/" + authId,
                                        rel: "self",
                                        method: "GET"
                                    }
                                ]
                            }
                        ]
                    }
                }
            ]
        };
    }
}

isolated function createValidationErrorResponse() returns http:Response {
    http:Response response = new;
    response.statusCode = 422;
    
    json errorJson = {
        "name": "UNPROCESSABLE_ENTITY",
        "details": [
            {
                "field": "/payment_source/card/number",
                "location": "body",
                "issue": "VALIDATION_ERROR",
                "description": "Invalid card number"
            }
        ],
        "message": "The requested action could not be performed, semantically incorrect, or failed business validation.",
        "debug_id": "mock_debug_id",
        "links": [
            {
                "href": "https://developer.paypal.com/api/rest/reference/orders/v2/errors/#VALIDATION_ERROR",
                "rel": "information_link",
                "method": "GET"
            }
        ]
    };
    
    response.setJsonPayload(errorJson);
    return response;
}
