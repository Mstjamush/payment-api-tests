package paymentapi.stepdefinitions;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

import com.fasterxml.jackson.databind.JsonNode;
import io.cucumber.java.en.Then;
import io.restassured.response.Response;
import org.junit.Assert;

import paymentapi.utils.JsonSupport;


/**
 * Response assertions shared by every feature file - the Then half of the
 * generic vocabulary (see HttpExecutionSteps/RequestBuildingSteps for the
 * Given/When half). Field paths are REST Assured's own GPath dot/bracket
 * notation ("merchant.id", "items[0].code", "onboarding.steps[1].done").
 */
public class CommonAssertionSteps {

    // ------------------------------------------------------------------ status

    @Then("the response status should be {int}")
    public void theResponseStatusShouldBe(int expected) {
        Response response = ResponseContext.get();
        Assert.assertEquals("Unexpected status. Body: " + response.asString(), expected, response.statusCode());
    }

    @Then("the response status should be {int} or {int}")
    public void theResponseStatusShouldBeEitherOf(int a, int b) {
        Response response = ResponseContext.get();
        int actual = response.statusCode();
        Assert.assertTrue("Expected " + a + " or " + b + " but got " + actual + ". Body: " + response.asString(),
                actual == a || actual == b);
    }

    @Then("the response status should be one of {string}")
    public void theResponseStatusShouldBeOneOf(String commaSeparatedStatuses) {
        Response response = ResponseContext.get();
        int actual = response.statusCode();
        List<String> allowed = JsonSupport.splitCommaList(commaSeparatedStatuses);
        boolean matches = allowed.stream().anyMatch(s -> Integer.parseInt(s.trim()) == actual);
        Assert.assertTrue("Expected one of " + allowed + " but got " + actual + ". Body: " + response.asString(), matches);
    }

    // ------------------------------------------------------------------ scalar fields

    @Then("the JSON response field {string} should equal {string}")
    public void theJsonResponseFieldShouldEqual(String field, String expectedRaw) {
        String expected = resolve(expectedRaw);
        Response response = ResponseContext.get();
        String actual = response.jsonPath().getString(field);
        Assert.assertEquals("Field '" + field + "'. Body: " + response.asString(), expected, actual);
    }

    @Then("the JSON response field {string} should equal the number {string}")
    public void theJsonResponseFieldShouldEqualTheNumber(String field, String expectedLiteralRaw) {
        Response response = ResponseContext.get();
        Object actual = response.jsonPath().get(field);
        Assert.assertNotNull("Missing numeric field '" + field + "'. Body: " + response.asString(), actual);
        BigDecimal expected = new BigDecimal(resolve(expectedLiteralRaw));
        BigDecimal actualDecimal = new BigDecimal(actual.toString());
        Assert.assertEquals("Field '" + field + "' = " + actualDecimal + ", expected " + expected + ". Body: "
                + response.asString(), 0, expected.compareTo(actualDecimal));
    }

    @Then("the JSON response field {string} should equal true")
    public void theJsonResponseFieldShouldEqualTrue(String field) {
        assertBoolean(field, true);
    }

    @Then("the JSON response field {string} should equal false")
    public void theJsonResponseFieldShouldEqualFalse(String field) {
        assertBoolean(field, false);
    }

    private void assertBoolean(String field, boolean expected) {
        Response response = ResponseContext.get();
        Boolean actual = response.jsonPath().getBoolean(field);
        Assert.assertEquals("Field '" + field + "'. Body: " + response.asString(), Boolean.valueOf(expected), actual);
    }

    @Then("the JSON response field {string} should be null")
    public void theJsonResponseFieldShouldBeNull(String field) {
        Response response = ResponseContext.get();
        JsonNode node = JsonSupport.atDotPath(JsonSupport.parseLiteral(response.asString()), field);
        Assert.assertFalse("Field '" + field + "' is absent, expected an explicit null. Body: " + response.asString(),
                node.isMissingNode());
        Assert.assertTrue("Field '" + field + "' = " + node + ", expected null. Body: " + response.asString(), node.isNull());
    }

    @Then("the JSON response field {string} should be absent")
    public void theJsonResponseFieldShouldBeAbsent(String field) {
        Response response = ResponseContext.get();
        JsonNode node = JsonSupport.atDotPath(JsonSupport.parseLiteral(response.asString()), field);
        Assert.assertTrue("Field '" + field + "' is present (" + node + "), expected it to be absent entirely. Body: "
                + response.asString(), node.isMissingNode());
    }

    @Then("the JSON response field {string} should not be null")
    public void theJsonResponseFieldShouldNotBeNull(String field) {
        Response response = ResponseContext.get();
        Object value = response.jsonPath().get(field);
        Assert.assertNotNull("Field '" + field + "' is null or absent. Body: " + response.asString(), value);
    }

