import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentFeeDetailsView extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String roll;
  final double monthlyFee;
  final List<Map<String, dynamic>> feeHistoryList;

  const StudentFeeDetailsView({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.roll,
    required this.monthlyFee,
    required this.feeHistoryList,
  });

  @override
  State<StudentFeeDetailsView> createState() => _StudentFeeDetailsViewState();
}

class _StudentFeeDetailsViewState extends State<StudentFeeDetailsView> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _otherCollectionsList = [];
  double _totalOtherCollected = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchOtherCollections();
  }

  // ব্যাকগ্রাউন্ডে সুপাবেস থেকে ডাটা ফেচ করা হবে, কোনো লোডিং স্ক্রিন দেখাবে না
  Future<void> _fetchOtherCollections() async {
    try {
      final response = await supabase
          .from('student_other_collections')
          .select()
          .eq('student_id', widget.studentId);

      List<Map<String, dynamic>> fetchedOthers =
          List<Map<String, dynamic>>.from(response);

      double sumOthers = 0.0;
      int currentYear = DateTime.now().year;

      for (var item in fetchedOthers) {
        String dateStr = item['payment_date'] ?? '';
        if (dateStr.startsWith(currentYear.toString())) {
          sumOthers +=
              double.tryParse((item['amount'] ?? '0').toString()) ?? 0.0;
        }
      }

      if (!mounted) return;
      setState(() {
        _otherCollectionsList = fetchedOthers;
        _totalOtherCollected = sumOthers;
      });
    } catch (e) {
      // ইমপ্লিসিট এরর হ্যান্ডলিং
    }
  }

  @override
  Widget build(BuildContext context) {
    List<String> standardMonths = [
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

    final now = DateTime.now();
    int currentMonthIndex = now.month - 1;
    List<String> applicableMonths = standardMonths.sublist(
      0,
      currentMonthIndex + 1,
    );

    Set<String> paidNormalizedSet = {};
    double totalMonthlyPaidThisYear = 0.0;
    int currentYear = now.year;

    for (var fee in widget.feeHistoryList) {
      String dateStr = fee['payment_date'] ?? '';
      if (dateStr.isEmpty || dateStr.startsWith(currentYear.toString())) {
        double paidAmt =
            double.tryParse(
              (fee['amount'] ?? fee['paid_amount'] ?? '0').toString(),
            ) ??
            0.0;
        totalMonthlyPaidThisYear += paidAmt;
      }

      String m = fee['month']?.toString().toLowerCase() ?? '';
      String clean = m.replaceAll(RegExp(r'[0-9]'), '').replaceAll(' ', '');
      paidNormalizedSet.add(clean);
    }

    int dueMonthsCount = 0;
    List<Map<String, dynamic>> monthlyStatusList = [];

    for (var month in applicableMonths) {
      String cleanStandard = month.replaceAll(' ', '').toLowerCase();
      bool isPaid = paidNormalizedSet.any(
        (paid) => paid.contains(cleanStandard),
      );

      if (!isPaid) {
        dueMonthsCount++;
      }

      monthlyStatusList.add({
        'month': month,
        'isPaid': isPaid,
        'amount': widget.monthlyFee,
      });
    }

    double totalDueAmount = dueMonthsCount * widget.monthlyFee;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'বেতন ও ফি বিবরণী',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ১. মূল একক কার্ড (সকল হিসাব এখানে একসাথে দেখানো হয়েছে)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal.shade200, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.teal,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'মাসিক বেতন ও আর্থিক সারসংক্ষেপ',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, thickness: 1),
                  _buildSummaryRow(
                    'নির্ধারিত মাসিক বেতন:',
                    '৳ ${widget.monthlyFee}',
                    Colors.black87,
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'এ বছর মোট পরিশোধিত বেতন:',
                    '৳ $totalMonthlyPaidThisYear',
                    Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'মোট বকেয়া বেতন:',
                    '৳ $totalDueAmount',
                    Colors.redAccent,
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'অন্যান্য খাতে জমা (সুপাবেস):',
                    '৳ $_totalOtherCollected',
                    Colors.indigo,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ২. অন্যান্য ফি ও জমা হিস্ট্রি (যদি থাকে)
            if (_otherCollectionsList.isNotEmpty) ...[
              const Text(
                'অন্যান্য ফি ও জমা হিস্ট্রি',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _otherCollectionsList.length,
                itemBuilder: (context, index) {
                  var item = _otherCollectionsList[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                color: Colors.teal,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['category'] ?? 'অন্যান্য ফি',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['payment_date'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          '৳ ${item['amount']}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],

            // ৩. চলতি বছরের মাসিক ফি স্ট্যাটাস (এক লাইনে ৩টি করে মাস এবং টিক/ক্রস)
            const Text(
              'চলতি বছরের মাসিক ফি স্ট্যাটাস',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: monthlyStatusList.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // এক লাইনে ৩টি কলাম
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.3,
              ),
              itemBuilder: (context, index) {
                var item = monthlyStatusList[index];
                bool isPaid = item['isPaid'];

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isPaid
                          ? Colors.green.shade300
                          : Colors.red.shade300,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          item['month'],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isPaid
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: isPaid ? Colors.green : Colors.redAccent,
                        size: 16,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String title, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
