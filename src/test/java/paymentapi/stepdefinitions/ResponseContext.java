package paymentapi.stepdefinitions;

import io.restassured.response.Response;

/** The most recent HTTP response, for Then steps to assert against. */
public final class ResponseContext {

    private static final ThreadLocal<Response> RESPONSE = new ThreadLocal<>();

    private ResponseContext() {
    }

    public static void set(Response response) {
        RESPONSE.set(response);
    }

    public static Response get() {
        Response response = RESPONSE.get();
        if (response == null) {
            throw new IllegalStateException("No response yet in this scenario - call a 'When I send a ... request' step first");
        }
        return response;
    }

    public static void clear() {
        RESPONSE.remove();
    }
}