    @Then("the JSON response should have a non-empty {string} field")
    public void theJsonResponseShouldHaveANonEmptyField(String field) {
        Response response = ResponseContext.get();
        Object value = response.jsonPath().get(field);
        Assert.assertNotNull("Missing field '" + field + "'. Body: " + response.asString(), value);
        Assert.assertFalse("Field '" + field + "' is empty. Body: " + response.asString(), value.toString().trim().isEmpty());
    }

    @Then("the JSON response field {string} should contain {string}")
    public void theJsonResponseFieldShouldContain(String field, String substringRaw) {
        String substring = resolve(substringRaw);
        Response response = ResponseContext.get();
        String actual = response.jsonPath().getString(field);
        Assert.assertNotNull("Missing field '" + field + "'. Body: " + response.asString(), actual);
        Assert.assertTrue("Field '" + field + "' = '" + actual + "', expected it to contain '" + substring + "'. Body: "
                + response.asString(), actual.contains(substring));
    }

    @Then("the JSON response field {string} should match the pattern {string}")
    public void theJsonResponseFieldShouldMatchThePattern(String field, String regexRaw) {
        String regex = resolve(regexRaw);
        Response response = ResponseContext.get();
        String actual = response.jsonPath().getString(field);
        Assert.assertNotNull("Missing field '" + field + "'. Body: " + response.asString(), actual);
        Assert.assertTrue("Field '" + field + "' = '" + actual + "', expected to match /" + regex + "/. Body: "
                + response.asString(), Pattern.matches(regex, actual));
    }

    // ------------------------------------------------------------------ arrays

    @Then("the JSON response should be a list of exactly {int} item(s)")
    public void theJsonResponseShouldBeAListOfExactly(int expected) {
        assertArraySize("$", expected);
    }

    @Then("the JSON response should be a list of at least {int} item(s)")
    public void theJsonResponseShouldBeAListOfAtLeast(int minimum) {
        assertArrayMinSize("$", minimum);
    }

    @Then("the JSON response array {string} should have size {int}")
    public void theJsonResponseArrayShouldHaveSize(String field, int expected) {
        assertArraySize(field, expected);
    }

    @Then("the JSON response array {string} should have at least {int} item(s)")
    public void theJsonResponseArrayShouldHaveAtLeast(String field, int minimum) {
        assertArrayMinSize(field, minimum);
    }

    private void assertArraySize(String field, int expected) {
        Response response = ResponseContext.get();
        List<Object> list = response.jsonPath().getList(field);
        Assert.assertNotNull("'" + field + "' is not a JSON array. Body: " + response.asString(), list);
        Assert.assertEquals("Size of '" + field + "'. Body: " + response.asString(), expected, list.size());
    }

    private void assertArrayMinSize(String field, int minimum) {
        Response response = ResponseContext.get();
        List<Object> list = response.jsonPath().getList(field);
        Assert.assertNotNull("'" + field + "' is not a JSON array. Body: " + response.asString(), list);
        Assert.assertTrue("Size of '" + field + "' is " + list.size() + ", expected >= " + minimum + ". Body: "
                + response.asString(), list.size() >= minimum);
    }

    @Then("the JSON response array {string} should contain {string}")
    public void theJsonResponseArrayShouldContainPlainValue(String field, String expectedRaw) {
        String expected = resolve(expectedRaw);
        Response response = ResponseContext.get();
        List<Object> list = response.jsonPath().getList(field);
        Assert.assertNotNull("'" + field + "' is not a JSON array. Body: " + response.asString(), list);
        boolean found = list.stream().anyMatch(value -> expected.equals(String.valueOf(value)));
        Assert.assertTrue("Array '" + field + "' = " + list + ", expected it to contain '" + expected + "'. Body: "
                + response.asString(), found);
    }

    @Then("the JSON response array {string} should not contain {string}")
    public void theJsonResponseArrayShouldNotContainPlainValue(String field, String expectedRaw) {
        String expected = resolve(expectedRaw);
        Response response = ResponseContext.get();
        List<Object> list = response.jsonPath().getList(field);
        Assert.assertNotNull("'" + field + "' is not a JSON array. Body: " + response.asString(), list);
        boolean found = list.stream().anyMatch(value -> expected.equals(String.valueOf(value)));
        Assert.assertFalse("Array '" + field + "' = " + list + ", expected it NOT to contain '" + expected + "'. Body: "
                + response.asString(), found);
    }

    @Then("the JSON response array {string} should contain an item where {string} equals {string}")
    public void theJsonResponseArrayShouldContainAnItemWhere(String arrayField, String itemField, String expectedRaw) {
        String expected = resolve(expectedRaw);
        Assert.assertTrue(describeArrayFailure(arrayField, itemField, expected, true),
                anyItemMatches(arrayField, itemField, expected));
    }

    @Then("the JSON response array {string} should not contain an item where {string} equals {string}")
    public void theJsonResponseArrayShouldNotContainAnItemWhere(String arrayField, String itemField, String expectedRaw) {
        String expected = resolve(expectedRaw);
        Assert.assertFalse(describeArrayFailure(arrayField, itemField, expected, false),
                anyItemMatches(arrayField, itemField, expected));
    }

