import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../integrations/remote_ui/default_remote_action_executor.dart';
import '../../../integrations/supabase/remote_ui/supabase_remote_screen_repository.dart';
import '../../../core/runtime/app_runtime_service.dart';
import '../../../services/api_service.dart';
import '../../../services/remote_config_service.dart';
import '../data/remote_screen_repository.dart';
import '../domain/execute_remote_action_usecase.dart';
import '../domain/load_remote_screen_usecase.dart';
import '../models/loaded_remote_screen.dart';
import '../models/remote_screen_query.dart';
import '../models/remote_screen_request.dart';

final remoteScreenRepositoryProvider = Provider<RemoteScreenRepository>(
  (ref) => SupabaseRemoteScreenRepository(),
);

final loadRemoteScreenUseCaseProvider = Provider<LoadRemoteScreenUseCase>(
  (ref) => LoadRemoteScreenUseCase(ref.watch(remoteScreenRepositoryProvider)),
);

final executeRemoteActionUseCaseProvider = Provider<ExecuteRemoteActionUseCase>(
  (ref) => ExecuteRemoteActionUseCase(DefaultRemoteActionExecutor()),
);

final remoteScreenProvider =
    FutureProvider.family<LoadedRemoteScreen?, RemoteScreenQuery>((
      ref,
      query,
    ) async {
      if (!RemoteConfigService.isRemoteUiEnabledForScreen(query.screenKey)) {
        return null;
      }

      final screenKey = query.screenKey;
      final context = query.context;
      final api = ApiService();
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      final flagSet = {
        'remote_ui': true,
        'help_screen_v1': true,
        'explore_screen_v1': true,
        'driver_home_v1': true,
        'provider_search_v1': true,
        'service_payment_v1': true,
        ...RemoteConfigService.activeFlagsSnapshot(),
      };
      final request = RemoteScreenRequest(
        screenKey: screenKey,
        appRole: api.role ?? 'guest',
        platform: defaultTargetPlatform.name,
        appVersion: const String.fromEnvironment(
          'APP_VERSION',
          defaultValue: '1.0.2+6',
        ),
        locale: locale.toLanguageTag(),
        patchVersion: AppRuntimeService.patchVersion,
        environment: AppRuntimeService.environment,
        featureSet: flagSet,
        context: context,
      );

      return ref.watch(loadRemoteScreenUseCaseProvider).execute(request);
    });
