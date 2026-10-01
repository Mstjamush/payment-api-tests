Feature: A merchant's own profile and API key (/api/merchant-profile*)

  A merchant's own staff manage their own merchant's API access here, as
  opposed to /api/merchants/* (platform staff managing any merchant).

  # ------------------------------------------------------------------ GET /api/merchant-profile

  Scenario: An administrator can view their own merchant's profile
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/merchant-profile"
    Then the response status should be 200
    And the JSON response field "code" should equal "{{merchantCode}}"
    And the JSON response field "apiEnabled" should equal false

  Scenario: transactions.view alone is enough to view the merchant profile
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/merchant-profile"
    Then the response status should be 200

  Scenario: A payer account cannot view a merchant profile
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/merchant-profile"
    Then the response status should be 403

  Scenario: Viewing the merchant profile requires authentication
    When I send a GET request to "/api/merchant-profile"
    Then the response status should be 401

  # ------------------------------------------------------------------ PUT /api/merchant-profile

  Scenario: An administrator can enable API access with a valid public callback URL
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": true, "apiCallbackUrl": "https://example.com/qa-callback"}
      """
    Then the response status should be 200
    And the JSON response field "apiEnabled" should equal true
    And the JSON response field "apiCallbackUrl" should equal "https://example.com/qa-callback"

  Scenario: Enabling API access without a callback URL is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": true}
      """
    Then the response status should be 400

  Scenario Outline: A callback URL that isn't a safe public http(s) URL is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": true, "apiCallbackUrl": "<url>"}
      """
    Then the response status should be 400

    Examples:
      | url                                 |
      | ftp://example.com/callback          |
      | not-a-url-at-all                    |
      | http://127.0.0.1:9000/callback      |
      | http://localhost/callback           |
      | http://169.254.169.254/latest       |
      | http://10.0.0.5/callback            |
      | https://user:pass@example.com/cb    |

  Scenario: Disabling API access forgets the cached key, which stops working immediately
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
    When I send a GET request to "/api/v1/uploads/does-not-matter"
    Then the response status should be 401

  Scenario: Updating the merchant profile requires settings.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": false}
      """
    Then the response status should be 403

  Scenario: A payer account cannot update a merchant profile
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": false}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ POST /api/merchant-profile/api-key

  Scenario: An administrator can issue their own merchant's API key
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/merchant-profile/api-key"
    Then the response status should be 200
    And the JSON response field "apiKey" should match the pattern "mk_.+"
    And the JSON response field "apiKeyPrefix" should not be null
    And the JSON response field "note" should not be null

  Scenario: A newly issued API key works against the merchant API
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": true, "apiCallbackUrl": "https://example.com/qa-callback"}
      """
    Then the response status should be 200
    When I send a POST request to "/api/merchant-profile/api-key"
    Then the response status should be 200
    Then I store the response field "apiKey" as "newApiKey"
    Given I am not authenticated
    And request header "X-Api-Key" is set to "{{newApiKey}}"
    When I send a GET request to "/api/v1/uploads/does-not-matter"
    Then the response status should be 404

  @edge-case
  Scenario: Issuing a new API key invalidates the previous one
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": true, "apiCallbackUrl": "https://example.com/qa-callback"}
      """
    Then the response status should be 200
    When I send a POST request to "/api/merchant-profile/api-key"
    Then the response status should be 200
    Then I store the response field "apiKey" as "firstApiKey"
    When I send a POST request to "/api/merchant-profile/api-key"
    Then the response status should be 200
    Given I am not authenticated
    And request header "X-Api-Key" is set to "{{firstApiKey}}"
    When I send a GET request to "/api/v1/uploads/does-not-matter"
    Then the response status should be 401

  Scenario: Issuing an API key requires settings.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a POST request to "/api/merchant-profile/api-key"
    Then the response status should be 403
