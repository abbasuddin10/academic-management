import 'dart:convert';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:academy_management/services/gemini_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' show Content;

/// Conversational, prompt-driven model-test builder.
///
/// The assistant collects missing details in plain Bangla chat and, once the
/// plan is complete, emits a strict JSON spec that is validated and persisted
/// through [ModelTestRepository] — including the same overlap rules the UI and
/// the database trigger enforce.
class ModelTestAiBuilderView extends StatefulWidget {
  final String academyId;
  final String className;
  final String? subjectName;
  final List<String> availableSubjects;
  final String? currentUserId;
  final String? currentUserName;
  final List<ModelTest> existingTests;
  final VoidCallback onCreated;

  const ModelTestAiBuilderView({
    super.key,
    required this.academyId,
    required this.className,
    required this.onCreated,
    this.subjectName,
    this.availableSubjects = const <String>[],
    this.currentUserId,
    this.currentUserName,
    this.existingTests = const <ModelTest>[],
  });

  @override
  State<ModelTestAiBuilderView> createState() => _ModelTestAiBuilderViewState();
}

class _ChatMessage {
  final bool isUser;
  final String text;

  const _ChatMessage(this.isUser, this.text);
}

class _ModelTestAiBuilderViewState extends State<ModelTestAiBuilderView> {
  final _repository = ModelTestRepository();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final List<Content> _history = <Content>[];

  bool _isTyping = false;
  bool get _configured => GeminiService.isConfigured;

  static const _examples = <String>[
    '১. ৮ম শ্রেণির গণিত মডেল টেস্ট, কাল ১০টা থেকে ১১টা, ২০ প্রশ্ন, প্রতি প্রশ্ন ১ নম্বর',
    '২. ৯ম শ্রেণি বিজ্ঞান — ১ম অধ্যায় থেকে ১৫ প্রশ্ন, আগামীকাল সকাল ৯-১০, নেগেটিভ ০.২৫',
    '৩. ১০ম শ্রেণি বাংলা খসড়া মডেল টেস্ট, ২৭ নভেম্বর ২টা-৩টা, ১০ প্রশ্ন',
  ];

