package paymentapi.stepdefinitions;

import java.util.LinkedHashMap;
import java.util.Map;

import com.fasterxml.jackson.databind.node.ObjectNode;

import paymentapi.utils.JsonSupport;

/**
 * The request a scenario is building up, one "When I send a ... request"
 * call at a time. Authentication persists across every request in a scenario
 * until a step explicitly changes it (most scenarios authenticate once, then
 * make several calls as that actor); the body, headers, query parameters and
 * multipart file are one-shot and clear after each request fires, since a
 * fresh "Given the request body is..." is expected before the next call that
 * needs one.
 */
public final class RequestContext {

    public enum AuthMode { NONE, BEARER, API_KEY }

    private static final ThreadLocal<State> STATE = ThreadLocal.withInitial(State::new);

    private RequestContext() {
    }

    private static final class State {
        AuthMode authMode = AuthMode.NONE;
        String authCredential;
        ObjectNode jsonBody;
        String rawTextBody;
        final Map<String, String> queryParams = new LinkedHashMap<>();
        final Map<String, String> headers = new LinkedHashMap<>();
        String multipartFilePath;
        String multipartFileFieldName;
        String multipartFileMimeType;
        final Map<String, String> multipartFormFields = new LinkedHashMap<>();
    }

    public static void resetForNewScenario() {
        STATE.remove();
    }

    public static void resetOneShotRequestState() {
        State state = STATE.get();
        state.jsonBody = null;
        state.rawTextBody = null;
        state.queryParams.clear();
        state.headers.clear();
        state.multipartFilePath = null;
        state.multipartFileFieldName = null;
        state.multipartFileMimeType = null;
        state.multipartFormFields.clear();
    }

    // ------------------------------------------------------------------ auth

    public static void setNoAuth() {
        State state = STATE.get();
        state.authMode = AuthMode.NONE;
        state.authCredential = null;
    }

    public static void setBearerToken(String token) {
        State state = STATE.get();
        state.authMode = AuthMode.BEARER;
        state.authCredential = token;
    }

    public static void setApiKey(String key) {
        State state = STATE.get();
        state.authMode = AuthMode.API_KEY;
        state.authCredential = key;
    }

    public static AuthMode authMode() {
        return STATE.get().authMode;
    }

    public static String authCredential() {
        return STATE.get().authCredential;
    }

    // ------------------------------------------------------------------ body

    /** The ObjectNode a scenario is building, creating an empty one if this is the first mutation of this request. */
    public static ObjectNode bodyForMutation() {
        State state = STATE.get();
        if (state.jsonBody == null) state.jsonBody = JsonSupport.newObject();
        state.rawTextBody = null;
        return state.jsonBody;
    }

    public static void setJsonBody(ObjectNode body) {
        State state = STATE.get();
        state.jsonBody = body;
        state.rawTextBody = null;
    }

    public static void setNoBody() {
        State state = STATE.get();
        state.jsonBody = null;
        state.rawTextBody = null;
    }

    public static void setRawTextBody(String text) {
        State state = STATE.get();
        state.rawTextBody = text;
        state.jsonBody = null;
    }

    public static ObjectNode jsonBody() {
        return STATE.get().jsonBody;
    }

    public static String rawTextBody() {
        return STATE.get().rawTextBody;
    }

    // ------------------------------------------------------------------ query / headers

    public static void addQueryParam(String name, String value) {
        STATE.get().queryParams.put(name, value);
    }

    public static Map<String, String> queryParams() {
        return STATE.get().queryParams;
    }

    public static void addHeader(String name, String value) {
        STATE.get().headers.put(name, value);
    }

    public static Map<String, String> headers() {
        return STATE.get().headers;
    }

    // ------------------------------------------------------------------ multipart

    public static void setMultipartFile(String fieldName, String filePath, String mimeType) {
        State state = STATE.get();
        state.multipartFileFieldName = fieldName;
        state.multipartFilePath = filePath;
        state.multipartFileMimeType = mimeType;
    }

    public static void addMultipartFormField(String name, String value) {
        STATE.get().multipartFormFields.put(name, value);
    }

    public static boolean hasMultipartFile() {
        return STATE.get().multipartFilePath != null;
    }

    public static String multipartFilePath() {
        return STATE.get().multipartFilePath;
    }

    public static String multipartFileFieldName() {
        return STATE.get().multipartFileFieldName;
    }

    public static String multipartFileMimeType() {
        return STATE.get().multipartFileMimeType;
    }

    public static Map<String, String> multipartFormFields() {
        return STATE.get().multipartFormFields;
    }
}
