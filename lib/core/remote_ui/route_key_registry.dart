class RouteKeyRegistry {
  static const Map<String, String> routes = {
    'home': '/home',
    'home_explore': '/home-explore',
    'help': '/help',
    'chats': '/chats',
    'provider_home': '/provider-home',
    'client_settings': '/client-settings',
    'provider_profile': '/provider-profile',
    'service_request_mobile': '/servicos',
    'service_request_fixed': '/beauty-booking',
  };

  static bool isAllowed(String routeKey) => routes.containsKey(routeKey);

  static String? resolve(String routeKey) => routes[routeKey];
}
