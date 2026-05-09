class CommandRegistry {
  static const Set<String> commands = {
    'accept_ride',
    'reject_ride',
    'open_offer',
    'open_support',
    'start_navigation',
    'refresh_home',
    'toggle_dispatch_availability',
    'open_provider_home',
    'open_active_service',
    'show_command_feedback',
    'open_service_tracking',
    'return_home',
    'refresh_search_status',
    'cancel_service_request',
    'show_search_details',
    'generate_platform_pix',
    'open_pix_screen',
    'retry_pix_generation',
    'confirm_direct_payment_intent',
    'open_chat',
    'confirm_service_completion',
  };

  static bool isAllowed(String commandKey) => commands.contains(commandKey);
}
