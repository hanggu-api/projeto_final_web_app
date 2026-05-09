import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/runtime/app_runtime_service.dart';
import '../../core/utils/navigation_helper.dart';
import '../../core/remote_ui/link_key_registry.dart';
import '../../core/remote_ui/navigation_action_resolver.dart';
import '../../core/remote_ui/command_registry.dart';
import '../../domains/remote_ui/domain/remote_action_executor.dart';
import '../../domains/remote_ui/models/remote_action.dart';
import '../../domains/remote_ui/models/remote_action_request.dart';
import '../../domains/remote_ui/models/remote_action_response.dart';
import '../../features/provider/widgets/service_offer_modal.dart';
import '../supabase/remote_ui/supabase_remote_action_api.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../services/provider_keepalive_service.dart';

class DefaultRemoteActionExecutor implements RemoteActionExecutor {
  DefaultRemoteActionExecutor({
    NavigationActionResolver? navigationResolver,
    SupabaseRemoteActionApi? remoteActionApi,
  }) : _navigationResolver = navigationResolver ?? NavigationActionResolver(),
       _remoteActionApi = remoteActionApi ?? SupabaseRemoteActionApi();

  final NavigationActionResolver _navigationResolver;
  final SupabaseRemoteActionApi _remoteActionApi;

  @override
  Future<void> execute(RemoteAction action, BuildContext context) async {
    switch (action.type) {
      case 'navigate_internal':
        final routeKey = action.routeKey;
        if (routeKey == null) return;
        await _navigationResolver.navigateInternal(context, routeKey: routeKey);
        return;
      case 'open_external_url':
        final linkKey = action.linkKey;
        if (linkKey == null) return;
        final uri = LinkKeyRegistry.resolve(linkKey);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      case 'show_snackbar':
        final message = action.message;
        if (message == null || message.isEmpty) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      case 'open_chat':
        await context.push('/chats');
        return;
      case 'open_help':
        await context.push('/help');
        return;
      case 'open_profile':
        await context.push('/provider-profile');
        return;
      case 'trigger_native_flow':
        await _handleNativeFlow(action, context);
        return;
      case 'refresh_screen':
        if (context.mounted) {
          (context as Element).markNeedsBuild();
        }
        return;
      case 'command':
        await _executeCommand(action, context);
        return;
      default:
        return;
    }
  }

  Future<void> _handleNativeFlow(
    RemoteAction action,
    BuildContext context,
  ) async {
    switch (action.nativeFlowKey) {
      case 'service_request_mobile':
        await context.push('/servicos');
        return;
      case 'service_request_fixed':
        await context.push('/beauty-booking');
        return;
      default:
        return;
    }
  }

  Future<void> _executeCommand(
    RemoteAction action,
    BuildContext context,
  ) async {
    final commandKey = action.commandKey;
    if (commandKey == null || !CommandRegistry.isAllowed(commandKey)) {
      AppRuntimeService.instance.logConfigFailure(
        'remote_command:unsupported',
        StateError('Command not allowed: ${action.commandKey}'),
      );
      return;
    }

    AppRuntimeService.instance.recordRemoteScreenSource(
      'command:$commandKey',
      'remote',
      revision: action.arguments['revision']?.toString(),
      logAnalytics: false,
    );
    AnalyticsService().logEvent(
      'REMOTE_COMMAND_EXECUTED',
      details: {
        'command_key': commandKey,
        'screen_key': action.arguments['screen_key'],
        'component_id': action.arguments['component_id'],
        'service_id': action.arguments['service_id'],
        'revision': action.arguments['revision'],
        'store_version': AppRuntimeService.storeVersion,
        'patch_version': AppRuntimeService.patchVersion,
      },
    );

    final backendResponse = await _remoteActionApi.postAction(
      RemoteActionRequest(
        actionType: action.type,
        commandKey: commandKey,
        screenKey:
            _requiredString(action.arguments, 'screen_key') ?? 'unknown_screen',
        componentId:
            _requiredString(action.arguments, 'component_id') ??
            'unknown_component',
        arguments: action.arguments,
        entityIds: {
          if (_requiredString(action.arguments, 'service_id') != null)
            'service_id': _requiredString(action.arguments, 'service_id'),
          if (_requiredString(action.arguments, 'trip_id') != null)
            'trip_id': _requiredString(action.arguments, 'trip_id'),
        },
      ),
    );

    if (backendResponse != null) {
      await _applyBackendResponse(backendResponse, context);
      if (backendResponse.handled) {
        return;
      }
    }

    switch (commandKey) {
      case 'accept_ride':
        await _acceptRide(action, context);
        return;
      case 'reject_ride':
        await _rejectRide(action, context);
        return;
      case 'open_offer':
        await _openOffer(action, context);
        return;
      case 'open_support':
        await _openSupport(context);
        return;
      case 'start_navigation':
        await _startNavigation(action, context);
        return;
      case 'refresh_home':
        if (context.mounted) {
          (context as Element).markNeedsBuild();
        }
        return;
      case 'toggle_dispatch_availability':
        await _toggleDispatchAvailability(action, context);
        return;
      case 'open_provider_home':
        await context.push('/provider-home');
        return;
      case 'open_active_service':
        await _openActiveService(action, context);
        return;
      case 'show_command_feedback':
        final message = action.message ?? 'Comando executado.';
        _showSnack(context, message);
        return;
    }
  }

