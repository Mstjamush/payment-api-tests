Feature: Provider payment-response intake (/api/v1/payment-responses/{payerCode})

  Where M-Pesa, AstroPay and Airtel deliver payment results. Nothing is
  parsed, verified or decided here - the raw body and a few headers are
  published untouched to the payment_responses queue for payment_consumers'
  payer controllers to handle, so a provider gets a fast, uniform answer.
  There is deliberately no authentication (providers can't present a bearer
  token or API key), so success here only ever needs the payer code to
  resolve and the broker to confirm the publish - the 200 response itself
  needs @requires-rabbitmq in this broker-less environment; payer resolution
  and the not-found path need neither and run by default.
  (PAYMENT_RESPONSE_ALLOWED_IPS is empty by default in this environment, so
  the IP-allowlist 403 branch is never reached and is not exercised here.)

  Scenario: An unknown payer code is not found
    When I send a POST request to "/api/v1/payment-responses/NO-SUCH-PAYER" with body:
      """
      {"ResultCode": 0}
      """
    Then the response status should be 404

  Scenario: A deactivated payer code is not found
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/payers/{{payerId}}" with body:
      """
      {"type": "MOBILE_MONEY", "contactEmail": "qa@example.com", "contactPhone": "254700000000", "active": false}
      """
    Then the response status should be 200
    Given I am not authenticated
    When I send a POST request to "/api/v1/payment-responses/{{payerCode}}" with body:
      """
      {"ResultCode": 0}
      """
    Then the response status should be 404

  Scenario: No authentication is required for a valid, active payer code
    Given a payer has been onboarded for provider "mpesa"
    Given I am not authenticated
    When I send a POST request to "/api/v1/payment-responses/{{payerCode}}" with body:
      """
      {"ResultCode": 0, "ResultDesc": "The service request is processed successfully."}
      """
    Then the response status should be 200 or 503

  Scenario: The payer code is matched case-insensitively
    Given a payer has been onboarded for provider "mpesa"
    Then the text "{{payerCode}}" is stored as "payerCodeUpper"
    Given I am not authenticated
    When I send a POST request to "/api/v1/payment-responses/{{payerCodeUpper}}" with body:
      """
      {"ResultCode": 0}
      """
    Then the response status should be 200 or 503

  Scenario: A non-JSON raw body is still accepted - the body is never parsed here
    Given a payer has been onboarded for provider "astropay"
    Given I am not authenticated
    Given the request body is the text "this is not JSON at all, just a raw provider payload <xml>ok</xml>"
    When I send a POST request to "/api/v1/payment-responses/{{payerCode}}"
    Then the response status should be 200 or 503

  Scenario: An empty body is still accepted
    Given a payer has been onboarded for provider "airtel"
    Given I am not authenticated
    Given the request body is the text ""
    When I send a POST request to "/api/v1/payment-responses/{{payerCode}}"
    Then the response status should be 200 or 503

  @requires-rabbitmq
  Scenario: An M-Pesa callback gets the ResultCode/ResultDesc shape M-Pesa expects
    Given a payer has been onboarded for provider "mpesa"
    Given I am not authenticated
    When I send a POST request to "/api/v1/payment-responses/{{payerCode}}" with body:
      """
      {"Body": {"stkCallback": {"ResultCode": 0, "ResultDesc": "Success"}}}
      """
    Then the response status should be 200
    And the JSON response field "ResultCode" should equal the number "0"
    And the JSON response field "ResultDesc" should not be null

  @requires-rabbitmq
  Scenario: A non-M-Pesa callback gets the generic queued-reference shape
    Given a payer has been onboarded for provider "astropay"
    Given I am not authenticated
    When I send a POST request to "/api/v1/payment-responses/{{payerCode}}" with body:
      """
      {"status": "APPROVED", "externalId": "qa-ext-id"}
      """
    Then the response status should be 200
    And the JSON response field "status" should equal "received"
    And the JSON response field "reference" should not be null
