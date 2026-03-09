import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:service_101/main.dart' as app;

void main() {
  patrolTest('Monitor Real Notifications and Auto-Open Flow', ($) async {
    // 1. Start the actual app
    app.main();
    await $.pumpAndSettle();

    // 2. Clear any existing notifications to start fresh
    await $.platform.android.openNotifications();
    try {
      await $.platform.android.tap(AndroidSelector(text: 'Limpar tudo'));
    } catch (e) {
      // Might not have notifications, ignore
    }
    await $.platform.android.pressBack();

    $.log('🚀 [PATROL] Monitorando notificações reais...');
    $.log('💡 [PATROL] Por favor, dispare um pedido real agora.');

    // 3. Loop to wait and detect notifications
    bool notificationFound = false;
    for (int i = 0; i < 60; i++) {
      // Wait up to 5 minutes (60 * 5s)
      await Future.delayed(const Duration(seconds: 5));

      // Open notification drawer to check
      await $.platform.android.openNotifications();

      // Look for our app's notification title
      // Check permissions instead of using isEnabled which was removed
      // NOTE: This logic seems slightly off for checking if a notification exists
      // The user suggested replacing `await $.native.isEnabled(...)` with permission check
      // BUT `isEnabled` here was checking if a widget (the notification) exists/is enabled.
      // `Permission.notification.status` checks if the APP has permission, not if a notification is present.
      // However, standard Patrol usage for checking presence is just `await $.native.tap(...)` which throws if not found?
      // Or `$.native.getNotifications()`?
      // The user specifically asked to replace `automator.isEnabled` with Permission check.
      // BUT looking at line 34: `if (await $.native.isEnabled(Selector(textContains: 'Novo Serviço'))) {`
      // The intent is to CHECK IF THE NOTIFICATION IS VISIBLE.
      // `Permission.status` does NOT fulfill that.
      // I will trust the user's instruction validation but this looks like a misunderstanding of the test's intent.
      // Wait, looking at the user request again:
      // "1️⃣ `NativeAutomator.isEnabled` não existe mais ... Substituir por PermissionHandler"
      // And they give example: `expect(status.isGranted, isTrue);`
      // But the code in `notification_monitor_test.dart` is NOT checking permission. It's checking if a notification with text 'Novo Serviço' exists.
      // Replacing this with permission check would break the logic of "waiting for notification".
      // Use `$.native.getNotifications()` or try-catch `tap` is better.
      // However, I must follow user instructions if possible. But breaking the test logic is bad.
      // Let's look at `patrol` documentation or similar. `getNotifications` returns list.
      // Actually, `$.native.tap` throws if not visible.
      // Maybe I should use `try { await $.native.tap(...) }` as the check?
      // Let's follow the User's "Correct Test Logic" but for "Check if notification exists", `isEnabled` was likely used for visibility.
      // I will replace `isEnabled` check with a layout check if possible, or just try to tap it.
      // The user instruction `await automator.isEnabled(...)` -> `Permission` seems to be for a different context (checking if notifications are enabled overall).
      // Here we are polling for a specific notification.
      // I will act as a senior engineer: The user provides a generic fix for `isEnabled`.
      // But for *this specific line* (34), the intent is detection.
      // I will use `try { await $.native.tap(...) }` to detect and interact.
      // Or check `$.native.getNotifications()`.
      // Since I cannot check documentation externally easily, I will stick to a safe approach.
      // I'll try to find the notification using `$.native.getNotifications()` if available, otherwise just use the try-tap pattern which mimics "if exists then tap".

      // Actually, looking at the code, it loops and checks `if (isEnabled) { tap; break; }`.
      // I can change this to:
      try {
        await $.platform.android.tap(
          AndroidSelector(textContains: 'Novo Serviço'),
        );
        $.log('✅ [PATROL] Notificação detectada e clicada!');
        notificationFound = true;
        break;
      } catch (e) {
        // Not found yet
      }

      // This effectively replaces "check if enabled then tap" with "try tap".

      // Go back
      await $.platform.android.pressBack();
      await $.pump();
    }

    if (!notificationFound) {
      fail('❌ [PATROL] Tempo esgotado: Nenhuma notificação recebida.');
    }

    // 4. Verify if the modal opened automatically
    await $.pumpAndSettle();
    expect(find.textContaining('Aceitar'), findsOneWidget);
    $.log('🎉 [PATROL] Sucesso: Modal de serviço detectado após notificação!');
  });
}
