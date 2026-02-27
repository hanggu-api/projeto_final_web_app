import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  final List<double> _weeklyEarnings = [120, 250, 180, 320, 210, 450, 380];
  final List<String> _days = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Header Flutuante Premium
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: AppTheme.primaryYellow,
            // borderRadius removido por não ser parâmetro do SliverAppBar
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Ganhos',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                  fontSize: 20,
                ),
              ),
              centerTitle: true,
            ),
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: AppTheme.textDark),
              onPressed: () => context.pop(),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Saldo Principal
                  _buildBalanceCard(),
                  const SizedBox(height: 32),

                  // Gráfico de Ganhos Semanais
                  Text(
                    'Esta Semana',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildEarningsChart(),
                  const SizedBox(height: 40),

                  // Histórico de Transações
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Histórico Recente',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          'Ver tudo',
                          style: GoogleFonts.manrope(
                            color: Colors.blue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTransactionList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.textDark,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Saldo Disponível',
            style: GoogleFonts.manrope(
              color: Colors.white.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'R\$ 1.250,45',
            style: GoogleFonts.manrope(
              color: AppTheme.primaryYellow,
              fontWeight: FontWeight.w900,
              fontSize: 36,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryYellow,
                foregroundColor: AppTheme.textDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                'TRANSFERIR AGORA',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsChart() {
    double maxEarning = _weeklyEarnings.reduce((a, b) => a > b ? a : b);
    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_weeklyEarnings.length, (index) {
          double heightFactor = _weeklyEarnings[index] / maxEarning;
          bool isMax = _weeklyEarnings[index] == maxEarning;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 32,
                height: 120 * heightFactor,
                decoration: BoxDecoration(
                  color: isMax ? AppTheme.primaryYellow : AppTheme.textDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _days[index],
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isMax ? AppTheme.textDark : AppTheme.textMuted,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTransactionList() {
    final transactions = [
      {'title': 'Corrida Econômico', 'time': 'Hoje, 14:20', 'value': 'R\$ 15,30', 'isAdd': true},
      {'title': 'Corrida Conforto', 'time': 'Hoje, 12:45', 'value': 'R\$ 22,50', 'isAdd': true},
      {'title': 'Transferência Banco', 'time': 'Ontem, 09:30', 'value': '- R\$ 450,00', 'isAdd': false},
      {'title': 'Corrida Econômico', 'time': 'Ontem, 18:15', 'value': 'R\$ 12,00', 'isAdd': true},
    ];

    return Column(
      children: transactions.map((t) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (t['isAdd'] as bool) ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                (t['isAdd'] as bool) ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
                size: 20,
                color: (t['isAdd'] as bool) ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['title'] as String,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                  ),
                  Text(
                    t['time'] as String,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              t['value'] as String,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: (t['isAdd'] as bool) ? Colors.green : AppTheme.textDark,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}
