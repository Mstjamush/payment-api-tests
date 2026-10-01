package paymentapi.hooks;

import io.cucumber.java.After;
import io.cucumber.java.Before;
import io.cucumber.java.Scenario;
import org.jboss.logging.Logger;

import paymentapi.stepdefinitions.RequestContext;
import paymentapi.stepdefinitions.ResponseContext;
import paymentapi.stepdefinitions.ScenarioData;

public class Hooks {

    private static final Logger LOG = Logger.getLogger("paymentapi.scenario");

    private long startedAtMs;

    @Before
    public void beforeScenario(Scenario scenario) {
        ResponseContext.clear();
        ScenarioData.clear();
        RequestContext.resetForNewScenario();
        startedAtMs = System.currentTimeMillis();
        LOG.infof("--- Starting: %s [%s] ---", scenario.getName(), String.join(" ", scenario.getSourceTagNames()));
    }

    @After
    public void afterScenario(Scenario scenario) {
        long elapsedMs = System.currentTimeMillis() - startedAtMs;
        LOG.infof("--- Finished: %s -> %s (%d ms) ---", scenario.getName(), scenario.getStatus(), elapsedMs);
        if (scenario.isFailed()) {
            try {
                LOG.errorf("Last response for failed scenario '%s': %s", scenario.getName(),
                        ResponseContext.get().asString());
            } catch (IllegalStateException ignored) {
                // no HTTP call was made before the failure - nothing extra to log
            }
        }
    }
}
