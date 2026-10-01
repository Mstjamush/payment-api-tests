Feature: Invoices (/api/v1/invoices merchant API, /api/invoices UI)

  Creating an invoice never writes the invoices table here: the request is
  validated then published to the "invoices" queue, and payment_consumers
  creates the row - so every scenario that needs a row to actually exist
  (the real 202 QUEUED success path, and anything that reads or cancels a
  created invoice) is tagged @requires-rabbitmq and/or @requires-consumer and
  does not run by default in this environment (no broker is installed here).
  Everything else - validation, auth, not-found, listing/pagination - happens
  entirely inside payment_api and is exercised below without any broker.

  # ------------------------------------------------------------------ auth & permissions

  Scenario: Creating an invoice via the UI requires authentication
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "does-not-matter", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 401

  Scenario: A payer account cannot create an invoice via the UI
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "does-not-matter", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 403

  Scenario: Creating an invoice via the merchant API requires a valid API key
    Given I use an invalid API key
    When I send a POST request to "/api/v1/invoices" with body:
      """
      {"serviceCode": "does-not-matter", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 401

  Scenario: Creating an invoice via the merchant API fails while API access is disabled
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
    When I send a POST request to "/api/v1/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 401

  Scenario: Listing invoices requires authentication
    When I send a GET request to "/api/invoices"
    Then the response status should be 401

  Scenario: A payer account cannot list invoices
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/invoices"
    Then the response status should be 403

  Scenario: Viewing a single invoice via the UI requires authentication
    When I send a GET request to "/api/invoices/1"
    Then the response status should be 401

  Scenario: Viewing a single invoice via the merchant API requires a valid API key
    Given I use an invalid API key
    When I send a GET request to "/api/v1/invoices/does-not-matter"
    Then the response status should be 401

  Scenario: Canceling an invoice via the UI requires authentication
    When I send a POST request to "/api/invoices/1/cancel"
    Then the response status should be 401

  Scenario: Canceling an invoice via the merchant API requires a valid API key
    Given I use an invalid API key
    When I send a POST request to "/api/v1/invoices/does-not-matter/cancel"
    Then the response status should be 401

  # ------------------------------------------------------------------ service resolution

  Scenario: Creating an invoice for an unknown serviceCode is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "no-such-service", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 404

  Scenario: Creating an invoice for an unknown serviceId is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceId": 999999999, "amount": 100, "currency": "KES"}
      """
    Then the response status should be 404

  Scenario: Creating an invoice without a serviceCode or serviceId is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: A merchant administrator cannot create an invoice for another merchant's service
    Given a merchant has been fully onboarded
    Then the text "{{serviceCode}}" is stored as "otherServiceCode"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{otherServiceCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 404

  Scenario: Creating an invoice for an unknown serviceCode is not found (merchant API)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    When I send a POST request to "/api/v1/invoices" with body:
      """
      {"serviceCode": "no-such-service", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 404

  Scenario: A service that does not allow invoices rejects invoice creation
    Given I am authenticated as the administrator of a newly onboarded merchant whose service does not allow invoices
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  # ------------------------------------------------------------------ field validation (shared by UI and API)

  Scenario: An invoiceNumber longer than 100 characters is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique string of length 101 is stored as "tooLongInvoiceNumber"
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{tooLongInvoiceNumber}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: Creating an invoice without an amount is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "currency": "KES"}
      """
    Then the response status should be 400

  Scenario: Creating an invoice without a currency is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 100}
      """
    Then the response status should be 400

  Scenario Outline: Invalid amounts are rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": <amount>, "currency": "KES"}
      """
    Then the response status should be 400

    Examples:
      | amount         |
      | 0              |
      | -50            |
      | "not-a-number" |
      | 10.555         |
      | 1000000000000000 |

  Scenario: A valid amount with up to two decimal places is not rejected for its amount
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 99.99, "currency": "KES"}
      """
    Then the response status should be 202 or 503

  Scenario: An invalid currency code is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 100, "currency": "1KE"}
      """
    Then the response status should be 400

  Scenario: An invalid dueDate format is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 100, "currency": "KES", "dueDate": "31-12-2026"}
      """
    Then the response status should be 400

  Scenario: An invalid customer email is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 100, "currency": "KES",
       "customer": {"firstName": "QA", "email": "not-an-email"}}
      """
    Then the response status should be 400

  # ------------------------------------------------------------------ GET /api/invoices (listing)

  Scenario: An administrator can list invoices (possibly empty) in the paginated shape
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/invoices"
    Then the response status should be 200
    And the JSON response field "total" should not be null
    And the JSON response field "page" should equal the number "0"
    And the JSON response field "size" should equal the number "30"
    And the JSON response field "hasMore" should not be null

  Scenario: transactions.view alone is enough to list invoices
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/invoices"
    Then the response status should be 200

  Scenario: A merchant administrator cannot list another merchant's invoices
    Given a merchant has been fully onboarded
    Then the text "{{merchantId}}" is stored as "otherMerchantId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "merchantId" is "{{otherMerchantId}}"
    When I send a GET request to "/api/invoices"
    Then the response status should be 403

  Scenario: The platform administrator can list invoices for any merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And query parameter "merchantId" is "{{merchantId}}"
    When I send a GET request to "/api/invoices"
    Then the response status should be 200

  Scenario: A page size above 100 is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "limit" is "101"
    When I send a GET request to "/api/invoices"
    Then the response status should be 400

  Scenario: A page size of zero is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "limit" is "0"
    When I send a GET request to "/api/invoices"
    Then the response status should be 400

  Scenario: A negative page is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "page" is "-1"
    When I send a GET request to "/api/invoices"
    Then the response status should be 400

  Scenario: A "to" date before "from" is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "from" is "2026-06-10"
    And query parameter "to" is "2026-06-01"
    When I send a GET request to "/api/invoices"
    Then the response status should be 400

  Scenario: An invalid "from" date format is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "from" is "10-06-2026"
    When I send a GET request to "/api/invoices"
    Then the response status should be 400

  # ------------------------------------------------------------------ GET /api/invoices/{id}, GET /api/v1/invoices/{number}

  Scenario: Viewing an unknown invoice id is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/invoices/999999999"
    Then the response status should be 404

  Scenario: Viewing an unknown invoice number is not found (merchant API)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    When I send a GET request to "/api/v1/invoices/no-such-invoice-number"
    Then the response status should be 404

  # ------------------------------------------------------------------ POST .../cancel

  Scenario: Canceling an unknown invoice id is not found (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/invoices/999999999/cancel"
    Then the response status should be 404

  Scenario: Canceling an unknown invoice number is not found (merchant API)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    When I send a POST request to "/api/v1/invoices/no-such-invoice-number/cancel"
    Then the response status should be 404

  Scenario: Canceling an invoice requires transactions.create, not just transactions.view
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a POST request to "/api/invoices/1/cancel"
    Then the response status should be 403

  # ------------------------------------------------------------------ requires a reachable broker and/or payment_consumers

  @requires-rabbitmq
  Scenario: An administrator can queue a new invoice for processing (UI)
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique invoice number is stored as "newInvoiceNumber"
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{newInvoiceNumber}}", "amount": 250, "currency": "KES",
       "description": "QA invoice", "customer": {"firstName": "QA", "phone": "254700000111"}}
      """
    Then the response status should be 202
    And the JSON response field "invoiceNumber" should equal "{{newInvoiceNumber}}"
    And the JSON response field "status" should equal "QUEUED"
    And the JSON response field "reference" should not be null

  @requires-rabbitmq
  Scenario: A merchant can queue a new invoice for processing via the API
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a unique invoice number is stored as "newInvoiceNumber"
    When I send a POST request to "/api/v1/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{newInvoiceNumber}}", "amount": 250, "currency": "KES"}
      """
    Then the response status should be 202
    And the JSON response field "status" should equal "QUEUED"

  @requires-rabbitmq
  Scenario: The merchant's own service invoiceRequirement of NOT_ALLOWED is still enforced via the API
    Given I am authenticated as the administrator of a newly onboarded merchant whose service does not allow invoices
    Given I am using the onboarded merchant's API key
    When I send a POST request to "/api/v1/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 400

  @requires-rabbitmq @requires-consumer
  Scenario: A queued invoice is created by payment_consumers and can then be read back
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique invoice number is stored as "newInvoiceNumber"
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{newInvoiceNumber}}", "amount": 300, "currency": "KES"}
      """
    Then the response status should be 202
    When I wait for the invoice "{{newInvoiceNumber}}" to exist for the onboarded merchant
    When I send a GET request to "/api/invoices/{{invoiceId}}"
    Then the response status should be 200
    And the JSON response field "invoiceNumber" should equal "{{newInvoiceNumber}}"
    And the JSON response field "amount" should equal the number "300.00"
    And the JSON response field "status" should not be null

  @requires-rabbitmq @requires-consumer
  Scenario: A queued invoice is also readable via the merchant API once created
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a unique invoice number is stored as "newInvoiceNumber"
    When I send a POST request to "/api/v1/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{newInvoiceNumber}}", "amount": 150, "currency": "KES"}
      """
    Then the response status should be 202
    When I wait for the invoice "{{newInvoiceNumber}}" to exist for the onboarded merchant
    When I send a GET request to "/api/v1/invoices/{{newInvoiceNumber}}"
    Then the response status should be 200
    And the JSON response field "invoiceNumber" should equal "{{newInvoiceNumber}}"
    And the JSON response array "payments" should have size 0

  @requires-rabbitmq @requires-consumer
  Scenario: A duplicate invoiceNumber for the same merchant is rejected once the first exists
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique invoice number is stored as "newInvoiceNumber"
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{newInvoiceNumber}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 202
    When I wait for the invoice "{{newInvoiceNumber}}" to exist for the onboarded merchant
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{newInvoiceNumber}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 409

  @requires-rabbitmq @requires-consumer
  Scenario: A newly created invoice can be canceled
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique invoice number is stored as "newInvoiceNumber"
    When I send a POST request to "/api/invoices" with body:
      """
      {"serviceCode": "{{serviceCode}}", "invoiceNumber": "{{newInvoiceNumber}}", "amount": 100, "currency": "KES"}
      """
    Then the response status should be 202
    When I wait for the invoice "{{newInvoiceNumber}}" to exist for the onboarded merchant
    When I send a POST request to "/api/invoices/{{invoiceId}}/cancel"
    Then the response status should be 200
    And the JSON response field "status" should equal "CANCELED"
    When I send a POST request to "/api/invoices/{{invoiceId}}/cancel"
    Then the response status should be 200
    And the JSON response field "status" should equal "CANCELED"
