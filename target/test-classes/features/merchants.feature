Feature: Merchant management (platform staff) - GET/PUT/DELETE /api/merchants/*

  Everything here needs a super-merchant caller with merchants.manage.
  Onboarding itself (POST /api/merchants through go-live) is covered in
  merchant_onboarding.feature; this file covers managing an already-onboarded
  merchant: its access policy, role policies, deactivation, admin password
  reset and API key.

  # ------------------------------------------------------------------ GET /api/merchants

  Scenario: The platform administrator can list merchants
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/merchants"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{merchantCode}}"

  Scenario: Merchants can be searched by name, code or contact email
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And query parameter "search" is "{{merchantCode}}"
    When I send a GET request to "/api/merchants"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{merchantCode}}"

  Scenario: Merchants can be filtered by onboarding status
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    And query parameter "onboarding" is "in_progress"
    When I send a GET request to "/api/merchants"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{merchantCode}}"

  Scenario: Merchants can be filtered by active status
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And query parameter "status" is "active"
    When I send a GET request to "/api/merchants"
    Then the response status should be 200
    And the JSON response array "$" should contain an item where "code" equals "{{merchantCode}}"

  Scenario: An invalid status filter is a validation error
    Given I am authenticated as the platform administrator
    And query parameter "status" is "not-a-real-status"
    When I send a GET request to "/api/merchants"
    Then the response status should be 400

  Scenario: An invalid onboarding filter is a validation error
    Given I am authenticated as the platform administrator
    And query parameter "onboarding" is "not-a-real-status"
    When I send a GET request to "/api/merchants"
    Then the response status should be 400

  Scenario: An invalid timeframe filter is a validation error
    Given I am authenticated as the platform administrator
    And query parameter "timeframe" is "not-a-real-timeframe"
    When I send a GET request to "/api/merchants"
    Then the response status should be 400

  Scenario: Listing merchants requires platform (super-merchant) access
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/merchants"
    Then the response status should be 403

  Scenario: Listing merchants requires authentication
    When I send a GET request to "/api/merchants"
    Then the response status should be 401

  Scenario: A payer account cannot list merchants
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/merchants"
    Then the response status should be 403

  # ------------------------------------------------------------------ PUT /api/merchants/{id}/access

  Scenario: The platform administrator can change which permissions a merchant may use
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/access" with body:
      """
      {"permissionNames": ["transactions.view", "reports.view"]}
      """
    Then the response status should be 200
    And the JSON response array "permissions" should have size 2
    And the JSON response array "permissions" should contain "transactions.view"

  Scenario: Shrinking a merchant's permissions prunes role policies and direct grants that now exceed it
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/access" with body:
      """
      {"permissionNames": ["transactions.view"]}
      """
    Then the response status should be 200
    # the merchant's existing token was just invalidated by the access change - sign in again for a fresh one
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{merchantAdminEmail}}", "password": "{{merchantAdminPassword}}"}
      """
    Then the response status should be 200
    Then I store the response field "accessToken" as "refreshedMerchantAdminToken"
    Given I use the bearer token stored as "refreshedMerchantAdminToken"
    When I send a GET request to "/api/auth/me"
    Then the response status should be 200
    And the JSON response array "permissions" should not contain "settings.manage"

  Scenario: Shrinking a merchant's permissions invalidates its users' sessions
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/access" with body:
      """
      {"permissionNames": ["transactions.view"]}
      """
    Then the response status should be 200
    Given I am authenticated as the administrator of that merchant
    When I send a GET request to "/api/auth/me"
    Then the response status should be 403
    And the error message should mention "Session is no longer valid"

  Scenario: A platform-only permission cannot be granted to a merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/access" with body:
      """
      {"permissionNames": ["merchants.manage"]}
      """
    Then the response status should be 400

  Scenario: Updating access for an unknown merchant is not found
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/999999999/access" with body:
      """
      {"permissionNames": []}
      """
    Then the response status should be 404

  Scenario: Updating merchant access requires platform access
    Given a merchant has been fully onboarded
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/merchants/{{merchantId}}/access" with body:
      """
      {"permissionNames": ["transactions.view"]}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ PUT /api/merchants/{id}/roles/{roleId}/permissions

  Scenario: The platform administrator can set a merchant's default role policy
    Given a merchant has been fully onboarded
    Given I am authenticated as the administrator of that merchant
    When I send a GET request to "/api/roles"
    Then I store the response field "find { it.name == 'merchant_user' }.id" as "merchantUserRoleId"
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/roles/{{merchantUserRoleId}}/permissions" with body:
      """
      {"permissionNames": ["transactions.view"]}
      """
    Then the response status should be 200
    And the JSON response array "permissions" should have size 1

  Scenario: A merchant's role policy cannot exceed its own enabled permissions
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/access" with body:
      """
      {"permissionNames": ["transactions.view"]}
      """
    Then the response status should be 200
    When I send a GET request to "/api/roles"
    Then I store the response field "find { it.name == 'merchant_admin' }.id" as "merchantAdminRoleId"
    When I send a PUT request to "/api/merchants/{{merchantId}}/roles/{{merchantAdminRoleId}}/permissions" with body:
      """
      {"permissionNames": ["settings.manage"]}
      """
    Then the response status should be 403

  Scenario: A merchant_user role policy cannot include a *.manage permission
    Given a merchant has been fully onboarded
    Given I am authenticated as the administrator of that merchant
    When I send a GET request to "/api/roles"
    Then I store the response field "find { it.name == 'merchant_user' }.id" as "merchantUserRoleId"
    Given I am authenticated as the platform administrator
    When I send a PUT request to "/api/merchants/{{merchantId}}/roles/{{merchantUserRoleId}}/permissions" with body:
      """
      {"permissionNames": ["settings.manage"]}
      """
    Then the response status should be 400

  # ------------------------------------------------------------------ DELETE /api/merchants/{id}

  Scenario: The platform administrator can deactivate a merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a DELETE request to "/api/merchants/{{merchantId}}"
    Then the response status should be 204
    When I send a GET request to "/api/merchants"
    And query parameter "status" is "inactive"
    When I send a GET request to "/api/merchants"
    Then the JSON response array "$" should contain an item where "code" equals "{{merchantCode}}"

  Scenario: Deactivating a merchant twice is idempotent
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a DELETE request to "/api/merchants/{{merchantId}}"
    Then the response status should be 204
    When I send a DELETE request to "/api/merchants/{{merchantId}}"
    Then the response status should be 204

  Scenario: Deactivating an unknown merchant is not found
    Given I am authenticated as the platform administrator
    When I send a DELETE request to "/api/merchants/999999999"
    Then the response status should be 404

  Scenario: Deactivating a merchant requires platform access
    Given a merchant has been fully onboarded
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a DELETE request to "/api/merchants/{{merchantId}}"
    Then the response status should be 403

  # ------------------------------------------------------------------ POST /api/merchants/{id}/initial-admin/reset-password

  Scenario: The platform administrator can reset a merchant's initial administrator password
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/initial-admin/reset-password"
    Then the response status should be 200
    And the JSON response field "temporaryPassword" should not be null
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{merchantAdminEmail}}", "password": "{{merchantAdminPassword}}"}
      """
    Then the response status should be 403

  Scenario: Resetting the initial admin password for an unknown merchant is not found
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/999999999/initial-admin/reset-password"
    Then the response status should be 404

  # ------------------------------------------------------------------ POST /api/merchants/{id}/api-key

  Scenario: The platform administrator can issue an API key once the merchant is live
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/api-key"
    Then the response status should be 200
    And the JSON response field "apiKey" should match the pattern "mk_.+"
    And the JSON response field "apiKeyPrefix" should not be null

  Scenario: An API key cannot be issued while onboarding is still in progress
    Given a merchant has been created but onboarding is not complete
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/api-key"
    Then the response status should be 409

  @edge-case
  Scenario: Issuing a new API key invalidates the previous one
    Given a merchant has been fully onboarded
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/merchant-profile" with body:
      """
      {"apiEnabled": true, "apiCallbackUrl": "https://example.com/qa-callback"}
      """
    Then the response status should be 200
    Given I am authenticated as the platform administrator
    When I send a POST request to "/api/merchants/{{merchantId}}/api-key"
    Then the response status should be 200
    Then I store the response field "apiKey" as "firstApiKey"
    When I send a POST request to "/api/merchants/{{merchantId}}/api-key"
    Then the response status should be 200
    Given I am not authenticated
    And request header "X-Api-Key" is set to "{{firstApiKey}}"
    When I send a GET request to "/api/v1/uploads/does-not-matter"
    Then the response status should be 401
