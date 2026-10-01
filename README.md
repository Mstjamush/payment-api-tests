# payment-api-tests

Automated API test suite for [`payment_api`](../../Personal_Co_code/payment_api)
(the payment gateway's FastAPI front end), built with **Cucumber 7**, **REST
Assured 5** and **JUnit 4**, in the same BDD/Gherkin style as the sibling
[`bulksms-api-tests`](../bulksms-api-tests) project.

It covers all 76 documented endpoints (see `payment_api/docs/API.md`) across
13 feature files, positive and negative, including validation edge cases,
permission boundaries, and cross-merchant isolation. Every scenario runs
against a real, running `payment_api` instance over HTTP - nothing here talks
to the database directly or mocks the app.

## Prerequisites

| Tool | Minimum version |
|---|---|
| Java JDK | 17 |
| Apache Maven | 3.8+ |
| MySQL | 8.0 (matching `payment_api`'s schema) |
| `payment_api` | running and reachable (see below) |
| RabbitMQ + `payment_consumers` | only for `@requires-rabbitmq` / `@requires-consumer` scenarios - see [Running against a partial stack](#running-against-a-partial-stack) |

## Setup

### 1. A disposable database

Never point this suite at a real `payments` database - it creates merchants,
services, payers and staff users by the hundred. Build a throwaway one from
`payment_api`'s own schema:

```bash
mysql -e "CREATE DATABASE payments_qa_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql payments_qa_test < ../../Personal_Co_code/payment_api/schema.sql
```

### 2. Seed the reference data and a platform administrator

```bash
cd ../../Personal_Co_code/payment_api
DB_NAME=payments_qa_test BOOTSTRAP_ADMIN_USERNAME=platform.admin \
  BOOTSTRAP_ADMIN_EMAIL=platform.admin@example.com \
  BOOTSTRAP_ADMIN_PASSWORD='ChangeMe123!' .venv/bin/python seed_admin.py
```

This matches `config.properties`' `platform.admin.*` defaults below - change
one, change the other.

### 3. Run payment_api against that database

```bash
DB_NAME=payments_qa_test .venv/bin/uvicorn app.main:app --port 8000
```

It boots and serves fine with no RabbitMQ reachable - every publish just
answers 503 until one is (see `payment_api/app/mq.py`). That's exactly the
state this suite is written to assume by default.

### 4. Install dependencies

```bash
mvn dependency:resolve
```

## Running the tests

### Everything that doesn't need a broker (the default, and what CI should run)

```bash
mvn test -Dcucumber.filter.tags="not @ignore and not @requires-rabbitmq and not @requires-consumer"
```

### Truly everything (needs RabbitMQ + payment_consumers, see below)

```bash
mvn test
```

### One feature file

```bash
mvn test -Dcucumber.filter.tags="not @requires-rabbitmq and not @requires-consumer" -Dcucumber.features="src/test/resources/features/services.feature"
```

### One area by tag

```bash
mvn test -Dcucumber.filter.tags="@edge-case"
```

## Running against a partial stack

Creating an invoice, a payment, or a bulk-upload row, and the payer-callback
intake endpoint, all **publish to RabbitMQ** - `payment_api` answers 503
instead of 202/200 until a broker is reachable (see `app/mq.py`'s
`BrokerUnavailable`). Reading that row back, or waiting for it to reach a
particular status, additionally needs **`payment_consumers` actually running**
against the same broker and database, since `payment_api` never writes an
invoice/payment row itself - only the consumer does.

| Tag | Needs | Scenarios |
|---|---|---|
| (none) | just `payment_api` | everything else - validation, auth, not-found, listing, the synchronous half of bulk uploads |
| `@requires-rabbitmq` | the above + RabbitMQ reachable from `payment_api` | the actual 202/200 success responses for invoice/payment/upload/payer-callback creation |
| `@requires-consumer` | the above + `payment_consumers` running | anything that reads back a row only the consumer creates (duplicate-id checks, cancel, upload completion) |

To bring up the fuller stack: `docker compose up -d rabbitmq` (or any local
RabbitMQ), then build and run `payment_consumers` per its own README, pointed
at the same `payments_qa_test` database and that broker. Then:

```bash
mvn test -Dcucumber.filter.tags="not @ignore"
```

**This suite was built and verified entirely without a broker** - every
scenario not tagged `@requires-rabbitmq`/`@requires-consumer` has been run
against a live `payment_api` and passes. The tagged scenarios are written from
the same source-level analysis as everything else, but have not been run
against a live broker/consumer in this environment - treat a first run of
them as the real verification, not this suite's word for it.

## Coverage

| Feature file | Endpoints | Notes |
|---|---|---|
| `health.feature` | `/health`, `/health/live` | |
| `authentication.feature` | `/api/auth/*` | login, lockout, change-password, session invalidation on `auth_version` bump, `mustChangePassword` restriction |
| `users_roles_permissions.feature` | `/api/users*`, `/api/roles*`, `/api/permissions` | staff CRUD, role assignment, direct permission grants, self-service limits |
| `merchants.feature` | `/api/merchants*` (platform-staff management) | access policy, role policy, deactivation, admin password reset, API key issuance |
| `merchant_onboarding.feature` | `POST /api/merchants`, `/api/merchants/{id}/services*`, `/api/merchants/{id}/onboarding*` | the full create -> add service -> configure settings -> go-live flow, and every way it can be left incomplete |
| `merchant_profile.feature` | `/api/merchant-profile*` | a merchant's self-service view of its own profile and API key |
| `payers.feature` | `/api/payers*`, `/api/payment-options` | payer CRUD, provider-config masking, payer accounts |
| `services.feature` | `/api/services*`, `/api/statuses` | service CRUD, settings (invoice requirement, charge models), payment options, notification preferences |
| `invoices.feature` | `/api/invoices*`, `/api/v1/invoices*` | validation, listing/pagination, not-found, cancellation; creation success and read-back are `@requires-rabbitmq`/`@requires-consumer` |
| `payments.feature` | `/api/payments*`, `/api/v1/payments*` | same shape as invoices, plus provider-specific field rules (phone for M-Pesa/Airtel, country for AstroPay) and acknowledgement validation |
| `uploads.feature` | `/api/*/invoices/upload`, `/api/*/payments/upload`, `/api/uploads*`, `/api/v1/uploads/*` | the batch row and its row-level validation are synchronous (no broker needed); only the eventual QUEUED/COMPLETED status needs one |
| `reports_dashboard_audit.feature` | `/api/reports/*`, `/api/payer-reports/*`, `/api/dashboard/summary`, `/api/audit-logs` | read-only aggregates - access control and validation, since no payments exist to aggregate without a consumer |
| `payment_responses.feature` | `/api/v1/payment-responses/{payerCode}` | the public provider-callback endpoint - payer resolution and the raw pass-through body, no auth |

~417 scenarios (Scenario Outline examples not expanded in that count), of
which 20 are tagged `@requires-rabbitmq` and 11 `@requires-consumer`.

## Project conventions

Rather than one bespoke Java method per endpoint, almost everything is built
from a small, generic step vocabulary:

- **`paymentapi.stepdefinitions.HttpExecutionSteps`** - one engine (`I send a
  <verb> request to "<path>"`, optionally `with body:`) that every scenario
  uses, regardless of endpoint.
- **`RequestBuildingSteps`** - generic `Given` steps to shape the next
  request: set/mutate a JSON body field by dot-path, set a query parameter or
  header, attach a multipart file, send a deliberately malformed body.
- **`CommonAssertionSteps`** - generic `Then` steps to check a status code, a
  JSON field or array by path, a header, or an error message.
- **`MerchantFixtures` / `PayerFixtures`** - everything a scenario needs as a
  precondition (an onboarded merchant, a configured service, a payer, a staff
  user) is built through the real API, never by writing to the database, and
  the resulting ids/codes/tokens are written to `ScenarioData` so later steps
  can reference them as `{{merchantId}}`, `{{serviceCode}}`, `{{payerCode}}`, etc.

This made it practical to cover 76 endpoints without one-off step classes for
each; new endpoints mostly just need new `.feature` scenarios, not new Java.

### `{{placeholder}}` substitution

Any `{{name}}` in a URL, JSON body, header, query parameter, or an assertion's
expected value is resolved against whatever the scenario has stored in
`ScenarioData` under that name (`paymentapi.utils.JsonSupport.substitutePlaceholders`).
A few steps exist purely to populate one: `a unique merchant code is stored as
"<name>"`, `I store the response field "<path>" as "<name>"`, `the text
"<value>" is stored as "<name>"`.

Since `payment_api` has its own, unrelated `{{...}}` template syntax for
notification `messageTemplate`s (filled in later by `payment_consumers`, not
by this harness), write `\{{fieldName}}` - a leading backslash - wherever you
mean that literal, app-level placeholder rather than a scenario-data lookup.
See `services.feature`'s notification-preference scenarios for examples.

## Test data fixtures

`src/test/resources/testdata/` holds static CSVs for the upload scenarios
(`invoices_all_valid.csv`, `payments_with_errors.csv`, etc.) and one
`.txt` file for the unsupported-extension case. They're deliberately small
and hand-written - no generator script, unlike the spreadsheet fixtures in
`bulksms-api-tests`. Row-level uniqueness (merchant/invoice/payment ids) is
checked only *within* a single uploaded file by `payment_api`, never against
history, so these files are safe to reuse unmodified on every run.

## Test reports

| Report | Path |
|---|---|
| HTML | `target/cucumber-html-report/index.html` |
| JSON | `target/cucumber.json` |

```bash
open target/cucumber-html-report/index.html
```

## Logs

Every HTTP call and scenario start/finish is logged, via `jboss-logging`
delegating to SLF4J/Logback (same pattern as `bulksms-api-tests`):

| Where | What |
|---|---|
| Console | One line per HTTP call (method, URI, status, duration) plus Cucumber's `pretty` output |
| `target/logs/payment-api-tests.log` | The same, rotating by day |

Default level is INFO (method/URI/status/duration only, no bodies). For full
request/response bodies:

```bash
mvn test -Dpaymentapi.http.log.level=DEBUG
```

## Configuration

Everything in `src/test/resources/config.properties` can be overridden by an
environment variable (dots -> underscores, upper-cased - `api.base.url` ->
`API_BASE_URL`) or a `-D` system property, without editing the file:

| Key | Default | |
|---|---|---|
| `api.base.url` | `http://localhost:8000` | |
| `platform.admin.email` / `.password` | `platform.admin@example.com` / `ChangeMe123!` | Must match whatever `seed_admin.py` was run with. This suite only ever reads this account - nothing changes its password or deactivates it. |
| `auth.invalid.api.key` | a well-formed but non-existent `mk_...` key | negative `X-Api-Key` tests |
| `auth.malformed.bearer.token` | a structurally invalid JWT | negative bearer-token tests |
| `wait.consumer.timeout.seconds` / `.poll.interval.ms` | 25 / 500 | `@requires-consumer` polling (waiting for a row to exist, or an upload batch to complete) |
| `wait.queue.publish.timeout.seconds` / `.poll.interval.ms` | 10 / 300 | `@requires-rabbitmq` polling (waiting for an upload batch to finish publishing) |

## Known limitations

- Written and verified in an environment with **no RabbitMQ installed**, so
  every `@requires-rabbitmq`/`@requires-consumer` scenario is unverified
  against a live broker - see the warning in [Running against a partial
  stack](#running-against-a-partial-stack).
- The `PAYMENT_RESPONSE_ALLOWED_IPS` 403 branch in `payment_responses.feature`
  is not exercised: it's empty by default in `payment_api`'s config, so the
  branch is unreachable without reconfiguring the running instance.
- File-size and row-count ceilings (`MAX_UPLOAD_BYTES` = 50 MB,
  `MAX_UPLOAD_ROWS` = 200,000, `MAX_CALLBACK_BYTES` = 256 KB) are not tested -
  generating fixtures that size isn't worth the repo weight or runtime.
- A payment's real acknowledgement happy path (reaching
  `PENDING_ACKNOWLEDGEMENT`) only arises once a provider has actually called
  back, which needs a working provider stub this suite doesn't have; only the
  validation and not-found paths of `POST .../acknowledgement` are covered.
