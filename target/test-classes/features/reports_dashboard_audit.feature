Feature: Reports, dashboard and audit logs (/api/reports/*, /api/payer-reports/*, /api/dashboard/summary, /api/audit-logs)

  These are all read-only aggregates over payments/invoices/audit_logs - no
  broker involved anywhere, so everything here runs by default. Without any
  payments actually landing (that needs payment_consumers), the numeric
  aggregates are simply zero/empty; these scenarios check structure, access
  control and validation rather than specific figures.

  # ------------------------------------------------------------------ GET /api/reports/summary

  Scenario: An administrator can view the merchant payments summary report
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/reports/summary"
    Then the response status should be 200
    And the JSON response field "totals" should not be null
    And the JSON response field "byStatus" should not be null
    And the JSON response field "byPayer" should not be null
    And the JSON response field "daily" should not be null
    And the JSON response field "byService" should not be null
    And the JSON response field "invoices" should not be null

  Scenario: transactions.view/reports.view defaults let a merchant_user view the report too
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/reports/summary"
    Then the response status should be 200

  Scenario: A payer account cannot view the merchant payments summary report
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/reports/summary"
    Then the response status should be 403

  Scenario: Viewing the merchant payments summary report requires authentication
    When I send a GET request to "/api/reports/summary"
    Then the response status should be 401

  Scenario: The platform administrator can view any merchant's summary report
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    And query parameter "merchantId" is "{{merchantId}}"
    When I send a GET request to "/api/reports/summary"
    Then the response status should be 200

  Scenario: A "to" date before "from" is a validation error on the summary report
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "from" is "2026-06-10"
    And query parameter "to" is "2026-06-01"
    When I send a GET request to "/api/reports/summary"
    Then the response status should be 400

  Scenario: An invalid "from" date format is a validation error on the summary report
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "from" is "not-a-date"
    When I send a GET request to "/api/reports/summary"
    Then the response status should be 400

  # ------------------------------------------------------------------ GET /api/payer-reports/summary, /api/payer-reports/payments

  Scenario: A payer account can view their own payer-reports summary
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    And the onboarded payer's account has changed its temporary password
    Given I am authenticated as that payer account
    When I send a GET request to "/api/payer-reports/summary"
    Then the response status should be 200
    And the JSON response field "payerId" should equal the number "{{payerId}}"

  Scenario: A payer account cannot request another payer's reports summary
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given a payer has been onboarded for provider "airtel"
    Then the text "{{payerId}}" is stored as "otherPayerId"
    Given I am authenticated as that payer account
    And query parameter "payerId" is "{{otherPayerId}}"
    When I send a GET request to "/api/payer-reports/summary"
    Then the response status should be 403

  Scenario: The platform administrator can view any payer's reports summary
    Given a payer has been onboarded for provider "mpesa"
    Given I am authenticated as the platform administrator
    And query parameter "payerId" is "{{payerId}}"
    When I send a GET request to "/api/payer-reports/summary"
    Then the response status should be 200
    And the JSON response field "payerId" should equal the number "{{payerId}}"

  Scenario: The platform administrator can view the reports summary across all payers
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/payer-reports/summary"
    Then the response status should be 200
    And the JSON response field "byMerchant" should not be null

  Scenario: A regular merchant administrator cannot view payer-reports, even with other permissions
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payer-reports/summary"
    Then the response status should be 403

  Scenario: Viewing the payer-reports summary requires authentication
    When I send a GET request to "/api/payer-reports/summary"
    Then the response status should be 401

  Scenario: A payer account can list their own payments via payer-reports
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    And the onboarded payer's account has changed its temporary password
    Given I am authenticated as that payer account
    When I send a GET request to "/api/payer-reports/payments"
    Then the response status should be 200
    And the JSON response field "total" should not be null
    And the JSON response field "items" should not be null

  Scenario: A regular merchant administrator cannot list payer-reports payments
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/payer-reports/payments"
    Then the response status should be 403

  Scenario: Listing payer-reports payments requires authentication
    When I send a GET request to "/api/payer-reports/payments"
    Then the response status should be 401

  Scenario: A page size above 100 is a validation error on payer-reports payments
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    And query parameter "limit" is "101"
    When I send a GET request to "/api/payer-reports/payments"
    Then the response status should be 400

  # ------------------------------------------------------------------ GET /api/dashboard/summary

  Scenario: An administrator can view the dashboard summary
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/dashboard/summary"
    Then the response status should be 200
    And the JSON response field "totalStaffUsers" should not be null
    And the JSON response field "activeStaffUsers" should not be null
    And the JSON response field "configuredRoles" should not be null
    And the JSON response field "recentActivity" should not be null
    And the JSON response field "paymentsToday" should not be null

  Scenario: transactions.view alone is enough to view the dashboard summary
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/dashboard/summary"
    Then the response status should be 200

  Scenario: A payer account cannot view the dashboard summary
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/dashboard/summary"
    Then the response status should be 403

  Scenario: Viewing the dashboard summary requires authentication
    When I send a GET request to "/api/dashboard/summary"
    Then the response status should be 401

  Scenario: The platform administrator can view the dashboard summary too
    Given I am authenticated as the platform administrator
    When I send a GET request to "/api/dashboard/summary"
    Then the response status should be 200

  # ------------------------------------------------------------------ GET /api/audit-logs

  Scenario: An administrator can view the audit log and see their own actions in it
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}" with body:
      """
      {"name": "QA Audited Rename", "active": true}
      """
    Then the response status should be 200
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 200
    And the JSON response field "total" should not be null
    And the JSON response array "items" should contain an item where "action" equals "SERVICE_UPDATED"

  Scenario: transactions.view alone is not enough to view the audit log
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 403

  Scenario: A payer account cannot view the audit log
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 403

  Scenario: Viewing the audit log requires authentication
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 401

  Scenario: An invalid audit log status filter is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "status" is "not-a-real-outcome"
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 400

  Scenario: An invalid audit log timeframe filter is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "timeframe" is "not-a-real-timeframe"
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 400

  Scenario: An invalid audit log date filter is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "date" is "not-a-date"
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 400

  Scenario: The audit log can be searched and filtered by action
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a PUT request to "/api/services/{{serviceId}}" with body:
      """
      {"name": "QA Searchable Rename", "active": true}
      """
    Then the response status should be 200
    Given query parameter "action" is "SERVICE_UPDATED"
    When I send a GET request to "/api/audit-logs"
    Then the response status should be 200
    And the JSON response array "items" should contain an item where "action" equals "SERVICE_UPDATED"
