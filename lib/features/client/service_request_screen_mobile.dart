import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class ServiceRequestScreenMobile extends StatefulWidget {
  final Function(Map<String, dynamic> data)? onSwitchToFixed;
  final Map<String, dynamic>? initialData;

  const ServiceRequestScreenMobile({
    super.key,
    this.onSwitchToFixed,
    this.initialData,
  });

  @override
  State<ServiceRequestScreenMobile> createState() =>
      _ServiceRequestScreenMobileState();
}

class _ServiceRequestScreenMobileState extends State<ServiceRequestScreenMobile> {
  int _currentStep = 1;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  bool _isLoading = false;
  final _api = ApiService();
  final MapController _mapController = MapController();
  double? _latitude;
  double? _longitude;
  String? _address;
  final bool _chooseOtherAddress = false;
  bool _locationPickedByUser = false;
  final List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  Timer? _geoDebounce;
  final double _priceEstimated = 150.00;
  final List<String> _imageKeys = [];
  String? _videoKey;
  final List<String> _audioKeys = [];

  int? _aiCategoryId;
  String? _aiCategoryName;
  String? _aiProfessionName;
  double? _aiConfidence;
  int? _aiTaskId;
  String? _aiTaskName;
  double? _aiTaskPrice;
  String? _aiSuggestionMessage;
  String? _aiServiceType;
  final List<Map<String, dynamic>> _aiSuggestions = [];
  final ScrollController _descScrollController = ScrollController();
  final bool _needsDetails = false;
  bool _aiClassifying = false;
  Timer? _aiDebounce;
  final TextEditingController _professionSearchController =
      TextEditingController();
  final List<String> _allProfessions = [];
  final List<String> _filteredProfessions = [];

  // --- Real-time Providers State ---
  List<Map<String, dynamic>> _nearbyCandidates = [];
  bool _loadingCandidates = false;
  int? _expandedProviderIndex;
  int? _selectedProviderId;

  final bool _showTeach = false;
  final bool _hasAiRun = false;

  String? _selectedProfession;

  // --- Manual Search State ---
  bool _isManualSearch = false;
  String? _manualProfession;
  String? _manualService;
  
  // Loaded from API
  Map<String, List<Map<String, dynamic>>> _professionsMap = {};
  Map<String, int> _professionNameIdMap = {};
  bool _isLoadingProfessions = false;
  
  bool get _isFixed {
    final nameLower = (_aiProfessionName ?? '').toLowerCase();
    return _aiServiceType == 'at_provider' || 
           nameLower.contains('barbeiro') || 
           nameLower.contains('cabel');
  }

  @override
  void initState() {
    super.initState();
    _loadProfessions();
    
    // Ler os dados passados da Home (Input Dinâmico)
    if (widget.initialData != null && widget.initialData!['description'] != null) {
       _descriptionController.text = widget.initialData!['description'];
       // Disparar classificação da IA logo após a interface renderizar
       WidgetsBinding.instance.addPostFrameCallback((_) {
          _classifyAi();
       });
    }

    if (!kIsWeb) {
      _useMyLocation(initialLoad: true);
    }
  }

