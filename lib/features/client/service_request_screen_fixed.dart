import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class ServiceRequestScreenFixed extends StatefulWidget {
  final int? initialProviderId;
  final Map<String, dynamic>? initialService;
  final Map<String, dynamic>? initialProvider;
  final Map<String, dynamic>? initialData; // DADOS VINDOS DA IA (MÓVEL -> FIXO)

  const ServiceRequestScreenFixed({
    super.key,
    this.initialProviderId,
    this.initialService,
    this.initialProvider,
    this.initialData,
    this.onBack,
  });

  final VoidCallback? onBack;

  @override
  State<ServiceRequestScreenFixed> createState() =>
      _ServiceRequestScreenFixedState();
}

class _ServiceRequestScreenFixedState extends State<ServiceRequestScreenFixed> {
  int _currentStep = 1;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  bool _isLoading = false;
  final _api = ApiService();
  double? _latitude;
  double? _longitude;
  String? _address;
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
  final GlobalKey _scheduleKey = GlobalKey();
  int? _selectedProviderId;
  final bool _needsDetails = false;
  final bool _aiClassifying = false;
  Timer? _aiDebounce;
  Position? _userPosition;
  final TextEditingController _professionSearchController =
      TextEditingController();
  final List<String> _allProfessions = [];
  final List<String> _filteredProfessions = [];
  Map<String, dynamic>? _selectedTimeSlotData;

  final Set<dynamic> _fetchedAddresses = {};

  final bool _showTeach = false;
  final bool _hasAiRun = false;

  String? _selectedProfession;
  Map<String, dynamic>? _selectedService;
  DateTime? _selectedDate;
  String? _selectedTimeSlot;

  List<Map<String, dynamic>> _realSlots = [];
  bool _loadingSlots = false;
  List<Map<String, dynamic>> _providers = [];
  bool _loadingProviders = false;

  Future<void> _fetchProviders(String profession) async {
    // Para fluxo fixo, talvez não precise buscar prestadores aqui se já foi selecionado antes
    // Mas mantemos a lógica caso venha de fluxo genérico
    if (_loadingProviders) return;
    setState(() => _loadingProviders = true);
    try {
      // Como é fixo, prestador está no endereço dele.
      // Se tivermos lat/lon, buscamos próximos.
      final providers = await _api.searchProviders(
        term: profession,
        lat: _latitude,
        lon: _longitude,
      );
      setState(() {
        _providers = providers;
      });
    } catch (e) {
      debugPrint('Error fetching providers: $e');
    } finally {
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  Future<void> _fetchSlots() async {
    if (_loadingSlots) return;
    if (_selectedProviderId == null) return;

    setState(() => _loadingSlots = true);
    try {
      final date = _selectedDate ??
          DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      final slots = await _api.getProviderSlots(
        _selectedProviderId!,
        date: dateStr,
      );

      // Filter out past slots if today
      final now = DateTime.now();
      if (_selectedDate != null &&
          _selectedDate!.year == now.year &&
          _selectedDate!.month == now.month &&
          _selectedDate!.day == now.day) {
        slots.removeWhere((slot) {
          final startStr = slot['start_time'].toString();
          final slotTime = DateTime.tryParse(startStr);
          return slotTime != null && slotTime.isBefore(now);
        });
      }

      setState(() {
        _realSlots = slots;
      });
    } catch (e) {
      debugPrint('Error fetching slots: $e');
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);

    _loadInitialState();
    _fetchUserLocation();
    _loadInitialState();
    _fetchUserLocation();
  }

  Future<void> _fetchAddressFromCoordinates(Map<String, dynamic> provider) async {
    if (provider['latitude'] == null || provider['longitude'] == null) return;
    
    try {
      double lat = double.parse(provider['latitude'].toString());
      double lon = double.parse(provider['longitude'].toString());
      
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = "${place.street ?? ''}, ${place.subLocality ?? ''} - ${place.subAdministrativeArea ?? ''}";
        if (place.street == null || place.street!.isEmpty) {
           address = "${place.subLocality ?? ''}, ${place.subAdministrativeArea ?? ''}";
        }
        
        setState(() {
          provider['address'] = address.replaceAll(RegExp(r'^, | - $'), '').trim();
        });
      }
    } catch (e) {
      debugPrint("Error fetching address for provider: $e");
    }
  }

  Future<void> _fetchUserLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPosition = pos);
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  void _loadInitialState() {
    // 1. DADOS VINDOS DA IA (MÓVEL -> FIXO)
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _descriptionController.text = d['description'] ?? '';
      _selectedProfession = d['profession'];
      _aiProfessionName = d['profession'];
      _aiTaskName = d['task_name'];
      _aiTaskId = d['task_id'];
      _aiTaskPrice = d['price'];
      _aiCategoryId = d['category_id'];
      _aiServiceType = d['service_type'];
      _latitude = d['lat'];
      _longitude = d['lon'];

      if (d['pre_selected_provider'] != null) {
        final p = d['pre_selected_provider'];
        _selectedProviderId = int.tryParse(p['id']?.toString() ?? '');
        _providers = [p];
        
        // Pega localização do prestador
        _latitude = double.tryParse(p['latitude']?.toString() ?? '');
        _longitude = double.tryParse(p['longitude']?.toString() ?? '');
        _address = p['address']?.toString();
        _addressController.text = _address ?? '';
        
        _currentStep = 3; // Pula para Agenda (Calendário)
        _fetchSlots();
      } else {
        if (_selectedProfession != null) {
          _fetchProviders(_selectedProfession!);
        }
        _currentStep = 2; // Começa no passo de Escolha de Prestador
      }
    }

