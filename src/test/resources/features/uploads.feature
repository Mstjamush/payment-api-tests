Feature: Bulk invoice and payment uploads (/api/*/invoices/upload, /api/*/payments/upload, /api/uploads*)

  Unlike a single invoice or payment, the upload batch row itself is written
  by payment_api synchronously - only the individual valid rows are handed to
  the background publisher, which needs RabbitMQ to actually reach QUEUED.
  So the POST response (totalRows/validRows/invalidRows/errors, and whether
  the batch starts PUBLISHING or FAILED) is fully deterministic without any
  broker, and is exercised below without tags. Anything that waits for a
  batch to finish publishing or to complete is tagged @requires-rabbitmq
  and/or @requires-consumer.

  # ------------------------------------------------------------------ auth & permissions

  Scenario: Uploading invoices via the UI requires authentication
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 401

  Scenario: A payer account cannot upload invoices
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "1"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 403

  Scenario: Uploading invoices via the merchant API requires a valid API key
    Given I use an invalid API key
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceCode" is set to "does-not-matter"
    When I send a POST request to "/api/v1/invoices/upload"
    Then the response status should be 401

  Scenario: Uploading payments via the UI requires authentication
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 401

  Scenario: A payer account cannot upload payments
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    Given the file "payments_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "1"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 403

  Scenario: Uploading payments via the merchant API requires a valid API key
    Given I use an invalid API key
    Given the file "payments_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceCode" is set to "does-not-matter"
    When I send a POST request to "/api/v1/payments/upload"
    Then the response status should be 401

  Scenario: Listing uploads requires authentication
    When I send a GET request to "/api/uploads"
    Then the response status should be 401

  Scenario: A payer account cannot list uploads
    Given a payer has been onboarded for provider "mpesa"
    And the onboarded payer has a payer account
    Given I am authenticated as that payer account
    When I send a GET request to "/api/uploads"
    Then the response status should be 403

  Scenario: Viewing an upload via the UI requires authentication
    When I send a GET request to "/api/uploads/1"
    Then the response status should be 401

  Scenario: Viewing an upload via the merchant API requires a valid API key
    Given I use an invalid API key
    When I send a GET request to "/api/v1/uploads/does-not-matter"
    Then the response status should be 401

  # ------------------------------------------------------------------ file & form validation

  Scenario: An unsupported file extension is rejected (invoices)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "unsupported_upload.txt" is attached as "file" with content type "text/plain"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 400

  Scenario: A file with no amount column is rejected (invoices)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_missing_amount_column.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 400

  Scenario: A file with only a header row is rejected (invoices)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_empty.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 400

  Scenario: Uploading invoices without selecting a service is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 400

  Scenario: Uploading invoices for an unknown service is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "999999999"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 404

  Scenario: An unsupported file extension is rejected (payments)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "unsupported_upload.txt" is attached as "file" with content type "text/plain"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 400

  Scenario: A file with no amount column is rejected (payments)
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "payments_missing_amount_column.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 400

  Scenario: Uploading payments without selecting a service is a validation error
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "payments_all_valid.csv" is attached as "file" with content type "text/csv"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 400

  Scenario: Uploading payments for an unknown service is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "payments_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "999999999"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 404

  # ------------------------------------------------------------------ invoice upload outcomes (synchronous, no broker needed)

  Scenario: A fully valid invoice file is accepted with no invalid rows
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    And the JSON response field "uploadId" should not be null
    And the JSON response field "uploadReference" should match the pattern "INVUP-.+"
    And the JSON response field "totalRows" should equal the number "3"
    And the JSON response field "validRows" should equal the number "3"
    And the JSON response field "invalidRows" should equal the number "0"
    And the JSON response field "status" should equal "PUBLISHING"

  Scenario: An invoice file with a mix of valid and invalid rows reports every bad row
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_with_errors.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    And the JSON response field "totalRows" should equal the number "4"
    And the JSON response field "validRows" should equal the number "1"
    And the JSON response field "invalidRows" should equal the number "3"
    And the JSON response array "errors" should have size 3
    And the JSON response field "status" should equal "PUBLISHING"

  Scenario: An invoice file where every row is invalid leaves the batch FAILED
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_invalid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    And the JSON response field "totalRows" should equal the number "2"
    And the JSON response field "validRows" should equal the number "0"
    And the JSON response field "invalidRows" should equal the number "2"
    And the JSON response field "status" should equal "FAILED"

  Scenario: A missing currency column falls back to the currency form field
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_no_currency_column.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    And form field "currency" is set to "KES"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    And the JSON response field "validRows" should equal the number "1"
    And the JSON response field "invalidRows" should equal the number "0"

  Scenario: The platform administrator can upload invoices for a specific merchant
    Given a merchant has been fully onboarded
    Given I am authenticated as the platform administrator
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    And query parameter "merchantId" is "{{merchantId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    And the JSON response field "validRows" should equal the number "3"

  Scenario: A merchant can upload invoices via the merchant API
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceCode" is set to "{{serviceCode}}"
    When I send a POST request to "/api/v1/invoices/upload"
    Then the response status should be 202
    And the JSON response field "validRows" should equal the number "3"

  # ------------------------------------------------------------------ payment upload outcomes (synchronous, no broker needed)

  Scenario: A fully valid payment file is accepted with no invalid rows
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    Given the file "payments_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    And form field "payerCode" is set to "{{payerCode}}"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 202
    And the JSON response field "uploadId" should not be null
    And the JSON response field "uploadReference" should match the pattern "PAYUP-.+"
    And the JSON response field "totalRows" should equal the number "2"
    And the JSON response field "validRows" should equal the number "2"
    And the JSON response field "invalidRows" should equal the number "0"
    And the JSON response field "status" should equal "PUBLISHING"

  Scenario: A payment file with a mix of valid and invalid rows reports every bad row
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    Given the file "payments_with_errors.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    And form field "payerCode" is set to "{{payerCode}}"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 202
    And the JSON response field "totalRows" should equal the number "4"
    And the JSON response field "validRows" should equal the number "1"
    And the JSON response field "invalidRows" should equal the number "3"
    And the JSON response array "errors" should have size 3
    And the JSON response field "status" should equal "PUBLISHING"

  Scenario: A payment file where every row is invalid leaves the batch FAILED
    Given I am authenticated as the administrator of a newly onboarded merchant
    And a payer has been onboarded for provider "mpesa"
    Given the file "payments_all_invalid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    And form field "payerCode" is set to "{{payerCode}}"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 202
    And the JSON response field "validRows" should equal the number "0"
    And the JSON response field "invalidRows" should equal the number "2"
    And the JSON response field "status" should equal "FAILED"

  Scenario: An unknown payer code for every row is reported per row, not as one failure
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "payments_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    And form field "payerCode" is set to "NO-SUCH-PAYER"
    When I send a POST request to "/api/payments/upload"
    Then the response status should be 202
    And the JSON response field "validRows" should equal the number "0"
    And the JSON response field "invalidRows" should equal the number "2"
    And the JSON response field "status" should equal "FAILED"

  Scenario: A merchant can upload payments via the merchant API
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    And a payer has been onboarded for provider "mpesa"
    Given the file "payments_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceCode" is set to "{{serviceCode}}"
    And form field "payerCode" is set to "{{payerCode}}"
    When I send a POST request to "/api/v1/payments/upload"
    Then the response status should be 202
    And the JSON response field "validRows" should equal the number "2"

  # ------------------------------------------------------------------ GET /api/uploads, GET /api/uploads/{id}, GET /api/v1/uploads/{reference}

  Scenario: An administrator can list uploads in the paginated shape
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/uploads"
    Then the response status should be 200
    And the JSON response field "total" should not be null
    And the JSON response field "page" should equal the number "0"

  Scenario: transactions.view alone is enough to list uploads
    Given I am authenticated as the administrator of a newly onboarded merchant
    And I am authenticated as a newly created merchant_user of the onboarded merchant
    When I send a GET request to "/api/uploads"
    Then the response status should be 200

  Scenario: A merchant administrator cannot list another merchant's uploads
    Given a merchant has been fully onboarded
    Then the text "{{merchantId}}" is stored as "otherMerchantId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    And query parameter "merchantId" is "{{otherMerchantId}}"
    When I send a GET request to "/api/uploads"
    Then the response status should be 403

  Scenario: An administrator can view an upload batch they just created
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    Then I store the response field "uploadId" as "newUploadId"
    When I send a GET request to "/api/uploads/{{newUploadId}}"
    Then the response status should be 200
    And the JSON response field "totalRows" should equal the number "3"
    And the JSON response field "type" should equal "INVOICE"
    And the JSON response field "status" should not be null

  Scenario: Viewing an unknown upload id is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/uploads/999999999"
    Then the response status should be 404

  Scenario: A merchant administrator cannot view another merchant's upload
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    Then I store the response field "uploadId" as "otherUploadId"
    Given I am authenticated as the administrator of a newly onboarded merchant
    When I send a GET request to "/api/uploads/{{otherUploadId}}"
    Then the response status should be 404

  Scenario: A merchant can view its own upload batch via the API by reference
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceCode" is set to "{{serviceCode}}"
    When I send a POST request to "/api/v1/invoices/upload"
    Then the response status should be 202
    Then I store the response field "uploadReference" as "newUploadReference"
    When I send a GET request to "/api/v1/uploads/{{newUploadReference}}"
    Then the response status should be 200
    And the JSON response field "reference" should equal "{{newUploadReference}}"

  Scenario: Viewing an unknown upload reference via the merchant API is not found
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given I am using the onboarded merchant's API key
    When I send a GET request to "/api/v1/uploads/no-such-reference"
    Then the response status should be 404

  # ------------------------------------------------------------------ requires a reachable broker and/or payment_consumers

  @requires-rabbitmq
  Scenario: A batch with valid rows eventually finishes publishing
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    Then I store the response field "uploadId" as "newUploadId"
    When I wait for the upload batch stored as "newUploadId" to finish publishing
    When I send a GET request to "/api/uploads/{{newUploadId}}"
    Then the response status should be 200
    And the JSON response field "status" should equal "QUEUED"

  @requires-rabbitmq @requires-consumer
  Scenario: A batch with valid rows eventually completes once payment_consumers processes it
    Given I am authenticated as the administrator of a newly onboarded merchant
    Given the file "invoices_all_valid.csv" is attached as "file" with content type "text/csv"
    And form field "serviceId" is set to "{{serviceId}}"
    When I send a POST request to "/api/invoices/upload"
    Then the response status should be 202
    Then I store the response field "uploadId" as "newUploadId"
    When I wait for the upload batch stored as "newUploadId" to complete
    When I send a GET request to "/api/uploads/{{newUploadId}}"
    Then the response status should be 200
    And the JSON response field "status" should equal "COMPLETED"
