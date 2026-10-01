package paymentapi.utils;

import java.math.BigDecimal;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.MissingNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import paymentapi.stepdefinitions.ScenarioData;

/**
 * Builds and mutates the JSON request bodies this suite sends. Request bodies
 * are built as a Jackson tree (not raw strings) so a scenario can set, remove
 * or type-check individual fields - including nested ones (service settings,
 * provider config, a customer object) - on top of a full example body, which
 * is what drives most negative/validation scenarios (one field removed, one
 * field given the wrong type, one extra unknown field).
 *
 * Response reading uses REST Assured's own JsonPath directly (see
 * CommonAssertionSteps) - this class is request-construction only.
 */
public final class JsonSupport {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final Pattern PLACEHOLDER = Pattern.compile("(\\\\)?\\{\\{([a-zA-Z0-9_]+)}}");

    private JsonSupport() {
    }

    public static ObjectNode newObject() {
        return MAPPER.createObjectNode();
    }

    /** Parses a JSON document (typically a feature-file docstring) after resolving {{placeholders}}. */
    public static JsonNode parse(String json) {
        try {
            return MAPPER.readTree(substitutePlaceholders(json));
        } catch (Exception e) {
            throw new IllegalArgumentException("Not valid JSON after placeholder substitution: " + e.getMessage()
                    + "\n--- resolved text ---\n" + substitutePlaceholders(json), e);
        }
    }

    /** Parses a response body as-is (no placeholder substitution - responses aren't templated). */
    public static JsonNode parseLiteral(String json) {
        try {
            return MAPPER.readTree(json);
        } catch (Exception e) {
            throw new IllegalArgumentException("Not valid JSON: " + e.getMessage() + "\n--- body ---\n" + json, e);
        }
    }

    /** The node at a dot path, or a MissingNode (node.isMissingNode() == true) if any segment along the way is absent -
     * distinguishable from an explicit JSON null (NullNode), which "should be absent" assertions rely on. */
    public static JsonNode atDotPath(JsonNode root, String dotPath) {
        JsonNode current = root;
        for (String segment : dotPath.split("\\.")) {
            if (current == null || !current.has(segment)) return MissingNode.getInstance();
            current = current.get(segment);
        }
        return current;
    }

    public static String write(JsonNode node) {
        try {
            return MAPPER.writeValueAsString(node);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /** Replaces every {{name}} with ScenarioData.get("name").toString() - fails loudly if "name" was never stored.
     * A backslash immediately before "{{" (i.e. \{{name}}) escapes it: the backslash is dropped and "{{name}}"
     * reaches the request literally, unresolved and without requiring "name" to be in ScenarioData. This is for
     * payloads that have their own, unrelated "{{...}}" template syntax - e.g. a notification messageTemplate
     * (services.feature), which uses "{{firstName}}" etc. for payment_consumers to fill in later, not for this
     * harness to resolve now. */
    public static String substitutePlaceholders(String raw) {
        if (raw == null) return null;
        Matcher matcher = PLACEHOLDER.matcher(raw);
        StringBuilder result = new StringBuilder();
        while (matcher.find()) {
            String key = matcher.group(2);
            if (matcher.group(1) != null) {
                matcher.appendReplacement(result, Matcher.quoteReplacement("{{" + key + "}}"));
                continue;
            }
            if (!ScenarioData.has(key)) {
                throw new IllegalStateException("No value stored as '" + key + "' for placeholder {{" + key
                        + "}} - check the scenario created/captured it before this step");
            }
            // Resolved through an Object local, not inline: ScenarioData.<T>get() is generic, and passing its
            // result straight into the overloaded String.valueOf(...) lets javac's target-typing bind T to
            // char[] instead of Object, which then fails at runtime with a ClassCastException on every non-char[]
            // value.
            Object value = ScenarioData.get(key);
            matcher.appendReplacement(result, Matcher.quoteReplacement(String.valueOf(value)));
        }
        matcher.appendTail(result);
        return result.toString();
    }

    /** Creates (if absent) every intermediate object along a dot path and sets the leaf to `value`. */
    public static void setPath(ObjectNode root, String dotPath, JsonNode value) {
        String[] segments = dotPath.split("\\.");
        ObjectNode current = root;
        for (int i = 0; i < segments.length - 1; i++) {
            JsonNode next = current.get(segments[i]);
            if (next == null || !next.isObject()) {
                ObjectNode created = MAPPER.createObjectNode();
                current.set(segments[i], created);
                current = created;
            } else {
                current = (ObjectNode) next;
            }
        }
        current.set(segments[segments.length - 1], value);
    }

    /** No-op if the path (or an intermediate segment) doesn't exist - "removing" an absent field is a valid precondition. */
    public static void removePath(ObjectNode root, String dotPath) {
        String[] segments = dotPath.split("\\.");
        ObjectNode current = root;
        for (int i = 0; i < segments.length - 1; i++) {
            JsonNode next = current.get(segments[i]);
            if (next == null || !next.isObject()) return;
            current = (ObjectNode) next;
        }
        current.remove(segments[segments.length - 1]);
    }

    public static JsonNode textValue(String value) {
        return JsonNodeFactory.instance.textNode(substitutePlaceholders(value));
    }

    /** Preserves the literal's own decimal places (e.g. "100.50" stays "100.50", not "100.5"). */
    public static JsonNode numberValue(String literal) {
        return JsonNodeFactory.instance.numberNode(new BigDecimal(substitutePlaceholders(literal)));
    }

    public static JsonNode booleanValue(boolean value) {
        return JsonNodeFactory.instance.booleanNode(value);
    }

    public static JsonNode nullValue() {
        return JsonNodeFactory.instance.nullNode();
    }

    public static ArrayNode emptyArray() {
        return MAPPER.createArrayNode();
    }

    /** "MPESA,AIRTEL" (or a single value with no comma) -> a JSON array of strings, trimmed, placeholders resolved. */
    public static ArrayNode arrayOfStrings(String commaSeparated) {
        ArrayNode array = MAPPER.createArrayNode();
        for (String raw : commaSeparated.split(",")) {
            String trimmed = raw.trim();
            if (!trimmed.isEmpty()) array.add(substitutePlaceholders(trimmed));
        }
        return array;
    }

    public static List<String> splitCommaList(String commaSeparated) {
        return List.of(commaSeparated.split("\\s*,\\s*"));
    }
}
