import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/domains/remote_ui/models/remote_action_response.dart';

void main() {
  test('parses backend-first action response', () {
    final response = RemoteActionResponse.fromJson({
      'success': true,
      'message': 'ok',
      'next_screen': '/provider-home',
      'refresh_screen': true,
      'handled': true,
      'updated_state': {'status': 'accepted'},
      'effects': [
        {'type': 'show_snackbar', 'message': 'feito'},
      ],
    });

    expect(response.success, isTrue);
    expect(response.message, 'ok');
    expect(response.nextScreen, '/provider-home');
    expect(response.refreshScreen, isTrue);
    expect(response.handled, isTrue);
    expect(response.updatedState['status'], 'accepted');
    expect(response.effects.first['type'], 'show_snackbar');
  });
}
