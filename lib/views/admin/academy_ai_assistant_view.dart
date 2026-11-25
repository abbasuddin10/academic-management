import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/services/gemini_service.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' show Content;

class AcademyAiAssistantView extends StatefulWidget {
  final String academyId;

  const AcademyAiAssistantView({super.key, required this.academyId});

  @override
  State<AcademyAiAssistantView> createState() => _AcademyAiAssistantViewState();
}

class _AcademyAiAssistantViewState extends State<AcademyAiAssistantView> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final List<Content> _history = [];

  bool get _configured => GeminiService.isConfigured;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();

    if (_configured) {
      _messages.add({
        'sender': 'ai',
        'text': 'হ্যালো! আমি আপনার একাডেমি এআই অ্যাসিস্ট্যান্ট। আজ আপনাকে কীভাবে সাহায্য করতে পারি?',
      });
    } else {
      _messages.add({
        'sender': 'ai',
        'text': 'এআই অ্যাসিস্ট্যান্ট চালু করতে GEMINI_API_KEY কনফিগার করা প্রয়োজন। '
            'অ্যাপটি বিল্ড করার সময় --dart-define=GEMINI_API_KEY=... প্রদান করুন '
            'এবং অ্যাডমিনের সাথে যোগাযোগ করুন।',
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (!_configured) return;

    final text = _messageController.text.trim();
    if (text.isEmpty || _isTyping) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _isTyping = true;
    });
    _messageController.clear();

    try {
      final reply = (await GeminiService.chat(_history, text))?.trim();

      if (!mounted) return;
      setState(() {
        _history.add(GeminiService.userContent(text));
        if (reply != null && reply.isNotEmpty) {
          _history.add(GeminiService.modelContent(reply));
        }
        _messages.add({
          'sender': 'ai',
          'text': reply ?? 'কোনো উত্তর পাওয়া যায়নি। আবার চেষ্টা করুন।',
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'sender': 'ai',
          'text': 'এআই সার্ভিসের সাথে সংযোগ করা যায়নি। পরে আবার চেষ্টা করুন।',
        });
      });
      debugPrint('Gemini request failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isTyping = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = _configured;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Text('একাডেমি AI অ্যাসিস্ট্যান্ট', style: TextStyle(fontSize: 16)),
          ],
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                bool isUser = message['sender'] == 'user';

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.teal : Colors.white,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isUser
                            ? Radius.circular(0)
                            : Radius.circular(16),
                        bottomLeft: !isUser
                            ? Radius.circular(0)
                            : Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.08),
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                      border: isUser
                          ? null
                          : Border.all(color: AppTheme.borderOf(context)),
                    ),
                    child: Text(
                      message['text'] ?? '',
                      style: TextStyle(
                        color: isUser ? Colors.white : AppTheme.inkOf(context),
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isTyping)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'AI টাইপ করছে...',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.mutedOf(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceOf(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: configured,
                    decoration: InputDecoration(
                      hintText: configured
                          ? 'এখানে কিছু লিখুন...'
                          : 'এআই কনফিগার করা হয়নি',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.teal),
                  onPressed: configured ? _sendMessage : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
