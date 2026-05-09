import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores typed entries and exposes active runtime flags from cache', () async {
    SharedPreferences.setMockInitialValues({
      'app_config_cache': jsonEncode({
        'configs': {
          'flag.remote_ui.enabled': true,
          'flag.remote_ui.help.enabled': true,
          'kill_switch.remote_ui.help': false,
        },
        'entries': {
          'flag.remote_ui.enabled': {
            'key': 'flag.remote_ui.enabled',
            'value': true,
            'category': 'featureFlag',
            'platform_scope': 'all',
            'is_active': true,
            'revision': 2,
          },
          'flag.remote_ui.help.enabled': {
            'key': 'flag.remote_ui.help.enabled',
            'value': true,
            'category': 'featureFlag',
            'platform_scope': 'all',
            'is_active': true,
            'revision': 4,
          },
          'kill_switch.remote_ui.help': {
            'key': 'kill_switch.remote_ui.help',
            'value': false,
            'category': 'killSwitch',
            'platform_scope': 'all',
            'is_active': true,
            'revision': 1,
          },
        },
      }),
    });

    await RemoteConfigService.init();

    expect(
      RemoteConfigService.activeFlagsSnapshot()['flag.remote_ui.help.enabled'],
      isTrue,
    );
    expect(RemoteConfigService.isRemoteUiEnabledForScreen('help'), isTrue);
  });

  test('kill switch disables remote ui screen immediately', () async {
    SharedPreferences.setMockInitialValues({
      'app_config_cache': jsonEncode({
        'configs': {
          'flag.remote_ui.enabled': true,
          'flag.remote_ui.help.enabled': true,
          'kill_switch.remote_ui.help': true,
        },
        'entries': {
          'kill_switch.remote_ui.help': {
            'key': 'kill_switch.remote_ui.help',
            'value': true,
            'category': 'killSwitch',
            'platform_scope': 'all',
            'is_active': true,
            'revision': 3,
          },
        },
      }),
    });

    await RemoteConfigService.init();

    expect(RemoteConfigService.isRemoteUiEnabledForScreen('help'), isFalse);
  });
}
