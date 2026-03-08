import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/theme_service.dart';
import 'steps/basic_info_step.dart';
import 'steps/identification_step.dart';
import 'steps/location_step.dart';
import 'steps/medical_service_step.dart';
import 'steps/profession_step.dart';
import 'steps/schedule_step.dart';
import 'steps/select_services_step.dart';
import 'steps/vehicle_selection_step.dart';
import 'steps/vehicle_details_step.dart';

class RegisterScreen extends StatefulWidget {
  final String? initialRole;
  const RegisterScreen({super.key, this.initialRole});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isValidatingData = false;
  final Map<String, String?> _fieldValidationErrors = {};

  // Data
  Map<String, dynamic>? _selectedProfession;
  bool _isClient = false;
  bool _isDriver = false;
  int? _selectedVehicleTypeId;
  Map<String, dynamic> _vehicleDetails = {};

  // Standard/Medical Flow Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _docController = TextEditingController();
  final _phoneController = TextEditingController();

  // Barber/Business Flow Controllers
  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();
  double? _latitude;
  double? _longitude;

  final _basicInfoFormKey = GlobalKey<FormState>();
  final _locationFormKey = GlobalKey<FormState>();
  final _identificationFormKey = GlobalKey<FormState>();

  Map<int, Map<String, dynamic>> _schedule = {};
  List<Map<String, dynamic>> _customServices = [];

  // Medical specific
  double? _medicalPrice;
  bool? _medicalHasReturn;