  Future<void> _applyBackendResponse(
    RemoteActionResponse response,
    BuildContext context,
  ) async {
    if ((response.message ?? '').isNotEmpty) {
      _showSnack(context, response.message!);
    }

    for (final effect in response.effects) {
      final type = (effect['type'] ?? '').toString().trim();
      switch (type) {
        case 'show_snackbar':
          final message = (effect['message'] ?? '').toString().trim();
          if (message.isNotEmpty) _showSnack(context, message);
          break;
        case 'navigate_internal':
          final routeKey = (effect['route_key'] ?? '').toString().trim();
          if (routeKey.isNotEmpty) {
            await _navigationResolver.navigateInternal(
              context,
              routeKey: routeKey,
            );
          }
          break;
        case 'open_external_url':
          final linkKey = (effect['link_key'] ?? '').toString().trim();
          if (linkKey.isNotEmpty) {
            final uri = LinkKeyRegistry.resolve(linkKey);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
          break;
        case 'refresh_screen':
          if (context.mounted) {
            (context as Element).markNeedsBuild();
          }
          break;
      }
    }

    if ((response.nextScreen ?? '').isNotEmpty && context.mounted) {
      await context.push(response.nextScreen!);
    } else if (response.refreshScreen && context.mounted) {
      (context as Element).markNeedsBuild();
    }
  }

  Future<void> _acceptRide(RemoteAction action, BuildContext context) async {
    final serviceId = _requiredString(action.arguments, 'service_id');
    if (serviceId == null) {
      _rejectCommand(context, 'service_id ausente para accept_ride', action);
      return;
    }
    try {
      await ApiService().dispatch.acceptService(serviceId);
      _showSnack(context, 'Serviço aceito com sucesso!');
      if (context.mounted) {
        context.go('/provider-active/$serviceId');
      }
    } catch (error, stackTrace) {
      AppRuntimeService.instance.logConfigFailure(
        'remote_command:accept_ride',
        error,
        stackTrace: stackTrace,
      );
      _showSnack(context, 'Não foi possível aceitar a corrida.');
    }
  }

  Future<void> _rejectRide(RemoteAction action, BuildContext context) async {
    final serviceId = _requiredString(action.arguments, 'service_id');
    if (serviceId == null) {
      _rejectCommand(context, 'service_id ausente para reject_ride', action);
      return;
    }
    try {
      await ApiService().dispatch.rejectService(serviceId);
      _showSnack(context, 'Corrida recusada.');
    } catch (error, stackTrace) {
      AppRuntimeService.instance.logConfigFailure(
        'remote_command:reject_ride',
        error,
        stackTrace: stackTrace,
      );
      _showSnack(context, 'Não foi possível recusar a corrida.');
    }
  }

  Future<void> _openOffer(RemoteAction action, BuildContext context) async {
    final serviceId = _requiredString(action.arguments, 'service_id');
    if (serviceId == null) {
      _rejectCommand(context, 'service_id ausente para open_offer', action);
      return;
    }
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceOfferModal(serviceId: serviceId),
    );
  }

  Future<void> _openSupport(BuildContext context) async {
    final uri =
        LinkKeyRegistry.resolve('support_whatsapp') ??
        LinkKeyRegistry.resolve('support_phone');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _startNavigation(
    RemoteAction action,
    BuildContext context,
  ) async {
    final latitude = _readDouble(action.arguments['latitude']);
    final longitude = _readDouble(action.arguments['longitude']);
    if (latitude == null || longitude == null) {
      _rejectCommand(
        context,
        'latitude/longitude ausentes para start_navigation',
        action,
      );
      return;
    }
    await NavigationHelper.openNavigation(
      latitude: latitude,
      longitude: longitude,
      label: _requiredString(action.arguments, 'label'),
    );
  }

  Future<void> _toggleDispatchAvailability(
    RemoteAction action,
    BuildContext context,
  ) async {
    final online = _readBool(action.arguments['online']);
    final api = ApiService();
    final userId = api.userId;
    if (userId == null || userId.trim().isEmpty) {
      _rejectCommand(
        context,
        'Usuário não carregado para disponibilidade',
        action,
      );
      return;
    }

    try {
      await ProviderKeepaliveService.persistKeepaliveContext(
        onlineForDispatch: online,
        userId: userId,
        userUid: Supabase.instance.client.auth.currentUser?.id,
        isFixedLocation: api.isFixedLocation,
      );
      if (online) {
        await ProviderKeepaliveService.startBackgroundService();
      } else {
        await ProviderKeepaliveService.clearKeepaliveContext();
      }
      _showSnack(
        context,
        online ? 'Disponibilidade ativada.' : 'Disponibilidade desativada.',
      );
    } catch (error, stackTrace) {
      AppRuntimeService.instance.logConfigFailure(
        'remote_command:toggle_dispatch_availability',
        error,
        stackTrace: stackTrace,
      );
      _showSnack(context, 'Não foi possível atualizar a disponibilidade.');
    }
  }

  Future<void> _openActiveService(
    RemoteAction action,
    BuildContext context,
  ) async {
    final serviceId = _requiredString(action.arguments, 'service_id');
    if (serviceId == null) {
      _rejectCommand(
        context,
        'service_id ausente para open_active_service',
        action,
      );
      return;
    }
    if (context.mounted) {
      context.go('/provider-active/$serviceId');
    }
  }

  void _rejectCommand(
    BuildContext context,
    String reason,
    RemoteAction action,
  ) {
    AppRuntimeService.instance.logConfigFailure(
      'remote_command:${action.commandKey}',
      StateError(reason),
    );
    _showSnack(context, 'Comando remoto inválido.');
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _requiredString(Map<String, dynamic> args, String key) {
    final value = args[key]?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  double? _readDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  bool _readBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final value = raw?.toString().trim().toLowerCase();
    return value == 'true' || value == '1';
  }
}
