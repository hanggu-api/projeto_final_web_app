import 'package:flutter/material.dart';

class ChatQuickAlertModal extends StatefulWidget {
  final String senderName;
  final String message;
  final Future<void> Function() onMarkRead;
  final Future<void> Function(String text) onReply;
  final VoidCallback? onOpenChat;

  const ChatQuickAlertModal({
    super.key,
    required this.senderName,
    required this.message,
    required this.onMarkRead,
    required this.onReply,
    this.onOpenChat,
  });

  @override
  State<ChatQuickAlertModal> createState() => _ChatQuickAlertModalState();
}

class _ChatQuickAlertModalState extends State<ChatQuickAlertModal> {
  final TextEditingController _controller = TextEditingController();
  bool _showReplyInput = false;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleMarkRead() async {
    setState(() => _loading = true);
    await widget.onMarkRead();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleReply() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    await widget.onReply(text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxWidth: 640),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOVA MENSAGEM',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.senderName,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_showReplyInput) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Responder rapido...',
                  hintStyle: TextStyle(
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF2F2F2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                onSubmitted: (_) => _handleReply(),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _loading ? null : _handleMarkRead,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black),
                  ),
                  child: const Text('Marcar como lida'),
                ),
                ElevatedButton(
                  onPressed: _loading
                      ? null
                      : () {
                          if (_showReplyInput) {
                            _handleReply();
                            return;
                          }
                          setState(() => _showReplyInput = true);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD400),
                    foregroundColor: Colors.black,
                  ),
                  child: Text(_showReplyInput ? 'Enviar resposta' : 'Responder'),
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          widget.onOpenChat?.call();
                          Navigator.of(context).pop();
                        },
                  child: const Text(
                    'Abrir chat',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
