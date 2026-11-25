import 'package:academy_management/services/bengali_numbers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shows the pre-flight confirmation for both official and practice attempts.
///
/// The caller must only call `start_model_test_attempt` (or start the local
/// practice timer) after this returns true.
Future<bool> showModelTestStartDialog({
  required String examTitle,
  required String subjectName,
  required int questionCount,
  required int durationMinutes,
  required double marksPerQuestion,
  required double negativeMarks,
  required bool practice,
}) async {
  final confirmed = await Get.dialog<bool>(
    Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: practice
                        ? Colors.orange.shade50
                        : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    practice ? Icons.school_outlined : Icons.assignment_add,
                    color: practice ? Colors.orange : Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    practice ? 'অনুশীলন শুরু করুন?' : 'পরীক্ষা শুরু করুন?',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              examTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (subjectName.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                'বিষয়: $subjectName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(
                  Icons.help_outline,
                  'মোট প্রশ্ন: ${bn(questionCount)} টি',
                ),
                _infoChip(
                  Icons.timer_outlined,
                  'সময়: ${bn(durationMinutes)} মিনিট',
                ),
                _infoChip(
                  Icons.star_border,
                  'প্রতি প্রশ্ন: ${bnNum(marksPerQuestion)} নম্বর',
                ),
                _infoChip(
                  Icons.remove_circle_outline,
                  'নেগেটিভ: ${bnNum(negativeMarks)} নম্বর',
                ),
              ],
            ),
            if (practice) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'অনুশীলন মোড: কোনো ফলাফল, প্রচেষ্টা বা র‍্যাঙ্কিংয়ে যুক্ত হবে না।',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => Get.back(result: false),
                    child: const Text(
                      'বাতিল করুন',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: practice ? Colors.orange : Colors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => Get.back(result: true),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(
                      practice ? 'অনুশীলন শুরু করুন' : 'পরীক্ষা শুরু করুন',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    barrierDismissible: false,
  );
  return confirmed ?? false;
}

Widget _infoChip(IconData icon, String label) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 260),
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    ),
  ),
);
