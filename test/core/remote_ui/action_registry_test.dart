import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/remote_ui/action_registry.dart';
import 'package:service_101/domains/remote_ui/models/remote_action.dart';

void main() {
  test('accepts supported command action', () {
    const action = RemoteAction(
      type: 'command',
      commandKey: 'open_offer',
      arguments: {'service_id': 'svc_1'},
    );

    expect(ActionRegistry.supports(action), isTrue);
  });

  test('rejects unsupported command action', () {
    const action = RemoteAction(
      type: 'command',
      commandKey: 'call_anything',
    );

    expect(ActionRegistry.supports(action), isFalse);
  });

  test('accepts backend-first payment command action', () {
    const action = RemoteAction(
      type: 'command',
      commandKey: 'generate_platform_pix',
      arguments: {'service_id': 'svc_2'},
    );

    expect(ActionRegistry.supports(action), isTrue);
  });
}
