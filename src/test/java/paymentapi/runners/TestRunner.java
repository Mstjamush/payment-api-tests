package paymentapi.runners;

import io.cucumber.junit.Cucumber;
import io.cucumber.junit.CucumberOptions;
import org.junit.runner.RunWith;

/**
 * Entry point for `mvn test`. The tag filter can be overridden at runtime,
 * e.g. to exclude scenarios that need a broker or a running consumer:
 *   mvn test -Dcucumber.filter.tags="not @ignore and not @requires-rabbitmq and not @requires-consumer"
 * See the README's "Running the tests" section.
 */
@RunWith(Cucumber.class)
@CucumberOptions(
        features = "src/test/resources/features",
        glue = {"paymentapi.stepdefinitions", "paymentapi.hooks"},
        plugin = {"pretty", "html:target/cucumber-html-report", "json:target/cucumber.json"},
        monochrome = true,
        tags = "not @ignore"
)
public class TestRunner {
}
