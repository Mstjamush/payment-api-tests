package paymentapi.stepdefinitions;

import io.cucumber.java.en.Given;
import io.cucumber.java.en.Then;
import io.restassured.response.Response;

import paymentapi.utils.JsonSupport;
import paymentapi.utils.RandomData;

/** Captures a value from the last response, or generates a fresh unique one, under a name later steps can
 * reference as {{name}} (see JsonSupport.substitutePlaceholders). */
public class CaptureSteps {

    @Then("I store the response field {string} as {string}")
    public void iStoreTheResponseFieldAs(String field, String name) {
        Response response = ResponseContext.get();
        Object value = response.jsonPath().get(field);
        if (value == null) {
            throw new IllegalStateException("Response field '" + field + "' is null or absent - can't store it as '"
                    + name + "'. Body: " + response.asString());
        }
        ScenarioData.put(name, value);
    }

    @Given("a unique merchant code is stored as {string}")
    public void aUniqueMerchantCodeIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniqueMerchantCode());
    }

    @Given("a unique service code is stored as {string}")
    public void aUniqueServiceCodeIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniqueServiceCode());
    }

    @Given("a unique payer code is stored as {string}")
    public void aUniquePayerCodeIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniquePayerCode());
    }

    @Given("a unique email address is stored as {string}")
    public void aUniqueEmailAddressIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniqueEmail("qa"));
    }

    @Given("a unique username is stored as {string}")
    public void aUniqueUsernameIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniqueUsername("qa.user"));
    }

    @Given("a unique phone number is stored as {string}")
    public void aUniquePhoneNumberIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniqueMsisdn());
    }

    @Given("a unique merchant payment id is stored as {string}")
    public void aUniqueMerchantPaymentIdIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniqueMerchantPaymentId());
    }

    @Given("a unique invoice number is stored as {string}")
    public void aUniqueInvoiceNumberIsStoredAs(String name) {
        ScenarioData.put(name, RandomData.uniqueInvoiceNumber());
    }

    @Given("a unique string of length {int} is stored as {string}")
    public void aUniqueStringOfLengthIsStoredAs(int length, String name) {
        ScenarioData.put(name, RandomData.randomAlpha(length));
    }

    @Given("the text {string} is stored as {string}")
    public void theTextIsStoredAs(String value, String name) {
        ScenarioData.put(name, JsonSupport.substitutePlaceholders(value));
    }
}
