import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClassWiseFeeReportView extends StatelessWidget {
  final String academyId;

  const ClassWiseFeeReportView({super.key, required this.academyId});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ক্লাসভিত্তিক ফি ও বকেয়া রিপোর্ট'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: Future.wait([
          supabase.from('students').select().eq('academy_id', academyId),
          supabase
              .from('student_fee_history')
              .select()
              .eq('academy_id', academyId),
        ]),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.teal),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('কোনো ডাটা পাওয়া যায়নি।'));
          }

          final students = snapshot.data![0] as List;
          final history = snapshot.data![1] as List;

          // ক্লাস অনুযায়ী গ্রুপ করা
          Map<String, List<dynamic>> classMap = {};
          for (var student in students) {
            String className = student['class_name'] ?? 'অন্যান্য';
            if (!classMap.containsKey(className)) classMap[className] = [];
            classMap[className]!.add(student);
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: classMap.keys.map((className) {
              final classStudents = classMap[className]!;
              double expectedTotal = 0;
              double collectedTotal = 0;
              List<dynamic> unpaidStudents = [];

              for (var student in classStudents) {
                double fee =
                    double.tryParse(
                      student['monthly_fee']?.toString() ?? '0',
                    ) ??
                    0.0;
                expectedTotal += fee;

                // বর্তমান মাসের কালেকশন চেক
                final now = DateTime.now();
                List<String> months = [
                  'জানুয়ারি',
                  'ফেব্রুয়ারি',
                  'মার্চ',
                  'এপ্রিল',
                  'মে',
                  'জুন',
                  'জুলাই',
                  'আগস্ট',
                  'সেপ্টেম্বর',
                  'অক্টোবর',
                  'নভেম্বর',
                  'ডিসেম্বর',
                ];
                String currentMonthStr = '${months[now.month - 1]} ${now.year}';

                var paidRecord = history.firstWhere(
                  (h) =>
                      h['student_id'] == student['id'] &&
                      (h['month']?.toString().contains(months[now.month - 1]) ??
                          false),
                  orElse: () => null,
                );

                if (paidRecord != null) {
                  collectedTotal +=
                      double.tryParse(
                        paidRecord['amount']?.toString() ?? '0',
                      ) ??
                      0.0;
                } else {
                  unpaidStudents.add(student);
                }
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ক্লাস: $className',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const Divider(),
                      Text('মোট ওঠার কথা: ৳ $expectedTotal'),
                      Text(
                        'মোট উঠেছে: ৳ $collectedTotal',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'বকেয়া ছাত্র সংখ্যা: ${unpaidStudents.length} জন',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ফি দেয়নি যারা:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      ...unpaidStudents.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2),
                          child: Text(
                            '• ${s['full_name']} (মোবাইল: ${s['phone'] ?? 'নেই'})',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
