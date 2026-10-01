package paymentapi.sessions;

import io.restassured.response.Response;

import paymentapi.config.Config;
import paymentapi.utils.ApiClient;

/**
 * The single platform administrator seeded by `python seed_admin.py`
 * (super_user on the super-merchant). Cached for the whole run and reused by
 * every scenario that needs platform-level access - no scenario in this
 * suite ever changes this account's password or active status, so the cache
 * stays valid for the life of the JVM.
 */
public final class PlatformAdminSession {

    private static String token;

    private PlatformAdminSession() {
    }

    public static synchronized String token() {
        if (token == null) {
            String email = Config.get("platform.admin.email");
            String password = Config.get("platform.admin.password");
            Response response = ApiClient.login(email, password);
            if (response.statusCode() != 200) {
                throw new IllegalStateException(
                        "Platform administrator login failed (" + response.statusCode() + "): " + response.asString()
                        + ". Check platform.admin.email/password in config.properties, and that `python seed_admin.py`"
                        + " has been run against the database payment_api is using (see payment_api/README.md).");
            }
            token = response.jsonPath().getString("accessToken");
        }
        return token;
    }
}
