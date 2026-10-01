package paymentapi.stepdefinitions;

import java.util.List;
import java.util.Map;
import java.util.Set;

import io.cucumber.java.en.When;
import io.restassured.response.Response;
import io.restassured.specification.RequestSpecification;

import paymentapi.config.Config;
import paymentapi.utils.ApiClient;
import paymentapi.utils.JsonSupport;
import paymentapi.utils.Waiter;

/**
 * Polls for state that only appears once a queued message is actually acted
 * on - by payment_api's own background publish task (needs RabbitMQ
 * reachable: @requires-rabbitmq) or by payment_consumers reading the queue
 * and writing a row (@requires-consumer). See the README's "Running against
 * a partial stack" section for what each tag needs running.
 */
public class WaitSteps {

    private static int rabbitTimeout() {
        return Integer.parseInt(Config.get("wait.queue.publish.timeout.seconds"));
    }

    private static long rabbitPollMs() {
        return Long.parseLong(Config.get("wait.queue.publish.poll.interval.ms"));
    }

    private static int consumerTimeout() {
        return Integer.parseInt(Config.get("wait.consumer.timeout.seconds"));
    }

    private static long consumerPollMs() {
        return Long.parseLong(Config.get("wait.consumer.poll.interval.ms"));
    }

    private static RequestSpecification asMerchantAdmin() {
        String token = ScenarioData.get("merchantAdminToken");
        return ApiClient.baseSpec().header("Authorization", "Bearer " + token);
    }

    @When("I wait for the invoice {string} to exist for the onboarded merchant")
    public void iWaitForTheInvoiceToExistForTheOnboardedMerchant(String invoiceNumberRaw) {
        String invoiceNumber = JsonSupport.substitutePlaceholders(invoiceNumberRaw);
        Object[] found = new Object[2];
        Waiter.until("invoice '" + invoiceNumber + "' to exist (needs payment_consumers running)",
                consumerTimeout(), consumerPollMs(), () -> {
            Response response = asMerchantAdmin().queryParam("search", invoiceNumber).get("/api/invoices");
            if (response.statusCode() != 200) return false;
            List<Map<String, Object>> items = response.jsonPath().getList("items");
            return items.stream().filter(item -> invoiceNumber.equals(item.get("invoiceNumber"))).findFirst()
                    .map(item -> {
                        found[0] = item.get("id");
                        found[1] = item.get("status");
                        return true;
                    }).orElse(false);
        });
        ScenarioData.put("invoiceId", found[0]);
        ScenarioData.put("invoiceStatus", found[1]);
    }

    @When("I wait for the payment {string} to exist for the onboarded merchant")
    public void iWaitForThePaymentToExistForTheOnboardedMerchant(String merchantPaymentIdRaw) {
        String merchantPaymentId = JsonSupport.substitutePlaceholders(merchantPaymentIdRaw);
        Object[] found = new Object[2];
        Waiter.until("payment '" + merchantPaymentId + "' to exist (needs payment_consumers running)",
                consumerTimeout(), consumerPollMs(), () -> {
            Response response = asMerchantAdmin().queryParam("search", merchantPaymentId).get("/api/payments");
            if (response.statusCode() != 200) return false;
            List<Map<String, Object>> items = response.jsonPath().getList("items");
            return items.stream().filter(item -> merchantPaymentId.equals(item.get("merchantPaymentId"))).findFirst()
                    .map(item -> {
                        found[0] = item.get("id");
                        found[1] = item.get("status");
                        return true;
                    }).orElse(false);
        });
        ScenarioData.put("paymentId", found[0]);
        ScenarioData.put("paymentStatus", found[1]);
    }

    @When("I wait for the payment stored as {string} to reach status {string}")
    public void iWaitForThePaymentStoredAsToReachStatus(String idKey, String expectedStatus) {
        int paymentId = ScenarioData.get(idKey);
        Waiter.until("payment #" + paymentId + " to reach status " + expectedStatus
                        + " (needs payment_consumers, a payer that will answer, and (for ACKNOWLEDGED/FAILED_ACKNOWLEDGED)"
                        + " the merchant callback being auto-acknowledged or answered)",
                consumerTimeout(), consumerPollMs(), () -> {
            Response response = asMerchantAdmin().get("/api/payments/" + paymentId);
            return response.statusCode() == 200 && expectedStatus.equals(response.jsonPath().getString("status"));
        });
    }

    private static final Set<String> PUBLISH_TERMINAL = Set.of("QUEUED", "PARTIAL", "FAILED");

    @When("I wait for the upload batch stored as {string} to finish publishing")
    public void iWaitForTheUploadBatchToFinishPublishing(String idKey) {
        int uploadId = ScenarioData.get(idKey);
        String[] status = new String[1];
        Waiter.until("upload batch #" + uploadId + " to finish publishing (needs RabbitMQ reachable from payment_api)",
                rabbitTimeout(), rabbitPollMs(), () -> {
            Response response = asMerchantAdmin().get("/api/uploads/" + uploadId);
            if (response.statusCode() != 200) return false;
            status[0] = response.jsonPath().getString("status");
            return PUBLISH_TERMINAL.contains(status[0]);
        });
        ScenarioData.put(idKey + "PublishStatus", status[0]);
    }

    @When("I wait for the upload batch stored as {string} to complete")
    public void iWaitForTheUploadBatchToComplete(String idKey) {
        int uploadId = ScenarioData.get(idKey);
        Waiter.until("upload batch #" + uploadId + " to complete (needs payment_consumers running)",
                consumerTimeout(), consumerPollMs(), () -> {
            Response response = asMerchantAdmin().get("/api/uploads/" + uploadId);
            return response.statusCode() == 200 && "COMPLETED".equals(response.jsonPath().getString("status"));
        });
    }
}
