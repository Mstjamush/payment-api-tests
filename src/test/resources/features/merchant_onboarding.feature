Feature: Merchant client onboarding (POST /api/merchants through /onboarding/complete)

  A merchant client only goes live once it has a service whose settings are
  configured:
    1. POST   /api/merchants                                      profile + first administrator -> IN_PROGRESS, inactive
    2. POST   /api/merchants/{id}/services                        a service (repeat for more)
    3. PUT    /api/merchants/{id}/services/{serviceId}/settings   its settings (required, per active service)
       PUT    .../payment-options, .../notification-preferences   optional
    4. POST   /api/merchants/{id}/onboarding/complete              go live
       GET    /api/merchants/{id}/onboarding                      checklist and next step, at any point
  All of it needs a super-merchant caller with merchants.manage.

  # ------------------------------------------------------------------ the full happy path, step by step

  Scenario: Onboarding a merchant client end to end
    Given I am authenticated as the platform administrator
    And a unique merchant code is stored as "newMerchantCode"
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"

    # Step 1: profile + administrator
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "QA Onboarding Co", "code": "{{newMerchantCode}}", "contactEmail": "ops@example.com",
       "contactPhone": "+254700000001", "superAdminUsername": "{{adminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "{{adminEmail}}"}
      """
    Then the response status should be 201
    And the response header "Location" should match the pattern "/api/merchants/[0-9]+/onboarding"
    And the JSON response field "merchant.active" should equal false
    And the JSON response field "merchant.onboardingStatus" should equal "IN_PROGRESS"
    And the JSON response field "superAdminId" should not be null
    And the JSON response field "onboarding.nextStep" should equal "SERVICE"
    And the JSON response field "onboarding.canComplete" should equal false
    Then I store the response field "merchant.id" as "newMerchantId"

    # It cannot go live yet, and its API key cannot be issued
    When I send a POST request to "/api/merchants/{{newMerchantId}}/onboarding/complete"
    Then the response status should be 409
    And the error message should mention "create at least one active service"
    When I send a POST request to "/api/merchants/{{newMerchantId}}/api-key"
    Then the response status should be 409

    # Step 2: a service, unconfigured
    When I send a POST request to "/api/merchants/{{newMerchantId}}/services" with body:
      """
      {"code": "qa-onboarding-service", "name": "QA Onboarding Service"}
      """
    Then the response status should be 201
    And the JSON response field "settings.configured" should equal false
    Then I store the response field "id" as "newServiceId"

    When I send a POST request to "/api/merchants/{{newMerchantId}}/onboarding/complete"
    Then the response status should be 409
    And the error message should mention "qa-onboarding-service"

    When I send a GET request to "/api/merchants/{{newMerchantId}}/onboarding"
    Then the response status should be 200
    And the JSON response field "nextStep" should equal "SERVICE_SETTINGS"
    And the JSON response field "services[0].settingsConfigured" should equal false

    # Step 3: configure its settings
    When I send a PUT request to "/api/merchants/{{newMerchantId}}/services/{{newServiceId}}/settings" with body:
      """
      {"invoiceRequirement": "OPTIONAL", "autoAcknowledge": false, "holdPayments": false, "ackMaxAttempts": 5,
       "notifyCustomers": true, "chargeModel": "NONE"}
      """
    Then the response status should be 200
    And the JSON response field "settings.configured" should equal true

    When I send a GET request to "/api/merchants/{{newMerchantId}}/onboarding"
    Then the response status should be 200
    And the JSON response field "canComplete" should equal true
    And the JSON response field "nextStep" should equal "COMPLETE"

    # Step 4: go live
    When I send a POST request to "/api/merchants/{{newMerchantId}}/onboarding/complete"
    Then the response status should be 200
    And the JSON response field "merchant.active" should equal true
    And the JSON response field "merchant.onboardingStatus" should equal "COMPLETED"
    And the JSON response field "onboarding.status" should equal "COMPLETED"
    And the JSON response field "initialAdmin.email" should equal "{{adminEmail}}"
    And the JSON response field "initialAdmin.temporaryPassword" should not be null
    Then I store the response field "initialAdmin.temporaryPassword" as "issuedTemporaryPassword"

    # completing again is rejected
    When I send a POST request to "/api/merchants/{{newMerchantId}}/onboarding/complete"
    Then the response status should be 409
    And the error message should mention "already complete"

    # the administrator can now sign in
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{adminEmail}}", "password": "{{issuedTemporaryPassword}}"}
      """
    Then the response status should be 200
    And the JSON response field "mustChangePassword" should equal true

  # ------------------------------------------------------------------ GET /api/merchants/{id}/onboarding

  Scenario: The checklist lists every step with its required flag
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/merchants/{{merchantId}}/onboarding"
    Then the response status should be 200
    And the JSON response array "steps" should have size 4
    And the JSON response field "steps[0].key" should equal "PROFILE"
    And the JSON response field "steps[0].done" should equal true
    And the JSON response field "steps[1].key" should equal "SERVICE"
    And the JSON response field "steps[1].required" should equal true
    And the JSON response field "steps[3].key" should equal "PAYMENT_OPTIONS"
    And the JSON response field "steps[3].required" should equal false

  Scenario: A fully onboarded merchant's checklist has no missing steps and no next step
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/merchants/{{merchantId}}/onboarding"
    Then the response status should be 200
    And the JSON response field "status" should equal "COMPLETED"
    And the JSON response array "missing" should have size 0
    And the JSON response field "canComplete" should equal false
    And the JSON response field "nextStep" should be null

  Scenario: Onboarding status for an unknown merchant is not found
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/merchants/999999999/onboarding"
    Then the response status should be 404

  Scenario: Onboarding status is platform-only
    Given a merchant has been fully onboarded
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/merchants/{{merchantId}}/onboarding"
    Then the response status should be 403

  # ------------------------------------------------------------------ POST /api/merchants (step 1) - negative / edge

  Scenario: A merchant code must be unique
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "Duplicate Co", "code": "{{merchantCode}}", "contactEmail": "ops2@example.com",
       "contactPhone": "+254700000002", "superAdminUsername": "{{adminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "{{adminEmail}}"}
      """
    Then the response status should be 409

  Scenario: The initial administrator's username or email must be unused
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And a unique merchant code is stored as "newMerchantCode"
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "QA Co", "code": "{{newMerchantCode}}", "contactEmail": "ops3@example.com",
       "contactPhone": "+254700000003", "superAdminUsername": "{{merchantAdminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "someone.new@example.com"}
      """
    Then the response status should be 409

  Scenario Outline: Creating a merchant with a missing or invalid field is a validation error
    Given I am authenticated as the platform administrator
    And a unique merchant code is stored as "newMerchantCode"
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"
    And the request body field "name" is set to the string "QA Co"
    And the request body field "code" is set to the string "{{newMerchantCode}}"
    And the request body field "contactEmail" is set to the string "ops@example.com"
    And the request body field "contactPhone" is set to the string "+254700000000"
    And the request body field "superAdminUsername" is set to the string "{{adminUsername}}"
    And the request body field "superAdminFullName" is set to the string "QA Admin"
    And the request body field "superAdminEmail" is set to the string "{{adminEmail}}"
    And <mutation>
    When I send a POST request to "/api/merchants"
    Then the response status should be 400

    Examples:
      | mutation                                                                |
      | the request body field "name" is removed                               |
      | the request body field "code" is removed                               |
      | the request body field "contactEmail" is removed                       |
      | the request body field "superAdminUsername" is removed                 |
      | the request body field "superAdminEmail" is removed                    |
      | the request body field "code" is set to the string "ab"                |
      | the request body field "code" is set to the string "has a space"       |
      | the request body field "contactEmail" is set to the string "not-valid" |
      | the request body field "superAdminEmail" is set to the string "nope"   |

  @edge-case
  Scenario: A merchant code is normalised to upper case
    Given I am authenticated as the platform administrator
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"
    And a unique string of length 8 is stored as "codeSuffix"
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "QA Lower Co", "code": "qa-lower-{{codeSuffix}}", "contactEmail": "ops@example.com",
       "contactPhone": "+254700000000", "superAdminUsername": "{{adminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "{{adminEmail}}"}
      """
    Then the response status should be 201
    And the JSON response field "merchant.code" should match the pattern "QA-LOWER-[A-Z0-9]+"

  Scenario: An unknown payer id in payerIds is rejected
    Given I am authenticated as the platform administrator
    And a unique merchant code is stored as "newMerchantCode"
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "QA Co", "code": "{{newMerchantCode}}", "contactEmail": "ops@example.com",
       "contactPhone": "+254700000000", "superAdminUsername": "{{adminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "{{adminEmail}}", "payerIds": [999999999]}
      """
    Then the response status should be 400

  Scenario: An existing payer can be dedicated to a new merchant at onboarding time
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    And a unique merchant code is stored as "newMerchantCode"
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "QA Co", "code": "{{newMerchantCode}}", "contactEmail": "ops@example.com",
       "contactPhone": "+254700000000", "superAdminUsername": "{{adminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "{{adminEmail}}", "payerIds": [{{payerId}}]}
      """
    Then the response status should be 201
    And the JSON response array "merchant.payerIds" should contain "{{payerId}}"

  Scenario: Enabling API access at onboarding requires a callback URL
    Given I am authenticated as the platform administrator
    And a unique merchant code is stored as "newMerchantCode"
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "QA Co", "code": "{{newMerchantCode}}", "contactEmail": "ops@example.com",
       "contactPhone": "+254700000000", "superAdminUsername": "{{adminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "{{adminEmail}}", "apiEnabled": true}
      """
    Then the response status should be 400

  Scenario: Onboarding requires platform access
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique merchant code is stored as "newMerchantCode"
    And a unique email address is stored as "adminEmail"
    And a unique username is stored as "adminUsername"
    When I send a POST request to "/api/merchants" with body:
      """
      {"name": "QA Co", "code": "{{newMerchantCode}}", "contactEmail": "ops@example.com",
       "contactPhone": "+254700000000", "superAdminUsername": "{{adminUsername}}",
       "superAdminFullName": "QA Admin", "superAdminEmail": "{{adminEmail}}"}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ step 2/3: services during onboarding

  Scenario: Sending settings at service creation configures it immediately
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "preconfigured", "name": "Preconfigured", "settings": {"invoiceRequirement": "OPTIONAL"}}
      """
    Then the response status should be 201
    And the JSON response field "settings.configured" should equal true

  Scenario: A service code must be unique within the merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "{{serviceCode}}", "name": "Duplicate"}
      """
    Then the response status should be 409

  Scenario Outline: An invalid service code at onboarding time is a validation error
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "<code>", "name": "QA Service"}
      """
    Then the response status should be 400

    Examples:
      | code            |
      | a               |
      | has a space     |
      | has_$ymbol      |

  Scenario: Adding a service to an unknown merchant is not found
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/999999999/services" with body:
      """
      {"code": "whatever", "name": "Whatever"}
      """
    Then the response status should be 404

  Scenario: Configuring settings for an unknown service on the merchant is not found
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/services/999999999/settings" with body:
      """
      {"invoiceRequirement": "OPTIONAL"}
      """
    Then the response status should be 404

  @edge-case
  Scenario: Settings default to OPTIONAL invoicing and no holding when sent empty
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "defaults-service", "name": "Defaults"}
      """
    Then the response status should be 201
    Then I store the response field "id" as "defaultsServiceId"
    When I send a PUT request to "/api/merchants/{{merchantId}}/services/{{defaultsServiceId}}/settings" with body:
      """
      {}
      """
    Then the response status should be 200
    And the JSON response field "settings.invoiceRequirement" should equal "OPTIONAL"
    And the JSON response field "settings.holdPayments" should equal false
    And the JSON response field "settings.ackMaxAttempts" should equal the number "5"
    And the JSON response field "settings.configured" should equal true

  Scenario: An invalid invoiceRequirement is a validation error
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "bad-settings", "name": "Bad"}
      """
    Then the response status should be 201
    Then I store the response field "id" as "badServiceId"
    When I send a PUT request to "/api/merchants/{{merchantId}}/services/{{badServiceId}}/settings" with body:
      """
      {"invoiceRequirement": "NOT_A_REAL_VALUE"}
      """
    Then the response status should be 400

  Scenario: A FIXED charge model requires a fixedChargeAmount
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "fixed-charge", "name": "Fixed"}
      """
    Then the response status should be 201
    Then I store the response field "id" as "fixedServiceId"
    When I send a PUT request to "/api/merchants/{{merchantId}}/services/{{fixedServiceId}}/settings" with body:
      """
      {"invoiceRequirement": "OPTIONAL", "chargeModel": "FIXED"}
      """
    Then the response status should be 400

  Scenario: A callback URL that resolves to an internal address is rejected
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "bad-callback", "name": "Bad Callback"}
      """
    Then the response status should be 201
    Then I store the response field "id" as "badCallbackServiceId"
    When I send a PUT request to "/api/merchants/{{merchantId}}/services/{{badCallbackServiceId}}/settings" with body:
      """
      {"invoiceRequirement": "OPTIONAL", "callbackUrl": "http://127.0.0.1:9000/callback"}
      """
    Then the response status should be 400

  Scenario: Onboarding step endpoints require platform access
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "nope", "name": "Nope"}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ step 4: go live - more edge cases

  @edge-case
  Scenario: An inactive service does not block onboarding or count towards it
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/services" with body:
      """
      {"code": "inactive-one", "name": "Inactive", "active": false}
      """
    Then the response status should be 201
    When I send a GET request to "/api/merchants/{{merchantId}}/onboarding"
    Then the response status should be 200
    And the JSON response field "nextStep" should equal "SERVICE"
    And the JSON response field "missing[0]" should equal "SERVICE"

  Scenario: Onboarding completion requires platform access
    Given a merchant has been fully onboarded without changing the administrator's temporary password
    Given I am authenticated as the administrator of that merchant
    When I send a POST request to "/api/merchants/{{merchantId}}/onboarding/complete"
    Then the response status should be 403
