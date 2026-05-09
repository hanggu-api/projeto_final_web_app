/// Supabase table names — use these constants instead of raw strings.
///
/// Example:
/// ```dart
/// final table = TableNames.users;
/// ```
abstract final class TableNames {
  static const appConfigs = 'app_configs';
  static const appointments = 'appointments';
  static const avatars = 'avatars';
  static const chatMessages = 'chat_messages';
  static const clientLocations = 'client_locations';
  static const driverDocuments = 'driver_documents';
  static const driverMercadopagoAccounts = 'driver_mercadopago_accounts';
  static const idVerification = 'id-verification';
  static const notifications = 'notifications';
  static const passengerMercadopagoAccounts = 'passenger_mercadopago_accounts';
  static const paymentAccounts = 'payment_accounts';
  static const professions = 'professions';
  static const providerLocations = 'provider_locations';
  static const providerProfessions = 'provider_professions';
  static const providers = 'providers';
  static const providerScheduleExceptions = 'provider_schedule_exceptions';
  static const providerSchedules = 'provider_schedules';
  static const providerTasks = 'provider_tasks';
  static const reviews = 'reviews';
  static const serviceDisputes = 'service_disputes';
  static const serviceLogs = 'service_logs';
  static const serviceOffers = 'service_offers';
  static const serviceRequestsNew = 'service_requests_new';
  static const taskCatalog = 'task_catalog';
  static const userPaymentMethods = 'user_payment_methods';
  static const userSavedPlaces = 'user_saved_places';
  static const users = 'users';
  static const vehicles = 'vehicles';
  static const addressesRegistry = 'addresses_registry';
}
