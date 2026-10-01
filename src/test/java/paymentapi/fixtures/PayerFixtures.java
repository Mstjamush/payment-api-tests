package paymentapi.fixtures;

import com.fasterxml.jackson.databind.node.ObjectNode;
import io.restassured.response.Response;

import paymentapi.sessions.PlatformAdminSession;
import paymentapi.stepdefinitions.ScenarioData;
import paymentapi.utils.ApiClient;
import paymentapi.utils.JsonSupport;
import paymentapi.utils.RandomData;

/**
 * Builds payer (payment option) preconditions through POST /api/payers. Only
 * "mpesa", "astropay" and "airtel" are accepted providers (the ones
 * payment_consumers has a controller for) - see REQUIRED_CONFIG in
 * payment_api/app/payers.py, mirrored by providerConfigFor() below.
 *
 * provider_config values are stored verbatim (the consumer's own concern) -
 * payment_api never resolves or calls out to them, so fixture URLs here are
 * harmless placeholders, unlike a merchant/service/payer apiCallbackUrl,
 * which payment_api itself validates and DNS-resolves (see
 * services.feature's "callback URL" scenarios).
 */
public final class PayerFixtures {

    public record CreatedPayer(int payerId, String payerCode, String provider) {
    }

    public record PayerUser(int userId, String username, String email, String password, String token) {
    }

    private PayerFixtures() {
    }

    private static io.restassured.specification.RequestSpecification asPlatformAdmin() {
        return ApiClient.baseSpec().header("Authorization", "Bearer " + PlatformAdminSession.token());
    }

    public static ObjectNode providerConfigFor(String provider) {
        ObjectNode config = JsonSupport.newObject();
        switch (provider) {
            case "mpesa" -> {
                config.put("baseUrl", "https://sandbox.safaricom.example.test");
                config.put("consumerKey", "qa-consumer-key");
                config.put("consumerSecret", "qa-consumer-secret");
                config.put("shortcode", "174379");
                config.put("passkey", "qa-passkey");
                config.put("callbackUrl", "https://gateway.example.test/api/v1/payment-responses/MPESA");
            }
            case "astropay" -> {
                config.put("baseUrl", "https://sandbox.astropay.example.test");
                config.put("appId", "qa-app-id");
                config.put("secretKey", "qa-secret-key");
                config.put("callbackUrl", "https://gateway.example.test/api/v1/payment-responses/ASTROPAY");
            }
            case "airtel" -> {
                config.put("baseUrl", "https://sandbox.airtel.example.test");
                config.put("clientId", "qa-client-id");
                config.put("clientSecret", "qa-client-secret");
                config.put("country", "KE");
                config.put("currency", "KES");
            }
            default -> throw new IllegalArgumentException("Unknown provider '" + provider
                    + "' - use mpesa, astropay or airtel (the only ones payment_consumers has a controller for)");
        }
        return config;
    }

    public static CreatedPayer createPayer(String provider) {
        return createPayer(provider, JsonSupport.newObject());
    }

    public static CreatedPayer createPayer(String provider, ObjectNode overrides) {
        String code = RandomData.uniquePayerCode();
        ObjectNode body = JsonSupport.newObject();
        body.put("name", "QA " + provider + " Payer " + RandomData.uniqueSuffix());
        body.put("code", code);
        body.put("type", "MOBILE_MONEY");
        body.put("provider", provider);
        body.put("contactEmail", RandomData.uniqueEmail("qa.payer"));
        body.put("contactPhone", RandomData.uniqueMsisdn());
        body.set("providerConfig", providerConfigFor(provider));
        body.setAll(overrides);

        Response response = asPlatformAdmin().body(JsonSupport.write(body)).post("/api/payers");
        if (response.statusCode() != 201) {
            throw new IllegalStateException("Fixture: POST /api/payers failed (" + response.statusCode() + "): "
                    + response.asString());
        }
        int payerId = response.jsonPath().getInt("id");
        String payerCode = response.jsonPath().getString("code");
        ScenarioData.put("payerId", payerId);
        ScenarioData.put("payerCode", payerCode);
        return new CreatedPayer(payerId, payerCode, provider);
    }

    /** A platform-wide active mpesa payer - the default payment option fixtures elsewhere assume when the provider doesn't matter. */
    public static CreatedPayer createDefaultPayer() {
        return createPayer("mpesa");
    }

    public static CreatedPayer createPayerDedicatedToMerchant(String provider, int merchantId) {
        ObjectNode overrides = JsonSupport.newObject();
        overrides.put("merchantId", merchantId);
        return createPayer(provider, overrides);
    }

    public static PayerUser createPayerUser(int payerId) {
        String username = RandomData.uniqueUsername("qa.payer.user");
        String email = RandomData.uniqueEmail("qa.payer.user");

        ObjectNode body = JsonSupport.newObject();
        body.put("username", username);
        body.put("email", email);
        body.put("fullName", "QA Payer User " + RandomData.uniqueSuffix());

        Response response = asPlatformAdmin().body(JsonSupport.write(body)).post("/api/payers/" + payerId + "/users");
        if (response.statusCode() != 201) {
            throw new IllegalStateException("Fixture: POST /api/payers/" + payerId + "/users failed ("
                    + response.statusCode() + "): " + response.asString());
        }
        int userId = response.jsonPath().getInt("userId");
        String temporaryPassword = response.jsonPath().getString("temporaryPassword");

        Response login = ApiClient.login(email, temporaryPassword);
        if (login.statusCode() != 200) {
            throw new IllegalStateException("Fixture: payer account login failed (" + login.statusCode() + "): "
                    + login.asString());
        }
        String token = login.jsonPath().getString("accessToken");
        ScenarioData.put("payerUserToken", token);
        ScenarioData.put("payerUserPassword", temporaryPassword);
        return new PayerUser(userId, username, email, temporaryPassword, token);
    }

    /** Changes a just-created payer account's temporary password, same reasoning as
     * MerchantFixtures.activateAdminSession: mustChangePassword restricts the caller to
     * /api/auth/me and /api/auth/change-password only, so a scenario that needs the payer
     * account to actually DO something else (payer-reports, acknowledgements, ...) must move
     * past that first. Overwrites "payerUserToken" so "I am authenticated as that payer
     * account" picks up the active session without needing to change. */
    public static String activatePayerSession() {
        String temporaryToken = ScenarioData.get("payerUserToken");
        String temporaryPassword = ScenarioData.get("payerUserPassword");
        String activePassword = "QaPayerActive123!";
        ObjectNode body = JsonSupport.newObject();
        body.put("currentPassword", temporaryPassword);
        body.put("newPassword", activePassword);
        Response response = ApiClient.baseSpec().header("Authorization", "Bearer " + temporaryToken)
                .body(JsonSupport.write(body)).post("/api/auth/change-password");
        if (response.statusCode() != 200) {
            throw new IllegalStateException("Fixture: activating the payer account's session failed ("
                    + response.statusCode() + "): " + response.asString());
        }
        String activeToken = response.jsonPath().getString("accessToken");
        ScenarioData.put("payerUserPassword", activePassword);
        ScenarioData.put("payerUserToken", activeToken);
        return activeToken;
    }
}
