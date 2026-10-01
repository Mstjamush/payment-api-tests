package paymentapi.utils;

import java.util.function.BooleanSupplier;
import java.util.function.Supplier;

import org.jboss.logging.Logger;

/**
 * Polls for something that happens asynchronously once a message is queued:
 * payment_api's own background publish task (needs only RabbitMQ reachable -
 * @requires-rabbitmq scenarios), or a row payment_consumers creates after
 * reading the queue (@requires-consumer scenarios). Fails with a message that
 * says exactly what was expected and for how long, which is what a run
 * against a partial stack will show.
 */
public final class Waiter {

    private static final Logger LOG = Logger.getLogger("paymentapi.wait");

    private Waiter() {
    }

    public static void until(String whatFor, int timeoutSeconds, long pollIntervalMs, BooleanSupplier predicate) {
        long deadline = System.currentTimeMillis() + timeoutSeconds * 1000L;
        Exception lastError = null;
        int attempts = 0;
        while (System.currentTimeMillis() < deadline) {
            attempts++;
            try {
                if (predicate.getAsBoolean()) {
                    LOG.debugf("wait.satisfied what=%s attempts=%d", whatFor, attempts);
                    return;
                }
                lastError = null;
            } catch (Exception e) {
                lastError = e;
            }
            sleep(pollIntervalMs);
        }
        throw new AssertionError("Timed out after " + timeoutSeconds + "s waiting for: " + whatFor
                + " (" + attempts + " attempt(s)). Is the required part of the stack running? See the README's"
                + " \"Running against a partial stack\" section."
                + (lastError != null ? " Last error: " + lastError : ""));
    }

    public static <T> T untilNonNull(String whatFor, int timeoutSeconds, long pollIntervalMs, Supplier<T> supplier) {
        Object[] holder = new Object[1];
        until(whatFor, timeoutSeconds, pollIntervalMs, () -> {
            T value = supplier.get();
            holder[0] = value;
            return value != null;
        });
        @SuppressWarnings("unchecked")
        T result = (T) holder[0];
        return result;
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException(e);
        }
    }
}
