package paymentapi.utils;

import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import io.restassured.specification.RequestSpecification;

import paymentapi.config.Config;

/**
 * The one place that knows payment_api's base URL. Per-request authentication
 * (Authorization: Bearer / X-Api-Key) is applied generically by
 * HttpExecutionSteps from RequestContext, not here - this class only builds
 * the unauthenticated spec and offers the one login call every session/
 * fixture needs (POST /api/auth/login).
 */
public final class ApiClient {

    static {
        HttpLogging.install();
    }

    private ApiClient() {
    }

    public static RequestSpecification baseSpec() {
        return RestAssured.given().baseUri(Config.get("api.base.url")).contentType(ContentType.JSON);
    }

    public static RequestSpecification unauthenticatedSpec() {
        return baseSpec();
    }

    /** No default Content-Type - for multipart uploads, where RestAssured sets it from the parts added. */
    public static RequestSpecification rawSpec() {
        return RestAssured.given().baseUri(Config.get("api.base.url"));
    }

    /** POST /api/auth/login. Doesn't assert the outcome - callers (sessions/fixtures) decide what a non-200 means. */
    public static Response login(String email, String password) {
        var body = JsonSupport.newObject();
        body.put("email", email);
        body.put("password", password);
        return baseSpec().body(JsonSupport.write(body)).post("/api/auth/login");
    }
}
