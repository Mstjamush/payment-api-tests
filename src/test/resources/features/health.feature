Feature: Health (GET /health/live, GET /health)

  No authentication is required for either endpoint.

  Scenario: Liveness always reports UP
    Given I am not authenticated
    When I send a GET request to "/health/live"
    Then the response status should be 200
    And the JSON response field "status" should equal "UP"

  Scenario: Readiness reports every dependency check
    Given I am not authenticated
    When I send a GET request to "/health"
    Then the response status should be 200 or 503
    And the JSON response should have a non-empty "status" field
    And the JSON response field "checks.database" should not be null
    And the JSON response field "checks.rabbitmq" should not be null
    And the JSON response field "checks.redis" should not be null

  @edge-case
  Scenario: Readiness reports the database as UP when payment_api is reachable at all
    # Every call in this suite depends on the database being reachable, so if
    # this fails, every other scenario will too - this is the canary.
    Given I am not authenticated
    When I send a GET request to "/health"
    Then the JSON response field "checks.database" should equal "UP"

  @edge-case
  Scenario: An unknown path returns a 404, not a server error
    Given I am not authenticated
    When I send a GET request to "/health/does-not-exist"
    Then the response status should be 404

  @edge-case
  Scenario: Health accepts no query parameters or body without erroring
    Given I am not authenticated
    And query parameter "foo" is "bar"
    And the request body is an empty JSON object
    When I send a GET request to "/health/live"
    Then the response status should be 200
