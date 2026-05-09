import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class HomeQuickCategoryTileData {
  final IconData icon;
  final String label;
  final String metric;
  final String summary;
  final Color accentColor;
  final VoidCallback onTap;
  final bool highlighted;

  const HomeQuickCategoryTileData({
    required this.icon,
    required this.label,
    required this.metric,
    required this.summary,
    required this.accentColor,
    required this.onTap,
    this.highlighted = false,
  });
}

class HomeQuickCategoryWrap extends StatelessWidget {
  final List<HomeQuickCategoryTileData> items;

  const HomeQuickCategoryWrap({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chipWidth = math.max((constraints.maxWidth - 10) / 2, 140.0);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map((item) {
            return SizedBox(
              width: chipWidth,
              child: _HomeQuickCategoryChip(data: item),
            );
          }).toList(),
        );
      },
    );
  }
}

class HomeProfessionQuickAccessGroup extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<HomeQuickCategoryTileData> items;
  final Color accentColor;
  final bool highlighted;

  const HomeProfessionQuickAccessGroup({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.accentColor,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final displayedItems = items.take(6).toList();
    final badgeLabel = highlighted
        ? '${displayedItems.length} destaques'
        : '${displayedItems.length} atalhos';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlighted
              ? Colors.black.withValues(alpha: 0.18)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: highlighted
                      ? Colors.white.withValues(alpha: 0.78)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  highlighted ? 'Em alta' : 'Explore',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: highlighted ? Colors.black : accentColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: highlighted
                      ? Colors.black.withValues(alpha: 0.68)
                      : AppTheme.darkBlueText.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: highlighted
                  ? Colors.black.withValues(alpha: 0.74)
                  : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final useSingleColumn =
                  highlighted ||
                  displayedItems.length == 1 ||
                  constraints.maxWidth < 520;
              final chipWidth = useSingleColumn
                  ? constraints.maxWidth
                  : math.max((constraints.maxWidth - 10) / 2, 160.0);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: displayedItems.map((item) {
                  return SizedBox(
                    width: chipWidth,
                    child: _HomeQuickCategoryChip(data: item),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeQuickCategoryChip extends StatelessWidget {
  final HomeQuickCategoryTileData data;

  const _HomeQuickCategoryChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = data.highlighted
        ? AppTheme.primaryYellow
        : Colors.white;
    final borderColor = data.highlighted
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.grey.shade200;
    final summaryColor = data.highlighted
        ? Colors.black.withValues(alpha: 0.76)
        : Colors.grey.shade700;
    final metricBackground = data.highlighted
        ? Colors.white.withValues(alpha: 0.78)
        : Colors.white;
    final metricTextColor = data.highlighted ? Colors.black : data.accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: data.highlighted
                          ? Colors.black
                          : data.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      data.icon,
                      color: data.highlighted ? Colors.white : data.accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: metricBackground,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: data.highlighted
                                  ? Colors.black.withValues(alpha: 0.08)
                                  : data.accentColor.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            data.metric,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: metricTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: data.highlighted
                          ? Colors.black
                          : Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: data.highlighted ? Colors.white : data.accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: summaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: data.highlighted
                        ? Colors.black
                        : data.accentColor.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      data.highlighted
                          ? 'Destaque pronto para abrir a busca'
                          : 'Toque para carregar opcoes dessa categoria',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: data.highlighted
                            ? Colors.black
                            : data.accentColor.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
