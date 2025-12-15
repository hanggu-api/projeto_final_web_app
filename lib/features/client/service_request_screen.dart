import 'package:flutter/material.dart';
      import 'package:flutter/foundation.dart' show kIsWeb;
      import 'package:go_router/go_router.dart';
      import 'package:lucide_icons/lucide_icons.dart';
      import '../../core/theme/app_theme.dart';
      import 'package:flutter_map/flutter_map.dart';
      import 'package:latlong2/latlong.dart';
      import 'package:geolocator/geolocator.dart';
      import 'dart:async';
      import 'package:http/http.dart' as http;
      import 'dart:convert';
      import '../../services/api_service.dart';
      import 'package:image_picker/image_picker.dart';
      import 'package:file_picker/file_picker.dart';
      


      class ServiceRequestScreen extends StatefulWidget {
        const ServiceRequestScreen({super.key});

        @override
        State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
      }

      class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
        int _currentStep = 1;
        int _selectedCategoryIndex = 0;
        final TextEditingController _descriptionController = TextEditingController();
        final TextEditingController _addressController = TextEditingController();
        bool _isLoading = false;
        final _api = ApiService();
        final MapController _mapController = MapController();
        double? _latitude;
        double? _longitude;
        String? _address;
        bool _chooseOtherAddress = false;
        List<Map<String, dynamic>> _suggestions = [];
        Timer? _debounce;
        Timer? _geoDebounce;
        final double _priceEstimated = 150.00;
        final double _priceUpfront = 33.00;
        final List<String> _imageKeys = [];
        String? _videoKey;
        final List<String> _audioKeys = [];
        

        final List<Map<String, dynamic>> _categories = [
          {'id': 1, 'icon': LucideIcons.droplets, 'label': 'Encanamento', 'color': Colors.blue},
          {'id': 2, 'icon': LucideIcons.zap, 'label': 'Elétrica', 'color': Colors.orange},
          {'id': 3, 'icon': LucideIcons.paintbrush, 'label': 'Pintura', 'color': Colors.purple},
          {'id': 4, 'icon': LucideIcons.hammer, 'label': 'Marcenaria', 'color': Colors.deepOrange},
          {'id': 5, 'icon': LucideIcons.wrench, 'label': 'Manutenção', 'color': Colors.green},
          {'id': 6, 'icon': LucideIcons.home, 'label': 'Geral', 'color': Colors.grey},
        ];

        @override
        void initState() {
          super.initState();
          // 1. No Web, solicitar geolocalização apenas por gesto do usuário
          // Para mobile, pode iniciar automaticamente
          if (!kIsWeb) {
            _useMyLocation(initialLoad: true);
          }
        }

        @override
        void dispose() {
          _debounce?.cancel();
          _geoDebounce?.cancel();
          _descriptionController.dispose();
          _addressController.dispose();
          super.dispose();
        }

        Future<void> _submitService() async {
          setState(() => _isLoading = true);
          
          try {
            final category = _categories[_selectedCategoryIndex];
            // Garantir que temos um endereço e coordenadas válidas antes de submeter
            if (_latitude == null || _longitude == null || (_addressController.text.isEmpty && _address == null)) {
              throw Exception("Localização ou endereço não definidos.");
            }
            await _api.loadToken();
            final addrRaw = _addressController.text.isEmpty ? (_address ?? '') : _addressController.text;
            final addressSafe = addrRaw.length > 255 ? addrRaw.substring(0, 255) : addrRaw;
            String desc = _descriptionController.text.isEmpty ? (category['label'] as String) : _descriptionController.text;
            if (desc.trim().length < 10) {
              desc = '${desc.trim()} - detalhar problema';
            }
            await _api.createService(
              categoryId: category['id'],
              description: desc,
              latitude: _latitude!,
              longitude: _longitude!,
              address: addressSafe,
              priceEstimated: _priceEstimated,
              priceUpfront: _priceUpfront,
              imageKeys: _imageKeys,
              videoKey: _videoKey,
              audioKeys: _audioKeys,
            );

            if (!mounted) return;
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Serviço solicitado com sucesso!'), backgroundColor: Colors.green),
            );
            context.go('/home');

          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro: ${e.toString()}'), backgroundColor: Colors.red),
            );
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        }

        void _nextStep() {
          // Adiciona validação simples para o Passo 3
          if (_currentStep == 3 && (_latitude == null || _longitude == null)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Por favor, defina a localização no mapa.'), backgroundColor: Colors.orange),
            );
            return;
          }

          if (_currentStep < 4) {
            setState(() {
              _currentStep++;
            });
          } else {
            _submitService();
          }
        }

        void _prevStep() {
          if (_currentStep > 1) {
            setState(() {
              _currentStep--;
            });
          } else {
            context.pop();
          }
        }

        // --- MÉTODOS DE LOCALIZAÇÃO ---

        Future<void> _useMyLocation({bool initialLoad = false}) async {
          // 3. Método para buscar a localização GPS
          LocationPermission perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
            perm = await Geolocator.requestPermission();
            if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Permissão de localização negada. Usando localização padrão.'), backgroundColor: Colors.orange),
              );
              if (!kIsWeb) {
                await Geolocator.openAppSettings();
                await Geolocator.openLocationSettings();
              }
              // Usa São Paulo como fallback
              _mapController.move(const LatLng(-23.550520, -46.633308), 13);
              setState(() {
                _latitude = -23.550520;
                _longitude = -46.633308;
                _address = 'Localização Padrão';
                _addressController.text = _address!;
                _chooseOtherAddress = false;
              });
              return;
            }
          }

          if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
            try {
              final serviceOn = await Geolocator.isLocationServiceEnabled();
              if (!serviceOn) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Serviço de localização desativado. Ative o GPS/Localização.'), backgroundColor: Colors.orange),
                );
                if (!kIsWeb) {
                  await Geolocator.openLocationSettings();
                }
              }
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
              );
              setState(() {
                _latitude = pos.latitude;
                _longitude = pos.longitude;
                // Se for clique em "Usar minha localização", volta para o modo de visualização.
                _chooseOtherAddress = false;
              });
              _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
              await _reverseGeocode(pos.latitude, pos.longitude);
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(kIsWeb ? 'Falha ao obter localização no Web (precisa de HTTPS). Usando padrão.' : 'Erro ao obter localização: ${e.toString()}'), backgroundColor: Colors.orange),
              );
              // Fallback no Web ou erro geral
              _mapController.move(const LatLng(-23.550520, -46.633308), 13);
              setState(() {
                _latitude = -23.550520;
                _longitude = -46.633308;
                _address = 'Localização Padrão';
                _addressController.text = _address!;
                _chooseOtherAddress = false;
              });
            }
          }
        }

        Future<void> _reverseGeocode(double lat, double lon) async {
          // 4. Método para buscar o endereço a partir da Lat/Lon (Nominatim API)
          try {
            final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon');
            final resp = await http.get(uri, headers: {'User-Agent': 'ConsertaApp/1.0'});
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body);
              String display = (data['display_name'] ?? '').toString();
              final addr = data['address'] as Map<String, dynamic>?;
              String short = '';
              if (addr != null) {
                final street = (addr['road'] ?? addr['pedestrian'] ?? addr['footway'] ?? addr['residential'])?.toString();
                final house = addr['house_number']?.toString();
                final neigh = (addr['suburb'] ?? addr['neighbourhood'] ?? addr['quarter'] ?? addr['hamlet'])?.toString();
                final city = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['municipality'])?.toString();
                final state = addr['state']?.toString();
                final part1 = [street, house].where((e) => e != null && e.isNotEmpty).join(', ');
                final part2 = [neigh].where((e) => e != null && e.isNotEmpty).join('');
                final part3 = [city, state].where((e) => e != null && e.isNotEmpty).join(', ');
                final parts = [part1, part2, part3].where((e) => e.isNotEmpty).toList();
                short = parts.join(' - ');
              }
              if (short.isEmpty && display.isNotEmpty) {
                final segs = display.split(',').map((s) => s.trim()).toList();
                short = segs.take(4).join(', ');
              }
              if (short.length > 120) short = short.substring(0, 120);
              setState(() {
                _address = short.isNotEmpty ? short : display;
                _addressController.text = _address!;
              });
            }
          } catch (_) {
            setState(() {
              _address = 'Endereço não encontrado';
              _addressController.text = _address!;
            });
          }
        }

        Future<void> _searchAddress(String q) async {
          // 5. Método para buscar Lat/Lon a partir do endereço (Nominatim API)
          if (q.trim().length < 3) {
            setState(() => _suggestions = []);
            return;
          }
          try {
            final uri = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(q)}&limit=6');
            final resp = await http.get(uri, headers: {'User-Agent': 'ConsertaApp/1.0'});
            if (resp.statusCode == 200) {
              final list = jsonDecode(resp.body) as List<dynamic>;
              setState(() {
                _suggestions = list.cast<Map<String, dynamic>>();
              });
            }
          } catch (_) {
            setState(() => _suggestions = []);
          }
        }

        // --- CONTEÚDO DOS PASSOS ---

        Widget _buildStepContent() {
          switch (_currentStep) {
            case 1:
              return _buildCategoryStep();
            case 2:
              return _buildDescriptionStep();
            case 3:
              return _buildLocationStep(); // Foco da mudança
            case 4:
              return _buildReviewStep();
            default:
              return const SizedBox.shrink();
          }
        }

        Widget _buildCategoryStep() {
          // ... (Mantido inalterado)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Qual tipo de serviço?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('Selecione a categoria que melhor descreve seu problema', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _selectedCategoryIndex == index;
                    return InkWell(
                      onTap: () => setState(() => _selectedCategoryIndex = index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryPurple : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(color: AppTheme.primaryPurple.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))
                            else
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(cat['icon'], size: 32, color: isSelected ? Colors.white : Colors.black54),
                            const SizedBox(height: 8),
                            Text(
                              cat['label'], 
                              style: TextStyle(
                                fontSize: 12, 
                                color: isSelected ? Colors.white : Colors.black87
                              )
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
            ],
          );
        }

        Widget _buildDescriptionStep() {
          // ... (Mantido inalterado)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Descreva o problema', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('Quanto mais detalhes, melhor', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              
              TextField(
                controller: _descriptionController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'Ex: Chuveiro da suíte não esquenta...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _onAttachMedia,
                      icon: const Icon(LucideIcons.camera),
                      label: const Text('Foto/Vídeo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _onRecordAudio,
                      icon: const Icon(LucideIcons.mic),
                      label: const Text('Áudio'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_imageKeys.isNotEmpty || _videoKey != null || _audioKeys.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_imageKeys.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _imageKeys.map((k) => FutureBuilder<String>(
                            future: _api.getMediaViewUrl(k),
                            builder: (context, snapshot) {
                              final url = snapshot.data;
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(width: 80, height: 80, child: url != null ? Image.network(url, fit: BoxFit.cover) : const SizedBox()),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: IconButton(
                                      icon: const Icon(LucideIcons.x, size: 16),
                                      onPressed: () {
                                        setState(() => _imageKeys.remove(k));
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          )).toList(),
                        ),
                      if (_videoKey != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Vídeo anexado'),
                            IconButton(
                              icon: const Icon(LucideIcons.x),
                              onPressed: () => setState(() => _videoKey = null),
                            ),
                          ],
                        ),
                      if (_audioKeys.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          children: _audioKeys.map((k) => Chip(
                            label: const Text('Áudio'),
                            deleteIcon: const Icon(LucideIcons.x),
                            onDeleted: () => setState(() => _audioKeys.remove(k)),
                          )).toList(),
                        ),
                    ],
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
            ],
          );
        }

        Future<void> _onAttachMedia() async {
          if (kIsWeb) {
            final resImg = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image);
            if (resImg != null && resImg.files.isNotEmpty) {
              for (final f in resImg.files.take(3 - _imageKeys.length)) {
                if (f.bytes != null) {
                  final key = await _api.uploadServiceImage(f.bytes!, filename: f.name);
                  setState(() => _imageKeys.add(key));
                }
              }
            }
            if (_videoKey == null) {
              final resVid = await FilePicker.platform.pickFiles(allowMultiple: false, type: FileType.video);
              if (resVid != null && resVid.files.isNotEmpty) {
                final f = resVid.files.first;
                if (f.bytes != null) {
                  final key = await _api.uploadServiceVideo(f.bytes!, filename: f.name);
                  setState(() => _videoKey = key);
                }
              }
            }
            return;
          }
          final picker = ImagePicker();
          if (_imageKeys.length < 3) {
            final img = await picker.pickImage(source: ImageSource.camera);
            if (img != null) {
              final bytes = await img.readAsBytes();
              final key = await _api.uploadServiceImage(bytes, filename: img.name);
              setState(() => _imageKeys.add(key));
            }
          }
          if (_videoKey == null) {
            final vid = await picker.pickVideo(source: ImageSource.camera);
            if (vid != null) {
              final bytes = await vid.readAsBytes();
              final key = await _api.uploadServiceVideo(bytes, filename: vid.name);
              setState(() => _videoKey = key);
            }
          }
        }

        Future<void> _onRecordAudio() async {
          if (_audioKeys.length >= 3) return;
          final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'wav']);
          if (res != null && res.files.isNotEmpty) {
            final f = res.files.first;
            if (f.bytes != null) {
              String mime = 'audio/mpeg';
              final String name = f.name.toLowerCase();
              if (name.endsWith('.wav')) {
                mime = 'audio/wav';
              } else if (name.endsWith('.m4a')) {
                mime = 'audio/mp4';
              } else if (name.endsWith('.aac')) {
                mime = 'audio/aac';
              }
              final key = await _api.uploadServiceAudio(f.bytes!, filename: f.name, mimeType: mime);
              setState(() => _audioKeys.add(key));
            }
          }
        }

        Widget _buildLocationStep() {
          // 2. Lógica para exibir o campo de endereço dinamicamente
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Onde é o serviço?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('Confirme ou ajuste a localização do serviço', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Icon(LucideIcons.mapPin, color: AppTheme.primaryPurple, size: 16),
                  SizedBox(width: 6),
                  Text('Endereço', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),

              // Campo de Endereço Unificado
              TextField(
                controller: _addressController,
                // O campo é readOnly quando está mostrando a localização atual (do GPS ou do mapa)
                readOnly: !_chooseOtherAddress, 
                onChanged: (value) {
                  // O onChanged só é relevante quando o campo é editável (_chooseOtherAddress é true)
                  if (_chooseOtherAddress) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () => _searchAddress(value));
                  }
                },
                decoration: InputDecoration(
                  // Ícone de busca se estiver no modo de escolha de endereço, ou Pin no modo de visualização
                  prefixIcon: _chooseOtherAddress ? const Icon(LucideIcons.search) : const Icon(LucideIcons.mapPin, color: AppTheme.primaryPurple),
                  hintText: _chooseOtherAddress ? 'Digite o endereço (rua, número, bairro...)' : 'Endereço da localização atual',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  // Ícone de fechar para sair do modo de escolha de outro endereço
                  suffixIcon: _chooseOtherAddress
                      ? IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            setState(() {
                              // Volta para o endereço atualmente selecionado pelo mapa/GPS
                              _addressController.text = _address ?? '';
                              _chooseOtherAddress = false;
                              _suggestions = [];
                            });
                          },
                        )
                      : null,
                ),
              ),

              // Botão para alternar entre "Usar localização atual" e "Escolher outro endereço"
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      if (!_chooseOtherAddress) {
                        // Se não estiver buscando outro, clique para buscar outro.
                        setState(() {
                          _chooseOtherAddress = true;
                          _addressController.clear(); // Limpa o input para digitar o novo
                          _suggestions = [];
                        });
                      } else {
                        // Se estiver buscando outro, clique para usar a localização atual (GPS).
                        _useMyLocation();
                      }
                    },
                    child: Text(
                      _chooseOtherAddress ? 'Usar minha localização atual' : 'Escolher outro endereço',
                    ),
                  ),
                ],
              ),

              // Sugestões de Endereço (somente se estiver no modo de busca)
              if (_chooseOtherAddress && _suggestions.isNotEmpty)
                Container(
                  height: _suggestions.length > 3 ? 180 : null, // Limita altura para listas maiores
                  constraints: const BoxConstraints(maxHeight: 180),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)]),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final s = _suggestions[index];
                      return ListTile(
                        leading: const Icon(LucideIcons.mapPin),
                        title: Text(() {
                          final disp = (s['display_name'] ?? '').toString();
                          final segs = disp.split(',').map((e) => e.trim()).toList();
                          final short = segs.take(4).join(', ');
                          return short.length > 120 ? short.substring(0, 120) : short;
                        }()),
                        onTap: () {
                          final lat = double.tryParse(s['lat'] ?? '') ?? _latitude ?? -23.55052;
                          final lon = double.tryParse(s['lon'] ?? '') ?? _longitude ?? -46.633308;
                          setState(() {
                            _latitude = lat;
                            _longitude = lon;
                            final disp = (s['display_name'] ?? '').toString();
                            final segs = disp.split(',').map((e) => e.trim()).toList();
                            final short = segs.take(4).join(', ');
                            _address = short.isNotEmpty ? (short.length > 120 ? short.substring(0, 120) : short) : disp;
                            _addressController.text = _address!;
                            _suggestions = [];
                            _chooseOtherAddress = false; // Volta para o modo de leitura
                          });
                          _mapController.move(LatLng(lat, lon), 15);
                          _geoDebounce?.cancel();
                          _geoDebounce = Timer(const Duration(milliseconds: 400), () {
                            if (_latitude != null && _longitude != null) {
                              _reverseGeocode(_latitude!, _longitude!);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              
              const SizedBox(height: 16),

              // Mapa (Fica abaixo e centraliza no Lat/Lng)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          // Usa a localização atual ou padrão
                          initialCenter: LatLng(_latitude ?? -23.550520, _longitude ?? -46.633308),
                          initialZoom: 15,
                          onTap: (tapPos, latLng) {
                            // Permite tocar para mover o mapa
                            _mapController.move(latLng, 15);
                            setState(() {
                              _latitude = latLng.latitude;
                              _longitude = latLng.longitude;
                              _addressController.text = 'Buscando endereço...';
                              _chooseOtherAddress = false;
                            });
                            _geoDebounce?.cancel();
                            _geoDebounce = Timer(const Duration(milliseconds: 400), () {
                              if (_latitude != null && _longitude != null) {
                                _reverseGeocode(_latitude!, _longitude!);
                              }
                            });
                          },
                          onPositionChanged: (camera, hasGesture) {
                            // 6. Ao mover o ícone/mapa
                            if (hasGesture) {
                              setState(() {
                                _latitude = camera.center.latitude;
                                _longitude = camera.center.longitude;
                                // Ao mover, o campo de endereço reflete a nova localização do mapa
                                _addressController.text = 'Buscando endereço...'; 
                                _chooseOtherAddress = false; // Sai do modo de busca
                              });
                              // Usa Debounce para evitar muitas chamadas de reverseGeocode
                              _geoDebounce?.cancel();
                              _geoDebounce = Timer(const Duration(milliseconds: 600), () {
                                if (_latitude != null && _longitude != null) {
                                  _reverseGeocode(_latitude!, _longitude!);
                                }
                              });
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                          ),
                        ],
                      ),
                      // Ícone de Ponto Fixo (Pin) no centro do mapa
                      const Icon(Icons.location_on, color: AppTheme.primaryPurple, size: 40),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  // Só habilita se a localização tiver sido definida
                  onPressed: (_latitude != null && _longitude != null) ? _nextStep : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
            ],
          );
        }

        Widget _buildReviewStep() {
          // ... (Mantido inalterado)
          final category = _categories[_selectedCategoryIndex];
          final restanteRaw = (_priceEstimated - _priceUpfront);
          final restante = restanteRaw < 0 ? 0.0 : restanteRaw;
          String formatBRL(double v) {
            final s = v.toStringAsFixed(2);
            return 'R\$ ${s.replaceAll('.', ',')}';
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Confirmar pedido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('Revise os detalhes para confirmar', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Categoria', style: TextStyle(color: Colors.grey)),
                        Text(category['label'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Divider(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Endereço', style: TextStyle(color: Colors.grey)),
                        Expanded(
                          child: Text(
                            _addressController.text.isEmpty ? (_address ?? 'Não Informado') : _addressController.text, 
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Divider(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Valor Estimado', style: TextStyle(color: Colors.grey)),
                        Text(formatBRL(_priceEstimated), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Entrada', style: TextStyle(color: Colors.grey)),
                        Text(formatBRL(_priceUpfront), style: const TextStyle(color: AppTheme.primaryPurple, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Restante', style: TextStyle(color: Colors.grey)),
                        Text(formatBRL(restante), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.lightbulb, color: AppTheme.primaryPurple, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Você paga agora a entrada de ${formatBRL(_priceUpfront)}. '
                              'O restante de ${formatBRL(restante)} '
                              'será pago na plataforma quando prestador chegar o prestador a plataforma só libera paramento á ele quando concluir o servirço ',
                              style: const TextStyle(color: Colors.black87, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isLoading ? null : _nextStep,
                  child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirmar Pedido'),
                ),
              ),
            ],
          );
        }

        @override
        Widget build(BuildContext context) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(LucideIcons.chevronLeft),
                onPressed: _prevStep,
              ),
              title: const Text('Solicitar serviço'),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Passo $_currentStep de 4', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _currentStep / 4,
                      color: AppTheme.primaryPurple,
                      backgroundColor: Colors.black.withOpacity(0.1),
                    ),
                    const SizedBox(height: 16),
                    Expanded(child: _buildStepContent()),
                  ],
                ),
              ),
            ),
          );
        }
      }