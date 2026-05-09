import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../integrations/supabase/payment/supabase_payment_repository.dart';
import '../../../services/api_service.dart';

class WithdrawalDialog extends StatefulWidget {
  final ApiService api;
  final double currentBalance;
  const WithdrawalDialog({
    super.key,
    required this.api,
    required this.currentBalance,
  });

  @override
  State<WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<WithdrawalDialog> {
  final SupabasePaymentRepository _paymentRepository =
      SupabasePaymentRepository();
  final TextEditingController pixController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  bool isLoading = false;
  String? error;

  @override
  void dispose() {
    pixController.dispose();
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Solicitar Saque',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.wallet, color: Colors.orange),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saldo disponível',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      Text(
                        'R\$ ${widget.currentBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chave PIX',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pixController,
              decoration: InputDecoration(
                hintText: 'CPF, Email, Telefone ou Aleatória',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(LucideIcons.key),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Valor do saque',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CurrencyInputFormatter(),
              ],
              decoration: InputDecoration(
                prefixText: 'R\$ ',
                hintText: '0,00',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final pix = pixController.text.trim();
                        final amount = double.tryParse(
                          amountController.text
                              .replaceAll('.', '')
                              .replaceAll(',', '.'),
                        );

                        if (pix.isEmpty) {
                          setState(() => error = 'Digite sua chave PIX');
                          return;
                        }
                        if (amount == null || amount <= 0) {
                          setState(() => error = 'Digite um valor válido');
                          return;
                        }
                        if (amount > widget.currentBalance) {
                          setState(() => error = 'Saldo insuficiente');
                          return;
                        }

                        setState(() {
                          isLoading = true;
                          error = null;
                        });

                        try {
                          await _paymentRepository.requestWithdrawal(
                            amount: amount,
                          );
                          if (!mounted) return;
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (e) {
                          setState(() {
                            isLoading = false;
                            error = 'Erro ao solicitar saque: $e';
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryYellow,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                    : const Text(
                        'Solicitar Saque',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpecialtiesDialog extends StatefulWidget {
  final ApiService api;
  final List<String> availableProfessions;
  final List<String> currentSpecialties;
  final Function(String) onAdded;
  final Function(String) onRemoved;

  const SpecialtiesDialog({
    super.key,
    required this.api,
    required this.availableProfessions,
    required this.currentSpecialties,
    required this.onAdded,
    required this.onRemoved,
  });

  @override
  State<SpecialtiesDialog> createState() => _SpecialtiesDialogState();
}

class _SpecialtiesDialogState extends State<SpecialtiesDialog> {
  final TextEditingController searchController = TextEditingController();
  bool isAdding = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gerenciar Profissões'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        return const Iterable<String>.empty();
                      }
                      return widget.availableProfessions.where((String option) {
                        return option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        );
                      });
                    },
                    onSelected: (String selection) {
                      searchController.text = selection;
                      // Keep it simple, just set the value.
                    },
                    fieldViewBuilder:
                        (
                          BuildContext context,
                          TextEditingController fieldTextEditingController,
                          FocusNode fieldFocusNode,
                          VoidCallback onFieldSubmitted,
                        ) {
                          // Sync external controller if needed, but and use internal for adding
                          return TextField(
                            controller: fieldTextEditingController,
                            focusNode: fieldFocusNode,
                            enabled: !isAdding,
                            decoration: const InputDecoration(
                              hintText: 'Buscar profissão...',
                              isDense: true,
                            ),
                            onChanged: (val) => searchController.text = val,
                            onSubmitted: (val) {
                              onFieldSubmitted();
                            },
                          );
                        },
                  ),
                ),
                isAdding
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.add_circle,
                          color: AppTheme.primaryPurple,
                        ),
                        onPressed: () async {
                          final name = searchController.text.trim();
                          if (name.isNotEmpty) {
                            setState(() => isAdding = true);
                            try {
                              await widget.api.addProviderSpecialty(name);
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao adicionar profissão: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => isAdding = false);
                            }
                          }
                        },
                      ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.currentSpecialties.isEmpty)
              const Text(
                'Nenhuma profissão adicionada.',
                style: TextStyle(color: Colors.grey),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.currentSpecialties
                      .map(
                        (e) => Chip(
                          label: Text(e),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: isAdding
                              ? null
                              : () async {
                                  setState(() => isAdding = true);
                                  try {
                                    await widget.api.removeProviderSpecialty(e);
                                    if (!mounted) return;
                                    widget.onRemoved(e);
                                    setState(() {});
                                  } catch (err) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Erro ao remover'),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => isAdding = false);
                                    }
                                  }
                                },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isAdding ? null : () => Navigator.pop(context),
          child: const Text('Concluir'),
        ),
      ],
    );
  }
}

class EditProfileDialog extends StatefulWidget {
  final ApiService api;
  final String currentName;
  final String currentPhone;

