import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/remote_config_service.dart';
import '../runtime/app_runtime_service.dart';
import '../../domains/remote_ui/models/loaded_remote_screen.dart';
import '../../domains/remote_ui/models/remote_screen_query.dart';
import '../../domains/remote_ui/presentation/remote_screen_providers.dart';
import 'remote_component_renderer.dart';

class RemoteScreenBody extends ConsumerWidget {
  const RemoteScreenBody({
    super.key,
    required this.screenKey,
    required this.fallbackBuilder,
    this.padding = const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    this.context = const <String, dynamic>{},
  });

  final String screenKey;
  final WidgetBuilder fallbackBuilder;
  final EdgeInsets padding;
  final Map<String, dynamic> context;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!RemoteConfigService.isRemoteUiEnabledForScreen(screenKey)) {
      AppRuntimeService.instance.recordRemoteScreenSource(
        screenKey,
        'local',
        revision: 'flag-disabled',
      );
      return fallbackBuilder(context);
    }

    final asyncScreen = ref.watch(
      remoteScreenProvider(
        RemoteScreenQuery(screenKey: screenKey, context: this.context),
      ),
    );
    final renderer = RemoteComponentRenderer(screenKey: screenKey);

    return asyncScreen.when(
      data: (loaded) {
        if (loaded == null || !loaded.screen.isEnabled) {
          AppRuntimeService.instance.recordRemoteScreenSource(
            screenKey,
            'local',
            revision: loaded?.screen.revision ?? 'native-fallback',
          );
          return fallbackBuilder(context);
        }

        final sourceLabel = loaded.source == RemoteScreenSource.cache
            ? 'cache'
            : 'remote';
        AppRuntimeService.instance.recordRemoteScreenSource(
          screenKey,
          sourceLabel,
          revision: loaded.screen.revision,
        );
        debugPrint(
          '✅ [RemoteUI] Rendering $screenKey from $sourceLabel rev=${loaded.screen.revision}',
        );

        return ListView(
          padding: padding,
          children: loaded.screen.components
              .map((component) => renderer.render(component, context, ref))
              .toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) {
        AppRuntimeService.instance.recordRemoteScreenSource(
          screenKey,
          'local',
          revision: 'error-fallback',
        );
        AppRuntimeService.instance.logConfigFailure(
          'remote_ui:$screenKey',
          error,
          stackTrace: stackTrace,
        );
        debugPrint('⚠️ [RemoteUI] Falling back to native $screenKey: $error');
        return fallbackBuilder(context);
      },
    );
  }
}
