import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'route_key_registry.dart';

class NavigationActionResolver {
  Future<void> navigateInternal(
    BuildContext context, {
    required String routeKey,
  }) async {
    final route = RouteKeyRegistry.resolve(routeKey);
    if (route == null) return;
    context.push(route);
  }
}
