import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:widgetbook/widgetbook.dart';

import '../core/theme/app_theme.dart';
import '../features/client/widgets/fixed_booking_expanded_schedule_card.dart';
import '../features/client/widgets/fixed_booking_provider_selection_card.dart';
import '../features/home/widgets/home_pending_fixed_payment_banner.dart';
import '../features/home/widgets/home_search_bar.dart';
import '../widgets/user_avatar.dart';

class Service101WidgetbookApp extends StatelessWidget {
  const Service101WidgetbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = _buildTheme();

    return Widgetbook.material(
      lightTheme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.light,
      directories: [
        WidgetbookFolder(
          name: 'Home',
          children: [
            WidgetbookComponent(
              name: 'HomeSearchBar',
              useCases: [
                WidgetbookUseCase(
                  name: 'Endereco carregado',
                  builder: (context) => _phoneCanvas(
                    child: HomeSearchBar(
                      currentAddress:
                          'Rua Eldorado 10, Imperatriz - Maranhao, 65903-210',
                      isLoadingLocation: false,
                      useInternalSearch: false,
                      autocompleteItems: const [],
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Com sugestoes',
                  builder: (context) => _phoneCanvas(
                    child: HomeSearchBar(
                      currentAddress:
                          'Rua Antonio de Miranda 102, Imperatriz - Maranhao',
                      useInternalSearch: false,
                      seedQuery: 'barba',
                      seedVersion: 1,
                      autocompleteItems: const [
                        {
                          'task_name': 'Combo cabelo e barba',
                          'profession_name': 'Barbearia',
                          'service_type': 'at_provider',
                          'pricing_type': 'fixed',
                          'price': 35.0,
                        },
                        {
                          'task_name': 'Barba completa',
                          'profession_name': 'Barbearia',
                          'service_type': 'at_provider',
                          'pricing_type': 'fixed',
                          'price': 20.0,
                        },
                        {
                          'kind': 'provider_profile',
                          'provider_id': 12,
                          'name': 'Casa Barba',
                          'task_name': 'Casa Barba',
                          'profession_name': 'Perfil do salao',
                          'service_type': 'provider_profile',
                          'address': 'Av. Babaculandia - Vila Lobao',
                        },
                      ],
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Carregando localizacao',
                  builder: (context) => _phoneCanvas(
                    child: const HomeSearchBar(
                      currentAddress: null,
                      isLoadingLocation: true,
                      useInternalSearch: false,
                    ),
                  ),
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'HomePendingFixedPaymentBanner',
              useCases: [
                WidgetbookUseCase(
                  name: 'Pix pendente',
                  builder: (context) => _phoneCanvas(
                    child: HomePendingFixedPaymentBanner(
                      scheduleLabel: 'Hoje as 14:30',
                      compactSummary:
                          'Combo: Cabelo + Barba · Hoje as 14:30 · Pix R\$ 7,00',
                      providerName: 'casa barba',
                      serviceLabel: 'Combo: Cabelo + Barba',
                      upfrontValueLabel: 'R\$ 7,00',
                      address: 'Av. Babaculandia - Vila Lobao - Maranhao',
                      details: const {
                        'intent_id': 'widgetbook-intent-1',
                        'service_name': 'Combo: Cabelo + Barba',
                      },
                      onOpenPayment: () {},
                      onRefreshNeeded: () {},
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Nome longo e sem endereco',
                  builder: (context) => _phoneCanvas(
                    child: HomePendingFixedPaymentBanner(
                      scheduleLabel: 'Amanha as 08:45',
                      compactSummary:
                          'Progressiva premium com hidracao e corte · Amanha as 08:45 · Pix R\$ 12,50',
                      providerName:
                          'Espaco de Beleza Especializado em Transformacao Capilar Imperial',
                      serviceLabel:
                          'Progressiva premium com reconstrucao e corte social',
                      upfrontValueLabel: 'R\$ 12,50',
                      address: null,
                      details: const {
                        'intent_id': 'widgetbook-intent-2',
                        'service_name':
                            'Progressiva premium com reconstrucao e corte social',
                      },
                      onOpenPayment: () {},
                      onRefreshNeeded: () {},
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Beauty Booking',
          children: [
            WidgetbookComponent(
              name: 'FixedBookingExpandedScheduleCard',
              useCases: [
                WidgetbookUseCase(
                  name: 'Selecao de horario',
                  builder: (context) => _phoneCanvas(
                    child: FixedBookingExpandedScheduleCard(
                      isPixReadyForProvider: false,
                      isSelectedProvider: true,
                      selectedDate: DateTime(2026, 4, 26),
                      selectedTimeSlot: '14:30',
                      realSlots: const [
                        {
                          'start_time': '2026-04-26T14:00:00',
                          'status': 'free',
                          'is_selectable': true,
                        },
                        {
                          'start_time': '2026-04-26T14:30:00',
                          'status': 'free',
                          'is_selectable': true,
                        },
                        {
                          'start_time': '2026-04-26T15:00:00',
                          'status': 'busy',
                          'is_selectable': false,
                        },
                        {
                          'start_time': '2026-04-26T15:30:00',
                          'status': 'free',
                          'is_selectable': true,
                        },
                        {
                          'start_time': '2026-04-26T16:00:00',
                          'status': 'free',
                          'is_selectable': true,
                        },
                        {
                          'start_time': '2026-04-26T16:30:00',
                          'status': 'free',
                          'is_selectable': true,
                        },
                      ],
                      loadingSlots: false,
                      preparingInlinePix: false,
                      changingPendingSchedule: false,
                      pendingPixPayload: '',
                      pendingPixImage: '',
                      pendingPixFee: 0,
                      onConfirmSchedule: () {},
                      onChangePendingSchedule: () {},
                      onDateSelected: (_) {},
                      onTimeSlotSelected: (_) {},
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Pix pendente no card',
                  builder: (context) => _phoneCanvas(
                    child: FixedBookingExpandedScheduleCard(
                      isPixReadyForProvider: true,
                      isSelectedProvider: true,
                      selectedDate: DateTime(2026, 4, 26),
                      selectedTimeSlot: '16:30',
                      realSlots: const [],
                      loadingSlots: false,
                      preparingInlinePix: false,
                      changingPendingSchedule: false,
                      pendingPixPayload:
                          '00020126360014BR.GOV.BCB.PIX0114+55999814018452040000530398654047.005802BR5915IRMENEZES6010Imperatriz62070503***6304ABCD',
                      pendingPixImage: '',
                      pendingPixFee: 7,
                      onConfirmSchedule: () {},
                      onChangePendingSchedule: () {},
                      onDateSelected: (_) {},
                      onTimeSlotSelected: (_) {},
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Preparando Pix',
                  builder: (context) => _phoneCanvas(
                    child: FixedBookingExpandedScheduleCard(
                      isPixReadyForProvider: false,
                      isSelectedProvider: true,
                      selectedDate: DateTime(2026, 4, 26),
                      selectedTimeSlot: '17:00',
                      realSlots: const [
                        {
                          'start_time': '2026-04-26T17:00:00',
                          'status': 'free',
                          'is_selectable': true,
                        },
                      ],
                      loadingSlots: false,
                      preparingInlinePix: true,
                      changingPendingSchedule: false,
                      pendingPixPayload: '',
                      pendingPixImage: '',
                      pendingPixFee: 0,
                      onConfirmSchedule: () {},
                      onChangePendingSchedule: () {},
                      onDateSelected: (_) {},
                      onTimeSlotSelected: (_) {},
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Pix com codigo longo',
                  builder: (context) => _phoneCanvas(
                    child: FixedBookingExpandedScheduleCard(
                      isPixReadyForProvider: true,
                      isSelectedProvider: true,
                      selectedDate: DateTime(2026, 4, 27),
                      selectedTimeSlot: '09:30',
                      realSlots: const [],
                      loadingSlots: false,
                      preparingInlinePix: false,
                      changingPendingSchedule: true,
                      pendingPixPayload:
                          '00020126360014BR.GOV.BCB.PIX0114+559998140184520400005303986540612.505802BR5915ESTETICABELA6011Imperatriz62140510agenda-1236304A1B200020126360014BR.GOV.BCB.PIX0114+559998140184520400005303986540612.505802BR5915ESTETICABELA6011Imperatriz62140510agenda-1236304A1B2',
                      pendingPixImage: '',
                      pendingPixFee: 12.5,
                      onConfirmSchedule: () {},
                      onChangePendingSchedule: () {},
                      onDateSelected: (_) {},
                      onTimeSlotSelected: (_) {},
                    ),
                  ),
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'FixedBookingProviderSelectionCard',
              useCases: [
                WidgetbookUseCase(
                  name: 'Selecionado',
                  builder: (context) => _phoneCanvas(
                    child: FixedBookingProviderSelectionCard(
                      isSelected: true,
                      providerName: 'Casa Barba',
                      providerAddress: 'Av. Babaculandia - Vila Lobao',
                      distanceLabel: '3,6 km',
                      nextSlotLabel: 'Hoje as 16:30',
                      serviceLabel: 'Combo',
                      selectedPrice: 70,
                      avatarUrl: null,
                      onTap: () {},
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Nome e endereco longos',
                  builder: (context) => _phoneCanvas(
                    child: FixedBookingProviderSelectionCard(
                      isSelected: false,
                      providerName:
                          'Instituto de Estetica e Beleza Avancada das Sobrancelhas Imperiais',
                      providerAddress:
                          'Rua Dom Pedro II, Quadra Especial, Centro expandido de Imperatriz - Maranhao',
                      distanceLabel: '12,4 km',
                      nextSlotLabel: 'Amanha as 08:00',
                      serviceLabel: 'Progressiva',
                      selectedPrice: 149.9,
                      avatarUrl: null,
                      onTap: () {},
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Profile',
          children: [
            WidgetbookComponent(
              name: 'UserAvatar',
              useCases: [
                WidgetbookUseCase(
                  name: 'Sem foto',
                  builder: (context) => _phoneCanvas(
                    child: const _AvatarShowcase(
                      title: 'Prestador sem avatar salvo',
                      subtitle: 'Valida fallback com inicial e contraste visual.',
                      avatar: UserAvatar(
                        avatar: null,
                        name: 'Alan',
                        radius: 28,
                      ),
                    ),
                  ),
                ),
                WidgetbookUseCase(
                  name: 'Nome longo',
                  builder: (context) => _phoneCanvas(
                    child: const _AvatarShowcase(
                      title:
                          'Espaco de Beleza Especializado em Transformacao Capilar Imperial',
                      subtitle:
                          'Nome extenso para validar truncamento e equilibrio com avatar.',
                      avatar: UserAvatar(
                        avatar: null,
                        name:
                            'Espaco de Beleza Especializado em Transformacao Capilar Imperial',
                        radius: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
      appBuilder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: theme,
          home: Scaffold(
            backgroundColor: const Color(0xFFF6F7FB),
            body: SafeArea(child: child),
          ),
        );
      },
    );
  }
}

ThemeData _buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTheme.primaryYellow,
      primary: AppTheme.primaryYellow,
      secondary: AppTheme.accentBlue,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFFF6F7FB),
  );

  return base.copyWith(
    textTheme: GoogleFonts.manropeTextTheme(base.textTheme),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.darkBlueText,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

class _AvatarShowcase extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget avatar;

  const _AvatarShowcase({
    required this.title,
    required this.subtitle,
    required this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.surfacedCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _phoneCanvas({required Widget child}) {
  return Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: child,
      ),
    ),
  );
}
