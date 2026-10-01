package paymentapi.stepdefinitions;

import java.nio.file.Paths;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.cucumber.java.en.Given;

import paymentapi.utils.JsonSupport;

/**
 * Builds the body/query/headers/multipart-file of the next "When I send a
 * ... request" call. Body steps operate on one JSON tree per request (dot
 * paths create nested objects as needed), which is what lets a scenario take
 * a realistic example payload and remove/retype/blank out exactly the one
 * field a negative scenario is about.
 */
public class RequestBuildingSteps {

    private static final String TESTDATA_DIR = "src/test/resources/testdata/";

    // ------------------------------------------------------------------ whole body

    @Given("the request body is:")
    public void theRequestBodyIs(String docString) {
        JsonNode parsed = JsonSupport.parse(docString);
        if (!parsed.isObject()) {
            throw new IllegalArgumentException("'the request body is:' needs a JSON object at the top level, got: " + parsed);
        }
        RequestContext.setJsonBody((ObjectNode) parsed);
    }

    @Given("no request body is sent")
    public void noRequestBodyIsSent() {
        RequestContext.setNoBody();
    }

    @Given("the request body is an empty JSON object")
    public void theRequestBodyIsAnEmptyJsonObject() {
        RequestContext.setJsonBody(JsonSupport.newObject());
    }

    @Given("the request body is the following malformed JSON:")
    public void theRequestBodyIsTheFollowingMalformedJson(String docString) {
        RequestContext.setRawTextBody(JsonSupport.substitutePlaceholders(docString));
    }

    @Given("the request body is the text {string}")
    public void theRequestBodyIsTheText(String text) {
        RequestContext.setRawTextBody(JsonSupport.substitutePlaceholders(text));
    }

    // ------------------------------------------------------------------ one field at a time

    @Given("the request body field {string} is set to the string {string}")
    public void fieldIsSetToString(String path, String value) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.textValue(value));
    }

    @Given("the request body field {string} is set to the number {string}")
    public void fieldIsSetToNumber(String path, String numberLiteral) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.numberValue(numberLiteral));
    }

    /** For exact string-length boundary tests (max_length validation) without counting characters by hand in a feature file. */
    @Given("the request body field {string} is set to a string of length {int}")
    public void fieldIsSetToAStringOfLength(String path, int length) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.textValue("x".repeat(length)));
    }

    @Given("the request body field {string} is set to true")
    public void fieldIsSetToTrue(String path) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.booleanValue(true));
    }

    @Given("the request body field {string} is set to false")
    public void fieldIsSetToFalse(String path) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.booleanValue(false));
    }

    @Given("the request body field {string} is set to null")
    public void fieldIsSetToNull(String path) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.nullValue());
    }

    @Given("the request body field {string} is removed")
    public void fieldIsRemoved(String path) {
        JsonSupport.removePath(RequestContext.bodyForMutation(), path);
    }

    @Given("the request body field {string} is set to an empty array")
    public void fieldIsSetToAnEmptyArray(String path) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.emptyArray());
    }

    @Given("the request body field {string} is set to the array {string}")
    public void fieldIsSetToTheArray(String path, String commaSeparatedValues) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.arrayOfStrings(commaSeparatedValues));
    }

    @Given("the request body field {string} is set to the following JSON:")
    public void fieldIsSetToTheFollowingJson(String path, String docString) {
        JsonSupport.setPath(RequestContext.bodyForMutation(), path, JsonSupport.parse(docString));
    }

    // ------------------------------------------------------------------ query / headers

    @Given("query parameter {string} is {string}")
    public void queryParameterIs(String name, String value) {
        RequestContext.addQueryParam(name, JsonSupport.substitutePlaceholders(value));
    }

    @Given("request header {string} is set to {string}")
    public void requestHeaderIsSetTo(String name, String value) {
        RequestContext.addHeader(name, JsonSupport.substitutePlaceholders(value));
    }

    // ------------------------------------------------------------------ multipart

    @Given("the file {string} is attached as {string} with content type {string}")
    public void theFileIsAttachedAs(String fileName, String fieldName, String contentType) {
        RequestContext.setMultipartFile(fieldName, TESTDATA_DIR + fileName, contentType);
    }

    @Given("form field {string} is set to {string}")
    public void formFieldIsSetTo(String name, String value) {
        RequestContext.addMultipartFormField(name, JsonSupport.substitutePlaceholders(value));
    }

    public static String testdataPath(String fileName) {
        return Paths.get(TESTDATA_DIR, fileName).toString();
    }
}