  Future<void> _loadProfessions() async {
    setState(() => _isLoadingProfessions = true);
    try {
      debugPrint('Fetching professions from API...');
      
      // Load raw professions for ID lookup
      final rawProfessions = await _api.getProfessions();
      final nameIdMap = <String, int>{};
      for (var p in rawProfessions) {
         if (p['name'] != null && p['id'] != null) {
            nameIdMap[p['name'].toString()] = int.parse(p['id'].toString());
         }
      }

      final data = await _api.getServicesMap();
      debugPrint('Professions fetched: ${data.keys.length} categories');
      if (mounted) {
        setState(() {
          _professionsMap = data;
          _professionNameIdMap = nameIdMap;
        });
      }
    } catch (e) {
      debugPrint('Error loading professions: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProfessions = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _geoDebounce?.cancel();
    _aiDebounce?.cancel();
    _descriptionController.dispose();
    _addressController.dispose();
    _professionSearchController.dispose();
    _descScrollController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitService() async {
    setState(() => _isLoading = true);
    try {
      await _api.loadToken();

      // Try to get location automatically if not set
      if (_latitude == null || _longitude == null) {
        debugPrint('⚠️ Location not set, attempting to get current location...');
        try {
          final pos = await Geolocator.getCurrentPosition();
          setState(() {
            _latitude = pos.latitude;
            _longitude = pos.longitude;
          });
          await _reverseGeocode(pos.latitude, pos.longitude);
          debugPrint('✅ Got location: $_latitude, $_longitude');
        } catch (locError) {
          debugPrint('❌ Failed to get location: $locError');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível obter sua localização. Por favor, permita o acesso ao GPS.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      if (_latitude == null ||
          _longitude == null ||
          (_addressController.text.isEmpty && _address == null)) {
        throw Exception("Localização ou endereço não definidos.");
      }

      final addrRaw = _addressController.text.isEmpty
          ? (_address ?? '')
          : _addressController.text;
      final addressSafe =
          addrRaw.length > 255 ? addrRaw.substring(0, 255) : addrRaw;

      String desc = _descriptionController.text.isEmpty
          ? ''
          : _descriptionController.text;
      if (desc.trim().length < 5) {
        desc = '${desc.trim()} - Serviço solicitado';
      }

      if (_aiTaskName != null) {
        desc = "$_aiTaskName\n$desc";
      }

      int categoryId = _aiCategoryId ?? 1;
      double price = _aiTaskPrice ?? _priceEstimated;
      double upfront = price * 0.30;

      final profName = _selectedProfession ?? _aiProfessionName;
      final profId = profName != null ? _professionNameIdMap[profName] : null;

      debugPrint('🔵 [SubmitService] AI Task Price: $_aiTaskPrice');
      debugPrint('🔵 [SubmitService] Default Estim. Price: $_priceEstimated');
      debugPrint('🔵 [SubmitService] Final Selected Price: $price');
      debugPrint('🔵 [SubmitService] Profession: $profName (ID: $profId)');

      if (price <= 0) {
        throw Exception("O valor estimado do serviço não pode ser zero. Por favor, detalhe melhor o pedido ou tente novamente.");
      }

      debugPrint('🔵 Creating service with categoryId: $categoryId, price: $price');

      final result = await _api.createService(
        categoryId: categoryId,
        description: desc,
        latitude: _latitude!,
        longitude: _longitude!,
        address: addressSafe,
        priceEstimated: price,
        priceUpfront: upfront,
        imageKeys: _imageKeys,
        videoKey: _videoKey,
        audioKeys: _audioKeys,
        profession: profName,
        professionId: profId,
        locationType: 'client', // Sempre client para Mobile/Imediato
        providerId: null, // Sem provider específico no fluxo mobile genérico
        taskId: _aiTaskId,
      );

      debugPrint('✅ Service created successfully: $result');
      _handleSuccess(result, upfront, price);
    } catch (e, stackTrace) {
      debugPrint('❌ Error creating service: $e');
      debugPrint('Stack trace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleSuccess(Map<String, dynamic> result, double upfront, double total) {
     if (!mounted) return;
    final serviceId =
        result['service']?['id']?.toString() ?? result['id']?.toString();

    debugPrint('🟢 Navigating to payment with serviceId: $serviceId, upfront: $upfront, total: $total');

    if (serviceId == null || serviceId == 'null' || serviceId.isEmpty) {
      debugPrint('❌ Invalid service ID received');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro: ID do serviço inválido. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    context.go(
      '/payment/$serviceId',
      extra: {
        'serviceId': serviceId,
        'amount': upfront,
        'total': total,
        'type': 'deposit',
      },
    );
  }

  void _tryAutoAdvanceFromStep1AfterLocationPick() {
    if (_currentStep != 1) return;
    if (_aiServiceType == 'at_provider') return; // Should not happen if correctly switched
    if (!_locationPickedByUser) return;
    if (_latitude == null) return;
    if (_descriptionController.text.trim().isEmpty && !_isManualSearch) return;
    if (_aiProfessionName == null && _selectedProfession == null && !_isManualSearch) return;
    
    // Manual Check
    if (_isManualSearch) {
       if (_manualProfession == null || _manualService == null) return;
    }
    
    _locationPickedByUser = false;
    _nextStep();
  }

  void _nextStep() async {
    if (_currentStep == 1) {
      if (!_isManualSearch && _descriptionController.text.trim().isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Descreva o problema.')));
         return;
      }

      if (_isManualSearch) {
        if (_manualProfession == null || _manualService == null) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selecione Profissão e Serviço.')));
           return;
        }
        // Force manual data into "AI" vars for compatibility
        _aiProfessionName = _manualProfession;
        _aiTaskName = _manualService;
        // Price handled in selection
      } else {
         if (_aiProfessionName == null && _selectedProfession == null) {
            if (_aiClassifying) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selecione uma profissão.')));
            return;
         }
      }

      // TRATAMENTO PARA FLUXO FIXO (AGENDADO)
      if (_aiServiceType == 'at_provider' && widget.onSwitchToFixed != null) {
        widget.onSwitchToFixed!({
          'description': _descriptionController.text,
          'profession': _aiProfessionName,
          'task_name': _aiTaskName,
          'task_id': _aiTaskId,
          'price': _aiTaskPrice,
          'category_id': _aiCategoryId,
          'service_type': _aiServiceType,
          'lat': _latitude,
          'lon': _longitude,
        });
        return;
      }

      setState(() => _currentStep++);
      return;
    }
    if (_currentStep == 2) {
       if (_latitude == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Defina o local.')));
          return;
       }
       setState(() => _currentStep++);
       return;
    }
    if (_currentStep == 3) {
      _submitService();
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() => _currentStep--);
    } else {
      context.pop();
    }
  }

  // --- Location Logic (Simplified Copy) ---
  Future<void> _useMyLocation({bool initialLoad = false}) async {
    try {
       if (!initialLoad) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Buscando GPS...')));
       }
       final pos = await Geolocator.getCurrentPosition();
       setState(() {
          _latitude = pos.latitude;
          _longitude = pos.longitude;
       });
       
       // Force move map if controller is ready, though might need checks
       try { _mapController.move(LatLng(pos.latitude, pos.longitude), 18); } catch (_) {}
       
       _reverseGeocode(pos.latitude, pos.longitude);
       if (_aiProfessionName != null) {
         _fetchNearbyCandidates();
       }
       if (!initialLoad) _tryAutoAdvanceFromStep1AfterLocationPick();
    } catch (e) {
       debugPrint('GPS Error: $e');
    }
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
     try {
        final res = await _api.get('/geo/reverse?lat=$lat&lon=$lon');
        if (mounted) {
          setState(() {
           _address = res['address'] is String ? res['address'] : 'Endereço encontrado';
           _addressController.text = _address!;
        });
        }
     } catch (_) {}
  }

  Future<void> _searchAddress(String q) async {
     // ... Implementation ...
  }
  
  // --- AI Logic ---
  void _onDescriptionChanged(String v) {
     _aiDebounce?.cancel();
     _aiDebounce = Timer(const Duration(milliseconds: 1000), _classifyAi);
  }

  Future<void> _classifyAi() async {
     if (_descriptionController.text.length < 5) return;
     setState(() => _aiClassifying = true);
     try {
        final body = {'text': _descriptionController.text};
        debugPrint('[APP-AI-DEBUG] Enviando texto para IA: "${_descriptionController.text}"');
        
        final r = await _api.post('/services/ai/classify', body);
        debugPrint('[APP-AI-DEBUG] Resposta Bruta da IA: $r');
        
        if (r['encontrado'] == true) {
           setState(() {
              _aiProfessionName = r['profissao'];
              _aiServiceType = r['service_type'];
              
              if (r['task'] != null) {
                _aiTaskId = r['task']['id'];
                _aiTaskName = r['task']['name'];
                _aiTaskPrice = double.tryParse(r['task']['unit_price']?.toString() ?? '0');
              } else if (r['candidates'] != null && (r['candidates'] as List).isNotEmpty) {
                 // Fallback: Use best candidate if explicit task is null
                 final best = r['candidates'][0];
                 _aiTaskId = best['id']; // This might be profession ID if task not present, check structure
                 _aiTaskName = best['task_name'];
                 _aiTaskPrice = double.tryParse(best['price']?.toString() ?? '0');
              } else {
                 _aiTaskId = null;
                 _aiTaskName = null;
                 _aiTaskPrice = null;
              }
           });

           // CHECK FOR SWITCH TO FIXED
           final nameLower = (_aiProfessionName ?? '').toLowerCase();
           bool isFixed = nameLower.contains('barbeiro') || nameLower.contains('cabel') || r['service_type'] == 'at_provider';
           
            // REMOVIDO: Switch automático. Agora o usuário clica em "Seguir para Agenda" no botão.
        }
     } catch (e) {
        debugPrint('AI Error: $e');
     } finally {
        if (mounted) setState(() => _aiClassifying = false);
     }
     if (_aiProfessionName != null) {
       _fetchNearbyCandidates();
     }
  }

  Future<void> _fetchNearbyCandidates() async {
    if (_aiProfessionName == null || _latitude == null || _longitude == null) return;
    setState(() => _loadingCandidates = true);
    try {
      final providers = await _api.searchProviders(
        term: _aiProfessionName,
        lat: _latitude,
        lon: _longitude,
      );
      if (mounted) {
        setState(() {
          _nearbyCandidates = providers;
          _expandedProviderIndex = null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching nearby candidates: $e');
    } finally {
      if (mounted) setState(() => _loadingCandidates = false);
    }
  }

  String _formatAddressData(Map<String, dynamic> addr) {
    return ""; // Helper
  }

  // --- Media Handlers ---
  Future<void> _handleImagesSelected(List<XFile> imgs) async {}
  Future<void> _handleVideoSelected(XFile video) async {}
  Future<void> _handleAudioSelected(PlatformFile file) async {}


  Widget _buildContent() {
    switch (_currentStep) {
      case 1:
        return _buildDescriptionStep();
      case 2:
        return _buildLocationStep();
      case 3:
        return _buildReviewStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDescriptionStep() {
    return SingleChildScrollView(
       controller: _descScrollController,
       child: Column(
          children: [
             if (!_isManualSearch) ...[
               const Text('O que você precisa?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
               const SizedBox(height: 16),
               TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  onChanged: _onDescriptionChanged,
                  enabled: !_isManualSearch, // Mantendo por segurança
                  decoration: InputDecoration(
                     hintText: 'Ex: Pneu furado na rua X...',
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                     filled: true,
                     fillColor: Colors.white,
                  ),
               ),
             ],
             
             // --- Advanced Search Toggle (Redesigned) ---
             Padding(
               padding: const EdgeInsets.symmetric(vertical: 8.0),
               child: InkWell(
                 onTap: () {
                   setState(() {
                     _isManualSearch = !_isManualSearch;
                     _aiProfessionName = null;
                     _aiTaskName = null;
                     _aiTaskPrice = null;
                   });
                 },
                 borderRadius: BorderRadius.circular(12),
                 child: AnimatedContainer(
                   duration: const Duration(milliseconds: 300),
                   width: double.infinity,
                   padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                   decoration: BoxDecoration(
                     color: _isManualSearch ? Colors.red.withValues(alpha: 0.05) : AppTheme.primaryPurple.withValues(alpha: 0.05),
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(
                       color: _isManualSearch ? Colors.red.withValues(alpha: 0.2) : AppTheme.primaryPurple.withValues(alpha: 0.2),
                     ),
                   ),
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(
                         _isManualSearch ? LucideIcons.xCircle : LucideIcons.search,
                         size: 22,
                         color: _isManualSearch ? Colors.red[700] : AppTheme.primaryPurple,
                       ),
                       const SizedBox(width: 12),
                       Text(
                         _isManualSearch ? 'Cancelar Busca Manual' : 'Busca Avançada',
                         style: TextStyle(
                           fontSize: 16,
                           fontWeight: FontWeight.bold,
                           color: _isManualSearch ? Colors.red[700] : AppTheme.primaryPurple,
                           letterSpacing: 0.5,
                         ),
                       ),
                     ],
                   ),
                 ),
               ),
             ),

             // --- Manual Search UI ---
             if (_isManualSearch) ...[
                const SizedBox(height: 16),
                Container(
                   padding: const EdgeInsets.all(16),
                   decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                   ),
                   child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         const Text('1. Qual a profissão?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                         const SizedBox(height: 8),
                         Autocomplete<String>(
                            optionsBuilder: (text) {
                               if (text.text.isEmpty) {
                                  return const Iterable<String>.empty();
                               }
                               debugPrint('Autocomplete searching for: ${text.text}');
                               debugPrint('Total professions available: ${_professionsMap.length}');
                               
                               final matches = _professionsMap.keys.where((k) => k.toLowerCase().contains(text.text.toLowerCase()));
                               debugPrint('Found matches: ${matches.length}');
                               return matches;
                            },
                            onSelected: (val) {
                               setState(() {
                                  _manualProfession = val;
                                  _manualService = null; // reset service
                               });
                            },
                            fieldViewBuilder: (ctx, tec, fn, _) {
                               return TextField(
                                  controller: tec,
                                  focusNode: fn,
                                  decoration: const InputDecoration(
                                     hintText: 'Ex: Eletricista',
                                     filled: true,
                                     fillColor: Colors.white,
                                  ),
                               );
                            },
                         ),
                         
                         if (_manualProfession != null) ...[
                            const SizedBox(height: 16),
                            const Text('2. Qual o serviço?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 8),
                            Autocomplete<Map<String, dynamic>>(
                               optionsBuilder: (text) {
                                  final services = _professionsMap[_manualProfession!] ?? [];
                                  return services.where((s) => s['name'].toString().toLowerCase().contains(text.text.toLowerCase()));
                               },
                               displayStringForOption: (opt) => opt['name'],
                               onSelected: (val) {
                                  setState(() {
                                     _manualService = val['name'];
                                     // Safe conversion to double
                                     final priceVal = val['price'];
                                     if (priceVal is num) {
                                       _aiTaskPrice = priceVal.toDouble();
                                     } else if (priceVal is String) {
                                       _aiTaskPrice = double.tryParse(priceVal) ?? 0.0;
                                     } else {
                                       _aiTaskPrice = 0.0;
                                     }
                                     
                                     _aiProfessionName = _manualProfession;
                                     _aiTaskName = _manualService;
                                     _aiTaskId = val['id']; // Fix: Capture Task ID
                                     _aiClassifying = false; // Force stop any AI loading if manual is used
                                  });
                                  _fetchNearbyCandidates();
                               },
                               fieldViewBuilder: (ctx, tec, fn, _) {
                                  return TextField(
                                     controller: tec,
                                     focusNode: fn,
                                     decoration: const InputDecoration(
                                        hintText: 'Ex: Troca de Tomada',
                                        filled: true,
                                        fillColor: Colors.white,
                                     ),
                                  );
                               },
                            ),
                         ]
                      ],
                   ),
                ),
             ],
             
             // AI Loading Indicator
             if (_aiClassifying) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Analisando seu pedido...', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
             ],

             // Result Header & Expandable Providers List
             if (_aiProfessionName != null && (_isManualSearch || !_aiClassifying)) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '$_aiProfessionName Identificado',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (_loadingCandidates)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ))
                else if (_isFixed) ...[
                   if (_nearbyCandidates.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Nenhum profissional encontrado para esta categoria nesta região.', textAlign: TextAlign.center),
                        ),
                      )
                   else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _nearbyCandidates.length,
                        itemBuilder: (ctx, idx) {
                          final p = _nearbyCandidates[idx];
                          final providerData = p['providers'] ?? p;
                          final name = providerData['commercial_name'] ?? p['full_name'] ?? 'Prestador';
                          final avatar = p['avatar_url'] ?? '';
                          final rating = double.tryParse(providerData['rating_avg']?.toString() ?? '5.0') ?? 5.0;
                          final count = providerData['rating_count'] ?? 0;
                          final distance = p['distance_km'] != null ? '${double.parse(p['distance_km'].toString()).toStringAsFixed(1)} km' : '-- km';
                          final bool isOpen = p['is_open'] == true;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.all(12),
                                  leading: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.2), width: 2),
                                    ),
                                    child: CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Colors.grey[200],
                                      backgroundImage: (avatar != null && avatar.isNotEmpty) 
                                          ? CachedNetworkImageProvider(avatar) 
                                          : null,
                                      child: (avatar == null || avatar.isEmpty) 
                                          ? const Icon(Icons.person, color: Colors.grey) 
                                          : null,
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 2),
                                      Text(
                                        _aiTaskName ?? _aiProfessionName ?? 'Serviço Identificado',
                                        style: TextStyle(
                                          color: AppTheme.primaryPurple,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.star, size: 14, color: Colors.amber),
                                          const SizedBox(width: 2),
                                          Text(
                                            '$rating ($count)',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('•', style: TextStyle(color: Colors.grey)),
                                          const SizedBox(width: 8),
                                          Text(
                                            distance,
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                        decoration: BoxDecoration(
                                          color: isOpen ? Colors.green.shade50 : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isOpen ? 'Aberto agora' : 'Indisponível agora',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isOpen ? Colors.green.shade700 : Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Divider(),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _aiTaskName ?? _aiProfessionName ?? 'Serviço Identificado',
                                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                ),
                                                const Text(
                                                  'Valor Estimado',
                                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            _aiTaskPrice != null ? 'R\$ ${_aiTaskPrice!.toStringAsFixed(2)}' : '--',
                                            style: TextStyle(
                                              fontSize: 24, 
                                              fontWeight: FontWeight.w900, 
                                              color: AppTheme.primaryPurple
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () {
                                             setState(() {
                                                _selectedProfession = _aiProfessionName;
                                                _selectedProviderId = int.tryParse(p['id'].toString());
                                             });
                                             
                                             if (widget.onSwitchToFixed != null) {
                                                widget.onSwitchToFixed!({
                                                  'description': _descriptionController.text,
                                                  'profession': _aiProfessionName,
                                                  'task_name': _aiTaskName,
                                                  'task_id': _aiTaskId,
                                                  'price': _aiTaskPrice,
                                                  'category_id': _aiCategoryId,
                                                  'service_type': _aiServiceType,
                                                  'lat': _latitude,
                                                  'lon': _longitude,
                                                  'pre_selected_provider': p,
                                                });
                                             } else {
                                                _nextStep();
                                             }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primaryPurple,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                          child: const Text('Selecionar para Agendamento', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                ] else ...[
                   // --- MODO UBER: Exibe apenas o card do serviço identificado ---
                   Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _aiTaskName ?? 'Serviço Identificado',
                                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Valor Estimado pelo Sistema',
                                        style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _aiTaskPrice != null ? 'R\$ ${_aiTaskPrice!.toStringAsFixed(2)}' : '--',
                                  style: TextStyle(
                                    fontSize: 32, 
                                    fontWeight: FontWeight.w900, 
                                    color: AppTheme.primaryPurple,
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            const Divider(height: 1),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _nextStep,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Solicitar serviço', 
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                   ),
                ],
             ],
                
                const SizedBox(height: 40),
             ],
          ),
       );
  }

  Widget _buildLocationStep() {
     return Column(
        children: [
           Text('Onde é o serviço?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
           SizedBox(height: 16),
            RawAutocomplete<Map<String, dynamic>>(
              textEditingController: _addressController,
              focusNode: _addressFocusNode,
              optionsBuilder: (TextEditingValue text) async {
                if (text.text.length < 3) return [];
                try {
                  final res = await _api.get('/geo/search?q=${text.text}');
                  if (res['results'] != null) {
                    return List<Map<String, dynamic>>.from(res['results']);
                  }
                } catch (e) {
                  debugPrint('Search error: $e');
                }
                return [];
              },
              displayStringForOption: (option) => option['display_name'] ?? '',
              onSelected: (option) {
                final lat = double.tryParse(option['lat'].toString()) ?? 0;
                final lon = double.tryParse(option['lon'].toString()) ?? 0;
                
                setState(() {
                  _latitude = lat;
                  _longitude = lon;
                  _address = option['display_name'];
                  _addressController.text = option['display_name']; // Ensure text update
                });

                _mapController.move(LatLng(lat, lon), 18);
                FocusScope.of(context).unfocus();
                
                // Trigger auto-advance check
                _tryAutoAdvanceFromStep1AfterLocationPick();
              },
              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                return TextField(
                   controller: controller,
                   focusNode: focusNode,
                   onEditingComplete: onEditingComplete,
                   decoration: InputDecoration(
                      prefixIcon: const Icon(LucideIcons.mapPin),
                      hintText: 'Endereço',
                      suffixIcon: IconButton(
                        onPressed: () {
                           _addressController.clear();
                           _useMyLocation();
                        }, 
                        icon: const Icon(Icons.my_location)
                      ),  
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                   ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    color: Colors.white,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width - 32,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            leading: const Icon(Icons.location_on, size: 20, color: Colors.grey),
                            title: Text(option['display_name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            Expanded(child: Stack(
               children: [
                 FlutterMap(
                   mapController: _mapController,
                   options: MapOptions(
                      initialCenter: LatLng(_latitude ?? -23.5, _longitude ?? -46.6),
                      initialZoom: 16.5,
                      onPositionChanged: (pos, hasGesture) {
                         if (hasGesture) {
                            _geoDebounce?.cancel();
                            _geoDebounce = Timer(const Duration(milliseconds: 800), () {
                                setState(() {
                                  _latitude = pos.center.latitude;
                                  _longitude = pos.center.longitude;
                                });
                                _reverseGeocode(pos.center.latitude, pos.center.longitude);
                                                         });
                         }
                      },
                   ),
                   children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.play101.app',
                      ),
                   ],
                 ),
                 Center(
                   child: Padding(
                     padding: const EdgeInsets.only(bottom: 40),
                     child: Icon(Icons.location_on, color: AppTheme.primaryPurple, size: 50),
                   ),
                 ),
                 Positioned(
                   right: 16,
                   bottom: 16,
                   child: Column(
                     children: [
                       FloatingActionButton.small(
                         heroTag: 'zoom_in',
                         onPressed: () {
                           final zoom = _mapController.camera.zoom + 1;
                           _mapController.move(_mapController.camera.center, zoom);
                         },
                         backgroundColor: Colors.white,
                         foregroundColor: Colors.black,
                         child: const Icon(Icons.add),
                       ),
                       const SizedBox(height: 8),
                       FloatingActionButton.small(
                         heroTag: 'zoom_out',
                         onPressed: () {
                           final zoom = _mapController.camera.zoom - 1;
                           _mapController.move(_mapController.camera.center, zoom);
                         },
                         backgroundColor: Colors.white,
                         foregroundColor: Colors.black,
                         child: const Icon(Icons.remove),
                       ),
                     ],
                   ),
                 ),
               ],
            )),
           SizedBox(height: 16),
           SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _nextStep, child: Text('Confirmar Local')))
        ],
     );
  }

   Widget _buildReviewStep() {
     final total = _aiTaskPrice ?? _priceEstimated;
     final entry = total * 0.30;
     final remaining = total * 0.70;

     return SingleChildScrollView(
       child: Column(
         children: [
            const Text('Resumo do Pedido', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            Container(
               width: double.infinity,
               padding: const EdgeInsets.all(20),
               decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                     BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                     )
                  ]
               ),
               child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Row(
                        children: [
                           Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: AppTheme.primaryPurple.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: Icon(LucideIcons.hammer, color: AppTheme.primaryPurple),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                              child: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                    Text(_aiTaskName ?? 'Serviço Personalizado', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    Text(_aiProfessionName ?? 'Profissional', style: TextStyle(color: Colors.grey.shade600)),
                                 ],
                              ),
                           )
                        ],
                     ),
                     const Divider(height: 32),
                     const Text('Detalhes do Pagamento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                     const SizedBox(height: 16),
                     
                     // Helper Row logic inlined for simplicity
                     Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Total do Serviço'),
                        Text('R\$ ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                     ]),
                     const SizedBox(height: 8),
                     Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Pagar Agora (30%)', style: TextStyle(color: Colors.green.shade700)),
                        Text('R\$ ${entry.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                     ]),
                     const SizedBox(height: 8),
                     Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Pagar ao Final (70%)', style: TextStyle(color: Colors.orange.shade800)),
                        Text('R\$ ${remaining.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                     ]),
                  ],
               ),
            ),

            const SizedBox(height: 24),
            Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
               child: Row(
                  children: [
                     const Icon(Icons.info_outline, color: Colors.blue),
                     const SizedBox(width: 12),
                     Expanded(child: Text(
                        'A entrada garante a reserva do profissional. O restante é pago apenas após a conclusão.',
                        style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                     )),
                  ],
               ),
            ),

            const SizedBox(height: 32),
            SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
               onPressed: _submitService,
               style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryOrange, 
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
               ),
               child: Text('Pagar Entrada R\$ ${entry.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            )),

            const SizedBox(height: 40),
            Column(
               children: [
                   Text('Como funciona?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                   const SizedBox(height: 24),
                   Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Expanded(child: Column(children: [
                             CircleAvatar(backgroundColor: Colors.green.withValues(alpha: 0.1), child: Icon(LucideIcons.banknote, color: Colors.green, size: 20)),
                             const SizedBox(height: 8),
                             const Text('1. Entrada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                             const Text('Pague 30% para\nreservar', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey))
                         ])),
                         Padding(padding: const EdgeInsets.only(top: 15), child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey.shade300)),
                         Expanded(child: Column(children: [
                             CircleAvatar(backgroundColor: Colors.blue.withValues(alpha: 0.1), child: Icon(LucideIcons.user, color: Colors.blue, size: 20)),
                             const SizedBox(height: 8),
                             const Text('2. Serviço', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                             const Text('Profissional vai\naté você', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey))
                         ])),
                         Padding(padding: const EdgeInsets.only(top: 15), child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey.shade300)),
                         Expanded(child: Column(children: [
                             CircleAvatar(backgroundColor: Colors.orange.withValues(alpha: 0.1), child: Icon(LucideIcons.checkCircle, color: Colors.orange, size: 20)),
                             const SizedBox(height: 8),
                             const Text('3. Final', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                             const Text('Pague 70% ao\nconcluir', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey))
                         ])),
                      ],
                   )
               ],
            ),
            const SizedBox(height: 32),
          ],
        )
     );
   }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Solicitar Serviço',
          style: TextStyle(
            color: AppTheme.darkBlueText,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.primaryYellow,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
          onPressed: _prevStep,
        ),
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: _buildContent()),
      ),
    );
  }
}
