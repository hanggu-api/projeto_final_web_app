import 'dart:convert';

import 'logger.dart';

class PaymentAuditLogger {
  static final Map<String, Map<String, dynamic>> _lastSnapshots = {};

  static double _round2(num value) => (value.toDouble() * 100).round() / 100;

  static bool _changed(num a, num b, {double epsilon = 0.01}) {
    return (a.toDouble() - b.toDouble()).abs() > epsilon;
  }

  static void logDriverWalletSnapshot({
    required String driverUserId,
    required String mode,
    required double appBalancePending,
    required double commissionDueTotal,
    required double directEarningsTotal,
    required int paymentsCount,
    required Map<String, double> amountsByMethod,
    double? driverDailyFeeAmount,
    double? driverPlatformTxFeeRate,
    String source = 'wallet',
  }) {
    final key = 'driver_wallet:$driverUserId';
    final prev = _lastSnapshots[key];

    final normalized = <String, dynamic>{
      'mode': mode,
      'app_balance_pending': _round2(appBalancePending),
      'commission_due_total': _round2(commissionDueTotal),
      'direct_earnings_total': _round2(directEarningsTotal),
      'payments_count': paymentsCount,
      'daily_fee_amount': driverDailyFeeAmount != null
          ? _round2(driverDailyFeeAmount)
          : null,
      'platform_tx_fee_rate': driverPlatformTxFeeRate != null
          ? _round2(driverPlatformTxFeeRate)
          : null,
      'by_method': amountsByMethod.map((k, v) => MapEntry(k, _round2(v))),
    };

    bool shouldLog = prev == null || prev['mode'] != normalized['mode'];
    if (!shouldLog) {
      final prevSnapshot = prev;
      shouldLog =
          _changed(
            prevSnapshot['app_balance_pending'] ?? 0,
            normalized['app_balance_pending'] ?? 0,
          ) ||
          _changed(
            prevSnapshot['commission_due_total'] ?? 0,
            normalized['commission_due_total'] ?? 0,
          ) ||
          _changed(
            prevSnapshot['direct_earnings_total'] ?? 0,
            normalized['direct_earnings_total'] ?? 0,
          ) ||
          (prevSnapshot['payments_count'] ?? 0) !=
              (normalized['payments_count'] ?? 0);
    }

    if (!shouldLog) return;
    _lastSnapshots[key] = normalized;

    AppLogger.info(
      '🧾 [PaymentAudit][$source] driver=$driverUserId mode=$mode '
      'app_pending=${_round2(appBalancePending)} '
      'commission_due=${_round2(commissionDueTotal)} '
      'direct_total=${_round2(directEarningsTotal)} '
      'payments=$paymentsCount '
      'daily_fee=${driverDailyFeeAmount != null ? _round2(driverDailyFeeAmount) : "N/A"} '
      'tx_rate=${driverPlatformTxFeeRate != null ? _round2(driverPlatformTxFeeRate) : "N/A"} '
      'breakdown=${jsonEncode(normalized['by_method'])}',
    );
  }

  static void logTripPaymentEvent({
    required String tripId,
    required String event,
    double? amount,
    String? paymentMethodId,
    double? commissionRate,
    double? commissionAmount,
    double? driverReceives,
    double? platformReceives,
    String? traceId,
    Map<String, dynamic>? extra,
  }) {
    final base = <String, dynamic>{
      'trip_id': tripId,
      'event': event,
      if (amount != null) 'amount': _round2(amount),
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      if (commissionRate != null) 'commission_rate': _round2(commissionRate),
      if (commissionAmount != null)
        'commission_amount': _round2(commissionAmount),
      if (driverReceives != null) 'driver_receives': _round2(driverReceives),
      if (platformReceives != null)
        'platform_receives': _round2(platformReceives),
      if (traceId != null) 'trace_id': traceId,
      if (extra != null) 'extra': extra,
    };

    AppLogger.info('🧾 [PaymentAudit][trip] ${jsonEncode(base)}');
  }

  static void logServicePaymentEvent({
    required String serviceId,
    required String event,
    double? amount,
    String? paymentMethodId,
    String? traceId,
    Map<String, dynamic>? extra,
  }) {
    final base = <String, dynamic>{
      'service_id': serviceId,
      'event': event,
      if (amount != null) 'amount': _round2(amount),
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      if (traceId != null) 'trace_id': traceId,
      if (extra != null) 'extra': extra,
    };

    AppLogger.info('🧾 [PaymentAudit][service] ${jsonEncode(base)}');
  }
}
