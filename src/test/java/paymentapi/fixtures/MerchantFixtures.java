package paymentapi.fixtures;

import com.fasterxml.jackson.databind.node.ObjectNode;
import io.restassured.response.Response;

import paymentapi.sessions.PlatformAdminSession;
import paymentapi.stepdefinitions.ScenarioData;
import paymentapi.utils.ApiClient;
import paymentapi.utils.JsonSupport;
import paymentapi.utils.RandomData;

/**
 * Builds merchant-client preconditions through the real onboarding endpoints
 * (POST /api/merchants -> POST .../services -> PUT .../settings ->
 * POST .../onboarding/complete) - the same four calls
 * merchant_onboarding.feature exercises directly. Used as a Background by
 * every other domain's feature files that need "a live merchant" without
 * re-narrating onboarding itself.
 *
 * Every fixture call uses fresh random codes/emails, so scenarios never
 * collide with each other and can run in any order or be repeated.
 * Everything created is also written into ScenarioData under the keys the
 * generic steps' {{placeholders}} expect (merchantId, serviceId, ...), so a
 * feature file can mix fixture Given steps with direct HTTP When steps freely.
 */
public final class MerchantFixtures {

    public record CreatedMerchant(int merchantId, String merchantCode, String adminUsername, String adminEmail) {
    }

    public record OnboardedMerchant(int merchantId, String merchantCode, int serviceId, String serviceCode,
                                    String adminUsername, String adminEmail, String adminPassword, String adminToken) {
    }

    public record StaffUser(int userId, String username, String email, String password, String token) {
    }

    private MerchantFixtures() {
    }

    private static io.restassured.specification.RequestSpecification asPlatformAdmin() {
        return ApiClient.baseSpec().header("Authorization", "Bearer " + PlatformAdminSession.token());
    }

    // ------------------------------------------------------------------ step 1: profile + administrator

    public static CreatedMerchant createMerchantProfile() {
        return createMerchantProfile(JsonSupport.newObject());
    }

    /** overrides is merged over the random defaults - lets a caller force a specific name/code/contact when needed. */
    public static CreatedMerchant createMerchantProfile(ObjectNode overrides) {
        String suffix = RandomData.uniqueSuffix();
        String code = RandomData.uniqueMerchantCode();
        String adminUsername = RandomData.uniqueUsername("qa.admin");
        String adminEmail = RandomData.uniqueEmail("qa.merchant.admin");

        ObjectNode body = JsonSupport.newObject();
        body.put("name", "QA Merchant " + suffix);
        body.put("code", code);
        body.put("contactEmail", RandomData.uniqueEmail("qa.merchant.contact"));
        body.put("contactPhone", "+254700" + suffix.substring(0, 6).replaceAll("\\D", "1"));
        body.put("superAdminUsername", adminUsername);
        body.put("superAdminFullName", "QA Admin " + suffix);
        body.put("superAdminEmail", adminEmail);
        body.setAll(overrides);

        Response response = asPlatformAdmin().body(JsonSupport.write(body)).post("/api/merchants");
        if (response.statusCode() != 201) {
            throw new IllegalStateException("Fixture: POST /api/merchants failed (" + response.statusCode() + "): "
                    + response.asString());
        }
        int merchantId = response.jsonPath().getInt("merchant.id");
        String merchantCode = response.jsonPath().getString("merchant.code");
        int adminUserId = response.jsonPath().getInt("superAdminId");

        ScenarioData.put("merchantId", merchantId);
        ScenarioData.put("merchantCode", merchantCode);
        ScenarioData.put("merchantAdminUsername", adminUsername);
        ScenarioData.put("merchantAdminEmail", adminEmail);
        ScenarioData.put("merchantAdminUserId", adminUserId);
        return new CreatedMerchant(merchantId, merchantCode, adminUsername, adminEmail);
    }

    // ------------------------------------------------------------------ step 2: a service

    public static int addUnconfiguredService(int merchantId) {
        String code = RandomData.uniqueServiceCode();
        ObjectNode body = JsonSupport.newObject();
        body.put("code", code);
        body.put("name", "QA Service " + RandomData.uniqueSuffix());

        Response response = asPlatformAdmin().body(JsonSupport.write(body)).post("/api/merchants/" + merchantId + "/services");
        if (response.statusCode() != 201) {
            throw new IllegalStateException("Fixture: POST /api/merchants/" + merchantId + "/services failed ("
                    + response.statusCode() + "): " + response.asString());
        }
        int serviceId = response.jsonPath().getInt("id");
        ScenarioData.put("serviceId", serviceId);
        ScenarioData.put("serviceCode", code);
        return serviceId;
    }

