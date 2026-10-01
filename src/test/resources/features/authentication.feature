Feature: Authentication (POST /api/auth/login, POST /api/auth/change-password, GET /api/auth/me)

  Background:
    Given I am not authenticated

  # ------------------------------------------------------------------ login: positive

  Scenario: The platform administrator can sign in with the correct credentials
    Given the configured platform administrator's login body is used
    When I send a POST request to "/api/auth/login"
    Then the response status should be 200
    And the JSON response field "accessToken" should not be null
    And the JSON response field "tokenType" should equal "Bearer"
    And the JSON response field "expiresIn" should equal the number "3600"

  Scenario: A freshly onboarded merchant administrator must change their password at first sign-in
    Given a merchant has been fully onboarded without changing the administrator's temporary password
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{merchantAdminEmail}}", "password": "{{merchantAdminPassword}}"}
      """
    Then the response status should be 200
    And the JSON response field "accessToken" should not be null
    And the JSON response field "mustChangePassword" should equal true

  # ------------------------------------------------------------------ login: negative

  Scenario: Logging in with the wrong password is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{merchantAdminEmail}}", "password": "definitely-the-wrong-password"}
      """
    Then the response status should be 403
    And the error message should mention "Invalid email or password"

  Scenario: Logging in with an email that has no account is rejected with the same message as a wrong password
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "no.such.user.at.all@example.com", "password": "whatever-password-123"}
      """
    Then the response status should be 403
    And the error message should mention "Invalid email or password"

  Scenario Outline: Logging in with a missing or blank required field is a validation error, not a server error
    When I send a POST request to "/api/auth/login" with body:
      """
      <body>
      """
    Then the response status should be 400
    And the response should list a validation problem for field "<field>"

    Examples:
      | body                                                            | field    |
      | {"password": "whatever-password-123"}                          | email    |
      | {"email": "someone@example.com"}                                | password |
      | {"email": "someone@example.com", "password": ""}                | password |

  Scenario: Logging in with an invalid email format is rejected as a validation error
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "not-an-email-address", "password": "whatever-password-123"}
      """
    Then the response status should be 400

  Scenario: Logging in with malformed JSON is a clean validation error, not a server error
    Given the request body is the following malformed JSON:
      """
      {"email": "someone@example.com", "password":
      """
    When I send a POST request to "/api/auth/login"
    Then the response status should be 400

  @edge-case
  Scenario: Logging in with a deactivated user's credentials is rejected like a wrong password
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a newly created staff user of the onboarded merchant has not changed their temporary password
    Given I am authenticated as the administrator of that merchant
    And the request body field "active" is set to false
    When I send a PATCH request to "/api/users/{{staffUserId}}/status"
    Then the response status should be 200
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{unchangedPasswordStaffEmail}}", "password": "{{unchangedPasswordStaffPassword}}"}
      """
    Then the response status should be 403
    And the error message should mention "Invalid email or password"

  @edge-case
  Scenario: Repeated failed logins for the same email are eventually locked out
    Given a unique email address is stored as "lockoutEmail"
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{lockoutEmail}}", "password": "wrong-1"}
      """
    Then the response status should be 403
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{lockoutEmail}}", "password": "wrong-2"}
      """
    Then the response status should be 403
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{lockoutEmail}}", "password": "wrong-3"}
      """
    Then the response status should be 403
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{lockoutEmail}}", "password": "wrong-4"}
      """
    Then the response status should be 403
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{lockoutEmail}}", "password": "wrong-5"}
      """
    Then the response status should be 403
    # The 6th attempt - even for a password that would have been wrong anyway - is locked out, not "wrong credentials".
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{lockoutEmail}}", "password": "wrong-6"}
      """
    Then the response status should be 429
    And the error message should mention "Too many failed login attempts"

  # ------------------------------------------------------------------ change-password: positive

  Scenario: A merchant administrator can change their own password
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/auth/change-password" with body:
      """
      {"currentPassword": "{{merchantAdminPassword}}", "newPassword": "ANewStrongPassword123!"}
      """
    Then the response status should be 200
    And the JSON response field "mustChangePassword" should equal false
    And the JSON response field "accessToken" should not be null

  Scenario: The new password can sign in and the old one can no longer
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/auth/change-password" with body:
      """
      {"currentPassword": "{{merchantAdminPassword}}", "newPassword": "ANewStrongPassword123!"}
      """
    Then the response status should be 200
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{merchantAdminEmail}}", "password": "ANewStrongPassword123!"}
      """
    Then the response status should be 200
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{merchantAdminEmail}}", "password": "{{merchantAdminPassword}}"}
      """
    Then the response status should be 403

  Scenario: Changing your password invalidates your previous session token
    Given I am authenticated as the administrator of a newly onboarded merchant
    And the text "{{merchantAdminToken}}" is stored as "tokenBeforeChange"
    When I send a POST request to "/api/auth/change-password" with body:
      """
      {"currentPassword": "{{merchantAdminPassword}}", "newPassword": "YetAnotherStrong123!"}
      """
    Then the response status should be 200
    Given I use the bearer token stored as "tokenBeforeChange"
    When I send a GET request to "/api/auth/me"
    Then the response status should be 403
    And the error message should mention "Session is no longer valid"

  # ------------------------------------------------------------------ change-password: negative / edge

  Scenario: Changing your password with the wrong current password is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/auth/change-password" with body:
      """
      {"currentPassword": "not-the-real-current-password", "newPassword": "ANewStrongPassword123!"}
      """
    Then the response status should be 403

  Scenario: The new password must differ from the current one
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a POST request to "/api/auth/change-password" with body:
      """
      {"currentPassword": "{{merchantAdminPassword}}", "newPassword": "{{merchantAdminPassword}}"}
      """
    Then the response status should be 400

  @edge-case
  Scenario: A new password shorter than 12 characters is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And the request body field "currentPassword" is set to the string "{{merchantAdminPassword}}"
    And the request body field "newPassword" is set to a string of length 11
    When I send a POST request to "/api/auth/change-password"
    Then the response status should be 400
    And the response should list a validation problem for field "newPassword"

  @edge-case
  Scenario: A new password of exactly the minimum length is accepted
    Given I am authenticated as the administrator of a newly onboarded merchant
    And the request body field "currentPassword" is set to the string "{{merchantAdminPassword}}"
    And the request body field "newPassword" is set to the string "Exactly12Ch!"
    When I send a POST request to "/api/auth/change-password"
    Then the response status should be 200

  @edge-case
  Scenario: A new password longer than the maximum length is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And the request body field "currentPassword" is set to the string "{{merchantAdminPassword}}"
    And the request body field "newPassword" is set to a string of length 129
    When I send a POST request to "/api/auth/change-password"
    Then the response status should be 400
    And the response should list a validation problem for field "newPassword"

  Scenario: Changing your password without authenticating is rejected
    When I send a POST request to "/api/auth/change-password" with body:
      """
      {"currentPassword": "whatever", "newPassword": "ANewStrongPassword123!"}
      """
    Then the response status should be 401

  Scenario: A user who must change their password can still call change-password itself
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a newly created staff user of the onboarded merchant has not changed their temporary password
    Given I am authenticated with that staff user's unchanged temporary-password token
    When I send a POST request to "/api/auth/change-password" with body:
      """
      {"currentPassword": "{{unchangedPasswordStaffPassword}}", "newPassword": "FreshStrongPassword123!"}
      """
    Then the response status should be 200
    And the JSON response field "mustChangePassword" should equal false

  # ------------------------------------------------------------------ GET /api/auth/me

  Scenario: An authenticated merchant administrator can view their own profile
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/auth/me"
    Then the response status should be 200
    And the JSON response field "email" should equal "{{merchantAdminEmail}}"
    And the JSON response field "active" should equal true
    # the fixture already moved it past its one-time temporary password
    And the JSON response field "mustChangePassword" should equal false
    And the JSON response field "merchantId" should equal the number "{{merchantId}}"
    And the JSON response field "superAdmin" should equal false
    And the JSON response field "payerId" should be null

  Scenario: The platform administrator's own profile reports superAdmin and empty explicit permissions
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/auth/me"
    Then the response status should be 200
    And the JSON response field "superAdmin" should equal true
    And the JSON response array "permissions" should have size 0
    And the JSON response array "directPermissions" should have size 0

  Scenario: A payer account's profile has a payerId
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/auth/me"
    Then the response status should be 200
    And the JSON response field "payerId" should not be null

  Scenario: Calling /api/auth/me without a token is rejected
    When I send a GET request to "/api/auth/me"
    Then the response status should be 401
    And the response header "WWW-Authenticate" should equal "Bearer"

  Scenario: Calling /api/auth/me with a malformed bearer token is rejected
    Given I use an invalid bearer token
    When I send a GET request to "/api/auth/me"
    Then the response status should be 401
    And the error message should mention "Invalid token"

  @edge-case
  Scenario: A bearer token without the "Bearer " scheme prefix is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the Authorization header is literally "{{merchantAdminToken}}"
    When I send a GET request to "/api/auth/me"
    Then the response status should be 401

  @edge-case
  Scenario: An empty Authorization header is rejected
    Given the Authorization header is literally ""
    When I send a GET request to "/api/auth/me"
    Then the response status should be 401

  @edge-case
  Scenario: Deactivating a merchant invalidates every one of its staff sessions immediately
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am authenticated as the platform administrator
    When I send a DELETE request to "/api/merchants/{{merchantId}}"
    Then the response status should be 204
    Given I am authenticated as the administrator of that merchant
    When I send a GET request to "/api/auth/me"
    Then the response status should be 403
    And the error message should mention "Session is no longer valid"
