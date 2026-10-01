package paymentapi.stepdefinitions;

import java.util.HashMap;
import java.util.Map;

/**
 * Scenario-scoped values shared across step classes: ids and codes of
 * merchants/services/payers/invoices/payments created earlier in the same
 * scenario, tokens, generated credentials. Cleared before each scenario
 * (Hooks). Conventional keys used by the fixtures and generic steps:
 *
 *   merchantId, merchantCode, merchantAdminUsername, merchantAdminEmail,
 *   merchantAdminPassword, merchantAdminToken, merchantApiKey,
 *   serviceId, serviceCode, payerId, payerCode, payerUserToken
 *
 * Any {{name}} placeholder in a feature file (in a URL, a JSON body docstring,
 * a header or query value) is resolved against this store - see JsonSupport.
 */
public final class ScenarioData {

    private static final ThreadLocal<Map<String, Object>> DATA = ThreadLocal.withInitial(HashMap::new);

    private ScenarioData() {
    }

    public static void put(String key, Object value) {
        DATA.get().put(key, value);
    }

    @SuppressWarnings("unchecked")
    public static <T> T get(String key) {
        Object value = DATA.get().get(key);
        if (value == null) {
            throw new IllegalStateException("Nothing stored as '" + key + "' in this scenario yet");
        }
        return (T) value;
    }

    public static boolean has(String key) {
        return DATA.get().containsKey(key);
    }

    public static void clear() {
        DATA.get().clear();
    }
}
