package paymentapi.stepdefinitions;

import com.fasterxml.jackson.databind.node.ObjectNode;
import io.cucumber.java.en.Given;
import io.restassured.response.Response;

import paymentapi.config.Config;
import paymentapi.fixtures.MerchantFixtures;
import paymentapi.fixtures.MerchantFixtures.CreatedMerchant;
import paymentapi.fixtures.MerchantFixtures.OnboardedMerchant;
import paymentapi.fixtures.MerchantFixtures.StaffUser;
import paymentapi.fixtures.PayerFixtures;
import paymentapi.fixtures.PayerFixtures.CreatedPayer;
import paymentapi.fixtures.PayerFixtures.PayerUser;
import paymentapi.sessions.PlatformAdminSession;
import paymentapi.utils.ApiClient;
import paymentapi.utils.JsonSupport;

/**
 * Two kinds of step here: who the next request(s) authenticate as
 * (RequestContext.setBearerToken/setApiKey/setNoAuth), and the fixtures that
 * create the merchant/payer/staff preconditions a scenario needs - built
 * through the real onboarding endpoints (see MerchantFixtures/PayerFixtures),
 * never by writing to the database directly. Created ids/codes/tokens are
 * also written to ScenarioData, so a feature file can reference them later as
 * {{merchantId}}, {{serviceCode}}, {{payerCode}}, etc.
 */
public class AuthContextSteps {

    // ------------------------------------------------------------------ raw auth state

    @Given("I am not authenticated")
    public void iAmNotAuthenticated() {
        RequestContext.setNoAuth();
    }

    @Given("I am authenticated as the platform administrator")
    public void iAmAuthenticatedAsThePlatformAdministrator() {
        RequestContext.setBearerToken(PlatformAdminSession.token());
    }

    @Given("I use an invalid bearer token")
    public void iUseAnInvalidBearerToken() {
        RequestContext.setBearerToken(Config.get("auth.malformed.bearer.token"));
    }

    @Given("the Authorization header is literally {string}")
    public void theAuthorizationHeaderIsLiterally(String literalValue) {
        RequestContext.setNoAuth();
        RequestContext.addHeader("Authorization", JsonSupport.substitutePlaceholders(literalValue));
    }

    @Given("I use the bearer token stored as {string}")
    public void iUseTheBearerTokenStoredAs(String key) {
        RequestContext.setBearerToken(ScenarioData.get(key));
    }

    @Given("the configured platform administrator's login body is used")
    public void theConfiguredPlatformAdministratorsLoginBodyIsUsed() {
        ObjectNode body = JsonSupport.newObject();
        body.put("email", Config.get("platform.admin.email"));
        body.put("password", Config.get("platform.admin.password"));
        RequestContext.setJsonBody(body);
    }

    @Given("I use an invalid API key")
    public void iUseAnInvalidApiKey() {
        RequestContext.setApiKey(Config.get("auth.invalid.api.key"));
    }

    @Given("I use no API key")
    public void iUseNoApiKey() {
        RequestContext.setNoAuth();
    }

    // ------------------------------------------------------------------ merchant fixtures (platform-staff perspective)

    @Given("a merchant has been fully onboarded")
    public void aMerchantHasBeenFullyOnboarded() {
        MerchantFixtures.onboardFullyConfiguredMerchant();
    }

    @Given("a merchant has been fully onboarded without changing the administrator's temporary password")
    public void aMerchantHasBeenFullyOnboardedKeepingTemporaryPassword() {
        MerchantFixtures.onboardFullyConfiguredMerchantKeepingTemporaryPassword();
    }

    @Given("a merchant has been created but onboarding is not complete")
    public void aMerchantHasBeenCreatedButOnboardingIsNotComplete() {
        MerchantFixtures.onboardMerchantInProgress();
    }

    @Given("that merchant also has an unconfigured service")
    public void thatMerchantAlsoHasAnUnconfiguredService() {
        int merchantId = ScenarioData.get("merchantId");
        int serviceId = MerchantFixtures.addUnconfiguredService(merchantId);
        ScenarioData.put("unconfiguredServiceId", serviceId);
        ScenarioData.put("unconfiguredServiceCode", ScenarioData.<String>get("serviceCode"));
    }

    // ------------------------------------------------------------------ merchant fixtures (merchant-staff perspective)

    @Given("I am authenticated as the administrator of a newly onboarded merchant")
    public void iAmAuthenticatedAsTheAdministratorOfANewlyOnboardedMerchant() {
        OnboardedMerchant merchant = MerchantFixtures.onboardFullyConfiguredMerchant();
        RequestContext.setBearerToken(merchant.adminToken());
    }

    @Given("I am authenticated as the administrator of a newly onboarded merchant whose service requires an invoice for every payment")
    public void merchantWithRequiredInvoiceService() {
        ObjectNode settings = MerchantFixtures.defaultServiceSettings();
        settings.put("invoiceRequirement", "REQUIRED");
        OnboardedMerchant merchant = MerchantFixtures.onboardFullyConfiguredMerchant(settings);
        RequestContext.setBearerToken(merchant.adminToken());
    }

    @Given("I am authenticated as the administrator of a newly onboarded merchant whose service does not allow invoices")
    public void merchantWithNoInvoiceService() {
        ObjectNode settings = MerchantFixtures.defaultServiceSettings();
        settings.put("invoiceRequirement", "NOT_ALLOWED");
        OnboardedMerchant merchant = MerchantFixtures.onboardFullyConfiguredMerchant(settings);
        RequestContext.setBearerToken(merchant.adminToken());
    }

