class PixPaymentArgs {
  final String resourceId;
  final String title;
  final String description;
  final String? providerName;
  final String? serviceLabel;
  final String? fiscalDescription;
  final String qrCode;
  final String qrCodeImage;
  final double amount;
  final String? successRoute;
  final String statusSource;
  final String paymentStage;

  const PixPaymentArgs({
    required this.resourceId,
    required this.title,
    required this.description,
    this.providerName,
    this.serviceLabel,
    this.fiscalDescription,
    required this.qrCode,
    required this.qrCodeImage,
    required this.amount,
    this.successRoute,
    this.statusSource = 'pending_fixed_booking',
    this.paymentStage = 'deposit',
  });

  factory PixPaymentArgs.fromUnknown(Object? extra) {
    if (extra is PixPaymentArgs) return extra;
    if (extra is Map) {
      return PixPaymentArgs(
        resourceId: (extra['resourceId'] ?? extra['intentId'] ?? '').toString(),
        title: (extra['title'] ?? 'Pagamento Pix').toString(),
        description:
            (extra['description'] ??
                    'Conclua o Pix para confirmar sua reserva.')
                .toString(),
        providerName: extra['providerName']?.toString(),
        serviceLabel: extra['serviceLabel']?.toString(),
        fiscalDescription: extra['fiscalDescription']?.toString(),
        qrCode: (extra['qrCode'] ?? '').toString(),
        qrCodeImage: (extra['qrCodeImage'] ?? '').toString(),
        amount: double.tryParse('${extra['amount'] ?? ''}') ?? 0,
        successRoute: extra['successRoute']?.toString(),
        statusSource: (extra['statusSource'] ?? 'pending_fixed_booking')
            .toString(),
        paymentStage: (extra['paymentStage'] ?? 'deposit').toString(),
      );
    }
    return const PixPaymentArgs(
      resourceId: '',
      title: 'Pagamento Pix',
      description: 'Conclua o Pix para confirmar sua reserva.',
      qrCode: '',
      qrCodeImage: '',
      amount: 0,
    );
  }
}

enum PixPaymentResult { paid, expired, notFound, cancelled }
