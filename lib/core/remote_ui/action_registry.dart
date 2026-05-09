import '../../domains/remote_ui/models/remote_action.dart';
import 'command_registry.dart';
import 'link_key_registry.dart';
import 'route_key_registry.dart';

class ActionRegistry {
  static const Set<String> supportedTypes = {
    'navigate_internal',
    'open_external_url',
    'show_snackbar',
    'open_chat',
    'open_help',
    'open_profile',
    'trigger_native_flow',
    'refresh_screen',
    'command',
  };

  static bool supports(RemoteAction action) {
    if (!supportedTypes.contains(action.type)) return false;

    switch (action.type) {
      case 'navigate_internal':
        return action.routeKey != null &&
            RouteKeyRegistry.isAllowed(action.routeKey!);
      case 'open_external_url':
        return action.linkKey != null &&
            LinkKeyRegistry.isAllowed(action.linkKey!);
      case 'show_snackbar':
        return (action.message ?? '').isNotEmpty;
      case 'open_chat':
      case 'open_help':
      case 'open_profile':
      case 'refresh_screen':
        return true;
      case 'trigger_native_flow':
        return (action.nativeFlowKey ?? '').isNotEmpty;
      case 'command':
        return action.commandKey != null &&
            CommandRegistry.isAllowed(action.commandKey!);
      default:
        return false;
    }
  }
}
