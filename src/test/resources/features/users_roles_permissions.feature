Feature: Staff users, roles and permissions (/api/users, /api/roles, /api/permissions)

  Manages staff of the caller's own merchant. Account types are merchant_admin
  and merchant_user; normal (merchant_user) staff can never hold a *.manage
  permission, and platform-only permissions (system.admin, merchants.*,
  payer_reports.view) can never be granted to a staff account.

  # ------------------------------------------------------------------ GET /api/roles, /api/permissions

  Scenario: The merchant administrator sees both staff roles with the merchant's default policy
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/roles"
    Then the response status should be 200
    And the JSON response should be a list of exactly 2 items
    And the JSON response array "$" should contain an item where "name" equals "merchant_admin"
    And the JSON response array "$" should contain an item where "name" equals "merchant_user"

  Scenario: The merchant administrator sees only permissions enabled for their merchant
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/permissions"
    Then the response status should be 200
    And the JSON response array "$" should not contain an item where "name" equals "merchants.manage"
    And the JSON response array "$" should not contain an item where "name" equals "system.admin"
    And the JSON response array "$" should not contain an item where "name" equals "payer_reports.view"

  Scenario: Without users.manage or roles.manage, listing roles is forbidden
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/roles"
    Then the response status should be 403

  Scenario: Listing roles without authentication is rejected
    When I send a GET request to "/api/roles"
    Then the response status should be 401

  # ------------------------------------------------------------------ PUT /api/roles/{roleId}/permissions

  Scenario: A merchant administrator can change the default permissions of merchant_user
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/roles"
    Then I store the response field "find { it.name == 'merchant_user' }.id" as "merchantUserRoleId"
    When I send a PUT request to "/api/roles/{{merchantUserRoleId}}/permissions" with body:
      """
      {"permissionNames": ["transactions.view"]}
      """
    Then the response status should be 200
    And the JSON response array "permissions" should have size 1
    And the JSON response field "permissions[0]" should equal "transactions.view"

  Scenario: A role policy cannot give merchant_user a *.manage permission
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/roles"
    Then I store the response field "find { it.name == 'merchant_user' }.id" as "merchantUserRoleId"
    When I send a PUT request to "/api/roles/{{merchantUserRoleId}}/permissions" with body:
      """
      {"permissionNames": ["settings.manage"]}
      """
    Then the response status should be 400

  Scenario: A role policy cannot exceed the merchant's own enabled permissions
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/roles"
    Then I store the response field "find { it.name == 'merchant_admin' }.id" as "merchantAdminRoleId"
    When I send a PUT request to "/api/roles/{{merchantAdminRoleId}}/permissions" with body:
      """
      {"permissionNames": ["merchants.manage"]}
      """
    Then the response status should be 400

  Scenario: An unknown role id is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/roles/999999999/permissions" with body:
      """
      {"permissionNames": []}
      """
    Then the response status should be 404

  @edge-case
  Scenario: Changing a role's policy signs out every other user holding that role, but not the editor
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a GET request to "/api/roles"
    Then I store the response field "find { it.name == 'merchant_user' }.id" as "merchantUserRoleId"
    When I send a PUT request to "/api/roles/{{merchantUserRoleId}}/permissions" with body:
      """
      {"permissionNames": ["transactions.view"]}
      """
    Then the response status should be 200
    # the editing administrator's own session still works
    When I send a GET request to "/api/auth/me"
    Then the response status should be 200
    # but the other merchant_user's earlier session does not
    Given I use the bearer token stored as "staffToken"
    When I send a GET request to "/api/auth/me"
    Then the response status should be 403
    And the error message should mention "Session is no longer valid"

  # ------------------------------------------------------------------ GET /api/users, /api/users/{id}

  Scenario: Listing staff users of the onboarded merchant includes its administrator
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/users"
    Then the response status should be 200
    And the JSON response array "items" should contain an item where "username" equals "{{merchantAdminUsername}}"

  Scenario: Staff users are paged
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "limit" is "1"
    And query parameter "page" is "0"
    When I send a GET request to "/api/users"
    Then the response status should be 200
    And the JSON response array "items" should have size 1
    And the JSON response field "size" should equal the number "1"

  Scenario: Staff users can be searched by username, email or full name
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "search" is "{{merchantAdminUsername}}"
    When I send a GET request to "/api/users"
    Then the response status should be 200
    And the JSON response array "items" should contain an item where "username" equals "{{merchantAdminUsername}}"

  Scenario: Staff users can be filtered by active status
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "status" is "inactive"
    When I send a GET request to "/api/users"
    Then the response status should be 200
    And the JSON response array "items" should have size 0

  Scenario: An invalid status filter is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "status" is "not-a-status"
    When I send a GET request to "/api/users"
    Then the response status should be 400

  Scenario: Fetching one staff user by id
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a GET request to "/api/users/{{staffUserId}}"
    Then the response status should be 200
    And the JSON response field "id" should equal the number "{{staffUserId}}"

  Scenario: Fetching a staff user that doesn't exist returns 404
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/users/999999999"
    Then the response status should be 404

  @edge-case
  Scenario: Users cannot see staff of a different merchant by id
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given the text "{{staffUserId}}" is stored as "otherMerchantStaffId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/users/{{otherMerchantStaffId}}"
    Then the response status should be 404

  Scenario: Listing users without users.manage is forbidden
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/users"
    Then the response status should be 403

  # ------------------------------------------------------------------ POST /api/users

  Scenario: Creating a staff user with an explicit role and permission list
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "A QA Created User", "roleNames": ["merchant_user"], "permissionNames": ["transactions.view"]}
      """
    Then the response status should be 201
    And the response header "Location" should match the pattern "/api/users/[0-9]+"
    And the JSON response field "username" should equal "{{newUsername}}"
    And the JSON response field "mustChangePassword" should equal true
    And the JSON response array "roles" should have size 1
    And the JSON response field "roles[0]" should equal "merchant_user"
    And the JSON response array "directPermissions" should contain "transactions.view"

  Scenario: Creating a staff user without serviceKeys defaults to every active service
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "A QA Created User", "roleNames": ["merchant_user"]}
      """
    Then the response status should be 201
    And the JSON response array "services" should have size 1
    And the JSON response field "services[0]" should equal "{{serviceCode}}"

  Scenario Outline: A staff user cannot be created with a username or email already in use
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "First", "roleNames": ["merchant_user"]}
      """
    Then the response status should be 201
    When I send a POST request to "/api/users" with body:
      """
      {"username": "<username>", "email": "<email>", "password": "StrongPassword123!",
       "fullName": "Second", "roleNames": ["merchant_user"]}
      """
    Then the response status should be 409

    Examples:
      | username              | email                        |
      | {{newUsername}}       | a.different.one@example.com  |
      | a-different-username  | {{newEmail}}                 |

  Scenario: A staff account cannot be created with a management permission while its role is merchant_user
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "QA User", "roleNames": ["merchant_user"], "permissionNames": ["users.manage"]}
      """
    Then the response status should be 400

  Scenario: A staff account cannot be created with a platform-only permission
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "QA User", "roleNames": ["merchant_admin"], "permissionNames": ["merchants.manage"]}
      """
    Then the response status should be 400

  Scenario: A staff account cannot be created with a permission not enabled for the merchant
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "QA User", "roleNames": ["merchant_user"], "permissionNames": ["payer_reports.view"]}
      """
    Then the response status should be 400

  Scenario: A staff account's role must be exactly one of merchant_admin or merchant_user
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "QA User", "roleNames": ["super_user"]}
      """
    Then the response status should be 400

  Scenario: A staff account cannot be given more than one role at once
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "QA User", "roleNames": ["merchant_admin", "merchant_user"]}
      """
    Then the response status should be 400

  Scenario Outline: Creating a user with a missing or invalid field is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    And the request body field "username" is set to the string "{{newUsername}}"
    And the request body field "email" is set to the string "{{newEmail}}"
    And the request body field "password" is set to the string "StrongPassword123!"
    And the request body field "fullName" is set to the string "QA User"
    And the request body field "roleNames" is set to the array "merchant_user"
    And <mutation>
    When I send a POST request to "/api/users"
    Then the response status should be 400

    Examples:
      | mutation                                                            |
      | the request body field "username" is removed                       |
      | the request body field "email" is removed                          |
      | the request body field "password" is removed                       |
      | the request body field "roleNames" is removed                      |
      | the request body field "username" is set to the string "ab"        |
      | the request body field "password" is set to the string "short"     |
      | the request body field "email" is set to the string "not-an-email" |
      | the request body field "roleNames" is set to an empty array        |

  @edge-case
  Scenario: A username of exactly the minimum length (3) is accepted
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique string of length 3 is stored as "shortUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{shortUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!", "fullName": "QA",
       "roleNames": ["merchant_user"]}
      """
    Then the response status should be 201

  @edge-case
  Scenario: A username longer than the maximum length (100) is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a unique email address is stored as "newEmail"
    And the request body field "username" is set to a string of length 101
    And the request body field "email" is set to the string "{{newEmail}}"
    And the request body field "password" is set to the string "StrongPassword123!"
    And the request body field "fullName" is set to the string "QA"
    And the request body field "roleNames" is set to the array "merchant_user"
    When I send a POST request to "/api/users"
    Then the response status should be 400

  Scenario: Creating a staff user without users.manage is forbidden
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    And a unique username is stored as "newUsername"
    And a unique email address is stored as "newEmail"
    When I send a POST request to "/api/users" with body:
      """
      {"username": "{{newUsername}}", "email": "{{newEmail}}", "password": "StrongPassword123!",
       "fullName": "QA User", "roleNames": ["merchant_user"]}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ PATCH /api/users/{id}/status

  Scenario: An administrator can deactivate and reactivate another staff member
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PATCH request to "/api/users/{{staffUserId}}/status" with body:
      """
      {"active": false}
      """
    Then the response status should be 200
    And the JSON response field "active" should equal false
    When I send a PATCH request to "/api/users/{{staffUserId}}/status" with body:
      """
      {"active": true}
      """
    Then the response status should be 200
    And the JSON response field "active" should equal true

  Scenario: An administrator cannot deactivate their own account
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PATCH request to "/api/users/{{merchantAdminUserId}}/status" with body:
      """
      {"active": false}
      """
    Then the response status should be 400
    And the error message should mention "You cannot deactivate your own account"

  @edge-case
  Scenario: A deactivated user's existing session stops working immediately
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PATCH request to "/api/users/{{staffUserId}}/status" with body:
      """
      {"active": false}
      """
    Then the response status should be 200
    Given I use the bearer token stored as "staffToken"
    When I send a GET request to "/api/auth/me"
    Then the response status should be 403
    And the error message should mention "Session is no longer valid"

  Scenario: Deactivating a staff user requires users.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a PATCH request to "/api/users/{{staffUserId}}/status" with body:
      """
      {"active": false}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ PUT /api/users/{id}/roles

  Scenario: An administrator can change another staff member's account type
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/users/{{staffUserId}}/roles" with body:
      """
      {"roleNames": ["merchant_admin"]}
      """
    Then the response status should be 200
    And the JSON response field "roles[0]" should equal "merchant_admin"

  Scenario: An administrator cannot change their own account type
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/users/{{merchantAdminUserId}}/roles" with body:
      """
      {"roleNames": ["merchant_user"]}
      """
    Then the response status should be 400
    And the error message should mention "You cannot change your own staff account type"

  Scenario: Changing roles requires roles.manage
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given the text "{{staffUserId}}" is stored as "targetStaffId"
    Given I use the bearer token stored as "staffToken"
    When I send a PUT request to "/api/users/{{targetStaffId}}/roles" with body:
      """
      {"roleNames": ["merchant_admin"]}
      """
    Then the response status should be 403

  # ------------------------------------------------------------------ PUT /api/users/{id}/permissions

  Scenario: An administrator can set a staff member's direct permissions
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/users/{{staffUserId}}/permissions" with body:
      """
      {"permissionNames": ["transactions.view", "reports.view"]}
      """
    Then the response status should be 200
    And the JSON response array "directPermissions" should have size 2

  Scenario: A missing permissionNames field is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/users/{{staffUserId}}/permissions" with body:
      """
      {}
      """
    Then the response status should be 400

  Scenario: A merchant_user cannot be given a management permission directly either
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/users/{{staffUserId}}/permissions" with body:
      """
      {"permissionNames": ["users.manage"]}
      """
    Then the response status should be 400

  # ------------------------------------------------------------------ PUT /api/users/{id}/services

  Scenario: An administrator can restrict a staff member to specific services
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/users/{{staffUserId}}/services" with body:
      """
      {"serviceKeys": ["{{serviceCode}}"]}
      """
    Then the response status should be 200
    And the JSON response array "services" should have size 1

  Scenario: Assigning an unknown service key is rejected
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a PUT request to "/api/users/{{staffUserId}}/services" with body:
      """
      {"serviceKeys": ["service-that-does-not-exist"]}
      """
    Then the response status should be 400

  # ------------------------------------------------------------------ POST /api/users/{id}/reset-password

  Scenario: An administrator can reset another staff member's password
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a POST request to "/api/users/{{staffUserId}}/reset-password"
    Then the response status should be 200
    And the JSON response field "temporaryPassword" should not be null

  Scenario: The reset temporary password can sign in, and the previous session is invalidated
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    Given I am authenticated as the administrator of that merchant
    When I send a POST request to "/api/users/{{staffUserId}}/reset-password"
    Then the response status should be 200
    Then I store the response field "temporaryPassword" as "resetPassword"
    Given I am not authenticated
    When I send a POST request to "/api/auth/login" with body:
      """
      {"email": "{{staffEmail}}", "password": "{{resetPassword}}"}
      """
    Then the response status should be 200
    And the JSON response field "mustChangePassword" should equal true
    # the old (pre-reset) session no longer works
    Given I use the bearer token stored as "staffToken"
    When I send a GET request to "/api/auth/me"
    Then the response status should be 403
