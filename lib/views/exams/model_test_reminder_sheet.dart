import 'dart:async';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/services/model_test_reminder_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

const _presets = <int>[15, 30, 60];

/// Smart reminder manager shown from the Model Test AppBar.
class ModelTestReminderSheet extends StatefulWidget {
  final String academyId;
  final String studentId;
  final List<ModelTest> tests;
  final VoidCallback onChanged;

  const ModelTestReminderSheet({
    super.key,
    required this.academyId,
    required this.studentId,
    required this.tests,
    required this.onChanged,
  });

  @override
  State<ModelTestReminderSheet> createState() => _ModelTestReminderSheetState();
}

class _ModelTestReminderSheetState extends State<ModelTestReminderSheet> {
  Timer? _ticker;
  List<TestReminder> _reminders = <TestReminder>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final reminders = await ModelTestReminderService.load(
      academyId: widget.academyId,
      studentId: widget.studentId,
    );
    if (!mounted) return;
    setState(() => _reminders = reminders);
  }

  TestReminder? _reminderFor(String testId) {
    for (final reminder in _reminders) {
      if (reminder.testId == testId) return reminder;
    }
    return null;
  }

  Future<void> _toggle(ModelTest test, int minutes) async {
    if (_busy) return;
    final existing = _reminderFor(test.id);
    setState(() => _busy = true);
    try {
      if (existing != null && existing.minutesBefore == minutes) {
        await ModelTestReminderService.remove(
          academyId: widget.academyId,
          studentId: widget.studentId,
          testId: test.id,
        );
        Get.snackbar(
          'রিমাইন্ডার বাতিল',
          '${test.examTitle} এর জন্য রিমাইন্ডার বাতিল করা হয়েছে।',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      } else {
        final startAt = test.startAt ?? DateTime.now();
        final result = await ModelTestReminderService.set(
          academyId: widget.academyId,
          studentId: widget.studentId,
          testId: test.id,
          testTitle: test.examTitle,
          startAt: startAt,
          minutesBefore: minutes,
        );
        Get.snackbar(
          result.saved ? 'সক্রিয়' : 'তথ্য',
          result.message,
          backgroundColor: result.saved ? Colors.teal : Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
      await _load();
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    await ModelTestReminderService.cancelAll(
      academyId: widget.academyId,
      studentId: widget.studentId,
    );
    await _load();
    widget.onChanged();
    Get.snackbar(
      'সম্পন্ন',
      'সব রিমাইন্ডার বাতিল করা হয়েছে।',
      backgroundColor: Colors.teal,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = widget.tests.where((test) => !test.isFinished).toList()
      ..sort((a, b) {
        final aStart = a.startAt ?? DateTime(0);
        final bStart = b.startAt ?? DateTime(0);
        return aStart.compareTo(bStart);
      });

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.borderOf(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.tileOf(context, Colors.amber),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: AppTheme.tileInkOf(context, Colors.amber),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'স্মার্ট রিমাইন্ডার',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.inkOf(context),
                      ),
                    ),
                    Text(
                      'আসন্ন পরীক্ষার আগে সময়মতো জানিয়ে দেব।',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.mutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (_reminders.isNotEmpty)
                TextButton(
                  onPressed: _clearAll,
                  child: Text(
                    'সব বাতিল',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.errorOf(context),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: upcoming.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_available_outlined,
                          size: 48,
                          color: AppTheme.mutedOf(context),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'এই মুহূর্তে কোনো আসন্ন পরীক্ষা নেই।',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.mutedOf(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: upcoming.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildTestCard(upcoming[index]),
                  ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildTestCard(ModelTest test) {
    final reminder = _reminderFor(test.id);
    final now = DateTime.now();
    final start = test.startAt;
    final diff = start == null ? Duration.zero : start.difference(now);
    final countdown = diff.isNegative
        ? 'পরীক্ষা চলছে / শেষ'
        : 'শুরু হতে ${_duration(diff)} বাকি';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.altSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reminder != null
              ? AppTheme.tileOf(context, Colors.amber)
              : AppTheme.borderOf(context),
          width: reminder != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.quiz_outlined,
                size: 17,
                color: AppTheme.tileInkOf(context, Colors.indigo),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  test.examTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.inkOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${test.subjectName} • ${_format(start)}',
            style: TextStyle(fontSize: 11, color: AppTheme.mutedOf(context)),
          ),
          const SizedBox(height: 4),
          Text(
            countdown,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: diff.isNegative ? Colors.red : Colors.teal,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final minutes in _presets) ...[
                ChoiceChip(
                  label: Text(
                    ModelTestReminderService.minutesLabel(minutes),
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: reminder?.minutesBefore == minutes,
                  onSelected: _busy ? null : (_) => _toggle(test, minutes),
                ),
                const SizedBox(width: 7),
              ],
            ],
          ),
          if (reminder != null) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 13,
                  color: reminder.scheduled ? Colors.teal : Colors.amber,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    reminder.scheduled
                        ? 'সক্রিয় — ${ModelTestReminderService.minutesLabel(reminder.minutesBefore)} আগে বিজ্ঞপ্তি'
                        : 'অ্যাপের ভেতরে সক্রিয় (বিজ্ঞপ্তি নির্ধারণ হয়নি)',
                    style: TextStyle(
                      fontSize: 10,
                      color: reminder.scheduled
                          ? Colors.teal
                          : Colors.amber.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _duration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (days > 0) return '$days দিন $hours ঘণ্টা';
    if (hours > 0) return '$hours ঘণ্টা $minutes মিনিট';
    return '$minutes মিনিট $seconds সেকেন্ড';
  }

  static String _format(DateTime? time) {
    if (time == null) return 'সময় নির্ধারিত নেই';
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hour:$minute';
  }
}