    // 2. DADOS VINDOS DE UM PERFIL ESPECÍFICO (BOTÃO AGENDAR)
    if (widget.initialProviderId != null) {
      _selectedProviderId = widget.initialProviderId;
      if (widget.initialProvider != null) {
        _providers = [widget.initialProvider!];

        final p = widget.initialProvider!;
        _latitude = double.tryParse(p['latitude']?.toString() ?? '');
        _longitude = double.tryParse(p['longitude']?.toString() ?? '');
        _address = p['address']?.toString();
        _addressController.text = _address ?? '';
      }

      if (widget.initialService != null) {
        _selectedService = widget.initialService;
        final rawCat = widget.initialService!['category'];
        final rawName = widget.initialService!['name'];
        _selectedProfession = rawName?.toString() ?? rawCat?.toString();
        _aiProfessionName = _selectedProfession;
        if (_descriptionController.text.isEmpty) {
          _descriptionController.text = "Agendamento de ${rawName?.toString() ?? ''}";
        }

        _aiTaskName = rawName?.toString();
        if (widget.initialService!['price'] != null) {
          _aiTaskPrice = double.tryParse(widget.initialService!['price'].toString());
        }
      }
      _currentStep = 3; // Pula escolha de prestador, vai para Agenda (Calendário)
      _fetchSlots();
    }
  }

  @override
  void dispose() {
    _aiDebounce?.cancel();
    _descriptionController.dispose();
    _addressController.dispose();
    _professionSearchController.dispose();
    _descScrollController.dispose();
    super.dispose();
  }

  Future<void> _submitService() async {
    setState(() => _isLoading = true);
    try {
      await _api.loadToken();

      // Para prestador fixo, o endereço é OBRIGATÓRIO ser o do prestador.
      if (_latitude == null || _longitude == null) {
         // Fallback: tentar pegar do provider selecionado
         if (_selectedProviderId != null) {
            final provider = _providers.firstWhere(
            (p) => int.tryParse(p['id'].toString()) == _selectedProviderId,
            orElse: () => {},
          );
          if (provider.isNotEmpty) {
            _latitude = double.tryParse(provider['latitude'].toString());
            _longitude = double.tryParse(provider['longitude'].toString());
            _address = provider['address']?.toString();
            _addressController.text = _address ?? '';
          }
         }
      }

      if (_latitude == null || _longitude == null) {
        throw Exception("Endereço do estabelecimento não encontrado.");
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
        desc = "Serviço: $_aiTaskName\n$desc";
      }

      int categoryId = _aiCategoryId ?? 1;
      double price = _aiTaskPrice ?? _priceEstimated;
      double upfront = price * 0.30;

      DateTime? scheduledAt;
      if (_selectedDate != null && _selectedTimeSlot != null) {
        try {
          final parts = _selectedTimeSlot!.split(':');
          if (parts.length == 2) {
            final hour = int.parse(parts[0]);
            final minute = int.parse(parts[1]);
            scheduledAt = DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
              hour,
              minute,
            );
          }
        } catch (e) {
          debugPrint('Erro ao calcular scheduledAt: $e');
        }
      }

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
        profession: _selectedProfession ?? _aiProfessionName,
        locationType: 'provider', // Sempre provider para Fixed
        providerId: _selectedProviderId,
        scheduledAt: scheduledAt,
        taskId: _aiTaskId,
      );

      _handleSuccess(result, upfront, price);
    } catch (e) {
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

  void _handleSuccess(
    Map<String, dynamic> result,
    double upfrontAmount,
    double totalAmount,
  ) {
    if (!mounted) return;
    final serviceId =
        result['service']?['id']?.toString() ?? result['id']?.toString();

    if (serviceId == null) {
      throw Exception("Não foi possível obter o ID do serviço criado.");
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Serviço criado! Iniciando pagamento...'),
        backgroundColor: Colors.green,
      ),
    );
    context.go(
      '/payment/$serviceId',
      extra: {
        'serviceId': serviceId,
        'amount': upfrontAmount,
        'total': totalAmount,
        'type': 'deposit',
      },
    );
  }

  void _nextStep() async {
    // Passo 1: Descrição/Detalhes
    if (_currentStep == 1) {
      if (_descriptionController.text.trim().isEmpty) {
        _descriptionController.text = "Agendamento simples";
      }
      
      // Se já temos um prestador (veio do perfil), pulamos a escolha e vamos para Agenda
      if (_selectedProviderId != null) {
        setState(() {
          _currentStep = 3; // Pula para Agenda
          _fetchSlots();
        });
      } else {
        setState(() {
          _currentStep = 2; // Vai para Escolha de Prestador
        });
        if (_selectedProfession != null) {
          _fetchProviders(_selectedProfession!);
        }
      }
      return;
    }

    // Passo 2: Escolha de Prestador
    if (_currentStep == 2) {
      if (_selectedProviderId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, selecione um profissional.')),
        );
        return;
      }
      setState(() {
        _currentStep = 3;
        _fetchSlots();
      });
      return;
    }

    // Passo 3: Agenda
    if (_currentStep == 3) {
      if (_selectedDate == null || _selectedTimeSlot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, escolha data e horário.')),
        );
        return;
      }
      setState(() => _currentStep = 4);
      return;
    }

    // Passo 4: Revisão
    if (_currentStep == 4) {
      _submitService();
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() {
        // Se estamos na Agenda (3) e viemos de um perfil, volta para Detalhes (1)
        if (_currentStep == 3 && widget.initialProviderId != null) {
          _currentStep = 1;
        } else {
          _currentStep--;
        }
      });
    } else {
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        context.pop();
      }
    }
  }
  
  // Placeholder para IA se necessário no futuro, ou se usuário quiser mudar descrição
  Future<void> _classifyAi() async {
     // Implement if needed for Fixed flow adaptation
  }
  
  // Placeholder media handlers
  Future<void> _handleImagesSelected(List<XFile> imgs) async {}
  Future<void> _handleVideoSelected(XFile video) async {}
  Future<void> _handleAudioSelected(PlatformFile file) async {}

  Widget _buildContent() {
    switch (_currentStep) {
      case 1:
        return _buildDescriptionStep();
      case 2:
        return _buildProviderSelectionStep();
      case 3:
        return _buildScheduleStep();
      case 4:
        return _buildReviewStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDescriptionStep() {
    // Simplified Description for Fixed (Optional details)
    return SingleChildScrollView(
      controller: _descScrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalhes do Agendamento',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Adicione observações para o profissional (Opcional)',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _descriptionController,
            minLines: 4,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Ex: Quero cortar somente as pontas...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Continuar para Agenda'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleStep() {
    final provider = _providers.firstWhere(
      (p) => int.tryParse(p['id'].toString()) == _selectedProviderId,
      orElse: () => {},
    );
    final providerName =
        (provider['commercial_name'] ?? provider['full_name'] ?? 'Profissional')
            .toString();
    
    final serviceName = _aiTaskName ?? _selectedService?['name'] ?? 'Serviço';

    return SingleChildScrollView(
      key: _scheduleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agendamento',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Escolha data e horário',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),

          // Provider Info Card (Enhanced)
           Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      image: provider['avatar_url'] != null
                          ? DecorationImage(
                              image: NetworkImage(provider['avatar_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: provider['avatar_url'] == null
                        ? const Icon(Icons.person, color: Colors.grey, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          Text(
                            providerName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          // Rating
                          if (provider['rating'] != null)
                            Row(
                              children: [
                                const Icon(Icons.star, size: 14, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  provider['rating'].toString(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(${provider['reviews_count'] ?? 0} avaliações)',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          // Address
                          // Address Fetch Trigger
                          if ((provider['address'] == null || provider['address'] == 'Endereço não informado') && 
                              provider['latitude'] != null && 
                              !_fetchedAddresses.contains(provider['id']))
                                Builder(builder: (context) {
                                  _fetchedAddresses.add(provider['id']);
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _fetchAddressFromCoordinates(provider);
                                  });
                                  return const SizedBox.shrink();
                                }),

                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  provider['address'] ?? 
                                    (provider['latitude'] != null 
                                      ? "Lat: ${provider['latitude']}, Lon: ${provider['longitude']}" 
                                      : 'Endereço não informado'),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          // Distance and Time
                          if (_userPosition != null && provider['latitude'] != null && provider['longitude'] != null) ...[
                             const SizedBox(height: 6),
                             Builder(
                               builder: (context) {
                                 final double distInMeters = Geolocator.distanceBetween(
                                    _userPosition!.latitude,
                                    _userPosition!.longitude,
                                    double.tryParse(provider['latitude'].toString()) ?? 0,
                                    double.tryParse(provider['longitude'].toString()) ?? 0,
                                 );
                                 final double distKm = distInMeters / 1000;
                                 // Estimativa grosseira: 30km/h média urbana = 0.5 km/min
                                 final int timeMin = (distKm / 30 * 60).round(); 
                                 
                                 return Row(
                                   children: [
                                     Icon(LucideIcons.mapPin, size: 14, color: AppTheme.primaryPurple),
                                     const SizedBox(width: 4),
                                     Text(
                                       '${distKm.toStringAsFixed(1)} km',
                                       style: TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold, fontSize: 12),
                                     ),
                                     const SizedBox(width: 12),
                                      Icon(LucideIcons.clock, size: 14, color: AppTheme.primaryPurple),
                                     const SizedBox(width: 4),
                                     Text(
                                       '~$timeMin min',
                                       style: TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold, fontSize: 12),
                                     ),
                                   ],
                                 );
                               }
                             )
                          ]
                       ],
                    )
                  )
               ],
            ),
           ),
           const SizedBox(height: 12),

          // Calendar
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: AppTheme.primaryBlue,
                    onPrimary: Colors.white,
                  ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: CalendarDatePicker(
              initialDate: _selectedDate ?? DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 60)),
              onDateChanged: (date) {
                setState(() {
                  _selectedDate = date;
                  _selectedTimeSlot = null;
                });
                _fetchSlots();
              },
            ),
          ),
          ),

          const SizedBox(height: 24),
          const Text('Horários', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),

          if (_loadingSlots)
            const Center(child: CircularProgressIndicator())
          else if (_realSlots.isEmpty)
             const Text('Nenhum horário livre.', style: TextStyle(color: Colors.orange))
          else
            Container(
              width: double.infinity, // Full width
              padding: const EdgeInsets.all(4), // Little padding
              child: GridView.builder(
                 shrinkWrap: true,
                 physics: const NeverScrollableScrollPhysics(),
                 gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4, // 4 columns
                    childAspectRatio: 1.8, // Aspect ratio for chips
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                 ),
                 itemCount: _realSlots.length,
                 itemBuilder: (context, index) {
                   final slot = _realSlots[index];
                   final bool isBusy = slot['status'] != 'free';
                   final String startStr = slot['start_time'].toString();
                   final String timeStr = startStr.contains('T')
                     ? startStr.split('T')[1].substring(0, 5)
                     : "${DateTime.parse(startStr).hour.toString().padLeft(2, '0')}:${DateTime.parse(startStr).minute.toString().padLeft(2, '0')}";
                   final isSelected = _selectedTimeSlot == timeStr;

                   return InkWell(
                     onTap: isBusy ? null : () => setState(() => _selectedTimeSlot = isSelected ? null : timeStr),
                     borderRadius: BorderRadius.circular(8),
                     child: Container(
                       decoration: BoxDecoration(
                         color: isSelected ? AppTheme.primaryBlue : (isBusy ? Colors.grey[100] : Colors.white),
                         borderRadius: BorderRadius.circular(10),
                         border: Border.all(
                           color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade300,
                         ),
                       ),
                       alignment: Alignment.center,
                       child: Text(
                         timeStr,
                         style: TextStyle(
                           fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                           color: isBusy ? Colors.grey : (isSelected ? Colors.white : Colors.black87),
                         ),
                       ),
                     ),
                   );
                 },
              ),
            ),
          
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_selectedDate != null && _selectedTimeSlot != null) ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Confirmar Horário'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final totalValue = _aiTaskPrice ?? _priceEstimated;
    final upfrontValue = totalValue * 0.30;
    
    final dateStr = _selectedDate != null
        ? DateFormat("EEEE, dd 'de' MMMM", 'pt_BR').format(_selectedDate!)
        : 'Hoje';
    final timeStr = _selectedTimeSlot ?? '--:--';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
             'Revisar Agendamento',
             style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          // Yellow Card
          Container(
             padding: EdgeInsets.all(24),
             decoration: BoxDecoration(
                color: AppTheme.primaryYellow,
                borderRadius: BorderRadius.circular(24),
             ),
             child: Center(
                child: Column(
                   children: [
                      Icon(LucideIcons.calendarCheck, size: 32),
                      SizedBox(height: 8),
                      Text(dateStr, style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(timeStr, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
                   ],
                ),
             ),
          ),
          
          const SizedBox(height: 32),
          Container(
             padding: EdgeInsets.all(16),
             decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(16)
             ),
             child: Column(
                children: [
                   Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         Text('Total'),
                         Text('R\$ ${totalValue.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                   ),
                   SizedBox(height: 8),
                   Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         Text('Pagar Agora (30%)', style: TextStyle(color: AppTheme.secondaryOrange)),
                         Text('R\$ ${upfrontValue.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondaryOrange)),
                      ],
                   )
                ],
             ),
          ),
          
          const SizedBox(height: 32),
          
          // Info Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "A entrada garante a reserva do profissional. O restante é pago apenas após a conclusão.",
                    style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          const Center(child: Text("Como funciona?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          const SizedBox(height: 16),
          
          // Flow Steps
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildFlowStep(LucideIcons.banknote, "1. Entrada", "Pague 30%\npara reservar"),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              _buildFlowStep(LucideIcons.mapPin, "2. Serviço", "Compareça\nao local"),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              _buildFlowStep(LucideIcons.checkCircle, "3. Final", "Pague 70%\nao concluir"),
            ],
          ),

          const SizedBox(height: 32),
          SizedBox(
             width: double.infinity,
             height: 56,
             child: ElevatedButton(
                onPressed: _submitService,
                style: ElevatedButton.styleFrom(
                   backgroundColor: AppTheme.secondaryOrange,
                   foregroundColor: Colors.white,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading ? CircularProgressIndicator(color: Colors.white) : Text('Confirmar e Pagar'),
             ),
          )
        ],
      ),
    );
  }

  Widget _buildFlowStep(IconData icon, String title, String subtitle) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.secondaryOrange, size: 24),
        ),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          subtitle, 
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProviderSelectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Escolha o Profissional',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Encontramos esses prestadores para $_selectedProfession',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (_loadingProviders)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_providers.isEmpty)
          const Expanded(
            child: Center(
              child: Text('Nenhum prestador encontrado para esta categoria.'),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _providers.length,
              itemBuilder: (context, index) {
                final p = _providers[index];
                final isSelected = _selectedProviderId == p['id'];
                return Card(
                  margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
                  elevation: 6,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryYellow : Colors.grey.shade100,
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                         _selectedProviderId = int.tryParse(p['id'].toString());
                         _latitude = double.tryParse(p['latitude']?.toString() ?? '');
                         _longitude = double.tryParse(p['longitude']?.toString() ?? '');
                         _address = p['address']?.toString();
                         _addressController.text = _address ?? '';
                      });
                      _nextStep();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 65,
                            height: 65,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              color: Colors.grey[100],
                              image: p['avatar_url'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(p['avatar_url']),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: p['avatar_url'] == null
                                ? const Icon(Icons.person, color: Colors.grey, size: 30)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['commercial_name'] ?? p['full_name'] ?? 'Profissional',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        p['address'] ?? 'Endereço não informado',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isSelected ? Icons.check_circle : Icons.chevron_right,
                            color: isSelected ? AppTheme.primaryYellow : Colors.grey.shade400,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Agendar Serviço - Etapa $_currentStep de 4',
          style: TextStyle(
            color: AppTheme.darkBlueText,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppTheme.primaryYellow,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
          onPressed: _prevStep,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: _currentStep / 4,
                color: AppTheme.darkBlueText,
                backgroundColor: Colors.grey[200],
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }
}
