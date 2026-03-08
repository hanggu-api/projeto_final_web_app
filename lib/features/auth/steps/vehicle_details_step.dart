import 'package:flutter/material.dart';
import '../data/vehicle_data.dart';
import '../../../core/theme/app_theme.dart';

class VehicleDetailsStep extends StatefulWidget {
  final bool isMoto;
  final Map<String, dynamic> vehicleDetails;
  final Function(Map<String, dynamic>) onChanged;

  const VehicleDetailsStep({
    super.key,
    required this.isMoto,
    required this.vehicleDetails,
    required this.onChanged,
  });

  @override
  State<VehicleDetailsStep> createState() => _VehicleDetailsStepState();
}

class _VehicleDetailsStepState extends State<VehicleDetailsStep> {
  late String? _selectedBrand;
  late String? _selectedModel;
  late int? _selectedYear;
  late Map<String, dynamic>? _selectedColor;
  late TextEditingController _plateController;
  late TextEditingController _pixKeyController;

  @override
  void initState() {
    super.initState();
    _selectedBrand = widget.vehicleDetails['brand'];
    _selectedModel = widget.vehicleDetails['model'];
    _selectedYear = widget.vehicleDetails['year'];
    _selectedColor = widget.vehicleDetails['color'] != null
        ? VehicleData.colors.firstWhere(
            (c) => c['name'] == widget.vehicleDetails['color'],
            orElse: () => VehicleData.colors.first,
          )
        : null;
    _plateController = TextEditingController(
      text: widget.vehicleDetails['plate'] ?? '',
    );
    _pixKeyController = TextEditingController(
      text: widget.vehicleDetails['pix_key'] ?? '',
    );
  }

  @override
  void dispose() {
    _plateController.dispose();
    _pixKeyController.dispose();
    super.dispose();
  }

  void _emitChange() {
    widget.onChanged({
      'brand': _selectedBrand,
      'model': _selectedModel,
      'year': _selectedYear,
      'color': _selectedColor?['name'],
      'color_hex': _selectedColor?['hex'],
      'plate': _plateController.text.toUpperCase(),
      'pix_key': _pixKeyController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final brands = VehicleData.getBrands(widget.isMoto);
    final models = _selectedBrand != null
        ? VehicleData.getModels(_selectedBrand!, widget.isMoto)
        : <String>[];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.isMoto ? 'Dados da Moto' : 'Dados do Carro',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Preencha os dados do seu veículo',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // ========== MARCA ==========
          _buildLabel('Marca'),
          const SizedBox(height: 6),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _selectedBrand ?? ''),
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return brands.keys;
              }
              return brands.keys.where(
                (b) => b.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ),
              );
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  return _buildTextField(
                    controller: controller,
                    focusNode: focusNode,
                    hint: 'Ex: Toyota, Honda...',
                    icon: Icons.business,
                  );
                },
            onSelected: (brand) {
              setState(() {
                _selectedBrand = brand;
                _selectedModel = null; // Reset model
              });
              _emitChange();
            },
            optionsViewBuilder: (context, onSelected, options) {
              return _buildOptionsView(options, onSelected);
            },
          ),
          const SizedBox(height: 18),

          // ========== MODELO ==========
          _buildLabel('Modelo'),
          const SizedBox(height: 6),
          Autocomplete<String>(
            key: ValueKey(_selectedBrand),
            initialValue: TextEditingValue(text: _selectedModel ?? ''),
            optionsBuilder: (textEditingValue) {
              if (models.isEmpty) return const Iterable.empty();
              if (textEditingValue.text.isEmpty) return models;
              return models.where(
                (m) => m.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ),
              );
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  return _buildTextField(
                    controller: controller,
                    focusNode: focusNode,
                    hint: _selectedBrand != null
                        ? 'Selecione o modelo'
                        : 'Selecione a marca primeiro',
                    icon: widget.isMoto
                        ? Icons.two_wheeler_outlined
                        : Icons.directions_car_outlined,
                    enabled: _selectedBrand != null,
                  );
                },
            onSelected: (model) {
              setState(() => _selectedModel = model);
              _emitChange();
            },
            optionsViewBuilder: (context, onSelected, options) {
              return _buildOptionsView(options, onSelected);
            },
          ),
          const SizedBox(height: 18),

          // ========== ANO ==========
          _buildLabel('Ano'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: _boxDecoration(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedYear,
                hint: const Text('Selecione o ano'),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down),
                items: VehicleData.years.map((year) {
                  return DropdownMenuItem(value: year, child: Text('$year'));
                }).toList(),
                onChanged: (year) {
                  setState(() => _selectedYear = year);
                  _emitChange();
                },
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ========== COR ==========
          _buildLabel('Cor'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: VehicleData.colors.map((color) {
              final isSelected = _selectedColor?['name'] == color['name'];
              final colorValue = Color(color['hex'] as int);
              final isBright = colorValue.computeLuminance() > 0.7;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedColor = color);
                  _emitChange();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: colorValue,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryYellow
                          : (isBright
                                ? Colors.grey.shade300
                                : Colors.transparent),
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: colorValue.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: isBright ? Colors.black : Colors.white,
                          size: 24,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
          if (_selectedColor != null) ...[
            const SizedBox(height: 8),
            Text(
              _selectedColor!['name'],
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 18),

          // ========== PLACA ==========
          _buildLabel('Placa'),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _plateController,
            hint: 'Ex: ABC-1D23',
            icon: Icons.badge_outlined,
            onChanged: (_) => _emitChange(),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 18),

          // ========== CHAVE PIX ==========
          _buildLabel('Chave PIX'),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _pixKeyController,
            hint: 'CPF, telefone, e-mail ou chave aleatória',
            icon: Icons.pix,
            onChanged: (_) => _emitChange(),
          ),
          const SizedBox(height: 8),
          Text(
            'Informe sua chave PIX para receber pagamentos diretamente.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    FocusNode? focusNode,
    bool enabled = true,
    Function(String)? onChanged,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Container(
      decoration: _boxDecoration(),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Icon(icon, color: AppTheme.primaryYellow, size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsView(
    Iterable<String> options,
    AutocompleteOnSelected<String> onSelected,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 340),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return ListTile(
                dense: true,
                title: Text(option, style: const TextStyle(fontSize: 15)),
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }
}
