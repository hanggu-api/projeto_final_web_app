import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../home_state.dart';
import '../../../core/utils/fixed_schedule_gate.dart';
import '../../../services/api_service.dart';

mixin HomeServiceMixin<T extends StatefulWidget>
    on State<T>, HomeStateMixin<T> {
  final ApiService _api = ApiService();

  void toggleServiceMode() {
    setState(() {
      isInServiceMode = !isInServiceMode;
      if (!isInServiceMode) {
        servicePromptController.clear();
        aiProfessionName = null;
        aiTaskId = null;
        aiTaskName = null;
        aiTaskPrice = null;
        aiServiceType = null;
        aiLogId = null;
        serviceCandidates.clear();
      }
    });
  }

  void onServicePromptChanged(String value) {
    if (serviceAiDebounce?.isActive ?? false) serviceAiDebounce!.cancel();

    if (value.trim().isNotEmpty) {
      serviceAiDebounce = Timer(
        const Duration(milliseconds: 1000),
        classifyServiceAi,
      );
    } else {
      setState(() {
        isServiceAiClassifying = false;
        aiProfessionName = null;
        serviceCandidates.clear();
      });
    }
  }

  Future<void> classifyServiceAi() async {
    // IA removida.
    if (!mounted) return;
    setState(() {
      isServiceAiClassifying = false;
      aiLogId = null;
      aiProfessionName = null;
      aiTaskId = null;
      aiTaskName = null;
      aiTaskPrice = null;
      serviceCandidates.clear();
    });
  }

  Future<void> fetchNearbyServiceCandidates() async {
    if (aiProfessionName == null) return;

    setState(() => isLoadingServiceCandidates = true);
    try {
      final providers = await _api.searchProviders(
        term: aiProfessionName,
        lat: currentPosition.latitude,
        lon: currentPosition.longitude,
      );
      if (mounted) {
        setState(() {
          serviceCandidates = providers;
        });
      }
    } catch (e) {
      debugPrint('Error fetching nearby candidates: $e');
    } finally {
      if (mounted) setState(() => isLoadingServiceCandidates = false);
    }
  }

  Future<void> createImmediateService() async {
    if (aiProfessionName == null || aiTaskPrice == null || aiTaskPrice! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível identificar o serviço. Tente detalhar mais.',
          ),
        ),
      );
      return;
    }

    setState(() => isCreatingService = true);

    try {
      double price = aiTaskPrice!;
      double rate = isFixedService ? 0.05 : 0.30;
      double upfront = price * rate;
      double onSite = price - upfront;
      String desc = servicePromptController.text.trim();

      if (desc.isEmpty) {
        desc = aiTaskName ?? 'Solicitação de serviço móvel';
      } else if (aiTaskName != null) {
        desc = "$aiTaskName\n$desc";
      }
      final resolvedProfessionId = await _api.resolveProfessionIdForServiceCreation(
        professionId: null,
        taskId: int.tryParse(aiTaskId ?? ''),
        professionName: aiProfessionName,
      );

      final result = await _api.createService(
        categoryId: 1,
        description: desc,
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
        address: 'Localização Atual',
        priceEstimated: price,
        priceUpfront: upfront,
        feeAdminRate: rate,
        feeAdminAmount: upfront,
        amountPayableOnSite: onSite,
        imageKeys: [],
        videoKey: null,
        audioKeys: [],
        profession: aiProfessionName,
        professionId: resolvedProfessionId,
        locationType: 'client',
        providerId: null,
        taskId: aiTaskId,
      );

      final serviceId =
          result['service']?['id']?.toString() ?? result['id']?.toString();

      // IA removida: sem feedback/treinamento.

      if (serviceId != null && mounted) {
        context.push(
          '/payment/$serviceId',
          extra: {
            'serviceId': serviceId,
            'amount': upfront,
            'total': price,
            'type': 'deposit',
            'entityType': isFixedService
                ? 'service_fixed'
                : 'service_mobile',
            'isFixed': isFixedService,
          },
        );
        toggleServiceMode();
        servicePromptController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao criar serviço: $e')));
      }
    } finally {
      if (mounted) setState(() => isCreatingService = false);
    }
  }

  @override
  bool get isFixedService => isCanonicalFixedServiceRecord(<String, dynamic>{
    'service_type': aiServiceType,
    'profession_name': aiProfessionName,
    'task_name': aiTaskName,
  });
}
