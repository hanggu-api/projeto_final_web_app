/// Supabase Edge Function names — use these constants instead of raw strings.
///
/// Example:
/// ```dart
/// apiService.callEdgeFunction(EdgeFunctions.acceptTrip, data);
/// ```
abstract final class EdgeFunctions {
  static const assignment = 'assignment';
  static const acceptTrip = 'accept-trip';
  static const cancelTrip = 'cancel-trip';
  static const config = 'config';
  static const dispatch = 'dispatch';
  static const dispatchQueue = 'dispatch-queue';
  static const geo = 'geo';
  static const getTripPartyProfile = 'get-trip-party-profile';
  static const lookupPlate = 'lookup-plate';
  static const mpCreatePreference = 'mp-create-preference';
  static const mpCustomerManager = 'mp-customer-manager';
  static const mpDisconnectAccount = 'mp-disconnect-account';
  static const mpDriverBalance = 'mp-driver-balance';
  static const mpDriverStatement = 'mp-driver-statement';
  static const mpGetAuthUrl = 'mp-get-auth-url';
  static const mpProcessPayment = 'mp-process-payment';
  static const mpRequestPayout = 'mp-request-payout';
  static const mpTokenizeCard = 'mp-tokenize-card';
  static const notifyDrivers = 'notify-drivers';
  static const paymentFlowStatus = 'payment-flow-status';
  static const sendChatMessage = 'send-chat-message';
  static const markChatMessageRead = 'mark-chat-message-read';
  static const simulatePixPaid = 'simulate-pix-paid';
  static const strings = 'strings';
  static const submitTripReview = 'submit-trip-review';
  static const theme = 'theme';
  static const updateTripStatus = 'update-trip-status';
  static const verifyCardFace = 'verify-card-face';
  static const verifyFace = 'verify-face';
  static const validateRekognition = 'validate-rekognition';
  static const mpConfirmCashPayment = 'mp-confirm-cash-payment';
  static const mpGetPixData = 'mp-get-pix-data';
  static const offer = 'offer';
  static const pushNotifications = 'push-notifications';
  static const serviceRequest = 'service-request';
  static const tracking = 'tracking';
}