  @override
  void initState() {
    super.initState();
    if (widget.initialRole == 'client') {
      _isClient = true;
      _isDriver = false;
    } else if (widget.initialRole == 'provider') {
      _isClient = false;
      _isDriver = false;
    } else if (widget.initialRole == 'driver') {
      _isClient = false;
      _isDriver = true;
    }

    _loadState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _docController.dispose();
    _phoneController.dispose();
    _businessNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('register_step', _currentStep);
    await prefs.setBool('register_is_client', _isClient);
    await prefs.setBool('register_is_driver', _isDriver);

    if (_selectedVehicleTypeId != null) {
      await prefs.setInt('register_vehicle_type_id', _selectedVehicleTypeId!);
    }

    if (_selectedProfession != null) {
      await prefs.setString(
        'register_profession',
        jsonEncode(_selectedProfession),
      );
    } else {
      await prefs.remove('register_profession');
    }

    await prefs.setString('register_name', _nameController.text);
    await prefs.setString('register_email', _emailController.text);
    await prefs.setString('register_password', _passwordController.text);
    await prefs.setString('register_doc', _docController.text);
    await prefs.setString('register_phone', _phoneController.text);

    await prefs.setString(
      'register_business_name',
      _businessNameController.text,
    );
    await prefs.setString('register_address', _addressController.text);
    if (_latitude != null) await prefs.setDouble('register_lat', _latitude!);
    if (_longitude != null) await prefs.setDouble('register_lng', _longitude!);

    final scheduleJson = _schedule.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString('register_schedule', jsonEncode(scheduleJson));

    await prefs.setString('register_services', jsonEncode(_customServices));
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _currentStep = prefs.getInt('register_step') ?? 0;

      if (widget.initialRole != null) {
        _isClient = widget.initialRole == 'client';
        _isDriver = widget.initialRole == 'driver';
        if (_isClient != (prefs.getBool('register_is_client') ?? false) ||
            _isDriver != (prefs.getBool('register_is_driver') ?? false)) {
          _currentStep = 0;
        }
      } else {
        _isClient = prefs.getBool('register_is_client') ?? false;
        _isDriver = prefs.getBool('register_is_driver') ?? false;
      }

      _selectedVehicleTypeId = prefs.getInt('register_vehicle_type_id');

      final profString = prefs.getString('register_profession');
      if (profString != null) {
        _selectedProfession = jsonDecode(profString);
      }

      _nameController.text = prefs.getString('register_name') ?? '';
      _emailController.text = prefs.getString('register_email') ?? '';
      _passwordController.text = prefs.getString('register_password') ?? '';
      _docController.text = prefs.getString('register_doc') ?? '';
      _phoneController.text = prefs.getString('register_phone') ?? '';

      _businessNameController.text =
          prefs.getString('register_business_name') ?? '';
      _addressController.text = prefs.getString('register_address') ?? '';
      _latitude = prefs.getDouble('register_lat');
      _longitude = prefs.getDouble('register_lng');

      final scheduleString = prefs.getString('register_schedule');
      if (scheduleString != null) {
        final Map<String, dynamic> decoded = jsonDecode(scheduleString);
        _schedule = decoded.map((k, v) => MapEntry(int.parse(k), v));
      }

      final servicesString = prefs.getString('register_services');
      if (servicesString != null) {
        final List<dynamic> decoded = jsonDecode(servicesString);
        _customServices = decoded.cast<Map<String, dynamic>>();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentStep);
      }
    });
  }

  Future<void> _clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('register_step');
    await prefs.remove('register_is_client');
    await prefs.remove('register_profession');
    await prefs.remove('register_name');
    await prefs.remove('register_email');
    await prefs.remove('register_password');
    await prefs.remove('register_doc');
    await prefs.remove('register_phone');
    await prefs.remove('register_business_name');
    await prefs.remove('register_address');
    await prefs.remove('register_lat');
    await prefs.remove('register_lng');
    await prefs.remove('register_schedule');
    await prefs.remove('register_services');
    await prefs.remove('register_medical_price');
    await prefs.remove('register_medical_return');
  }

  List<Widget> get _steps {
    final steps = <Widget>[];

    if (!_isClient && !_isDriver) {
      steps.add(
        ProfessionStep(
          selectedProfession: _selectedProfession,
          onSelect: (prof) {
            setState(() {
              _selectedProfession = prof;
              _isClient = false;
            });
          },
        ),
      );
    }

    bool isSalonFlow = false;
    if (_selectedProfession != null) {
      final profName =
          _selectedProfession?['name'].toString().toLowerCase() ?? '';
      final profType =
          _selectedProfession?['service_type']?.toString().toLowerCase() ?? '';

      isSalonFlow =
          profName.contains('barbeiro') ||
          profName.contains('barbearia') ||
          profName.contains('cabeleireiro') ||
          profName.contains('manicure') ||
          profName.contains('esteticista') ||
          profType == 'salon' ||
          profType == 'beauty';
    }

    if (isSalonFlow && !_isClient) {
      steps.add(
        ScheduleStep(
          schedule: _schedule,
          onChanged: (schedule) {
            setState(() => _schedule = schedule);
            _saveState();
          },
        ),
      );

      steps.add(
        LocationStep(
          formKey: _locationFormKey,
          addressController: _addressController,
          initialLat: _latitude,
          initialLng: _longitude,
          onLocationChanged: (lat, lng) {
            setState(() {
              _latitude = lat;
              _longitude = lng;
            });
            _saveState();
          },
        ),
      );

      steps.add(
        SelectServicesStep(
          selectedServices: _customServices,
          professionId: _selectedProfession!['id'],
          professionName: _selectedProfession!['name'],
          onChanged: (services) {
            setState(() => _customServices = services);
            _saveState();
          },
        ),
      );

      steps.add(
        IdentificationStep(
          formKey: _identificationFormKey,
          businessNameController: _businessNameController,
          nameController: _nameController,
          docController: _docController,
          phoneController: _phoneController,
          emailController: _emailController,
          passwordController: _passwordController,
          onValidationChanged: (isValidating, errors) {
            setState(() {
              _isValidatingData = isValidating;
              _fieldValidationErrors.addAll(errors);
            });
          },
        ),
      );
    } else {
      if (_isDriver) {
        steps.add(
          VehicleSelectionStep(
            selectedVehicleTypeId: _selectedVehicleTypeId,
            onSelect: (id) {
              setState(() => _selectedVehicleTypeId = id);
              _saveState();
            },
          ),
        );

        steps.add(
          VehicleDetailsStep(
            isMoto: _selectedVehicleTypeId == 3,
            vehicleDetails: _vehicleDetails,
            onChanged: (details) {
              setState(() => _vehicleDetails = details);
              _saveState();
            },
          ),
        );
      }

      steps.add(
        BasicInfoStep(
          formKey: _basicInfoFormKey,
          nameController: _nameController,
          emailController: _emailController,
          passwordController: _passwordController,
          docController: _docController,
          phoneController: _phoneController,
          role: _isDriver ? 'driver' : (_isClient ? 'client' : 'provider'),
          onRoleToggle: () {},
          onValidationChanged: (isValidating, errors) {
            setState(() {
              _isValidatingData = isValidating;
              _fieldValidationErrors.addAll(errors);
            });
          },
        ),
      );

      if (!_isClient && !_isDriver && _selectedProfession != null) {
        final type = _selectedProfession!['service_type'] ?? 'standard';

        if (type == 'salon' || type == 'standard' || type == 'construction') {
          steps.add(
            SelectServicesStep(
              selectedServices: _customServices,
              professionId: _selectedProfession!['id'],
              professionName: _selectedProfession!['name'],
              onChanged: (services) {
                setState(() => _customServices = services);
                _saveState();
              },
            ),
          );
        }

        if (type == 'medical') {
          final profName =
              _selectedProfession?['name'].toString().toLowerCase() ?? '';
          final isDoctor =
              !profName.contains('psicólogo') &&
              !profName.contains('psicologo') &&
              !profName.contains('terapeuta');

          steps.add(
            MedicalServiceStep(
              isDoctor: isDoctor,
              initialPrice: _medicalPrice,
              initialHasReturn: _medicalHasReturn,
              onChanged: (price, hasReturn) {
                setState(() {
                  _medicalPrice = price;
                  _medicalHasReturn = hasReturn;
                });
                _saveState();
              },
            ),
          );
        }

        if (type == 'salon' || type == 'medical' || type == 'standard') {
          steps.add(
            ScheduleStep(
              schedule: _schedule,
              onChanged: (schedule) {
                setState(() => _schedule = schedule);
                _saveState();
              },
            ),
          );
        }
      }
    }

    return steps;
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
    _saveState();
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep--);
    _saveState();
  }

  Future<void> _submit() async {
    if (_passwordController.text.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A senha deve ter pelo menos 6 caracteres.'),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ApiService();

      String role = 'client';
      if (_isDriver) {
        role = 'driver';
      } else if (!_isClient) {
        role = 'provider';
      }

      final professionName = (_isClient || _isDriver)
          ? null
          : _selectedProfession?['name'];
      final docClean = _docController.text.replaceAll(RegExp(r'\D'), '');

      final authResponse = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {'full_name': _nameController.text.trim(), 'role': role},
      );

      final session = authResponse.session;
      if (session == null && authResponse.user != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor, confirme seu email para continuar.'),
            ),
          );
        }
        return;
      }

      if (session == null) throw Exception('Falha ao obter token do Supabase');

      await api.register(
        token: session.accessToken,
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        role: role,
        documentValue: docClean,
        documentType: docClean.length > 11 ? 'cnpj' : 'cpf',
        professions: professionName != null ? [professionName] : null,
        commercialName: _businessNameController.text.isNotEmpty
            ? _businessNameController.text
            : null,
        address: _addressController.text.isNotEmpty
            ? _addressController.text
            : null,
        latitude: _latitude,
        longitude: _longitude,
        vehicleTypeId: _selectedVehicleTypeId,
        vehicleBrand: _vehicleDetails['brand'],
        vehicleModel: _vehicleDetails['model'],
        vehicleYear: _vehicleDetails['year'],
        vehicleColor: _vehicleDetails['color'],
        vehicleColorHex: _vehicleDetails['color_hex'],
        vehiclePlate: _vehicleDetails['plate'],
        pixKey: _vehicleDetails['pix_key'],
      );

      if (!_isClient) {
        final List<Future> setupActions = [];

        final type = _selectedProfession?['service_type'];
        if (type == 'medical' && _customServices.isEmpty) {
          final profName =
              _selectedProfession?['name'].toString().toLowerCase() ?? '';
          final isPsychologist =
              profName.contains('psicólogo') ||
              profName.contains('psicologo') ||
              profName.contains('terapeuta');
          final duration = isPsychologist ? 45 : 30;

          _customServices.add({
            'name': 'Consulta',
            'description': 'Consulta com especialista',
            'price': _medicalPrice ?? 0.0,
            'duration': duration,
            'has_return': _medicalHasReturn ?? false,
          });
        }

        if (_schedule.isNotEmpty) {
          setupActions.add(api.saveProviderSchedule(_schedule.values.toList()));
        }

        if (_customServices.isNotEmpty) {
          for (final service in _customServices) {
            setupActions.add(api.saveProviderService(service));
          }
        }

        if (setupActions.isNotEmpty) {
          await Future.wait(setupActions).catchError((e) {
            debugPrint('Non-critical setup error: $e');
            return [];
          });
        }
      }

      if (mounted) {
        await _clearState();
        _redirectUserBasedOnRole();
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        if (errorMsg.contains('already exists') ||
            errorMsg.contains('já existe')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Este email ou documento já está cadastrado.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erro: $errorMsg')));
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _redirectUserBasedOnRole() {
    if (!mounted) return;

    final api = ApiService();
    final role = api.role;
    debugPrint('🚀 [Register] Redirecionando usuário com role: $role');

    if (role == 'driver') {
      ThemeService().setProviderMode(true);
      context.go('/uber-driver');
    } else if (role == 'provider') {
      ThemeService().setProviderMode(true);
      if (api.isMedical) {
        context.go('/medical-home');
      } else {
        context.go('/provider-home');
      }
    } else {
      ThemeService().setProviderMode(false);
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;

    if (_currentStep >= steps.length) {
      _currentStep = steps.length - 1;
    }

    final isLastStep = _currentStep == steps.length - 1;
    final progress = (_currentStep + 1) / steps.length;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep > 0) {
          _prevPage();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryYellow,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'Cadastro',
            style: GoogleFonts.manrope(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          iconTheme: IconThemeData(color: AppTheme.textDark),
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
            onPressed: () {
              if (_currentStep > 0) {
                _prevPage();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.black.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textDark),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: steps,
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed:
                            (_isLoading ||
                                _isValidatingData ||
                                _fieldValidationErrors.values.any(
                                  (e) => e != null,
                                ))
                            ? null
                            : () {
                                if (steps[_currentStep] is BasicInfoStep) {
                                  if (_basicInfoFormKey.currentState != null &&
                                      !_basicInfoFormKey.currentState!
                                          .validate()) {
                                    return;
                                  }
                                }
                                if (steps[_currentStep] is LocationStep) {
                                  if (_locationFormKey.currentState != null &&
                                      !_locationFormKey.currentState!
                                          .validate()) {
                                    return;
                                  }
                                }
                                if (steps[_currentStep] is IdentificationStep) {
                                  if (_identificationFormKey.currentState !=
                                          null &&
                                      !_identificationFormKey.currentState!
                                          .validate()) {
                                    return;
                                  }
                                }

                                if (steps[_currentStep] is ProfessionStep &&
                                    _selectedProfession == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Selecione sua profissão.'),
                                    ),
                                  );
                                  return;
                                }

                                if (steps[_currentStep]
                                        is VehicleSelectionStep &&
                                    _selectedVehicleTypeId == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Selecione o tipo de veículo.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                if (steps[_currentStep] is VehicleDetailsStep) {
                                  final brand = _vehicleDetails['brand'];
                                  final model = _vehicleDetails['model'];
                                  final color = _vehicleDetails['color'];
                                  final plate = _vehicleDetails['plate'];
                                  if (brand == null ||
                                      model == null ||
                                      color == null ||
                                      plate == null ||
                                      plate.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Preencha os dados do veículo.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                }

                                if (steps[_currentStep] is SelectServicesStep &&
                                    _customServices.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Selecione pelo menos um serviço.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                if (isLastStep) {
                                  _submit();
                                } else {
                                  _nextPage();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryYellow,
                          foregroundColor: AppTheme.textDark,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading || _isValidatingData
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isLastStep ? 'CONCLUIR CADASTRO' : 'PRÓXIMO',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
