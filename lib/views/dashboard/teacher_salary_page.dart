import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherSalaryPageView extends StatefulWidget {
  final String academyId;
  final String teacherEmail;
  final String teacherName;
  final String teacherId; // শিক্ষকের ইউনিক আইডি (সুপাবেসের users টেবিলের id)

  const TeacherSalaryPageView({
    super.key,
    required this.academyId,
    required this.teacherEmail,
    required this.teacherName,
    required this.teacherId,
  });

  @override
  State<TeacherSalaryPageView> createState() => _TeacherSalaryPageViewState();
}

class _TeacherSalaryPageViewState extends State<TeacherSalaryPageView> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<Map<String, dynamic>> salaryHistoryList = [];

  double monthlySalary = 0.0;
  double totalPaid = 0.0;
  double dueSalary = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchTeacherSalaryAndHistory();
  }

  // অ্যাডমিনের লজিক অনুযায়ী সুপারবেজ থেকে শিক্ষকের বেতন, বকেয়া এবং পেমেন্ট হিস্ট্রি হিসাব করার ফাংশন
  Future<void> _fetchTeacherSalaryAndHistory() async {
    try {
      setState(() {
        isLoading = true;
      });

      // ১. ইউজারের মূল প্রোফাইল থেকে মাসিক বেতন এবং জয়েনিং ডেট (created_at) আনা
      final userResponse = await supabase
          .from('users')
          .select('salary, created_at')
          .eq('id', widget.teacherId)
          .maybeSingle();

      double tempMonthly = 0.0;
      String createdAtStr = '';

      if (userResponse != null) {
        tempMonthly =
            double.tryParse(userResponse['salary']?.toString() ?? '0') ?? 0.0;
        createdAtStr = userResponse['created_at']?.toString() ?? '';
      }

      // ২. অ্যাডমিনের লজিক অনুযায়ী মোট প্রদেয় বেতন হিসাব করা
      double totalPayableSalary = tempMonthly;
      if (createdAtStr.isNotEmpty) {
        DateTime createdAt = DateTime.parse(createdAtStr);
        DateTime now = DateTime.now();

        int totalMonths =
            (now.year - createdAt.year) * 12 + now.month - createdAt.month + 1;
        if (totalMonths < 1) totalMonths = 1;

        totalPayableSalary = totalMonths * tempMonthly;
      }

      // ৩. শিক্ষক স্যালারি হিস্ট্রি টেবিল থেকে পেমেন্ট হিস্ট্রি এবং মোট পরিশোধিত টাকা আনা
      final historyResponse = await supabase
          .from('teacher_salary_history')
          .select('*')
          .eq('teacher_id', widget.teacherId)
          .eq('academy_id', widget.academyId)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> tempList = [];
      double tempPaid = 0.0;

      if (historyResponse != null) {
        tempList = List<Map<String, dynamic>>.from(historyResponse);
        for (var item in tempList) {
          double amt =
              double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
          tempPaid += amt;
        }
      }

      // ৪. চূড়ান্ত বকেয়া হিসাব করা
      double tempDue = totalPayableSalary - tempPaid;
      if (tempDue < 0) tempDue = 0.0;

      if (mounted) {
        setState(() {
          monthlySalary = tempMonthly;
          totalPaid = tempPaid;
          dueSalary = tempDue;
          salaryHistoryList = tempList;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      print("Error fetching salary history: $e");
    }
  }

  // পূর্ববর্তী সকল বেতনের ইতিহাস দেখার পপআপ (অ্যাডমিন প্যানেলের স্টাইলে)
  void _showAllSalaryHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.teacherName} - এর সকল বেতনের ইতিহাস',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.teal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: salaryHistoryList.isEmpty
                        ? const Center(
                            child: Text('কোনো বেতনের ইতিহাস পাওয়া যায়নি।'),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: salaryHistoryList.length,
                            itemBuilder: (context, index) {
                              final history = salaryHistoryList[index];
                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color.fromARGB(
                                    255,
                                    91,
                                    104,
                                    103,
                                  ),
                                  child: Icon(
                                    Icons.receipt_long,
                                    color: Colors.teal,
                                  ),
                                ),
                                title: Text('মাস: ${history['month']}'),
                                subtitle: Text(
                                  'তারিখ: ${history['payment_date'] ?? 'প্রযোজ্য নয়'}',
                                ),
                                trailing: Text(
                                  '৳ ${history['amount']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                    fontSize: 15,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'বেতন ও বকেয়া বিবরণী',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTeacherSalaryAndHistory,
        child: Column(
          children: [
            // উপরে সামারি কার্ড (স্বয়ংক্রিয় হিসাব দেখাবে)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryCard(
                        'মাসের বেতন',
                        '৳${monthlySalary.toStringAsFixed(0)}',
                        Colors.white,
                      ),
                      _buildSummaryCard(
                        'পরিশোধিত',
                        '৳${totalPaid.toStringAsFixed(0)}',
                        Colors.greenAccent,
                      ),
                      _buildSummaryCard(
                        'বকেয়া বেতন',
                        '৳${dueSalary.toStringAsFixed(0)}',
                        Colors.orangeAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // হিস্ট্রি সেকশনের শিরোনাম এবং সব ইতিহাস দেখার বাটন
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'সর্বশেষ পেমেন্ট ইতিহাস',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  TextButton(
                    onPressed: _showAllSalaryHistory,
                    child: const Text(
                      'সব ইতিহাস →',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // পেমেন্ট হিস্ট্রি লিস্ট
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    )
                  : salaryHistoryList.isEmpty
                  ? const Center(
                      child: Text(
                        'কোনো পেমেন্ট হিস্ট্রি পাওয়া যায়নি।',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      itemCount: salaryHistoryList.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final item = salaryHistoryList[index];
                        double amount =
                            double.tryParse(
                              item['amount']?.toString() ?? '0',
                            ) ??
                            0.0;
                        String monthStr = item['month'] ?? 'মাস উল্লেখ নেই';
                        String paymentDate = item['payment_date'] ?? '';

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.shade50,
                              child: const Icon(
                                Icons.payments,
                                color: Colors.teal,
                              ),
                            ),
                            title: Text(
                              'মাস: $monthStr',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              paymentDate.isNotEmpty
                                  ? 'প্রদানের তারিখ: $paymentDate'
                                  : '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            trailing: Text(
                              '+ ৳${amount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String amount, Color textColor) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
