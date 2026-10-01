Feature: A merchant's services and their settings (/api/services*, /api/statuses)

  A merchant has one or more services (school fees, water bills, a shop...).
  A service created without "settings" in the request gets defaults but is
  not *configured* until PUT .../settings is called - it can't take invoices
  or payments until then. Writes need settings.manage; reads accept
  settings.manage, transactions.view or reports.view.

  # ------------------------------------------------------------------ GET /api/statuses

  Scenario: The shared invoice statuses can be listed
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/statuses"
    Then the response status should be 200
    And the JSON response should be a list of exactly 9 items
    And the JSON response array "$" should contain an item where "code" equals "NEW"
    And the JSON response array "$" should contain an item where "code" equals "ACKNOWLEDGED"

  Scenario: A merchant administrator can also list the shared statuses
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/statuses"
    Then the response status should be 200

  Scenario: Listing statuses requires authentication
    When I send a GET request to "/api/statuses"
    Then the response status should be 401

  Scenario: A payer account cannot list statuses
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/statuses"
    Then the response status should be 403

  # ------------------------------------------------------------------ GET /api/services

  Scenario: An administrator can list their own merchant's services
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/services"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{serviceCode}}"

  Scenario: transactions.view alone is enough to list services
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/services"
    Then the response status should be 200

  Scenario: The platform administrator can list any merchant's services by id
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And query parameter "merchantId" is "{{merchantId}}"
    When I send a GET request to "/api/services"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{serviceCode}}"

  Scenario: A merchant administrator cannot list another merchant's services
    Given a merchant has been fully onboarded
    Then the text "{{merchantId}}" is stored as "otherMerchantId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "merchantId" is "{{otherMerchantId}}"
    When I send a GET request to "/api/services"
    Then the response status should be 403

  Scenario: Listing services requires authentication
    When I send a GET request to "/api/services"
    Then the response status should be 401

  Scenario: A payer account cannot list services
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/services"
    Then the response status should be 403

  # ------------------------------------------------------------------ GET /api/services/{id}

  Scenario: An administrator can view one of their own services
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/services/{{serviceId}}"
    Then the response status should be 200
    And the JSON response field "id" should equal the number "{{serviceId}}"
    And the JSON response field "code" should equal "{{serviceCode}}"
    And the JSON response field "settings.configured" should equal true
    And the JSON response field "settings.invoiceRequirement" should equal "OPTIONAL"
    And the JSON response field "settings.chargeModel" should equal "NONE"

  Scenario: An unconfigured service is reported as not configured
    Given a merchant has been fully onboarded
    And that merchant also has an unconfigured service
    Given I am authenticated as the administrator of that merchant
    When I send a GET request to "/api/services/{{unconfiguredServiceId}}"
    Then the response status should be 200
    And the JSON response field "settings.configured" should equal false
    And the JSON response field "settings.configuredAt" should be null

  Scenario: The platform administrator can view any merchant's service
    Given I am authenticated as the administrator of a newly onboarded merchant
    Then the text "{{serviceId}}" is stored as "otherServiceId"
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/services/{{otherServiceId}}"
    Then the response status should be 200

  Scenario: A merchant administrator cannot view another merchant's service by id
    Given I am authenticated as the administrator of a newly onboarded merchant
    Then the text "{{serviceId}}" is stored as "otherServiceId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/services/{{otherServiceId}}"
    Then the response status should be 404

  Scenario: Viewing an unknown service is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/services/999999999"
    Then the response status should be 404

  Scenario: Viewing a service requires authentication
    When I send a GET request to "/api/services/1"
    Then the response status should be 401

  # ------------------------------------------------------------------ POST /api/services

  Scenario: An administrator can create a fully configured service in one call
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/services" with body:
      """
      {
        "code": "{{newServiceCode}}",
        "name": "QA Water Bills",
        "description": "Water billing",
        "settings": {"invoiceRequirement": "REQUIRED", "autoAcknowledge": true, "holdPayments": true,
                      "ackMaxAttempts": 3, "notifyCustomers": true, "chargeModel": "NONE"},
        "paymentOptions": ["{{payerCode}}"],
        "notificationPreferences": [{"statusCode": "NEW", "channel": "SMS", "enabled": true,
                                      "messageTemplate": "Hi \{{firstName}}, invoice \{{invoiceNumber}} created"}]
      }
      """
    Then the response status should be 201
    And the response header "Location" should match the pattern "/api/services/[0-9]+"
    And the JSON response field "code" should equal "{{newServiceCode}}"
    And the JSON response field "settings.configured" should equal true
    And the JSON response field "settings.invoiceRequirement" should equal "REQUIRED"
    And the JSON response array "paymentOptions" should have size 1
    And the JSON response array "notificationPreferences" should have size 1

  Scenario: An administrator can create a service without settings, left unconfigured
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Unconfigured Service"}
      """
    Then the response status should be 201
    And the JSON response field "settings.configured" should equal false
    And the JSON response field "settings.invoiceRequirement" should equal "OPTIONAL"
    And the JSON response field "settings.chargeModel" should equal "NONE"

  Scenario: Mixed-case service codes are silently lower-cased, not rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "lowerServiceCode"
    Then the text "QA-MIXED-{{lowerServiceCode}}" is stored as "mixedServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{mixedServiceCode}}", "name": "QA Mixed Case Code"}
      """
    Then the response status should be 201
    And the JSON response field "code" should match the pattern "qa-mixed-[a-z0-9-]+"

  Scenario: A service code must be unique within a merchant
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{serviceCode}}", "name": "QA Duplicate Code"}
      """
    Then the response status should be 409

  Scenario: The same service code is allowed for two different merchants
    Given a merchant has been fully onboarded
    Then the text "{{serviceCode}}" is stored as "sharedServiceCode"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{sharedServiceCode}}", "name": "QA Shared Code"}
      """
    Then the response status should be 201

  Scenario Outline: An invalid service code is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/services" with body:
      """
      {"code": "<code>", "name": "QA Invalid Code"}
      """
    Then the response status should be 400

    Examples:
      | code                 |
      | _starts-with-dash     |
      | -starts-with-dash     |
      | has a space           |
      | has/a/slash           |
      | x                     |

  Scenario: Creating a service without a name is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}"}
      """
    Then the response status should be 400

  Scenario: Creating a service with a blank name is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": ""}
      """
    Then the response status should be 400

  Scenario: An invalid invoiceRequirement is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"invoiceRequirement": "SOMETIMES"}}
      """
    Then the response status should be 400

  Scenario: An invalid chargeModel is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "DYNAMIC"}}
      """
    Then the response status should be 400

  Scenario: The FIXED charge model requires a non-negative fixedChargeAmount
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service", "settings": {"chargeModel": "FIXED"}}
      """
    Then the response status should be 400

  Scenario: A negative fixedChargeAmount is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "FIXED", "fixedChargeAmount": -5}}
      """
    Then the response status should be 400

  Scenario: A valid FIXED charge model is accepted
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "FIXED", "fixedChargeAmount": 50}}
      """
    Then the response status should be 201
    And the JSON response field "settings.chargeModel" should equal "FIXED"

  Scenario: The PERCENTAGE charge model requires a chargePercentage between 0 and 100
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service", "settings": {"chargeModel": "PERCENTAGE"}}
      """
    Then the response status should be 400

  Scenario: A chargePercentage above 100 is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "PERCENTAGE", "chargePercentage": 150}}
      """
    Then the response status should be 400

  Scenario: A valid PERCENTAGE charge model is accepted
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "PERCENTAGE", "chargePercentage": 2.5}}
      """
    Then the response status should be 201
    And the JSON response field "settings.chargeModel" should equal "PERCENTAGE"

  Scenario: The LAYERED charge model requires at least one tier
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "LAYERED", "layeredChargeConfig": []}}
      """
    Then the response status should be 400

  Scenario: Overlapping LAYERED tiers are rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "LAYERED", "layeredChargeConfig": [
         {"min": 0, "max": 1000, "fixed": 10, "percentage": 0},
         {"min": 500, "max": 2000, "fixed": 20, "percentage": 0}
       ]}}
      """
    Then the response status should be 400

  Scenario: A valid LAYERED charge model with non-overlapping tiers is accepted
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"chargeModel": "LAYERED", "layeredChargeConfig": [
         {"min": 0, "max": 1000, "fixed": 10, "percentage": 0},
         {"min": 1000, "max": null, "fixed": 0, "percentage": 1.5}
       ]}}
      """
    Then the response status should be 201
    And the JSON response field "settings.chargeModel" should equal "LAYERED"

  Scenario Outline: An unsafe settings callback URL is rejected on create
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "settings": {"callbackUrl": "<url>"}}
      """
    Then the response status should be 400

    Examples:
      | url                                |
      | ftp://example.com/callback          |
      | http://127.0.0.1:9000/callback      |
      | http://169.254.169.254/latest       |

  Scenario: An unknown payer code as a payment option is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service", "paymentOptions": ["NO-SUCH-PAYER-CODE"]}
      """
    Then the response status should be 400

  Scenario: An unknown statusCode in a notification preference is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "notificationPreferences": [{"statusCode": "NOT_A_REAL_STATUS", "channel": "SMS", "enabled": true,
                                     "messageTemplate": "hi"}]}
      """
    Then the response status should be 400

  Scenario: An invalid notification channel is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "notificationPreferences": [{"statusCode": "NEW", "channel": "CARRIER_PIGEON", "enabled": true,
                                     "messageTemplate": "hi"}]}
      """
    Then the response status should be 400

  Scenario: Duplicate notification preferences for the same status and channel are rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "notificationPreferences": [
         {"statusCode": "NEW", "channel": "SMS", "enabled": true, "messageTemplate": "hi"},
         {"statusCode": "NEW", "channel": "SMS", "enabled": false}
       ]}
      """
    Then the response status should be 400

  Scenario: An enabled notification preference requires a messageTemplate
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "notificationPreferences": [{"statusCode": "NEW", "channel": "SMS", "enabled": true}]}
      """
    Then the response status should be 400

  Scenario: A disabled notification preference does not require a messageTemplate
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "notificationPreferences": [{"statusCode": "NEW", "channel": "SMS", "enabled": false}]}
      """
    Then the response status should be 201

  Scenario: An unknown message template placeholder is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service",
       "notificationPreferences": [{"statusCode": "NEW", "channel": "SMS", "enabled": true,
                                     "messageTemplate": "Hi \{{secretInternalField}}"}]}
      """
    Then the response status should be 400

  Scenario: The platform administrator can create a service for a specific merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"merchantId": {{merchantId}}, "code": "{{newServiceCode}}", "name": "QA Platform-Created Service"}
      """
    Then the response status should be 201
    And the JSON response field "merchantId" should equal the number "{{merchantId}}"

  Scenario: A merchant administrator cannot create a service for another merchant
    Given a merchant has been fully onboarded
    Then the text "{{merchantId}}" is stored as "otherMerchantId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"merchantId": {{otherMerchantId}}, "code": "{{newServiceCode}}", "name": "QA Cross-Merchant"}
      """
    Then the response status should be 403

  Scenario: Creating a service requires settings.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    And a unique service code is stored as "newServiceCode"
    When I send a POST request to "/api/services" with body:
      """
      {"code": "{{newServiceCode}}", "name": "QA Service"}
      """
    Then the response status should be 403

  Scenario: Creating a service requires authentication
    When I send a POST request to "/api/services" with body:
      """
      {"code": "qa-anon-service", "name": "QA Service"}
      """
    Then the response status should be 401

  # ------------------------------------------------------------------ PUT /api/services/{id}

  Scenario: An administrator can rename and deactivate a service
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}" with body:
      """
      {"name": "QA Renamed Service", "description": "Updated description", "active": false}
      """
    Then the response status should be 200
    And the JSON response field "name" should equal "QA Renamed Service"
    And the JSON response field "active" should equal false

  Scenario: Updating a service with a blank name is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}" with body:
      """
      {"name": "", "active": true}
      """
    Then the response status should be 400

  Scenario: Updating an unknown service is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/999999999" with body:
      """
      {"name": "QA Service", "active": true}
      """
    Then the response status should be 404

  Scenario: A merchant administrator cannot update another merchant's service
    Given I am authenticated as the administrator of a newly onboarded merchant
    Then the text "{{serviceId}}" is stored as "otherServiceId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{otherServiceId}}" with body:
      """
      {"name": "QA Service", "active": true}
      """
    Then the response status should be 404

  Scenario: Updating service details requires settings.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}" with body:
      """
      {"name": "QA Service", "active": true}
      """
    Then the response status should be 403

  Scenario: Updating service details requires authentication
    When I send a PUT request to "/api/services/1" with body:
      """
      {"name": "QA Service", "active": true}
      """
    Then the response status should be 401

  # ------------------------------------------------------------------ PUT /api/services/{id}/settings

  Scenario: Configuring an unconfigured service's settings marks it configured
    Given a merchant has been fully onboarded
    And that merchant also has an unconfigured service
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/services/{{unconfiguredServiceId}}/settings" with body:
      """
      {"invoiceRequirement": "REQUIRED", "autoAcknowledge": true, "holdPayments": false,
       "ackMaxAttempts": 4, "notifyCustomers": true, "chargeModel": "NONE"}
      """
    Then the response status should be 200
    And the JSON response field "settings.configured" should equal true
    And the JSON response field "settings.configuredAt" should not be null
    And the JSON response field "settings.invoiceRequirement" should equal "REQUIRED"

  Scenario: Settings for an already-configured service can be changed
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/settings" with body:
      """
      {"invoiceRequirement": "NOT_ALLOWED", "autoAcknowledge": false, "holdPayments": false,
       "ackMaxAttempts": 7, "notifyCustomers": false, "chargeModel": "NONE"}
      """
    Then the response status should be 200
    And the JSON response field "settings.invoiceRequirement" should equal "NOT_ALLOWED"
    And the JSON response field "settings.ackMaxAttempts" should equal the number "7"
    And the JSON response field "settings.notifyCustomers" should equal false

  Scenario: An invalid invoiceRequirement on settings update is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/settings" with body:
      """
      {"invoiceRequirement": "WHENEVER"}
      """
    Then the response status should be 400

  Scenario: An unsafe callback URL on settings update is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/settings" with body:
      """
      {"callbackUrl": "http://localhost/callback"}
      """
    Then the response status should be 400

  Scenario: Updating settings for an unknown service is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/999999999/settings" with body:
      """
      {"invoiceRequirement": "OPTIONAL"}
      """
    Then the response status should be 404

  Scenario: Updating service settings requires settings.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/settings" with body:
      """
      {"invoiceRequirement": "OPTIONAL"}
      """
    Then the response status should be 403

  Scenario: Updating service settings requires authentication
    When I send a PUT request to "/api/services/1/settings" with body:
      """
      {"invoiceRequirement": "OPTIONAL"}
      """
    Then the response status should be 401

  # ------------------------------------------------------------------ PUT /api/services/{id}/payment-options

  Scenario: An administrator can set a service's payment options
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a PUT request to "/api/services/{{serviceId}}/payment-options" with body:
      """
      {"payerCodes": ["{{payerCode}}"]}
      """
    Then the response status should be 200
    And the JSON response array "paymentOptions" should have size 1
    And the JSON response array "paymentOptions" should contain an item where "payerCode" equals "{{payerCode}}"

  Scenario: Payment options can be cleared with an empty list
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a PUT request to "/api/services/{{serviceId}}/payment-options" with body:
      """
      {"payerCodes": ["{{payerCode}}"]}
      """
    Then the response status should be 200
    When I send a PUT request to "/api/services/{{serviceId}}/payment-options" with body:
      """
      {"payerCodes": []}
      """
    Then the response status should be 200
    And the JSON response array "paymentOptions" should have size 0

  Scenario: An unknown payer code in a payment-options update is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/payment-options" with body:
      """
      {"payerCodes": ["NO-SUCH-PAYER-CODE"]}
      """
    Then the response status should be 400

  Scenario: Updating payment options for an unknown service is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/999999999/payment-options" with body:
      """
      {"payerCodes": []}
      """
    Then the response status should be 404

  Scenario: Updating payment options requires settings.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/payment-options" with body:
      """
      {"payerCodes": []}
      """
    Then the response status should be 403

  Scenario: Updating payment options requires authentication
    When I send a PUT request to "/api/services/1/payment-options" with body:
      """
      {"payerCodes": []}
      """
    Then the response status should be 401

  # ------------------------------------------------------------------ PUT /api/services/{id}/notification-preferences

  Scenario: An administrator can set a service's notification preferences
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/notification-preferences" with body:
      """
      {"preferences": [{"statusCode": "ACKNOWLEDGED", "channel": "EMAIL", "enabled": true,
                          "messageTemplate": "Dear \{{customerName}}, payment acknowledged"}]}
      """
    Then the response status should be 200
    And the JSON response array "notificationPreferences" should have size 1
    And the JSON response array "notificationPreferences" should contain an item where "statusCode" equals "ACKNOWLEDGED"

  Scenario: Notification preferences can be cleared with an empty list
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/notification-preferences" with body:
      """
      {"preferences": [{"statusCode": "NEW", "channel": "SMS", "enabled": false}]}
      """
    Then the response status should be 200
    When I send a PUT request to "/api/services/{{serviceId}}/notification-preferences" with body:
      """
      {"preferences": []}
      """
    Then the response status should be 200
    And the JSON response array "notificationPreferences" should have size 0

  Scenario: An unknown statusCode in a notification-preferences update is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/notification-preferences" with body:
      """
      {"preferences": [{"statusCode": "BOGUS", "channel": "SMS", "enabled": false}]}
      """
    Then the response status should be 400

  Scenario: Updating notification preferences for an unknown service is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/999999999/notification-preferences" with body:
      """
      {"preferences": []}
      """
    Then the response status should be 404

  Scenario: Updating notification preferences requires settings.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}/notification-preferences" with body:
      """
      {"preferences": []}
      """
    Then the response status should be 403

  Scenario: Updating notification preferences requires authentication
    When I send a PUT request to "/api/services/1/notification-preferences" with body:
      """
      {"preferences": []}
      """
    Then the response status should be 401
