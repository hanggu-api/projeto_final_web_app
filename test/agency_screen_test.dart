
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/features/agency/screens/agency_home_screen.dart';
import 'package:service_101/features/agency/widgets/agency_campaign_card.dart';

void main() {
  testWidgets('Agency Home Screen renders correctly', (WidgetTester tester) async {
    // Pump the widget
    await tester.pumpWidget(const MaterialApp(home: AgencyHomeScreen()));

    // Verify Title
    expect(find.text('Minha Agência IA'), findsOneWidget);

    // Verify Quick Actions
    expect(find.text('Nova Campanha'), findsOneWidget);
    expect(find.text('Identidade Visual'), findsOneWidget);
  });

  testWidgets('Agency Campaign Card displays version', (WidgetTester tester) async {
    const card = AgencyCampaignCard(
      title: 'Test Campaign',
      status: 'active',
      platform: 'Instagram',
      date: '07 Jan',
      version: 'v2.0',
    );

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: card)));

    // Verify Title and Version
    expect(find.text('Test Campaign'), findsOneWidget);
    expect(find.text('v2.0'), findsOneWidget);
  });
}
