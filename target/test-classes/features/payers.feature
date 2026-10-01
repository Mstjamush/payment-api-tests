Feature: Payers and payment options (/api/payers*, /api/payment-options)

  A payer is a payment option a merchant's services can offer (M-Pesa,
  AstroPay, Airtel). Onboarded by the platform; only "mpesa", "astropay" and
  "airtel" are accepted providers - the ones payment_consumers has a
  controller for.

  # ------------------------------------------------------------------ GET /api/payers, /api/payers/{id}

  Scenario: The platform administrator can list payers
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/payers"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{payerCode}}"

  Scenario: The platform administrator can fetch one payer by id
    Given a payer has been onboarded for provider "astropay"
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/payers/{{payerId}}"
    Then the response status should be 200
    And the JSON response field "provider" should equal "astropay"

  Scenario: Fetching an unknown payer is not found
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/payers/999999999"
    Then the response status should be 404

  Scenario: Listing payers requires platform access
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payers"
    Then the response status should be 403

  # ------------------------------------------------------------------ POST /api/payers

  Scenario: Onboarding an M-Pesa payer with full provider configuration
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA M-Pesa Paybill", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "mpesa.qa@example.com", "contactPhone": "254700000000",
       "providerConfig": {"baseUrl": "https://sandbox.safaricom.example.test", "consumerKey": "key",
                          "consumerSecret": "secret", "shortcode": "174379", "passkey": "passkey",
                          "callbackUrl": "https://gateway.example.test/api/v1/payment-responses/MPESA"}}
      """
    Then the response status should be 201
    And the response header "Location" should match the pattern "/api/payers/[0-9]+"
    And the JSON response field "code" should equal "{{newPayerCode}}"
    And the JSON response field "active" should equal true
    And the JSON response field "providerConfig.baseUrl" should equal "https://sandbox.safaricom.example.test"

  Scenario: A payer's secret-looking configuration values are masked when read back
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000",
       "providerConfig": {"baseUrl": "https://sandbox.test", "consumerKey": "key", "consumerSecret": "verysecret",
                          "shortcode": "174379", "passkey": "verypasskey",
                          "callbackUrl": "https://gateway.example.test/cb"}}
      """
    Then the response status should be 201
    And the JSON response field "providerConfig.consumerSecret" should equal "********"
    And the JSON response field "providerConfig.passkey" should equal "********"
    And the JSON response field "providerConfig.baseUrl" should equal "https://sandbox.test"

  Scenario: An env-reference secret value is not masked
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000",
       "providerConfig": {"baseUrl": "https://sandbox.test", "consumerKey": "key", "consumerSecret": "${ENV:MPESA_SECRET}",
                          "shortcode": "174379", "passkey": "${ENV:MPESA_PASSKEY}",
                          "callbackUrl": "https://gateway.example.test/cb"}}
      """
    Then the response status should be 201
    And the JSON response field "providerConfig.consumerSecret" should equal "${ENV:MPESA_SECRET}"

  Scenario: A payer code must be unique
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "Duplicate", "code": "{{payerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000"}
      """
    Then the response status should be 409

  Scenario: An unsupported provider is rejected
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "paypal",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000"}
      """
    Then the response status should be 400

  Scenario Outline: Required provider configuration keys are enforced per provider
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "<provider>",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000", "providerConfig": <config>}
      """
    Then the response status should be 400
    And the error message should mention "providerConfig"

    Examples:
      | provider | config                                                                      |
      | mpesa    | {"baseUrl": "https://x.test"}                                              |
      | astropay | {"baseUrl": "https://x.test"}                                              |
      | airtel   | {"baseUrl": "https://x.test", "clientId": "c"}                             |

  Scenario: A missing merchantId is accepted, making the payer platform-wide
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000"}
      """
    Then the response status should be 201
    And the JSON response field "merchantId" should be null

  Scenario: An unknown merchantId is rejected
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000", "merchantId": 999999999}
      """
    Then the response status should be 400

  Scenario: A payer can be dedicated to a specific merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000", "merchantId": {{merchantId}}}
      """
    Then the response status should be 201
    And the JSON response field "merchantId" should equal the number "{{merchantId}}"

  Scenario: A payer and an account for it can be onboarded in one request
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    And a unique username is stored as "payerUsername"
    And a unique email address is stored as "payerUserEmail"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000",
       "payerUser": {"username": "{{payerUsername}}", "email": "{{payerUserEmail}}", "fullName": "QA Payer User"}}
      """
    Then the response status should be 201
    And the JSON response field "payerUser.username" should equal "{{payerUsername}}"
    And the JSON response field "payerUser.temporaryPassword" should not be null

  Scenario Outline: Creating a payer with a missing or invalid field is a validation error
    Given I am authenticated as the platform administrator
    And a unique payer code is stored as "newPayerCode"
    And the request body field "name" is set to the string "QA Payer"
    And the request body field "code" is set to the string "{{newPayerCode}}"
    And the request body field "type" is set to the string "MOBILE_MONEY"
    And the request body field "provider" is set to the string "mpesa"
    And the request body field "contactEmail" is set to the string "qa@example.com"
    And the request body field "contactPhone" is set to the string "254700000000"
    And <mutation>
    When I send a POST request to "/api/payers"
    Then the response status should be 400

    Examples:
      | mutation                                                              |
      | the request body field "name" is removed                             |
      | the request body field "code" is removed                             |
      | the request body field "provider" is removed                         |
      | the request body field "contactEmail" is removed                     |
      | the request body field "code" is set to the string "ab"              |
      | the request body field "contactEmail" is set to the string "invalid" |

  Scenario: Creating a payer requires platform access
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique payer code is stored as "newPayerCode"
    When I send a POST request to "/api/payers" with body:
      """
      {"name": "QA Payer", "code": "{{newPayerCode}}", "type": "MOBILE_MONEY", "provider": "mpesa",
       "contactEmail": "qa@example.com", "contactPhone": "254700000000"}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ PUT /api/payers/{id}

  Scenario: The platform administrator can update a payer's contact details
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/payers/{{payerId}}"
    Then the response status should be 200
    Then I store the response field "providerConfig" as "existingConfig"
    When I send a PUT request to "/api/payers/{{payerId}}" with body:
      """
      {"type": "MOBILE_MONEY", "contactEmail": "updated@example.com", "contactPhone": "254711111111",
       "splitPaymentsAllowed": true, "autoAcknowledgement": true, "apiEnabled": false, "isTestMode": true,
       "active": true}
      """
    Then the response status should be 200
    And the JSON response field "contactEmail" should equal "updated@example.com"
    And the JSON response field "isTestMode" should equal true

  Scenario: A payer can be deactivated
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/payers/{{payerId}}" with body:
      """
      {"type": "MOBILE_MONEY", "contactEmail": "qa@example.com", "contactPhone": "254700000000", "active": false}
      """
    Then the response status should be 200
    And the JSON response field "active" should equal false

  Scenario: Updating an unknown payer is not found
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/payers/999999999" with body:
      """
      {"type": "MOBILE_MONEY", "contactEmail": "qa@example.com", "contactPhone": "254700000000"}
      """
    Then the response status should be 404

  @edge-case
  Scenario: Updating a payer with providerConfig containing only ******** keeps the stored secret
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/payers/{{payerId}}" with body:
      """
      {"type": "MOBILE_MONEY", "contactEmail": "qa@example.com", "contactPhone": "254700000000",
       "providerConfig": {"baseUrl": "https://sandbox.safaricom.example.test", "consumerKey": "qa-consumer-key",
                          "consumerSecret": "********", "shortcode": "174379", "passkey": "********",
                          "callbackUrl": "https://gateway.example.test/api/v1/payment-responses/MPESA"}}
      """
    Then the response status should be 200
    And the JSON response field "providerConfig.consumerSecret" should equal "********"

  Scenario: Updating requires platform access
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/payers/{{payerId}}" with body:
      """
      {"type": "MOBILE_MONEY", "contactEmail": "qa@example.com", "contactPhone": "254700000000"}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ GET/POST /api/payers/{id}/users

  Scenario: A payer account can be created for an onboarded payer
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    And a unique username is stored as "payerUsername"
    And a unique email address is stored as "payerUserEmail"
    When I send a POST request to "/api/payers/{{payerId}}/users" with body:
      """
      {"username": "{{payerUsername}}", "email": "{{payerUserEmail}}", "fullName": "QA Payer User"}
      """
    Then the response status should be 201
    And the JSON response field "username" should equal "{{payerUsername}}"
    And the JSON response field "temporaryPassword" should not be null

  Scenario: Listing a payer's accounts
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/payers/{{payerId}}/users"
    Then the response status should be 200
    And the JSON response should be a list of at least 1 items

  Scenario: A payer account's username must be unique
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as the platform administrator
    And a unique username is stored as "duplicateUsername"
    And a unique email address is stored as "newEmail"
    And a unique email address is stored as "anotherNewEmail"
    When I send a POST request to "/api/payers/{{payerId}}/users" with body:
      """
      {"username": "{{duplicateUsername}}", "email": "{{newEmail}}", "fullName": "QA"}
      """
    Then the response status should be 201
    When I send a POST request to "/api/payers/{{payerId}}/users" with body:
      """
      {"username": "{{duplicateUsername}}", "email": "{{anotherNewEmail}}", "fullName": "QA"}
      """
    Then the response status should be 409

  Scenario: Creating a payer account for an unknown payer is not found
    Given I am authenticated as the platform administrator
    And a unique username is stored as "payerUsername"
    And a unique email address is stored as "payerUserEmail"
    When I send a POST request to "/api/payers/999999999/users" with body:
      """
      {"username": "{{payerUsername}}", "email": "{{payerUserEmail}}", "fullName": "QA"}
      """
    Then the response status should be 404

  # ------------------------------------------------------------------ GET /api/payment-options

  Scenario: A merchant's staff see platform-wide payers as available payment options
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payment-options"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{payerCode}}"

  Scenario: An inactive payer is not offered as a payment option
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/payers/{{payerId}}" with body:
      """
      {"type": "MOBILE_MONEY", "contactEmail": "qa@example.com", "contactPhone": "254700000000", "active": false}
      """
    Then the response status should be 200
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payment-options"
    Then the response status should be 200
    And the JSON response array "$" should not contain an item where "code" equals "{{payerCode}}"

  Scenario: A payer dedicated to one merchant is not offered to another
    Given a merchant has been fully onboarded
    And a payer has been onboarded for provider "mpesa" dedicated to the onboarded merchant
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payment-options"
    Then the response status should be 200
    And the JSON response array "$" should not contain an item where "code" equals "{{payerCode}}"

  Scenario: Payment options require a merchant account, not a payer account
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/payment-options"
    Then the response status should be 403

  Scenario: Payment options require authentication
    When I send a GET request to "/api/payment-options"
    Then the response status should be 401
