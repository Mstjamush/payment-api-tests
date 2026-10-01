package paymentapi.utils;

import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/** Keeps repeated test runs from colliding on unique columns (merchant_code,
 * payer_code, service_code, username, email, merchant_payment_id...). */
public final class RandomData {

    private RandomData() {
    }

    /** 8 lower-case hex characters - safe inside codes, usernames and emails alike. */
    public static String uniqueSuffix() {
        return UUID.randomUUID().toString().replace("-", "").substring(0, 8).toLowerCase();
    }

    public static String uniqueMerchantCode() {
        return "QA_MERCH_" + uniqueSuffix().toUpperCase();
    }

    public static String uniqueServiceCode() {
        return "qa-service-" + uniqueSuffix();
    }

    public static String uniquePayerCode() {
        return "QA_PAYER_" + uniqueSuffix().toUpperCase();
    }

    public static String uniqueUsername(String prefix) {
        return prefix + "." + uniqueSuffix();
    }

    public static String uniqueEmail(String localPartPrefix) {
        return localPartPrefix + "+" + uniqueSuffix() + "@example.com";
    }

    public static String uniqueMerchantPaymentId() {
        return "QA-PAY-" + uniqueSuffix().toUpperCase();
    }

    public static String uniqueInvoiceNumber() {
        return "QA-INV-" + uniqueSuffix().toUpperCase();
    }

    /** A syntactically valid Kenyan-looking MSISDN (254 + 9 digits). */
    public static String uniqueMsisdn() {
        long suffix = Math.abs(UUID.randomUUID().getLeastSignificantBits()) % 1_000_000_00L;
        return String.format("25471%07d", suffix);
    }

    /** Exactly `length` random lowercase letters - for boundary-length tests (e.g. a username at its minimum
     * length) where RandomData's usual 8-char-suffixed helpers would be too long, but a hardcoded literal would
     * collide with a leftover row from an earlier run against the same database. */
    public static String randomAlpha(int length) {
        StringBuilder result = new StringBuilder(length);
        ThreadLocalRandom random = ThreadLocalRandom.current();
        for (int i = 0; i < length; i++) {
            result.append((char) ('a' + random.nextInt(26)));
        }
        return result.toString();
    }

    public static String randomAmount(int minor) {
        int whole = 100 + ThreadLocalRandom.current().nextInt(9900);
        return whole + "." + String.format("%02d", minor % 100);
    }
}