    @Given("I am authenticated as the administrator of a newly onboarded merchant whose service requires invoices and holds partial payments")
    public void merchantWithHoldingService() {
        ObjectNode settings = MerchantFixtures.defaultServiceSettings();
        settings.put("invoiceRequirement", "REQUIRED");
        settings.put("holdPayments", true);
        OnboardedMerchant merchant = MerchantFixtures.onboardFullyConfiguredMerchant(settings);
        RequestContext.setBearerToken(merchant.adminToken());
    }

    @Given("I am authenticated as the administrator of a newly onboarded merchant whose service auto-acknowledges successful payments")
    public void merchantWithAutoAckService() {
        ObjectNode settings = MerchantFixtures.defaultServiceSettings();
        settings.put("autoAcknowledge", true);
        OnboardedMerchant merchant = MerchantFixtures.onboardFullyConfiguredMerchant(settings);
        RequestContext.setBearerToken(merchant.adminToken());
    }

    @Given("I am authenticated as the administrator of that merchant")
    public void iAmAuthenticatedAsTheAdministratorOfThatMerchant() {
        RequestContext.setBearerToken(ScenarioData.get("merchantAdminToken"));
    }

    @Given("I am using the onboarded merchant's API key")
    public void iAmUsingTheOnboardedMerchantsApiKey() {
        int merchantId = ScenarioData.get("merchantId");
        String adminToken = ScenarioData.get("merchantAdminToken");
        String apiKey = MerchantFixtures.enableApiAccessAndIssueKey(merchantId, adminToken);
        RequestContext.setApiKey(apiKey);
    }

    @Given("the onboarded merchant's API access is disabled")
    public void theOnboardedMerchantsApiAccessIsDisabled() {
        ObjectNode body = JsonSupport.newObject();
        body.put("apiEnabled", false);
        String adminToken = ScenarioData.get("merchantAdminToken");
        ApiClient.baseSpec().header("Authorization", "Bearer " + adminToken).body(JsonSupport.write(body))
                .put("/api/merchant-profile");
    }

    // ------------------------------------------------------------------ staff users

    @Given("I am authenticated as a newly created merchant_user of the onboarded merchant")
    public void iAmAuthenticatedAsANewlyCreatedMerchantUser() {
        String adminToken = ScenarioData.get("merchantAdminToken");
        StaffUser staff = MerchantFixtures.createActiveStaffUser(adminToken, "merchant_user");
        ScenarioData.put("staffUserId", staff.userId());
        ScenarioData.put("staffUsername", staff.username());
        ScenarioData.put("staffEmail", staff.email());
        ScenarioData.put("staffToken", staff.token());
        RequestContext.setBearerToken(staff.token());
    }

    @Given("a newly created staff user of the onboarded merchant has not changed their temporary password")
    public void aNewlyCreatedStaffUserHasNotChangedTheirPassword() {
        String adminToken = ScenarioData.get("merchantAdminToken");
        StaffUser staff = MerchantFixtures.createStaffUser(adminToken, "merchant_user");
        ScenarioData.put("staffUserId", staff.userId());
        ScenarioData.put("unchangedPasswordStaffToken", staff.token());
        ScenarioData.put("unchangedPasswordStaffEmail", staff.email());
        ScenarioData.put("unchangedPasswordStaffPassword", staff.password());
    }

    @Given("I am authenticated with that staff user's unchanged temporary-password token")
    public void iAmAuthenticatedWithUnchangedTemporaryPasswordToken() {
        RequestContext.setBearerToken(ScenarioData.get("unchangedPasswordStaffToken"));
    }

    // ------------------------------------------------------------------ payers

    @Given("a payer has been onboarded for provider {string}")
    public void aPayerHasBeenOnboardedForProvider(String provider) {
        PayerFixtures.createPayer(provider);
    }

    @Given("a payer has been onboarded for provider {string} dedicated to the onboarded merchant")
    public void aPayerHasBeenOnboardedDedicatedToTheMerchant(String provider) {
        int merchantId = ScenarioData.get("merchantId");
        PayerFixtures.createPayerDedicatedToMerchant(provider, merchantId);
    }

    @Given("the onboarded payer has a payer account")
    public void theOnboardedPayerHasAPayerAccount() {
        int payerId = ScenarioData.get("payerId");
        PayerFixtures.createPayerUser(payerId);
    }

    @Given("the onboarded payer's account has changed its temporary password")
    public void theOnboardedPayersAccountHasChangedItsTemporaryPassword() {
        PayerFixtures.activatePayerSession();
    }

    @Given("I am authenticated as that payer account")
    public void iAmAuthenticatedAsThatPayerAccount() {
        RequestContext.setBearerToken(ScenarioData.get("payerUserToken"));
    }

    @Given("the onboarded payer is offered as a payment option by the onboarded service")
    public void theOnboardedPayerIsOfferedByTheOnboardedService() {
        int merchantId = ScenarioData.get("merchantId");
        int serviceId = ScenarioData.get("serviceId");
        String payerCode = ScenarioData.get("payerCode");
        String adminToken = ScenarioData.get("merchantAdminToken");
        ObjectNode body = JsonSupport.newObject();
        body.putArray("payerCodes").add(payerCode);
        Response response = ApiClient.baseSpec().header("Authorization", "Bearer " + adminToken)
                .body(JsonSupport.write(body)).put("/api/services/" + serviceId + "/payment-options");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: attaching payer " + payerCode + " to service " + serviceId
                    + " failed (" + response.statusCode() + "): " + response.asString());
        }
    }
}
