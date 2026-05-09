import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domains/remote_ui/models/remote_action.dart';
import '../../domains/remote_ui/models/remote_component.dart';
import '../../domains/remote_ui/presentation/remote_screen_providers.dart';
import '../theme/app_theme.dart';
import 'icon_key_resolver.dart';
import 'remote_form_widget.dart';

class RemoteComponentRenderer {
  const RemoteComponentRenderer({this.screenKey});

  final String? screenKey;

  Widget render(
    RemoteComponent component,
    BuildContext context,
    WidgetRef ref,
  ) {
    switch (component.type) {
      case 'text':
        return _buildText(component);
      case 'rich_text':
        return _buildRichText(component);
      case 'image':
        return _buildImage(component);
      case 'button':
        return _buildButton(component, context, ref);
      case 'section':
        return _buildSection(component, context, ref);
      case 'card':
        return _buildCard(component, context, ref);
      case 'list':
        return _buildList(component);
      case 'banner':
        return _buildBanner(component, context, ref);
      case 'badge':
        return _buildBadge(component);
      case 'status_block':
        return _buildStatusBlock(component, context, ref);
      case 'warning_card':
        return _buildInfoCard(
          component,
          backgroundColor: const Color(0xFFFFF7E8),
          borderColor: const Color(0xFFE8C777),
          iconColor: const Color(0xFF8A5A00),
        );
      case 'info_card':
        return _buildInfoCard(
          component,
          backgroundColor: const Color(0xFFF5F8FF),
          borderColor: const Color(0xFFB8CCFF),
          iconColor: AppTheme.primaryBlue,
        );
      case 'amount_card':
        return _buildAmountCard(component);
      case 'timeline_step':
        return _buildTimelineStep(component);
      case 'form':
        return RemoteFormWidget(
          component: component,
          childrenBuilder: render,
        );
      case 'field_group':
        return _buildFieldGroup(component, context, ref);
      case 'input':
        return const SizedBox.shrink();
      case 'spacer':
        return SizedBox(height: _readDouble(component.props['height'], 16));
      case 'divider':
        return const Divider(height: 1);
      case 'dialog':
      case 'bottom_sheet':
        return _buildCard(component, context, ref);
      case 'stack':
        return Stack(
          children: component.children
              .map((child) => render(child, context, ref))
              .toList(),
        );
      case 'row':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: component.children
              .map((child) => Expanded(child: render(child, context, ref)))
              .toList(),
        );
      case 'column':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: component.children
              .map((child) => render(child, context, ref))
              .toList(),
        );
      default:
        debugPrint(
          '⚠️ [RemoteUI] Unsupported component type: ${component.type}',
        );
        return const SizedBox.shrink();
    }
  }

  Widget _buildText(RemoteComponent component) {
    final value = _readString(component.props['value']);
    final align = _readTextAlign(component.props['align']);
    return Padding(
      padding: _readEdgeInsets(component.props['padding']),
      child: Text(
        value,
        textAlign: align,
        style: TextStyle(
          color: _readColor(component.props['color']) ?? AppTheme.textDark,
          fontSize: _readDouble(component.props['size'], 14),
          fontWeight: _readFontWeight(component.props['weight']),
          height: _readDouble(component.props['height'], 1.3),
        ),
      ),
    );
  }

  Widget _buildRichText(RemoteComponent component) {
    final title = _readString(component.props['title']);
    final subtitle = _readString(component.props['subtitle']);
    return Padding(
      padding: _readEdgeInsets(component.props['padding']),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                fontSize: _readDouble(component.props['title_size'], 18),
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          if (subtitle.isNotEmpty) const SizedBox(height: 6),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: _readDouble(component.props['subtitle_size'], 14),
                color: AppTheme.textMuted,
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(RemoteComponent component) {
    final url = _readString(component.props['url']);
    final radius = _readDouble(component.props['border_radius'], 20);
    final height = _readDouble(component.props['height'], 180);
    return Padding(
      padding: _readEdgeInsets(component.props['padding']),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: url.isEmpty
            ? Container(height: height, color: Colors.grey.shade200)
            : Image.network(
                url,
                fit: BoxFit.cover,
                height: height,
                width: double.infinity,
              ),
      ),
    );
  }

  Widget _buildButton(
    RemoteComponent component,
    BuildContext context,
    WidgetRef ref,
  ) {
    final label = _readString(component.props['label']);
    final isPrimary =
        _readString(component.props['style'], fallback: 'primary') == 'primary';
    final iconKey = _readString(component.props['icon_key']);
    final action = component.action;

    return Padding(
      padding: _readEdgeInsets(component.props['padding']),
      child: SizedBox(
        width: double.infinity,
        child: isPrimary
            ? ElevatedButton.icon(
                onPressed: action == null
                    ? null
                    : () => _executeAction(
                        action,
                        context,
                        ref,
                        componentId: component.id,
                      ),
                style: AppTheme.primaryActionButtonStyle(),
                icon: Icon(IconKeyResolver.resolve(iconKey), size: 18),
                label: Text(label),
              )
            : OutlinedButton.icon(
                onPressed: action == null
                    ? null
                    : () => _executeAction(
                        action,
                        context,
                        ref,
                        componentId: component.id,
                      ),
                style: AppTheme.secondaryActionButtonStyle(),
                icon: Icon(IconKeyResolver.resolve(iconKey), size: 18),
                label: Text(label),
              ),
      ),
    );
  }

  Widget _buildSection(
    RemoteComponent component,
    BuildContext context,
    WidgetRef ref,
  ) {
    final title = _readString(component.props['title']);
    final subtitle = _readString(component.props['subtitle']);
    final eyebrow = _readString(component.props['eyebrow']);
    final children = component.children
        .map((child) => render(child, context, ref))
        .toList();

    return Container(
      width: double.infinity,
      margin: _readEdgeInsets(component.props['margin']),
      padding: _readEdgeInsets(
        component.props['padding'],
      ).add(const EdgeInsets.all(20)),
      decoration: BoxDecoration(
        color: _readColor(component.props['background_color']) ?? Colors.white,
        borderRadius: BorderRadius.circular(
          _readDouble(component.props['border_radius'], 24),
        ),
        border: Border.all(
          color:
              _readColor(component.props['border_color']) ??
              const Color(0xFFEAECEF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F5F7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (eyebrow.isNotEmpty) const SizedBox(height: 12),
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
          if (subtitle.isNotEmpty) const SizedBox(height: 8),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppTheme.textMuted,
              ),
            ),
          if (children.isNotEmpty) const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCard(
    RemoteComponent component,
    BuildContext context,
    WidgetRef ref,
  ) {
    final title = _readString(component.props['title']);
    final subtitle = _readString(component.props['subtitle']);
    final footnote = _readString(component.props['footnote']);
    final imageUrl = _readString(component.props['image_url']);
    final actionLabel = _readString(component.props['action_label']);
    final iconKey = _readString(component.props['icon_key']);

    return Container(
      width: double.infinity,
      margin: _readEdgeInsets(
        component.props['margin'],
      ).add(const EdgeInsets.only(bottom: 12)),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _readColor(component.props['background_color']) ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                height: 148,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          if (imageUrl.isNotEmpty) const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8E7C2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  IconKeyResolver.resolve(iconKey),
                  size: 20,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    if (subtitle.isNotEmpty) const SizedBox(height: 6),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppTheme.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (footnote.isNotEmpty) const SizedBox(height: 10),
          if (footnote.isNotEmpty)
            Text(
              footnote,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted.withValues(alpha: 0.9),
              ),
            ),
          if (component.children.isNotEmpty) const SizedBox(height: 12),
          ...component.children.map((child) => render(child, context, ref)),
          if (actionLabel.isNotEmpty && component.action != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    _executeAction(
                      component.action!,
                      context,
                      ref,
                      componentId: component.id,
                    ),
                style: AppTheme.primaryActionButtonStyle(),
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(RemoteComponent component) {
    final items = _readStringList(component.props['items']);
    final style = _readString(component.props['style'], fallback: 'chips');
    if (items.isEmpty) return const SizedBox.shrink();

    if (style == 'bullets') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F5F7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildBanner(
    RemoteComponent component,
    BuildContext context,
    WidgetRef ref,
  ) {
    final eyebrow = _readString(component.props['eyebrow']);
    final title = _readString(component.props['title']);
    final subtitle = _readString(component.props['subtitle']);
    final imageUrl = _readString(component.props['image_url']);
    final highlights = _readStringList(component.props['highlights']);
    final primaryAction = _readAction(component.props['primary_action']);
    final secondaryAction = _readAction(component.props['secondary_action']);
    final primaryLabel = _readString(
      _readMap(component.props['primary_action'])['label'],
    );
    final secondaryLabel = _readString(
      _readMap(component.props['secondary_action'])['label'],
    );

    return Container(
      width: double.infinity,
      margin: _readEdgeInsets(component.props['margin']),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: imageUrl.isEmpty
                ? Container(height: 220, color: AppTheme.primaryYellow)
                : Image.network(
                    imageUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
          ),
          Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  const Color(0xFF0D1B2A).withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (eyebrow.isNotEmpty) const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle.isNotEmpty) const SizedBox(height: 6),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                if (highlights.isNotEmpty) const SizedBox(height: 12),
                if (highlights.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: highlights
                        .map(
                          (item) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                if ((primaryAction != null && primaryLabel.isNotEmpty) ||
                    (secondaryAction != null && secondaryLabel.isNotEmpty))
                  const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (primaryAction != null && primaryLabel.isNotEmpty)
                      ElevatedButton(
                        onPressed: () =>
                            _executeAction(
                              primaryAction,
                              context,
                              ref,
                              componentId: component.id,
                            ),
                        style: AppTheme.primaryActionButtonStyle(),
                        child: Text(primaryLabel),
                      ),
                    if (secondaryAction != null && secondaryLabel.isNotEmpty)
                      OutlinedButton(
                        onPressed: () =>
                            _executeAction(
                              secondaryAction,
                              context,
                              ref,
                              componentId: component.id,
                            ),
                        style: AppTheme.secondaryActionButtonStyle(),
                        child: Text(
                          secondaryLabel,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(RemoteComponent component) {
    final label = _readString(component.props['label']);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: _readEdgeInsets(component.props['margin']),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _readColor(component.props['background_color']) ??
            const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: _readDouble(component.props['size'], 12),
          fontWeight: _readFontWeight(
            component.props['weight'] ?? 'w800',
          ),
          color: _readColor(component.props['color']) ?? AppTheme.textDark,
        ),
      ),
    );
  }

  Widget _buildStatusBlock(
    RemoteComponent component,
    BuildContext context,
    WidgetRef ref,
  ) {
    final title = _readString(component.props['title']);
    final value = _readString(component.props['value']);
    final subtitle = _readString(component.props['subtitle']);
    final status = _readString(component.props['status']);
    final actionLabel = _readString(component.props['action_label']);

    return Container(
      width: double.infinity,
      margin: _readEdgeInsets(
        component.props['margin'],
      ).add(const EdgeInsets.only(bottom: 12)),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _readColor(component.props['background_color']) ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _readColor(component.props['border_color']) ??
              const Color(0xFFEAECEF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status.isNotEmpty)
            _buildBadge(
              RemoteComponent(
                id: '${component.id}_status',
                type: 'badge',
                props: {
                  'label': status,
                  'background_color': component.props['status_background_color'],
                  'color': component.props['status_color'],
                },
              ),
            ),
          if (status.isNotEmpty) const SizedBox(height: 10),
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
          if (value.isNotEmpty) const SizedBox(height: 6),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(
                fontSize: _readDouble(component.props['value_size'], 26),
                fontWeight: FontWeight.w900,
                color: _readColor(component.props['value_color']) ??
                    AppTheme.textDark,
              ),
            ),
          if (subtitle.isNotEmpty) const SizedBox(height: 6),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppTheme.textMuted,
              ),
            ),
          if (component.children.isNotEmpty) const SizedBox(height: 12),
          ...component.children.map((child) => render(child, context, ref)),
          if (component.action != null && actionLabel.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    _executeAction(
                      component.action!,
                      context,
                      ref,
                      componentId: component.id,
                    ),
                style: AppTheme.primaryActionButtonStyle(),
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    RemoteComponent component, {
    required Color backgroundColor,
    required Color borderColor,
    required Color iconColor,
  }) {
    final title = _readString(
      component.props['title'] ?? component.props['headline'],
    );
    final subtitle = _readString(component.props['subtitle']);
    final icon = IconKeyResolver.resolve(_readString(component.props['icon_key']));
    return Container(
      width: double.infinity,
      margin: _readEdgeInsets(component.props['margin']),
      padding: _readEdgeInsets(component.props['padding']) +
          const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                if (subtitle.isNotEmpty) const SizedBox(height: 6),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountCard(RemoteComponent component) {
    final title = _readString(component.props['title']);
    final amount = _readString(
      component.props['amount_label'] ?? component.props['value'],
    );
    return Container(
      width: double.infinity,
      margin: _readEdgeInsets(component.props['margin']),
      padding: _readEdgeInsets(component.props['padding']) +
          const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
          if (amount.isNotEmpty) const SizedBox(height: 8),
          if (amount.isNotEmpty)
            Text(
              amount,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep(RemoteComponent component) {
    final label = _readString(
      component.props['label'] ?? component.props['title'],
    );
    final description = _readString(component.props['description']);
    return Padding(
      padding: _readEdgeInsets(component.props['padding']) +
          const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty)
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (description.isNotEmpty) const SizedBox(height: 4),
                if (description.isNotEmpty)
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldGroup(
    RemoteComponent component,
    BuildContext context,
    WidgetRef ref,
  ) {
    final title = _readString(component.props['title']);
    return Padding(
      padding: _readEdgeInsets(component.props['padding']),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ...component.children.map((child) => render(child, context, ref)),
        ],
      ),
    );
  }

  Future<void> _executeAction(
    RemoteAction action,
    BuildContext context,
    WidgetRef ref,
    {String? componentId}
  ) {
    final enriched = RemoteAction(
      type: action.type,
      commandKey: action.commandKey,
      routeKey: action.routeKey,
      linkKey: action.linkKey,
      message: action.message,
      nativeFlowKey: action.nativeFlowKey,
      arguments: {
        ...action.arguments,
        if (componentId != null && componentId.isNotEmpty)
          'component_id': componentId,
        if (screenKey != null && screenKey!.isNotEmpty) 'screen_key': screenKey,
      },
    );
    return ref
        .read(executeRemoteActionUseCaseProvider)
        .execute(enriched, context);
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

  static String _readString(dynamic raw, {String fallback = ''}) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static double _readDouble(dynamic raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static FontWeight _readFontWeight(dynamic raw) {
    final value = _readString(raw).toLowerCase();
    return value == 'bold' || value == 'w700' || value == 'w800'
        ? FontWeight.w800
        : FontWeight.normal;
  }

  static TextAlign _readTextAlign(dynamic raw) {
    switch (_readString(raw).toLowerCase()) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  static Color? _readColor(dynamic raw) {
    final value = _readString(raw);
    if (value.isEmpty) return null;
    final normalized = value.replaceFirst('#', '');
    if (normalized.length != 6 && normalized.length != 8) return null;
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    return Color(int.tryParse(hex, radix: 16) ?? 0xFFFFFFFF);
  }

  static Map<String, dynamic> _readMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static RemoteAction? _readAction(dynamic raw) {
    final map = _readMap(raw);
    if (map.isEmpty) return null;
    return RemoteAction.fromJson(map);
  }
}
