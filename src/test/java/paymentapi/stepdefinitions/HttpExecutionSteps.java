package paymentapi.stepdefinitions;

import java.io.File;
import java.nio.file.Files;
import java.util.Locale;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.cucumber.java.en.When;
import io.restassured.http.Method;
import io.restassured.response.Response;
import io.restassured.specification.RequestSpecification;

import paymentapi.stepdefinitions.RequestContext.AuthMode;
import paymentapi.utils.ApiClient;
import paymentapi.utils.JsonSupport;

/**
 * The one execution engine every feature file's "When" steps funnel through:
 * fires the request RequestContext/RequestBuildingSteps have built up against
 * any payment_api path. One generic step covers all 76 documented endpoints -
 * domain feature files only need to say *what* to send, via the Given steps
 * in RequestBuildingSteps and AuthContextSteps.
 */
public class HttpExecutionSteps {

    /** Convenience for the common case of a one-off call with its own full body - equivalent to
     * "Given the request body is:" immediately followed by this same request. */
    @When("I send a {word} request to {string} with body:")
    public void iSendARequestToWithBody(String method, String rawPath, String docString) {
        JsonNode parsed = JsonSupport.parse(docString);
        if (!parsed.isObject()) {
            throw new IllegalArgumentException("'... with body:' needs a JSON object at the top level, got: " + parsed);
        }
        RequestContext.setJsonBody((ObjectNode) parsed);
        iSendARequestTo(method, rawPath);
    }

    @When("I send a {word} request to {string}")
    public void iSendARequestTo(String method, String rawPath) {
        String path = JsonSupport.substitutePlaceholders(rawPath);
        RequestSpecification spec = RequestContext.hasMultipartFile() ? buildMultipartSpec() : buildJsonSpec();
        applyAuth(spec);
        applyHeaders(spec);
        applyQueryParams(spec);

        Response response = spec.request(Method.valueOf(method.toUpperCase(Locale.ROOT)), path);
        ResponseContext.set(response);
        RequestContext.resetOneShotRequestState();
    }

    private RequestSpecification buildJsonSpec() {
        RequestSpecification spec = ApiClient.baseSpec();
        if (RequestContext.rawTextBody() != null) {
            spec.body(RequestContext.rawTextBody());
        } else if (RequestContext.jsonBody() != null) {
            spec.body(JsonSupport.write(RequestContext.jsonBody()));
        }
        return spec;
    }

    private RequestSpecification buildMultipartSpec() {
        RequestSpecification spec = ApiClient.rawSpec();
        File file = new File(RequestContext.multipartFilePath());
        if (!file.isFile()) {
            throw new IllegalStateException("Multipart fixture file not found: " + file.getAbsolutePath()
                    + " - see src/test/resources/testdata/");
        }
        try {
            spec.multiPart(RequestContext.multipartFileFieldName(), file.getName(), Files.readAllBytes(file.toPath()),
                    RequestContext.multipartFileMimeType());
        } catch (Exception e) {
            throw new RuntimeException("Could not read multipart fixture file " + file.getAbsolutePath(), e);
        }
        for (Map.Entry<String, String> field : RequestContext.multipartFormFields().entrySet()) {
            spec.multiPart(field.getKey(), field.getValue());
        }
        return spec;
    }

    private void applyAuth(RequestSpecification spec) {
        if (RequestContext.authMode() == AuthMode.BEARER) {
            spec.header("Authorization", "Bearer " + RequestContext.authCredential());
        } else if (RequestContext.authMode() == AuthMode.API_KEY) {
            spec.header("X-Api-Key", RequestContext.authCredential());
        }
    }

    private void applyHeaders(RequestSpecification spec) {
        RequestContext.headers().forEach(spec::header);
    }

    private void applyQueryParams(RequestSpecification spec) {
        RequestContext.queryParams().forEach(spec::queryParam);
    }
}
