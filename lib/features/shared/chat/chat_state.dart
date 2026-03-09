import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../../../../services/api_service.dart';

mixin ChatStateMixin<T extends StatefulWidget> on State<T> {
  final ApiService api = ApiService();
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final AudioRecorder rec = AudioRecorder();
  final GlobalKey inputAreaKey = GlobalKey();

  List<dynamic> messages = [];
  final List<Map<String, dynamic>> pendingMessages = [];

  StreamSubscription? chatSubscription;
  StreamSubscription?
  driverLocationSubscription; // Relevant for trip-related chats
  Timer? pollingTimer;
  Timer? recordTicker;

  Map<String, dynamic>? serviceDetails;
  int? myUserId;
  int? otherUserId;
  String? role;
  bool isRecording = false;
  DateTime? recordStartAt;
  bool isOtherOnline = false;
  double bottomPadding = 80;

  // Upload state
  bool isUploading = false;
  String uploadingType = '';

  final Map<String, Future<Uint8List>> imageFutureCache = {};

  void disposeChatState() {
    messageController.dispose();
    scrollController.dispose();
    chatSubscription?.cancel();
    pollingTimer?.cancel();
    recordTicker?.cancel();
    rec.dispose();
  }
}
