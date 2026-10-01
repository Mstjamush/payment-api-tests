Feature: Payments (/api/v1/payments merchant API, /api/payments UI)

  Like invoices, a payment request is validated then published to the
  "payments" queue - payment_consumers creates the row, applies the
  service's invoice rules, and calls the payer; the eventual
  PENDING_ACKNOWLEDGEMENT state (and a real acknowledgement happy path) only
  arises once a provider has actually answered, which is beyond what this
  broker-less environment can exercise. Scenarios tagged @requires-rabbitmq
  and/or @requires-consumer need that stack and do not run by default here;
  everything else (validation, auth, not-found, listing) is broker-independent
  and runs below.

  # ------------------------------------------------------------------ auth & permissions

  Scenario: Creating a payment via the UI requires authentication
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "does-not-matter", "payerCode": "DOES-NOT-MATTER", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 401

  Scenario: A payer account cannot create a payment via the UI
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "does-not-matter", "payerCode": "DOES-NOT-MATTER", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 403

  Scenario: Creating a payment via the merchant API requires a valid API key
    Given I use an invalid API key
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "does-not-matter", "payerCode": "DOES-NOT-MATTER", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 401

  Scenario: Creating a payment via the merchant API fails while API access is disabled
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": true, "apiCallbackUrl": "https://example.com/qa-callback"}
      """
    Then the response status should be 200
    When I send a POST request to "/api/merchant-profile/api-key"
    Then the response status should be 200
    Then I store the response field "apiKey" as "disabledApiKey"
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": false}
      """
    Then the response status should be 200
    Given I am not authenticated
    And request header "X-Api-Key" is set to "{{disabledApiKey}}"
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "does-not-matter", "payerCode": "DOES-NOT-MATTER", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 401

  Scenario: Listing payments requires authentication
    When I send a GET request to "/api/payments"
    Then the response status should be 401

  Scenario: A payer account cannot list payments
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/payments"
    Then the response status should be 403

  Scenario: Viewing a single payment via the UI requires authentication
    When I send a GET request to "/api/payments/1"
    Then the response status should be 401

  Scenario: Viewing a single payment via the merchant API requires a valid API key
    Given I use an invalid API key
    When I send a GET request to "/api/v1/payments/does-not-matter"
    Then the response status should be 401

  Scenario: Acknowledging a payment via the UI requires authentication
    When I send a POST request to "/api/payments/1/acknowledgement" with body:
      """
      {"status": "ACCEPTED"}
      """
    Then the response status should be 401

  Scenario: Acknowledging a payment via the merchant API requires a valid API key
    Given I use an invalid API key
    When I send a POST request to "/api/v1/payments/does-not-matter/acknowledgement" with body:
      """
      {"status": "ACCEPTED"}
      """
    Then the response status should be 401

  Scenario: Acknowledging a payment requires transactions.create
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a POST request to "/api/payments/1/acknowledgement" with body:
      """
      {"status": "ACCEPTED"}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ service & payer resolution

  Scenario: Creating a payment for an unknown serviceCode is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "no-such-service", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 404

  Scenario: Creating a payment for an unknown serviceId is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceId": 999999999, "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 404

  Scenario: Creating a payment without a serviceCode or serviceId is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"payerCode": "{{payerCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A merchant administrator cannot create a payment for another merchant's service
    Given a merchant has been fully onboarded
    Then the text "{{serviceCode}}" is stored as "otherServiceCode"
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{otherServiceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 404

  Scenario: Creating a payment for an unknown serviceCode is not found (merchant API)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "no-such-service", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES",
       "phone": "254700000111"}
      """
    Then the response status should be 404

  Scenario: An unknown payer code is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "NO-SUCH-PAYER", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A missing payer code is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A payer not on the service's restricted payment-options list is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    And the onboarded payer is offered as a payment option by the onboarded service
    And a payer has been onboarded for provider "airtel"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES",
       "phone": "254700000111"}
      """
    Then the response status should be 400

  # ------------------------------------------------------------------ field validation (shared by UI and API)

  Scenario: merchantPaymentId is required on the merchant API (not auto-generated there)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES",
       "phone": "254700000111"}
      """
    Then the response status should be 400

  Scenario: merchantPaymentId is auto-generated on the UI when omitted
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES",
       "phone": "254700000111"}
      """
    Then the response status should be 202 or 503

  Scenario: A merchantPaymentId longer than 100 characters is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    And a unique string of length 101 is stored as "tooLongPaymentId"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "merchantPaymentId": "{{tooLongPaymentId}}",
       "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A phone number is required for an M-Pesa payer
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A phone number is required for an Airtel Money payer
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "airtel"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A valid ISO-3166 alpha-2 country is required for an AstroPay payer
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "astropay"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A 3-letter country code is rejected for an AstroPay payer
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "astropay"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES",
       "country": "KEN"}
      """
    Then the response status should be 400

  Scenario: A valid AstroPay payment passes validation with a proper country code
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "astropay"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES",
       "country": "BR"}
      """
    Then the response status should be 202 or 503

  Scenario: An invalid customer email is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 100, "currency": "KES",
       "phone": "254700000111", "email": "not-an-email"}
      """
    Then the response status should be 400

  Scenario Outline: Invalid amounts are rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "phone": "254700000111",
       "amount": <amount>, "currency": "KES"}
      """
    Then the response status should be 400

    Examples:
      | amount            |
      | 0                 |
      | -50               |
      | "not-a-number"    |
      | 10.555            |
      | 1000000000000000  |

  Scenario: An invalid currency code is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "phone": "254700000111",
       "amount": 100, "currency": "1KE"}
      """
    Then the response status should be 400

  Scenario: A fully valid M-Pesa payment passes validation
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "amount": 99.99, "currency": "KES",
       "phone": "254700000111", "firstName": "QA", "description": "QA payment"}
      """
    Then the response status should be 202 or 503

  # ------------------------------------------------------------------ GET /api/payments (listing)

  Scenario: An administrator can list payments (possibly empty) in the paginated shape
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payments"
    Then the response status should be 200
    And the JSON response field "total" should not be null
    And the JSON response field "page" should equal the number "0"
    And the JSON response field "size" should equal the number "30"
    And the JSON response field "hasMore" should not be null

  Scenario: transactions.view alone is enough to list payments
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/payments"
    Then the response status should be 200

  Scenario: A merchant administrator cannot list another merchant's payments
    Given a merchant has been fully onboarded
    Then the text "{{merchantId}}" is stored as "otherMerchantId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "merchantId" is "{{otherMerchantId}}"
    When I send a GET request to "/api/payments"
    Then the response status should be 403

  Scenario: The platform administrator can list payments for any merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And query parameter "merchantId" is "{{merchantId}}"
    When I send a GET request to "/api/payments"
    Then the response status should be 200

  Scenario: A page size above 100 is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "limit" is "101"
    When I send a GET request to "/api/payments"
    Then the response status should be 400

  Scenario: A negative page is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "page" is "-1"
    When I send a GET request to "/api/payments"
    Then the response status should be 400

  Scenario: A "to" date before "from" is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "from" is "2026-06-10"
    And query parameter "to" is "2026-06-01"
    When I send a GET request to "/api/payments"
    Then the response status should be 400

  # ------------------------------------------------------------------ GET /api/payments/{id}, GET /api/v1/payments/{merchantPaymentId}

  Scenario: Viewing an unknown payment id is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payments/999999999"
    Then the response status should be 404

  Scenario: Viewing an unknown merchantPaymentId is not found (merchant API)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    When I send a GET request to "/api/v1/payments/no-such-payment-id"
    Then the response status should be 404

  # ------------------------------------------------------------------ acknowledgement validation

  Scenario: An invalid acknowledgement status value is rejected (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/payments/999999999/acknowledgement" with body:
      """
      {"status": "MAYBE"}
      """
    Then the response status should be 400

  Scenario: An invalid acknowledgement status value is rejected (merchant API)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    When I send a POST request to "/api/v1/payments/no-such-payment-id/acknowledgement" with body:
      """
      {"status": "MAYBE"}
      """
    Then the response status should be 400

  Scenario: Acknowledging an unknown payment id is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/payments/999999999/acknowledgement" with body:
      """
      {"status": "ACCEPTED"}
      """
    Then the response status should be 404

  Scenario: Acknowledging an unknown merchantPaymentId is not found (merchant API)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    When I send a POST request to "/api/v1/payments/no-such-payment-id/acknowledgement" with body:
      """
      {"status": "REJECTED"}
      """
    Then the response status should be 404

  # ------------------------------------------------------------------ requires a reachable broker and/or payment_consumers

  @requires-rabbitmq
  Scenario: An administrator can queue a new payment for processing (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    And a unique merchant payment id is stored as "newPaymentId"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "merchantPaymentId": "{{newPaymentId}}",
       "amount": 250, "currency": "KES", "phone": "254700000111"}
      """
    Then the response status should be 202
    And the JSON response field "merchantPaymentId" should equal "{{newPaymentId}}"
    And the JSON response field "status" should equal "QUEUED"
    And the JSON response field "reference" should not be null

  @requires-rabbitmq
  Scenario: A merchant can queue a new payment for processing via the API
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a payer has been onboarded for provider "mpesa"
    And a unique merchant payment id is stored as "newPaymentId"
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "merchantPaymentId": "{{newPaymentId}}",
       "amount": 250, "currency": "KES", "phone": "254700000111"}
      """
    Then the response status should be 202
    And the JSON response field "status" should equal "QUEUED"

  @requires-rabbitmq @requires-consumer
  Scenario: A queued payment is created by payment_consumers and can then be read back
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    And a unique merchant payment id is stored as "newPaymentId"
    When I send a POST request to "/api/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "merchantPaymentId": "{{newPaymentId}}",
       "amount": 300, "currency": "KES", "phone": "254700000111"}
      """
    Then the response status should be 202
    When I wait for the payment "{{newPaymentId}}" to exist for the onboarded merchant
    When I send a GET request to "/api/payments/{{paymentId}}"
    Then the response status should be 200
    And the JSON response field "merchantPaymentId" should equal "{{newPaymentId}}"
    And the JSON response field "amount" should equal the number "300.00"

  @requires-rabbitmq @requires-consumer
  Scenario: A queued payment is also readable via the merchant API once created
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a payer has been onboarded for provider "mpesa"
    And a unique merchant payment id is stored as "newPaymentId"
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "merchantPaymentId": "{{newPaymentId}}",
       "amount": 150, "currency": "KES", "phone": "254700000111"}
      """
    Then the response status should be 202
    When I wait for the payment "{{newPaymentId}}" to exist for the onboarded merchant
    When I send a GET request to "/api/v1/payments/{{newPaymentId}}"
    Then the response status should be 200
    And the JSON response field "merchantPaymentId" should equal "{{newPaymentId}}"

  @requires-rabbitmq @requires-consumer
  Scenario: Repeating the same merchantPaymentId is idempotent once the first payment exists
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a payer has been onboarded for provider "mpesa"
    And a unique merchant payment id is stored as "newPaymentId"
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "merchantPaymentId": "{{newPaymentId}}",
       "amount": 100, "currency": "KES", "phone": "254700000111"}
      """
    Then the response status should be 202
    When I wait for the payment "{{newPaymentId}}" to exist for the onboarded merchant
    When I send a POST request to "/api/v1/payments" with body:
      """
      {"serviceCode": "{{serviceCode}}", "payerCode": "{{payerCode}}", "merchantPaymentId": "{{newPaymentId}}",
       "amount": 100, "currency": "KES", "phone": "254700000111"}
      """
    Then the response status should be 200
    And the JSON response field "merchantPaymentId" should equal "{{newPaymentId}}"