    @Then("every item in the JSON response array {string} should have {string} equal to {string}")
    public void everyItemShouldHaveFieldEqualTo(String arrayField, String itemField, String expectedRaw) {
        String expected = resolve(expectedRaw);
        Response response = ResponseContext.get();
        List<Object> actualValues = response.jsonPath().getList(itemFieldPath(arrayField, itemField));
        Assert.assertNotNull("'" + arrayField + "' is not a JSON array, or has no '" + itemField + "'. Body: "
                + response.asString(), actualValues);
        for (Object value : actualValues) {
            Assert.assertEquals("An item in '" + arrayField + "' had '" + itemField + "' = " + value + ", expected '"
                    + expected + "'. Body: " + response.asString(), expected, String.valueOf(value));
        }
    }

    private boolean anyItemMatches(String arrayField, String itemField, String expected) {
        Response response = ResponseContext.get();
        List<Object> actualValues = response.jsonPath().getList(itemFieldPath(arrayField, itemField));
        if (actualValues == null) return false;
        return actualValues.stream().anyMatch(value -> expected.equals(String.valueOf(value)));
    }

    /** "$" is the response's own root array - REST Assured's GPath plucks a field from each of ITS elements via
     * the bare field name ("name"), not "$.name" (which silently returns nothing). Any other array field nests
     * normally ("items.username"). */
    private static String itemFieldPath(String arrayField, String itemField) {
        return "$".equals(arrayField) ? itemField : arrayField + "." + itemField;
    }

    private String describeArrayFailure(String arrayField, String itemField, String expected, boolean expectedPresent) {
        Response response = ResponseContext.get();
        return "Array '" + arrayField + "', field '" + itemField + "' - expected " + (expectedPresent ? "" : "no ")
                + "item equal to '" + expected + "'. Body: " + response.asString();
    }

    // ------------------------------------------------------------------ headers

    @Then("the response header {string} should equal {string}")
    public void theResponseHeaderShouldEqual(String header, String expectedRaw) {
        String expected = resolve(expectedRaw);
        Response response = ResponseContext.get();
        Assert.assertEquals("Header '" + header + "'. Body: " + response.asString(), expected, response.header(header));
    }

    @Then("the response header {string} should match the pattern {string}")
    public void theResponseHeaderShouldMatchThePattern(String header, String regexRaw) {
        String regex = resolve(regexRaw);
        Response response = ResponseContext.get();
        String actual = response.header(header);
        Assert.assertNotNull("Missing header '" + header + "'. Body: " + response.asString(), actual);
        Assert.assertTrue("Header '" + header + "' = '" + actual + "', expected to match /" + regex + "/",
                Pattern.matches(regex, actual));
    }

    @Then("the response header {string} should be present")
    public void theResponseHeaderShouldBePresent(String header) {
        Response response = ResponseContext.get();
        Assert.assertNotNull("Missing header '" + header + "'. Body: " + response.asString(), response.header(header));
    }

    @Then("the response header {string} should be absent")
    public void theResponseHeaderShouldBeAbsent(String header) {
        Response response = ResponseContext.get();
        Assert.assertNull("Header '" + header + "' should not be present, was '" + response.header(header) + "'",
                response.header(header));
    }

    // ------------------------------------------------------------------ error envelope

    @Then("the error message should mention {string}")
    public void theErrorMessageShouldMention(String substring) {
        theJsonResponseFieldShouldContain("message", substring);
    }

    @Then("the response should list a validation problem for field {string}")
    public void theResponseShouldListAValidationProblemForField(String field) {
        Response response = ResponseContext.get();
        List<Map<String, Object>> violations = response.jsonPath().getList("violations");
        Assert.assertNotNull("No 'violations' array in the response. Body: " + response.asString(), violations);
        boolean present = violations.stream().anyMatch(v -> field.equals(String.valueOf(v.get("field"))));
        Assert.assertTrue("No validation problem reported for field '" + field + "'. Body: " + response.asString(), present);
    }

    @Then("the error timestamp field should look like an ISO-8601 UTC timestamp")
    public void theErrorTimestampFieldShouldLookLikeIso8601() {
        theJsonResponseFieldShouldMatchThePattern("timestamp", "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z");
    }

    // ------------------------------------------------------------------ raw body

    @Then("the response body should contain {string}")
    public void theResponseBodyShouldContain(String textRaw) {
        String text = resolve(textRaw);
        Response response = ResponseContext.get();
        Assert.assertTrue("Body does not contain '" + text + "': " + response.asString(), response.asString().contains(text));
    }

    /** Expected-value literals (not field paths) may reference {{placeholders}} too. */
    private static String resolve(String literal) {
        return JsonSupport.substitutePlaceholders(literal);
    }

    @Then("the response body should be empty")
    public void theResponseBodyShouldBeEmpty() {
        Response response = ResponseContext.get();
        Assert.assertTrue("Expected an empty body, got: " + response.asString(), response.asString().isBlank());
    }
}
