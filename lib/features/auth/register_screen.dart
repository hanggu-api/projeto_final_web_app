import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/fixed_schedule_gate.dart';
import '../../services/api_service.dart';
import '../../services/theme_service.dart';
import '../../integrations/supabase/auth/supabase_auth_repository.dart';

import 'steps/basic_info_step.dart';
import 'steps/identification_step.dart';
import 'steps/location_step.dart';
import 'steps/medical_service_step.dart';
import 'steps/profession_step.dart';
import 'steps/schedule_step.dart';
import 'steps/select_services_step.dart';
import 'steps/facial_liveness_step.dart';

class RegisterScreen extends StatefulWidget {
  final String? initialRole;
  const RegisterScreen({super.key, this.initialRole});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isValidatingData = false;
  final Map<String, String?> _fieldValidationErrors = {};

  // Data
  Map<String, dynamic>? _selectedProfession;
  bool _isClient = false;
  String? _subRole;
  Map<String, dynamic> _verificationData = {};

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _docController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _botBirthDateController = TextEditingController();
  final _botMotherNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();
  double? _latitude;
  double? _longitude;

  final _basicInfoFormKey = GlobalKey<FormState>();
  final _locationFormKey = GlobalKey<FormState>();
  final _identificationFormKey = GlobalKey<FormState>();

  bool _basicInfoStepValid = false;

  Map<int, Map<String, dynamic>> _schedule = {};
  List<Map<String, dynamic>> _customServices = [];

  double? _medicalPrice;
  bool? _medicalHasReturn;