  @override
  void initState() {
    super.initState();
    // Seed the chat history with the rules so the model keeps following them
    // for every later turn (GeminiService.chat sends the whole history).
    if (_configured) {
      _history
        ..add(GeminiService.userContent(_systemPrompt()))
        ..add(
          GeminiService.modelContent(
            'বুঝেছি। আমি এই নিয়মগুলো মেনে চলব এবং প্রয়োজন হলে এক এক করে তথ্য জিজ্ঞেস করব।',
          ),
        );
    }
    _messages.add(
      _ChatMessage(
        false,
        _configured
            ? 'হ্যালো! আমি মডেল টেস্ট বিল্ডার। সংক্ষেপে বলুন কী চাই — '
                  'যেমন "৮ম শ্রেণির গণিত, কাল ১০-১১টা, ২০ প্রশ্ন"। '
                  'কোনো তথ্য না দিলে আমি এক এক করে জিজ্ঞেস করব। নিচের উদাহরণগুলোও টিপে নিতে পারেন।'
            : 'এআই বিল্ডার চালু করতে GEMINI_API_KEY কনফিগার করুন '
                  '(--dart-define=GEMINI_API_KEY=...)। তার আগ পর্যন্ত সাধারণ ফর্ম '
                  'থেকেই মডেল টেস্ট তৈরি করতে পারেন।',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _systemPrompt() {
    final occupied = widget.existingTests
        .where((test) => test.status == 'published' || test.status == 'draft')
        .map(
          (test) =>
              '${test.examTitle} [${_fmt(test.startAt)} → ${_fmt(test.endAt)}, class ${test.className}]',
        )
        .join('\n');
    return '''
আপনি একজন Bangla-speaking "মডেল টেস্ট বিল্ডার" সহকারী। ব্যবহারকারী সংক্ষেপে লিখলে আপনি প্রয়োজনীয় তথ্য যোগ করুন। একবারে শুধু একটি করে প্রশ্ন করে ঘাটতি পূরণ করুন।

প্রসঙ্গ:
- Academy ID: ${widget.academyId}
- Class: ${widget.className}
- Subject (if chosen): ${widget.subjectName ?? 'unknown'}
- Available subjects: ${widget.availableSubjects.join(', ')}
- Today (local): ${_fmt(DateTime.now())}
- Already booked test windows (same academy):
${occupied.isEmpty ? '(none)' : occupied}

অবশ্যই মেনে চলুন:
1. কোনো নতুন টেস্টের সময় উপরের booked windows-এর সাথে অতিব্যাপ্ত (overlap) হতে পারবে না। ব্যবহারকারী overlapping সময় দিলে স্পষ্ট করে অন্য সময় চেয়ে নিন।
2. শেষ সময় শুরুর পরে হতে হবে এবং কমপক্ষে ১ মিনিটের ব্যবধান থাকতে হবে। অতীতের সময় দেবেন না।
3. প্রয়োজনীয় তথ্য: title, subject, chapter (ঐচ্ছিক), start, end, marks_per_question, negative_marks, pass_percent, status (published/draft) এবং questions (ঐচ্ছিক; না দিলে বিদ্যমান প্রশ্নব্যাংক ব্যবহার হবে)।
4. যখন সব তথ্য পেয়ে যাবেন, শুধু একটি JSON অবজেক্ট আউটপুট দিন — অন্য কোনো কথা লিখবেন না:
{"kind":"ready","title":"...","subject":"...","chapter":"...","start":"YYYY-MM-DDTHH:mm","end":"YYYY-MM-DDTHH:mm","status":"published","marks_per_question":1,"negative_marks":0,"pass_percent":33,"questions":[{"question":"...","options":["...","...","...","..."],"correct":"A","explanation":""}]}
5. questions না চাইলে "questions": [] দিন। correct অবশ্যই A/B/C/D।
6. JSON ছাড়া অন্য সববার স্বাভাবিক Bangla কথোপকথন করুন।
''';
  }

  Future<void> _send({String? preset}) async {
    if (!_configured || _isTyping) return;
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(true, text));
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final reply = (await GeminiService.chat(_history, text))?.trim() ?? '';
      if (!mounted) return;
      _history
        ..add(GeminiService.userContent(text))
        ..add(GeminiService.modelContent(reply));

      final spec = _extractSpec(reply);
      if (spec != null) {
        await _createFromSpec(spec);
      } else {
        setState(() {
          _messages.add(
            _ChatMessage(false, reply.isEmpty ? 'আবার চেষ্টা করুন।' : reply),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _ChatMessage(
            false,
            'এআই সার্ভিসের সাথে সংযোগ করা যায়নি। পরে আবার চেষ্টা করুন অথবা সাধারণ ফর্ম ব্যবহার করুন।',
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isTyping = false);
        _scrollToBottom();
      }
    }
  }

  Map<String, dynamic>? _extractSpec(String reply) {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(reply.substring(start, end + 1));
      if (decoded is Map<String, dynamic> && decoded['kind'] == 'ready') {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _createFromSpec(Map<String, dynamic> spec) async {
    final className =
        (spec['class_name']?.toString().trim().isNotEmpty == true
                ? spec['class_name'].toString()
                : widget.className)
            .trim();
    final subject =
        (spec['subject']?.toString().trim().isNotEmpty == true
                ? spec['subject'].toString()
                : widget.subjectName ?? '')
            .trim();
    final title = (spec['title']?.toString() ?? '').trim();
    if (title.isEmpty || className.isEmpty || subject.isEmpty) {
      _addAssistant('title, class ও subject ছাড়া পরীক্ষা তৈরি করা যাবে না।');
      return;
    }

    final start = _parseLocal(spec['start']);
    final end = _parseLocal(spec['end']);
    if (start == null || end == null || !end.isAfter(start)) {
      _addAssistant('শুরু ও শেষ সময় সঠিক নয়। আবার সময় দিন।');
      return;
    }
    final durationMinutes = end.difference(start).inMinutes;
    if (durationMinutes <= 0) {
      _addAssistant('পরীক্ষার সময়কাল কমপক্ষে ১ মিনিট হতে হবে।');
      return;
    }
    if (end.isBefore(DateTime.now())) {
      _addAssistant('অতীতের সময়ে পরীক্ষা তৈরি করা যাবে না।');
      return;
    }

    final overlap = await _repository.findOverlap(
      academyId: widget.academyId,
      className: className,
      startAt: start,
      endAt: end,
    );
    if (overlap != null) {
      _addAssistant(
        'এই সময়ে $className শ্রেণিতে "${overlap['exam_title'] ?? 'অন্য পরীক্ষা'}" '
        'ইতিমধ্যে নির্ধারিত। দয়া করে অন্য একটি সময় বলুন — আমি সঙ্গে সঙ্গে বানিয়ে দেব।',
      );
      return;
    }

    try {
      final marks = asDouble(spec['marks_per_question'], 1);
      final negative = asDouble(spec['negative_marks']);
      final pass = asDouble(spec['pass_percent'], 33);
      final status =
          (spec['status']?.toString() ?? 'published').trim().toLowerCase() ==
              'draft'
          ? 'draft'
          : 'published';

      final ids = await _resolveQuestionIds(
        spec: spec,
        className: className,
        subject: subject,
        chapter: spec['chapter']?.toString().trim().isNotEmpty == true
            ? spec['chapter'].toString()
            : null,
      );
      if (ids.isEmpty) {
        _addAssistant(
          'এই বিষয়ের কোনো প্রশ্ন পাওয়া যায়নি। প্রথমে প্রশ্নব্যাংকে কয়েকটি প্রশ্ন '
          'যোগ করুন, অথবা চ্যাটে প্রশ্নসহ সম্পূর্ণ তালিকা দিন।',
        );
        return;
      }

      await _repository.createTest(
        academyId: widget.academyId,
        className: className,
        subjectName: subject,
        examTitle: title,
        chapterName: spec['chapter']?.toString().trim().isNotEmpty == true
            ? spec['chapter'].toString()
            : null,
        selectedQuestionIds: jsonEncode(ids),
        startAt: start,
        endAt: end,
        status: status,
        creatorId: widget.currentUserId ?? '',
        creatorName: widget.currentUserName ?? 'Teacher',
        durationMinutes: durationMinutes,
        marksPerQuestion: marks,
        totalMarks: marks * ids.length,
        negativeMarks: negative,
        passPercent: pass,
      );

      _addAssistant(
        'সম্পন্ন! "$title" মডেল টেস্ট ${_fmt(start)} থেকে ${_fmt(end)} '
        '(${ids.length} প্রশ্ন, $durationMinutes মিনিট) তৈরি করা হয়েছে। '
        'মডেল টেস্ট তালিকায় ফিরে দেখতে পারেন।',
      );
      widget.onCreated();
    } catch (e) {
      _addAssistant(
        'সংরক্ষণ করা যায়নি: ${ModelTestRepository.friendlyError(e)}',
      );
    }
  }

  Future<List<String>> _resolveQuestionIds({
    required Map<String, dynamic> spec,
    required String className,
    required String subject,
    String? chapter,
  }) async {
    final rawQuestions = spec['questions'];
    if (rawQuestions is List && rawQuestions.isNotEmpty) {
      final hashes = <String>[];
      for (final item in rawQuestions) {
        if (item is! Map) continue;
        final question = item['question']?.toString().trim() ?? '';
        if (question.isEmpty) continue;
        final options = (item['options'] as List?) ?? const <dynamic>[];
        if (options.length != 4) continue;
        final hash = _hash(question);
        await _repository.saveQuestion(
          academyId: widget.academyId,
          className: className,
          subjectName: subject,
          chapterName: chapter ?? 'সম্পূর্ণ বই',
          questionText: question,
          optionA: options[0].toString(),
          optionB: options[1].toString(),
          optionC: options[2].toString(),
          optionD: options[3].toString(),
          correctOption: (item['correct']?.toString() ?? 'A').toUpperCase(),
          explanation: item['explanation']?.toString() ?? '',
          questionHash: hash,
        );
        hashes.add(hash);
      }
      final byHash = await _repository.fetchIdsByHashes(
        academyId: widget.academyId,
        hashes: hashes,
      );
      return hashes.map((hash) => byHash[hash]).whereType<String>().toList();
    }
    return _repository.fetchQuestionIds(
      academyId: widget.academyId,
      className: className,
      subjectName: subject,
      chapterName: chapter,
    );
  }

  void _addAssistant(String text) {
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage(false, text)));
    _scrollToBottom();
  }

  static String _hash(String text) =>
      sha256.convert(utf8.encode(text.trim().toLowerCase())).toString();

  static DateTime? _parseLocal(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal();

  static String _fmt(DateTime? time) {
    if (time == null) return '-';
    final local = time.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text(
              'AI মডেল টেস্ট বিল্ডার',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: AppTheme.tileInkOf(context, Colors.teal),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final message = _messages[index];
                  return Align(
                    alignment: message.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                      ),
                      decoration: BoxDecoration(
                        color: message.isUser
                            ? AppTheme.tileOf(context, Colors.indigo)
                            : AppTheme.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: message.isUser
                            ? null
                            : Border.all(color: AppTheme.borderOf(context)),
                      ),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          fontSize: 13,
                          color: message.isUser
                              ? AppTheme.tileInkOf(context, Colors.indigo)
                              : AppTheme.inkOf(context),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceOf(context),
                border: Border(
                  top: BorderSide(color: AppTheme.borderOf(context)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'প্রম্পট উদাহরণ (টিপে বসানো যায়):',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.mutedOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _examples.map((example) {
                      return ActionChip(
                        label: Text(
                          '${example.split('.').first}.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        tooltip: example,
                        onPressed: _configured && !_isTyping
                            ? () => _send(preset: example)
                            : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: _configured && !_isTyping,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: _configured
                                ? 'সংক্ষেপে লিখুন… যেমন: ${_examples.first.replaceFirst(RegExp(r'^[^.]+\.\s*'), '')}'
                                : 'GEMINI_API_KEY কনফিগার করুন',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _configured && !_isTyping
                            ? () => _send()
                            : null,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
