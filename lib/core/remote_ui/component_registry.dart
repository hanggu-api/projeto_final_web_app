import '../../domains/remote_ui/models/remote_component.dart';
import 'action_registry.dart';

class ComponentRegistry {
  static const Set<String> supportedTypes = {
    'text',
    'rich_text',
    'image',
    'button',
    'section',
    'card',
    'list',
    'banner',
    'badge',
    'status_block',
    'warning_card',
    'info_card',
    'amount_card',
    'timeline_step',
    'form',
    'field_group',
    'input',
    'spacer',
    'divider',
    'stack',
    'row',
    'column',
    'dialog',
    'bottom_sheet',
  };

  static bool supportsTree(List<RemoteComponent> components) {
    for (final component in components) {
      if (!supports(component)) {
        return false;
      }
    }
    return true;
  }

  static bool supports(RemoteComponent component) {
    if (!supportedTypes.contains(component.type)) return false;
    if (component.action != null &&
        !ActionRegistry.supports(component.action!)) {
      return false;
    }
    return supportsTree(component.children);
  }
}
