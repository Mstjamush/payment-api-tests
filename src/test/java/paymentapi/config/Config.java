package paymentapi.config;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

/**
 * Reads config.properties, with environment variables (then -D system
 * properties) taking precedence - "api.base.url" is overridden by env var
 * API_BASE_URL, "platform.admin.password" by PLATFORM_ADMIN_PASSWORD, and so
 * on (dots -> underscores, upper-cased). This is what lets CI inject real
 * values without editing the committed properties file.
 */
public final class Config {

    private static final Properties PROPS = new Properties();

    static {
        try (InputStream in = Config.class.getClassLoader().getResourceAsStream("config.properties")) {
            PROPS.load(in);
        } catch (IOException | NullPointerException e) {
            throw new RuntimeException("Failed to load config.properties", e);
        }
    }

    private Config() {
    }

    public static String get(String key) {
        String fromEnv = System.getenv(toEnvVarName(key));
        if (fromEnv != null && !fromEnv.isBlank()) return fromEnv;

        String fromSystemProperty = System.getProperty(key);
        if (fromSystemProperty != null && !fromSystemProperty.isBlank()) return fromSystemProperty;

        String value = PROPS.getProperty(key);
        if (value == null) throw new IllegalStateException("No config value for '" + key + "'");
        return value;
    }

    public static String get(String key, String fallback) {
        try {
            return get(key);
        } catch (IllegalStateException e) {
            return fallback;
        }
    }

    public static int getInt(String key) {
        return Integer.parseInt(get(key).trim());
    }

    private static String toEnvVarName(String key) {
        return key.toUpperCase().replace('.', '_');
    }
}
