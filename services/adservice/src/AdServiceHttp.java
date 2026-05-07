import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class AdServiceHttp {
  private static final String SERVICE_NAME = env("SERVICE_NAME", "adservice");
  private static final int SERVICE_PORT = Integer.parseInt(env("SERVICE_PORT", env("PORT", "9555")));
  private static final Map<String, List<Ad>> ADS = createAdsMap();

  private AdServiceHttp() {
  }

  public static void main(String[] args) throws IOException {
    HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", SERVICE_PORT), 0);
    server.createContext("/", AdServiceHttp::handle);
    server.setExecutor(null);
    server.start();
    System.out.println(SERVICE_NAME + " listening on 0.0.0.0:" + SERVICE_PORT);
  }

  static Response route(String method, String rawPath, String rawQuery) {
    if (!"GET".equals(method)) {
      return json(405, "{\"error\":\"method_not_allowed\"}");
    }

    if ("/health".equals(rawPath)) {
      return json(200, "{\"status\":\"ok\",\"service\":\"" + SERVICE_NAME + "\"}");
    }

    if ("/ready".equals(rawPath)) {
      return json(200, "{\"status\":\"ready\",\"adCount\":" + allAds().size() + "}");
    }

    if ("/".equals(rawPath)) {
      return json(200, "{\"service\":\"" + SERVICE_NAME + "\",\"adCount\":" + allAds().size()
          + ",\"protocol\":\"http\",\"sourceProtocol\":\"grpc\"}");
    }

    if ("/ads".equals(rawPath)) {
      List<String> contexts = queryValues(rawQuery, "context");
      return json(200, "{\"ads\":" + adsJson(selectAds(contexts)) + "}");
    }

    return json(404, "{\"error\":\"not_found\"}");
  }

  static List<Ad> selectAds(List<String> contexts) {
    List<Ad> selected = new ArrayList<>();

    for (String context : contexts) {
      selected.addAll(ADS.getOrDefault(context.toLowerCase(), Collections.emptyList()));
    }

    if (selected.isEmpty()) {
      List<Ad> ads = allAds();
      return ads.subList(0, Math.min(2, ads.size()));
    }

    return selected;
  }

  private static void handle(HttpExchange exchange) throws IOException {
    URI uri = exchange.getRequestURI();
    Response response = route(exchange.getRequestMethod(), uri.getPath(), uri.getRawQuery());
    byte[] body = response.body().getBytes(StandardCharsets.UTF_8);
    exchange.getResponseHeaders().set("Content-Type", "application/json");
    exchange.sendResponseHeaders(response.statusCode(), body.length);

    try (OutputStream output = exchange.getResponseBody()) {
      output.write(body);
    }
  }

  private static Response json(int statusCode, String body) {
    return new Response(statusCode, body);
  }

  private static String adsJson(List<Ad> ads) {
    StringBuilder builder = new StringBuilder("[");
    for (int i = 0; i < ads.size(); i++) {
      if (i > 0) {
        builder.append(',');
      }
      Ad ad = ads.get(i);
      builder.append("{\"redirectUrl\":\"")
          .append(escape(ad.redirectUrl()))
          .append("\",\"text\":\"")
          .append(escape(ad.text()))
          .append("\"}");
    }
    return builder.append(']').toString();
  }

  private static List<String> queryValues(String rawQuery, String key) {
    if (rawQuery == null || rawQuery.isBlank()) {
      return Collections.emptyList();
    }

    List<String> values = new ArrayList<>();
    for (String part : rawQuery.split("&")) {
      String[] pieces = part.split("=", 2);
      if (pieces.length == 2 && key.equals(pieces[0])) {
        values.add(pieces[1].replace("+", " ").toLowerCase());
      }
    }
    return values;
  }

  private static List<Ad> allAds() {
    List<Ad> all = new ArrayList<>();
    for (List<Ad> ads : ADS.values()) {
      all.addAll(ads);
    }
    return all;
  }

  private static Map<String, List<Ad>> createAdsMap() {
    Map<String, List<Ad>> ads = new LinkedHashMap<>();
    ads.put("clothing", List.of(new Ad("/product/66VCHSJNUP", "Tank top for sale. 20% off.")));
    ads.put("accessories", List.of(new Ad("/product/1YMWWN1N4O", "Watch for sale. Buy one, get second kit for free")));
    ads.put("footwear", List.of(new Ad("/product/L9ECAV7KIM", "Loafers for sale. Buy one, get second one for free")));
    ads.put("hair", List.of(new Ad("/product/2ZYFJ3GM2N", "Hairdryer for sale. 50% off.")));
    ads.put("decor", List.of(new Ad("/product/0PUK6V6EV0", "Candle holder for sale. 30% off.")));
    ads.put("kitchen", List.of(
        new Ad("/product/9SIQT8TOJO", "Bamboo glass jar for sale. 10% off."),
        new Ad("/product/6E92ZMYYFZ", "Mug for sale. Buy two, get third one for free")));
    return ads;
  }

  private static String escape(String value) {
    return value.replace("\\", "\\\\").replace("\"", "\\\"");
  }

  private static String env(String name, String fallback) {
    String value = System.getenv(name);
    return value == null || value.isBlank() ? fallback : value;
  }

  record Ad(String redirectUrl, String text) {
  }

  record Response(int statusCode, String body) {
  }
}