    public static ObjectNode defaultServiceSettings() {
        ObjectNode settings = JsonSupport.newObject();
        settings.put("invoiceRequirement", "OPTIONAL");
        settings.put("autoAcknowledge", false);
        settings.put("holdPayments", false);
        settings.put("ackMaxAttempts", 5);
        settings.put("notifyCustomers", true);
        settings.put("chargeModel", "NONE");
        return settings;
    }

    public static void configureServiceSettings(int merchantId, int serviceId, ObjectNode settings) {
        Response response = asPlatformAdmin().body(JsonSupport.write(settings))
                .put("/api/merchants/" + merchantId + "/services/" + serviceId + "/settings");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: PUT .../services/" + serviceId + "/settings failed ("
                    + response.statusCode() + "): " + response.asString());
        }
    }

    // ------------------------------------------------------------------ step 4: go live

    public record CompletionResult(String adminPassword, String adminToken) {
    }

    public static CompletionResult completeOnboarding(int merchantId, String adminEmail) {
        Response response = asPlatformAdmin().post("/api/merchants/" + merchantId + "/onboarding/complete");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: POST .../onboarding/complete failed (" + response.statusCode()
                    + "): " + response.asString());
        }
        String password = response.jsonPath().getString("initialAdmin.temporaryPassword");
        Response login = ApiClient.login(adminEmail, password);
        if (login.statusCode() != 200) {
            throw new IllegalStateException("Fixture: merchant administrator login after onboarding failed ("
                    + login.statusCode() + "): " + login.asString());
        }
        String token = login.jsonPath().getString("accessToken");
        ScenarioData.put("merchantAdminPassword", password);
        ScenarioData.put("merchantAdminToken", token);
        return new CompletionResult(password, token);
    }

    // ------------------------------------------------------------------ full flows

    /**
     * Changes a just-onboarded administrator's temporary password, so the token this returns can call anything the
     * role allows straight away. A fresh administrator token can otherwise only call /api/auth/me and
     * /api/auth/change-password - require("users.manage"), require("settings.manage") etc. all depend on
     * current_actor (password_change_allowed=False), so e.g. creating a staff user with a not-yet-activated
     * admin token fails with 403 "Password change required".
     */
    public static OnboardedMerchant activateAdminSession(int merchantId, String merchantCode, int serviceId,
                                                          String serviceCode, String adminUsername, String adminEmail,
                                                          CompletionResult completion) {
        String activePassword = "QaMerchantAdminActive123!";
        ObjectNode body = JsonSupport.newObject();
        body.put("currentPassword", completion.adminPassword());
        body.put("newPassword", activePassword);
        Response response = ApiClient.baseSpec().header("Authorization", "Bearer " + completion.adminToken())
                .body(JsonSupport.write(body)).post("/api/auth/change-password");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: activating the merchant administrator's session failed ("
                    + response.statusCode() + "): " + response.asString());
        }
        String activeToken = response.jsonPath().getString("accessToken");
        ScenarioData.put("merchantAdminPassword", activePassword);
        ScenarioData.put("merchantAdminToken", activeToken);
        return new OnboardedMerchant(merchantId, merchantCode, serviceId, serviceCode, adminUsername, adminEmail,
                activePassword, activeToken);
    }

    /** A live merchant with one active, configured (default-settings, OPTIONAL invoices, no hold) service, and an
     * administrator session that has already moved past its temporary password - the common case every other
     * domain's fixtures/feature files build on. */
    public static OnboardedMerchant onboardFullyConfiguredMerchant() {
        return onboardFullyConfiguredMerchant(defaultServiceSettings());
    }

    public static OnboardedMerchant onboardFullyConfiguredMerchant(ObjectNode serviceSettings) {
        OnboardedMerchant raw = onboardFullyConfiguredMerchantKeepingTemporaryPassword(serviceSettings);
        return activateAdminSession(raw.merchantId(), raw.merchantCode(), raw.serviceId(), raw.serviceCode(),
                raw.adminUsername(), raw.adminEmail(),
                new CompletionResult(raw.adminPassword(), raw.adminToken()));
    }

    /** Same as onboardFullyConfiguredMerchant, but leaves the administrator's password as the one-time temporary
     * one handed out by onboarding/complete - for scenarios about that first-sign-in behaviour itself
     * (authentication.feature), where changing it immediately would defeat the point. */
    public static OnboardedMerchant onboardFullyConfiguredMerchantKeepingTemporaryPassword() {
        return onboardFullyConfiguredMerchantKeepingTemporaryPassword(defaultServiceSettings());
    }

    public static OnboardedMerchant onboardFullyConfiguredMerchantKeepingTemporaryPassword(ObjectNode serviceSettings) {
        CreatedMerchant merchant = createMerchantProfile();
        int serviceId = addUnconfiguredService(merchant.merchantId());
        configureServiceSettings(merchant.merchantId(), serviceId, serviceSettings);
        CompletionResult completion = completeOnboarding(merchant.merchantId(), merchant.adminEmail());
        String serviceCode = ScenarioData.get("serviceCode");
        return new OnboardedMerchant(merchant.merchantId(), merchant.merchantCode(), serviceId, serviceCode,
                merchant.adminUsername(), merchant.adminEmail(), completion.adminPassword(), completion.adminToken());
    }

    /** Still IN_PROGRESS - created, but with none of the remaining onboarding steps done yet. */
    public static CreatedMerchant onboardMerchantInProgress() {
        return createMerchantProfile();
    }

    // ------------------------------------------------------------------ API key

    public static String issueMerchantApiKey(int merchantId) {
        Response response = asPlatformAdmin().post("/api/merchants/" + merchantId + "/api-key");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: POST /api/merchants/" + merchantId + "/api-key failed ("
                    + response.statusCode() + "): " + response.asString());
        }
        String apiKey = response.jsonPath().getString("apiKey");
        ScenarioData.put("merchantApiKey", apiKey);
        return apiKey;
    }

    /** Enables API access (with a safe, publicly-resolvable callback URL) and issues a key, in one call. */
    public static String enableApiAccessAndIssueKey(int merchantId, String merchantAdminToken) {
        ObjectNode body = JsonSupport.newObject();
        body.put("apiEnabled", true);
        body.put("apiCallbackUrl", "https://example.com/qa-callback");
        Response response = ApiClient.baseSpec().header("Authorization", "Bearer " + merchantAdminToken)
                .body(JsonSupport.write(body)).put("/api/merchant-profile");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: PUT /api/merchant-profile failed (" + response.statusCode()
                    + "): " + response.asString());
        }
        return issueMerchantApiKey(merchantId);
    }

    // ------------------------------------------------------------------ staff users

    /** Creates a staff user of the merchant the given admin token belongs to. roleName: merchant_admin | merchant_user. */
    public static StaffUser createStaffUser(String actingAdminToken, String roleName) {
        String username = RandomData.uniqueUsername("qa.staff");
        String email = RandomData.uniqueEmail("qa.staff");
        String password = "QaStaffPassword123!";

        ObjectNode body = JsonSupport.newObject();
        body.put("username", username);
        body.put("email", email);
        body.put("password", password);
        body.put("fullName", "QA Staff " + RandomData.uniqueSuffix());
        body.putArray("roleNames").add(roleName);

        Response response = ApiClient.baseSpec().header("Authorization", "Bearer " + actingAdminToken)
                .body(JsonSupport.write(body)).post("/api/users");
        if (response.statusCode() != 201) {
            throw new IllegalStateException("Fixture: POST /api/users failed (" + response.statusCode() + "): "
                    + response.asString());
        }
        int userId = response.jsonPath().getInt("id");

        Response login = ApiClient.login(email, password);
        String token = login.statusCode() == 200 ? login.jsonPath().getString("accessToken") : null;
        return new StaffUser(userId, username, email, password, token);
    }

    /**
     * Same as createStaffUser, but also changes the temporary password immediately, so the returned token can call
     * any endpoint the role allows straight away (POST /api/users always sets mustChangePassword - a fresh token
     * from that account can otherwise only call /api/auth/me and /api/auth/change-password).
     */
    public static StaffUser createActiveStaffUser(String actingAdminToken, String roleName) {
        StaffUser created = createStaffUser(actingAdminToken, roleName);
        String newPassword = "QaStaffActive123!";
        ObjectNode changeBody = JsonSupport.newObject();
        changeBody.put("currentPassword", created.password());
        changeBody.put("newPassword", newPassword);
        Response response = ApiClient.baseSpec().header("Authorization", "Bearer " + created.token())
                .body(JsonSupport.write(changeBody)).post("/api/auth/change-password");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: change-password for a freshly created staff user failed ("
                    + response.statusCode() + "): " + response.asString());
        }
        String activeToken = response.jsonPath().getString("accessToken");
        return new StaffUser(created.userId(), created.username(), created.email(), newPassword, activeToken);
    }
}
