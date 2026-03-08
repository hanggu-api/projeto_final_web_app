import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../home_state.dart';
import '../../../services/api_service.dart';

mixin HomeServiceMixin<T extends StatefulWidget> on State<T>, HomeStateMixin<T> {
  final ApiService _api = ApiService();

  void toggleServiceMode() {
    setState(() {
      isInServiceMode = !isInServiceMode;
      if (!isInServiceMode) {
        servicePromptController.clear();
        aiProfessionName = null;
        aiTaskName = null;
        serviceCandidates.clear();
      }
    });
  }

  void onServicePromptChanged(String value) {
    if (serviceAiDebounce?.isActive ?? false) serviceAiDebounce!.cancel();
    
    if (value.trim().isNotEmpty) {
      serviceAiDebounce = Timer(const Duration(milliseconds: 1000), classifyServiceAi);
    } else {
      setState(() {
        isServiceAiClassifying = false;
        aiProfessionName = null;
        serviceCandidates.clear();
      });
    }
  }

  Future<void> classifyServiceAi() async {
    final text = servicePromptController.text.trim();
    if (text.length < 4) return;

    setState(() => isServiceAiClassifying = true);
    try {
      final r = await _api.classifyServiceAi(text);

      if (r['encontrado'] == true && mounted) {
        setState(() {
          aiProfessionName = r['profissao'];
          aiServiceType = r['service_type'];

          if (r['task'] != null) {
            aiTaskName = r['task']['name'];
            aiTaskPrice = double.tryParse(r['task']['unit_price']?.toString() ?? '0');
          } else if (r['candidates'] != null && (r['candidates'] as List).isNotEmpty) {
            final best = r['candidates'][0];
            aiTaskName = best['task_name'];
            aiTaskPrice = double.tryParse(best['price']?.toString() ?? '0');
          } else {
            aiTaskName = null;
            aiTaskPrice = null;
          }
        });
        
        if (aiProfessionName != null) {
          fetchNearbyServiceCandidates();
        }
      } else if (mounted) {
        setState(() {
          aiProfessionName = null;
        });
      }
    } catch (e) {
      debugPrint('AI Error: $e');
    } finally {
      if (mounted) setState(() => isServiceAiClassifying = false);
    }
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
        const SnackBar(content: Text('Não foi possível identificar o serviço. Tente detalhar mais.')),
      );
      return;
    }

    setState(() => isCreatingService = true);

    try {
      double price = aiTaskPrice!;
      double upfront = price * 0.30;
      String desc = servicePromptController.text.trim();

      if (desc.isEmpty) {
        desc = aiTaskName ?? 'Solicitação de serviço móvel';
      } else if (aiTaskName != null) {
        desc = "$aiTaskName\n$desc";
      }

      final result = await _api.createService(
        categoryId: 1,
        description: desc,
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
        address: 'Localização Atual',
        priceEstimated: price,
        priceUpfront: upfront,
        imageKeys: [],
        videoKey: null,
        audioKeys: [],
        profession: aiProfessionName,
        professionId: null,
        locationType: 'client',
        providerId: null,
        taskId: null,
      );

      final serviceId = result['service']?['id']?.toString() ?? result['id']?.toString();

      if (serviceId != null && mounted) {
        context.push(
          '/payment/$serviceId',
          extra: {
            'serviceId': serviceId,
            'amount': upfront,
            'total': price,
            'type': 'deposit',
          },
        );
        toggleServiceMode();
        servicePromptController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao criar serviço: $e')));
      }
    } finally {
      if (mounted) setState(() => isCreatingService = false);
    }
  }

  bool get isFixedService => aiServiceType == 'fixed';
}
