import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/remote_ui/component_registry.dart';
import 'package:service_101/domains/remote_ui/models/remote_component.dart';

void main() {
  test('accepts supported component tree', () {
    const component = RemoteComponent(
      id: 'root',
      type: 'form',
      children: [
        RemoteComponent(
          id: 'title',
          type: 'status_block',
          props: {'title': 'Title', 'value': 'Body'},
        ),
        RemoteComponent(
          id: 'message',
          type: 'input',
          props: {'field_key': 'message'},
        ),
      ],
    );

    expect(ComponentRegistry.supportsTree(const [component]), isTrue);
  });

  test('rejects unsupported component tree', () {
    const component = RemoteComponent(id: 'root', type: 'custom_widget');

    expect(ComponentRegistry.supportsTree(const [component]), isFalse);
  });
}
