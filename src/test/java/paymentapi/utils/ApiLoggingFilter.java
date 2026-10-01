package paymentapi.utils;

import io.restassured.filter.Filter;
import io.restassured.filter.FilterContext;
import io.restassured.response.Response;
import io.restassured.specification.FilterableRequestSpecification;
import io.restassured.specification.FilterableResponseSpecification;
import org.jboss.logging.Logger;

/**
 * Logs every request/response that goes through RestAssured - registered once
 * globally (see HttpLogging.install()). One INFO line per call (method, URI,
 * status, duration); bodies only at DEBUG, since request bodies can contain
 * passwords and API keys.
 */
public class ApiLoggingFilter implements Filter {

    private static final Logger LOG = Logger.getLogger("paymentapi.http");

    @Override
    public Response filter(FilterableRequestSpecification requestSpec,
                            FilterableResponseSpecification responseSpec,
                            FilterContext ctx) {
        String method = requestSpec.getMethod();
        String uri = requestSpec.getURI();

        if (LOG.isDebugEnabled() && requestSpec.getBody() != null) {
            LOG.debugf(">> %s %s body: %s", method, uri, requestSpec.getBody());
        }

        long startedAt = System.currentTimeMillis();
        Response response = ctx.next(requestSpec, responseSpec);
        long tookMs = System.currentTimeMillis() - startedAt;

        LOG.infof("%s %s -> %d (%d ms)", method, uri, response.getStatusCode(), tookMs);
        if (LOG.isDebugEnabled()) {
            LOG.debugf("<< %d body: %s", response.getStatusCode(), response.getBody().asString());
        }

        return response;
    }
}
