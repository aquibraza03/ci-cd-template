import java.util.List;

public final class AdServiceHttpTest {
  public static void main(String[] args) {
    healthEndpointReturnsOk();
    readyEndpointReturnsAdCount();
    categorySelectionReturnsMatchingAd();
    unknownCategoryFallsBackToDefaultAds();
    System.out.println("adservice tests passed");
  }

  private static void healthEndpointReturnsOk() {
    AdServiceHttp.Response response = AdServiceHttp.route("GET", "/health", null);
    assertEquals(200, response.statusCode(), "health status");
    assertContains(response.body(), "\"status\":\"ok\"", "health body");
  }

  private static void readyEndpointReturnsAdCount() {
    AdServiceHttp.Response response = AdServiceHttp.route("GET", "/ready", null);
    assertEquals(200, response.statusCode(), "ready status");
    assertContains(response.body(), "\"adCount\":7", "ready body");
  }

  private static void categorySelectionReturnsMatchingAd() {
    List<AdServiceHttp.Ad> ads = AdServiceHttp.selectAds(List.of("kitchen"));
    assertEquals(2, ads.size(), "kitchen ad count");
    assertContains(ads.get(0).text(), "Bamboo", "kitchen ad text");
  }

  private static void unknownCategoryFallsBackToDefaultAds() {
    List<AdServiceHttp.Ad> ads = AdServiceHttp.selectAds(List.of("unknown"));
    assertEquals(2, ads.size(), "fallback ad count");
  }

  private static void assertEquals(Object expected, Object actual, String label) {
    if (!expected.equals(actual)) {
      throw new AssertionError(label + ": expected " + expected + " but got " + actual);
    }
  }

  private static void assertContains(String value, String expected, String label) {
    if (!value.contains(expected)) {
      throw new AssertionError(label + ": expected to find " + expected + " in " + value);
    }
  }
}