  const EditProfileDialog({
    super.key,
    required this.api,
    required this.currentName,
    required this.currentPhone,
  });

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late TextEditingController nameController;
  late TextEditingController phoneController;
  bool isLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    phoneController = TextEditingController(text: widget.currentPhone);
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Perfil'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: AppTheme.inputDecoration(
              'Nome Completo',
              LucideIcons.user,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: AppTheme.inputDecoration('Telefone', LucideIcons.phone),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: isLoading
              ? null
              : () async {
                  setState(() {
                    isLoading = true;
                    error = null;
                  });
                  try {
                    await widget.api.updateProfile(
                      name: nameController.text.trim(),
                      phone: phoneController.text.trim(),
                    );
                    if (!mounted) return;
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    setState(() {
                      isLoading = false;
                      error = 'Erro ao atualizar: $e';
                    });
                  }
                },
          style: AppTheme.primaryActionButtonStyle(radius: 16, height: 48),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

class EditBusinessDialog extends StatefulWidget {
  final ApiService api;
  final String currentCommercialName;
  final String currentAddress;

  const EditBusinessDialog({
    super.key,
    required this.api,
    required this.currentCommercialName,
    required this.currentAddress,
  });

  @override
  State<EditBusinessDialog> createState() => _EditBusinessDialogState();
}

class _EditBusinessDialogState extends State<EditBusinessDialog> {
  late TextEditingController commercialNameController;
  late TextEditingController addressController;
  bool isLoading = false;
  bool isResolvingLocation = false;
  String? error;

  @override
  void initState() {
    super.initState();
    commercialNameController = TextEditingController(
      text: widget.currentCommercialName,
    );
    addressController = TextEditingController(text: widget.currentAddress);
  }

  String _formatReadableAddressFromMap(Map<String, dynamic> data) {
    final displayName = (data['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;

    final parts = <String>[
      if ((data['street'] ?? '').toString().trim().isNotEmpty)
        (data['street']).toString().trim(),
      if ((data['house_number'] ?? '').toString().trim().isNotEmpty)
        (data['house_number']).toString().trim(),
      if ((data['neighborhood'] ??
              data['suburb'] ??
              data['neighbourhood'] ??
              '')
          .toString()
          .trim()
          .isNotEmpty)
        (data['neighborhood'] ?? data['suburb'] ?? data['neighbourhood'])
            .toString()
            .trim(),
      if ((data['city'] ?? '').toString().trim().isNotEmpty)
        (data['city']).toString().trim(),
      if ((data['state_code'] ?? data['state'] ?? '')
          .toString()
          .trim()
          .isNotEmpty)
        (data['state_code'] ?? data['state']).toString().trim(),
    ];

    return parts.join(', ').trim();
  }

  @override
  void dispose() {
    commercialNameController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Estabelecimento'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: commercialNameController,
            decoration: AppTheme.inputDecoration(
              'Nome do estabelecimento',
              LucideIcons.store,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: addressController,
            minLines: 2,
            maxLines: 3,
            decoration: AppTheme.inputDecoration(
              'Endereço',
              LucideIcons.mapPin,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: isLoading || isResolvingLocation
                  ? null
                  : _useCurrentLocation,
              icon: isResolvingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.locateFixed, size: 16),
              label: Text(
                isResolvingLocation
                    ? 'Obtendo localização...'
                    : 'Usar minha localização atual',
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: isLoading
              ? null
              : () async {
                  setState(() {
                    isLoading = true;
                    error = null;
                  });
                  try {
                    await widget.api.updateProviderProfile(
                      commercialName: commercialNameController.text.trim(),
                      address: addressController.text.trim(),
                    );
                    if (!mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    setState(() {
                      isLoading = false;
                      error = 'Erro ao atualizar: $e';
                    });
                  }
                },
          style: AppTheme.primaryActionButtonStyle(radius: 16, height: 48),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      isResolvingLocation = true;
      error = null;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permissão de localização não concedida.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String resolvedAddress = '';

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = <String>[
            if ((place.street ?? '').trim().isNotEmpty)
              (place.street ?? '').trim(),
            if ((place.subLocality ?? '').trim().isNotEmpty)
              (place.subLocality ?? '').trim(),
            if ((place.locality ?? '').trim().isNotEmpty)
              (place.locality ?? '').trim(),
            if ((place.administrativeArea ?? '').trim().isNotEmpty)
              (place.administrativeArea ?? '').trim(),
          ];
          resolvedAddress = parts.join(' - ').trim();
        }
      } catch (_) {
        // Fallback tratado abaixo com reverseGeocode do ApiService.
      }

      if (resolvedAddress.isEmpty) {
        final reverse = await widget.api.reverseGeocode(
          position.latitude,
          position.longitude,
        );
        resolvedAddress = _formatReadableAddressFromMap(reverse);
      }

      if (resolvedAddress.isEmpty) {
        resolvedAddress =
            'Loc.: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      }

      if (!mounted) return;
      setState(() {
        addressController.text = resolvedAddress;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Não foi possível usar a localização atual: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          isResolvingLocation = false;
        });
      }
    }
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.selection.baseOffset == 0) {
      return newValue;
    }

    try {
      double value = double.parse(newValue.text);
      final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: '');
      String newText = formatter.format(value / 100);

      return newValue.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    } catch (_) {
      return oldValue;
    }
  }
}
