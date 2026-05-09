import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/domains/remote_ui/models/remote_screen_request.dart';

void main() {
  test('serializes runtime context for segmented remote ui requests', () {
    const request = RemoteScreenRequest(
      screenKey: 'help',
      appRole: 'guest',
      platform: 'android',
      appVersion: '1.0.2+6',
      locale: 'pt-BR',
      patchVersion: '12',
      environment: 'production',
      featureSet: {'flag.remote_ui.help.enabled': true},
      context: {'service_id': 'svc_1'},
    );

    final json = request.toJson();

    expect(json['screen_key'], 'help');
    expect(json['patch_version'], '12');
    expect(json['environment'], 'production');
    expect(
      (json['feature_set'] as Map<String, bool>)['flag.remote_ui.help.enabled'],
      isTrue,
    );
    expect(
      (json['context'] as Map<String, dynamic>)['service_id'],
      'svc_1',
    );
  });
}