  String _effectiveProviderSubRole() {
    if (_isClient) return 'seeker';

    final forceFixedProvider =
        (_selectedProfession != null &&
            isCanonicalFixedServiceRecord(_selectedProfession!)) ||
        ({'salon', 'beauty', 'fixed'}.contains(
          (_selectedProfession?['service_type'] ?? '')
              .toString()
              .trim()
              .toLowerCase(),
        ));
    if (forceFixedProvider) return 'fixed';

    final current = (_subRole ?? '').trim().toLowerCase();
    return current == 'fixed' ? 'fixed' : 'mobile';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Define o papel inicial imediatamente para evitar build incorreto
    // Se não houver initialRole, o padrão será 'provider' (false) até que o loadState decida.
    if (widget.initialRole == 'client') {
      _isClient = true;
    } else if (widget.initialRole == 'provider') {
      _isClient = false;
    }

    _loadState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _docController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _botBirthDateController.dispose();
    _botMotherNameController.dispose();
    _businessNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveState();
    }
  }

  static const _secureStorage = FlutterSecureStorage();

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('register_step', _currentStep);
    await prefs.setBool('register_is_client', _isClient);
    await prefs.setString('register_sub_role', _subRole ?? '');
    await prefs.setString('register_birth_date', _birthDateController.text);

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
    await _secureStorage.write(
      key: 'register_password',
      value: _passwordController.text,
    );
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
    await prefs.setString(
      'register_verification_data',
      jsonEncode(_verificationData),
    );

    if (_medicalPrice != null)
      await prefs.setDouble('register_medical_price', _medicalPrice!);
    if (_medicalHasReturn != null)
      await prefs.setBool('register_medical_return', _medicalHasReturn!);
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final bool? savedIsClient = prefs.getBool('register_is_client');

    // O initialRole do widget sempre tem prioridade sobre o cache.
    // Isso garante que clicar em "Prestador" nunca abre o fluxo de "Cliente" e vice-versa.
    if (widget.initialRole != null) {
      final bool targetIsClient = widget.initialRole == 'client';
      if (savedIsClient != null && targetIsClient != savedIsClient) {
        // Cache de um fluxo diferente — reseta tudo
        debugPrint(
          '🔄 Role alterado (${savedIsClient ? "client" : "provider"} → ${targetIsClient ? "client" : "provider"}). Resetando fluxo.',
        );
        await _clearState();
        if (mounted) {
          setState(() {
            _isClient = targetIsClient;
            _currentStep = 0;
          });
        }
        return;
      }
      // Mesmo role ou sem cache: usa sempre o initialRole para garantir sincronia
      if (mounted) {
        setState(() {
          _isClient = targetIsClient;
        });
      }
    } else if (savedIsClient != null) {
      // Se não há initialRole vindo da navegação, usa o que está no cache
      if (mounted) {
        setState(() {
          _isClient = savedIsClient;
        });
      }
    }

    setState(() {
      _currentStep = prefs.getInt('register_step') ?? 0;
      _subRole = prefs.getString('register_sub_role');
      _birthDateController.text = prefs.getString('register_birth_date') ?? '';

      final profString = prefs.getString('register_profession');
      if (profString != null) {
        _selectedProfession = jsonDecode(profString);
      }

      _nameController.text = prefs.getString('register_name') ?? '';
      _emailController.text = prefs.getString('register_email') ?? '';
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

      final verificationString = prefs.getString('register_verification_data');
      if (verificationString != null && verificationString.trim().isNotEmpty) {
        _verificationData = Map<String, dynamic>.from(
          jsonDecode(verificationString),
        );
      }

      _medicalPrice = prefs.getDouble('register_medical_price');
      _medicalHasReturn = prefs.getBool('register_medical_return');
    });

    final savedPassword = await _secureStorage.read(key: 'register_password');
    if (savedPassword != null && mounted) {
      _passwordController.text = savedPassword;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentStep);
      }
    });
  }

  Future<void> _clearState() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      'register_step',
      'register_is_client',
      'register_profession',
      'register_name',
      'register_email',
      'register_doc',
      'register_phone',
      'register_business_name',
      'register_address',
      'register_lat',
      'register_lng',
      'register_schedule',
      'register_services',
      'register_medical_price',
      'register_medical_return',
      'register_sub_role',
      'register_birth_date',
      'register_verification_data',
    ];
    for (var key in keys) {
      await prefs.remove(key);
    }
    await _secureStorage.delete(key: 'register_password');
  }

  List<Widget> get _steps {
    final steps = <Widget>[];

    if (!_isClient) {
      steps.add(
        FacialLivenessStep(
          verificationData: _verificationData,
          onSubmit: _submit,
          onChanged: (data) {
            setState(() => _verificationData = data);
            _saveState();
          },
        ),
      );

      steps.add(
        ProfessionStep(
          selectedProfession: _selectedProfession,
          onSelect: (prof) {
            setState(() {
              _selectedProfession = {
                ...prof,
                'id': prof['id']?.toString(),
                'name': prof['name']?.toString() ?? '',
                'service_type': prof['service_type']?.toString() ?? 'standard',
              };
            });
            _saveState();
            _nextPage();
          },
        ),
      );
    }

    // INFORMAÇÕES BÁSICAS (Comum a todos)
    steps.add(
      BasicInfoStep(
        formKey: _basicInfoFormKey,
        nameController: _nameController,
        emailController: _emailController,
        passwordController: _passwordController,
        confirmPasswordController: _confirmPasswordController,
        docController: _docController,
        phoneController: _phoneController,
        botBirthDateController: _botBirthDateController,
        botMotherNameController: _botMotherNameController,
        birthDateController: _birthDateController,
        role: _isClient ? 'client' : 'provider',
        subRole: _subRole,
        onSubRoleChanged: (val) {
          setState(() => _subRole = val);
          _saveState();
        },
        onValidationChanged: (isValidating, errors) {
          setState(() {
            _isValidatingData = isValidating;
            _fieldValidationErrors.addAll(errors);
            _basicInfoStepValid = errors['__basic_info_step_valid'] == 'true';
          });
        },
      ),
    );

    // Passos adicionais apenas para PRESTADOR
    if (!_isClient) {
      bool isSalonFlow = false;
      if (_selectedProfession != null) {
        final profType =
            _selectedProfession?['service_type']?.toString().toLowerCase() ??
            '';
        isSalonFlow =
            profType == 'salon' ||
            profType == 'beauty' ||
            isCanonicalFixedServiceRecord(_selectedProfession!);
      }

      if (isSalonFlow) {
        steps.add(
          ScheduleStep(
            schedule: _schedule,
            onChanged: (s) {
              setState(() => _schedule = s);
              _saveState();
            },
          ),
        );
        steps.add(
          LocationStep(
            formKey: _locationFormKey,
            addressController: _addressController,
            isMobileProvider: _effectiveProviderSubRole() == 'mobile',
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
            onChanged: (s) {
              setState(() => _customServices = s);
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
            confirmPasswordController: _confirmPasswordController,
            onValidationChanged: (isValidating, errors) {
              setState(() {
                _isValidatingData = isValidating;
                _fieldValidationErrors.addAll(errors);
              });
            },
          ),
        );
      } else if (_selectedProfession != null) {
        steps.add(
          LocationStep(
            formKey: _locationFormKey,
            addressController: _addressController,
            isMobileProvider: _effectiveProviderSubRole() == 'mobile',
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

        final type = _selectedProfession!['service_type'] ?? 'standard';
        if (type == 'medical') {
          steps.add(
            MedicalServiceStep(
              isDoctor: !(_selectedProfession?['name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains('psicolo'),
              initialPrice: _medicalPrice,
              initialHasReturn: _medicalHasReturn,
              onChanged: (p, r) {
                setState(() {
                  _medicalPrice = p;
                  _medicalHasReturn = r;
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
              onChanged: (s) {
                setState(() => _schedule = s);
                _saveState();
              },
            ),
          );
        }
      }
    }

    return steps;
  }

  IconData _stepIcon(Widget step) {
    if (step is FacialLivenessStep) return LucideIcons.scanFace;
    if (step is ProfessionStep) return LucideIcons.briefcase;
    if (step is BasicInfoStep) return LucideIcons.user;
    if (step is ScheduleStep) return LucideIcons.calendarDays;
    if (step is LocationStep) return LucideIcons.mapPin;
    if (step is SelectServicesStep) return LucideIcons.listChecks;
    if (step is IdentificationStep) return LucideIcons.badgeCheck;
    if (step is MedicalServiceStep) return LucideIcons.stethoscope;
    return LucideIcons.circle;
  }

  String _stepLabel(Widget step) {
    if (step is FacialLivenessStep) return 'Vida';
    if (step is ProfessionStep) return 'Profissão';
    if (step is BasicInfoStep) return 'Dados';
    if (step is ScheduleStep) return 'Agenda';
    if (step is LocationStep) return 'Local';
    if (step is SelectServicesStep) return 'Serviços';
    if (step is IdentificationStep) return 'Empresa';
    if (step is MedicalServiceStep) return 'Atendimento';
    return 'Etapa';
  }

  Widget _buildStepIndicator(List<Widget> steps) {
    return Container(
      color: AppTheme.primaryYellow,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              _buildStepIndicatorItem(
                icon: _stepIcon(steps[index]),
                label: _stepLabel(steps[index]),
                isActive: index == _currentStep,
                isCompleted: index < _currentStep,
              ),
              if (index < steps.length - 1)
                Container(
                  width: 24,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 20),
                  color: index < _currentStep
                      ? AppTheme.textDark
                      : AppTheme.textDark.withOpacity(0.16),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicatorItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isCompleted,
  }) {
    final foreground = isActive || isCompleted
        ? Colors.white
        : AppTheme.textDark;
    final background = isActive || isCompleted
        ? AppTheme.textDark
        : Colors.white.withOpacity(0.42);

    return SizedBox(
      width: 66,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isActive ? 36 : 32,
            height: isActive ? 36 : 32,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? AppTheme.textDark
                    : AppTheme.textDark.withOpacity(0.18),
                width: isActive ? 2 : 1,
              ),
            ),
            child: Icon(
              isCompleted ? LucideIcons.check : icon,
              size: isActive ? 18 : 16,
              color: foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  void _nextPage() {
    final total = _steps.length;
    if (_currentStep >= total - 1) return;
    setState(() => _currentStep++);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    _saveState();
  }

  void _prevPage() {
    if (_currentStep <= 0) return;
    setState(() => _currentStep--);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    _saveState();
  }

  String? _birthDateIso() {
    final raw = _birthDateController.text.trim();
    if (raw.isEmpty) return null;
    final parts = raw.split('/');
    if (parts.length == 3)
      return '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
    return null;
  }

  Future<void> _submit() async {
    if (_botBirthDateController.text.trim().isNotEmpty ||
        _botMotherNameController.text.trim().isNotEmpty)
      return;
    if (_confirmPasswordController.text != _passwordController.text) return;
    if (!_isClient && _verificationData['liveness_validated'] != true) return;

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      String role = _isClient ? 'client' : 'provider';
      final professionName = _isClient ? null : _selectedProfession?['name'];
      final docClean = _docController.text.replaceAll(RegExp(r'\D'), '');

      await SupabaseAuthRepository().signUpOrSignIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        role: role,
      );
      if (!mounted) return;

      await api.register(
        token: '',
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        role: role,
        subRole: _effectiveProviderSubRole(),
        documentValue: docClean,
        documentType: docClean.length > 11 ? 'cnpj' : 'cpf',
        birthDate: _birthDateIso(),
        professions: professionName != null ? [professionName] : null,
        commercialName: _businessNameController.text.isNotEmpty
            ? _businessNameController.text
            : null,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : (role == 'provider' ? 'Imperatriz - MA' : null),
        latitude: _latitude ?? (role == 'provider' ? -5.5265 : null),
        longitude: _longitude ?? (role == 'provider' ? -47.4761 : null),
        metadata: _verificationData,
      );
      if (!mounted) return;

      if (!_isClient) {
        if (_schedule.isNotEmpty)
          await api.saveProviderSchedule(_schedule.values.toList());
        if (!mounted) return;
        if (_customServices.isNotEmpty) {
          for (final s in _customServices) await api.saveProviderService(s);
          if (!mounted) return;
        }
      }

      if (!mounted) return;
      await _clearState();
      if (!mounted) return;
      await _redirectUserBasedOnRole();
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Erro ao concluir cadastro.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _redirectUserBasedOnRole() async {
    if (!mounted) return;
    final api = ApiService();
    if (api.role == 'provider') {
      ThemeService().setProviderMode(true);
      context.go(api.isMedical ? '/medical-home' : '/provider-home');
    } else {
      ThemeService().setProviderMode(false);
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (_currentStep >= steps.length) _currentStep = steps.length - 1;

    final isLastStep = _currentStep == steps.length - 1;
    final isProfessionStep = steps[_currentStep] is ProfessionStep;
    final progress = (_currentStep + 1) / steps.length;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep > 0) _prevPage();
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
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
            onPressed: () =>
                _currentStep > 0 ? _prevPage() : Navigator.of(context).pop(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(82),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStepIndicator(steps),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.black.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textDark),
                ),
              ],
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
              if (!isProfessionStep &&
                  steps[_currentStep] is! FacialLivenessStep)
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isValidatingData)
                          ? null
                          : () {
                              final s = steps[_currentStep];
                              if (s is BasicInfoStep) {
                                if (!(_basicInfoFormKey.currentState
                                        ?.validate() ??
                                    false))
                                  return;
                                if (!_basicInfoStepValid) return;
                              }
                              if (isLastStep)
                                _submit();
                              else
                                _nextPage();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}
