class RemoteActionRequest {
  const RemoteActionRequest({
    required this.actionType,
    required this.commandKey,
    required this.screenKey,
    required this.componentId,
    this.arguments = const <String, dynamic>{},
    this.entityIds = const <String, dynamic>{},
  });

  final String actionType;
  final String commandKey;
  final String screenKey;
  final String componentId;
  final Map<String, dynamic> arguments;
  final Map<String, dynamic> entityIds;

  Map<String, dynamic> toJson() {
    return {
      'action_type': actionType,
      'command_key': commandKey,
      'screen_key': screenKey,
      'component_id': componentId,
      'arguments': arguments,
      'entity_ids': entityIds,
    };
  }
}
