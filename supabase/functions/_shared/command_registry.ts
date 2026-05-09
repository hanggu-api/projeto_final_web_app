// Espelho do CommandRegistry do Flutter
// Nenhum comando fora desta lista pode ser executado
export const ALLOWED_COMMANDS = new Set([
  'open_provider_home',
  'open_service_tracking',
  'open_active_service',
  'return_home',
  'open_support',
  'refresh_search_status',
  'cancel_service_request',
  'show_search_details',
  'accept_ride',
  'reject_ride',
  'open_offer',
  'toggle_dispatch_availability',
  'refresh_home',
  'show_command_feedback',
  'generate_platform_pix',
  'open_pix_screen',
  'retry_pix_generation',
  'confirm_direct_payment_intent',
  'start_navigation',
  'open_chat',
  'confirm_service_completion',
])

export function isCommandAllowed(commandKey: string): boolean {
  return ALLOWED_COMMANDS.has(commandKey)
}
