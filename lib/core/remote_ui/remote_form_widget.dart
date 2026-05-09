import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domains/remote_ui/models/remote_action.dart';
import '../../domains/remote_ui/models/remote_component.dart';
import '../../domains/remote_ui/presentation/remote_screen_providers.dart';
import '../theme/app_theme.dart';

class RemoteFormWidget extends ConsumerStatefulWidget {
  const RemoteFormWidget({
    super.key,
    required this.component,
    required this.childrenBuilder,
  });

  final RemoteComponent component;
  final Widget Function(
    RemoteComponent child,
    BuildContext context,
    WidgetRef ref,
  )
  childrenBuilder;

  @override
  ConsumerState<RemoteFormWidget> createState() => _RemoteFormWidgetState();
}

class _RemoteFormWidgetState extends ConsumerState<RemoteFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _readString(widget.component.props['title']);
    final submitLabel = _readString(
      widget.component.props['submit_label'],
      fallback: 'Enviar',
    );
    final action = widget.component.action;

    return Container(
      width: double.infinity,
      margin: _readEdgeInsets(widget.component.props['margin']),
      padding: _readEdgeInsets(
        widget.component.props['padding'],
      ).add(const EdgeInsets.all(18)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAECEF)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
            if (title.isNotEmpty) const SizedBox(height: 14),
            ...widget.component.children.map(
              (child) => _buildFieldAwareChild(child),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _submit(action),
                  style: AppTheme.primaryActionButtonStyle(),
                  child: Text(submitLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFieldAwareChild(RemoteComponent child) {
    if (child.type == 'input') {
      return _buildInputField(child);
    }
    if (child.type == 'field_group') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: child.children.map(_buildFieldAwareChild).toList(),
      );
    }
    return widget.childrenBuilder(child, context, ref);
  }

  Widget _buildInputField(RemoteComponent component) {
    final fieldKey = _readString(component.props['field_key']);
    final label = _readString(component.props['label']);
    final hint = _readString(component.props['hint']);
    final requiredField = _readBool(component.props['required']);
    final initialValue = _readString(component.props['initial_value']);

    final controller = _controllers.putIfAbsent(
      fieldKey,
      () => TextEditingController(text: initialValue),
    );

    return Padding(
      padding: _readEdgeInsets(
        component.props['padding'],
      ).add(const EdgeInsets.only(bottom: 12)),
      child: TextFormField(
        controller: controller,
        minLines: _readBool(component.props['multiline']) ? 3 : 1,
        maxLines: _readBool(component.props['multiline']) ? 5 : 1,
        decoration: InputDecoration(
          labelText: label.isEmpty ? null : label,
          hintText: hint.isEmpty ? null : hint,
          border: const OutlineInputBorder(),
        ),
        validator: requiredField
            ? (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Campo obrigatório';
                }
                return null;
              }
            : null,
      ),
    );
  }

  Future<void> _submit(RemoteAction action) async {
    if (!_formKey.currentState!.validate()) return;
    final values = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      values[entry.key] = entry.value.text.trim();
    }

    final mergedAction = RemoteAction(
      type: action.type,
      commandKey: action.commandKey,
      routeKey: action.routeKey,
      linkKey: action.linkKey,
      message: action.message,
      nativeFlowKey: action.nativeFlowKey,
      arguments: {
        ...action.arguments,
        'form_values': values,
      },
    );

    await ref
        .read(executeRemoteActionUseCaseProvider)
        .execute(mergedAction, context);
  }

  static String _readString(dynamic raw, {String fallback = ''}) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  static EdgeInsets _readEdgeInsets(dynamic raw) {
    if (raw is num) {
      return EdgeInsets.all(raw.toDouble());
    }
    if (raw is List && raw.length == 4) {
      return EdgeInsets.fromLTRB(
        _readDouble(raw[0], 0),
        _readDouble(raw[1], 0),
        _readDouble(raw[2], 0),
        _readDouble(raw[3], 0),
      );
    }
    return EdgeInsets.zero;
  }

  static double _readDouble(dynamic raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static bool _readBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = raw?.toString().trim().toLowerCase();
    return text == 'true' || text == '1';
  }
}
