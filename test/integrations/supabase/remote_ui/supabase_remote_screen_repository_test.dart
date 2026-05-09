import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/integrations/supabase/remote_ui/supabase_remote_screen_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('reads cached remote screen from shared preferences', () async {
    SharedPreferences.setMockInitialValues({
      'remote_screen_cache:help': jsonEncode({
        'version': 1,
        'screen': 'help',
        'revision': 'cache-rev-1',
        'ttl_seconds': 300,
        'features': {
          'enabled': true,
          'kill_switch': false,
          'flags': {'help_screen_v1': true},
        },
        'layout': {'kind': 'scroll'},
        'fallback_policy': {
          'mode': 'use_cache_then_native',
          'allow_cache': true,
        },
        'components': [
          {
            'id': 'cached_title',
            'type': 'text',
            'props': {'value': 'Ajuda cacheada'},
          },
        ],
      }),
    });

    final repository = SupabaseRemoteScreenRepository();
    final loaded = await repository.readCachedScreen('help');

    expect(loaded, isNotNull);
    expect(loaded!.screen.revision, 'cache-rev-1');
    expect(loaded.screen.components.first.id, 'cached_title');
  });
}
