import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminComplaintsView extends StatefulWidget {
  final String academyId;

  const AdminComplaintsView({super.key, required this.academyId});

  @override
  State<AdminComplaintsView> createState() => _AdminComplaintsViewState();
}

class _AdminComplaintsViewState extends State<AdminComplaintsView> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // অভিযোগের স্ট্যাটাস আপডেট করার ফাংশন
  Future<void> _updateComplaintStatus(
    String complaintId,
    String newStatus,
  ) async {
    try {
      await _supabase
          .from('complaints')
          .update({'status': newStatus})
          .eq('id', complaintId);

      Get.snackbar(
        'সফল',
        'অভিযোগের স্ট্যাটাস আপডেট করা হয়েছে ($newStatus)',
        backgroundColor: Colors.green.shade50,
        colorText: Colors.green.shade900,
        snackPosition: SnackPosition.BOTTOM,
      );
      setState(() {}); // UI রিফ্রেশ করার জন্য
    } catch (e) {
      Get.snackbar(
        'ত্রুটি',
        'স্ট্যাটাস আপডেট করতে সমস্যা হয়েছে: $e',
        backgroundColor: Colors.red.shade50,
        colorText: Colors.red.shade900,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Widget _buildComplaintCard(Map<String, dynamic> item, bool isPending) {
    final complaintId = item['id'].toString();
    final title = item['title'] ?? 'শিরোনামহীন';
    final details = item['details'] ?? '';
    final studentName = item['student_name'] ?? 'Anonymous';
    final className = item['class_name'] ?? '';
    final roll = item['roll'] ?? '';
    final isAnonymous = item['is_anonymous'] ?? true;
    final status = item['status'] ?? (isPending ? 'Pending' : 'Resolved');

    Color statusColor = isPending ? Colors.orange : Colors.green;

    String dateStr = '';
    if (item['created_at'] != null) {
      try {
        dateStr = item['created_at'].toString().substring(0, 10);
      } catch (_) {
        dateStr = '';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              details,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ৩টি লাইন নিচে নিচে সাজানো হয়েছে
                      if (isAnonymous)
                        const Text(
                          'প্রেরক: গোপন (Anonymous)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        )
                      else ...[
                        Text(
                          'নাম: $studentName',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'রোল: $roll',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ক্লাস: $className',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                      if (dateStr.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'তারিখ: $dateStr',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isPending)
                  ElevatedButton.icon(
                    onPressed: () {
                      _updateComplaintStatus(complaintId, 'Resolved');
                    },
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text(
                      'সমাধান করুন',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  )
                else
                  const Text(
                    'সম্পন্ন',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'শিক্ষার্থীদের অভিযোগসমূহ',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _supabase
            .from('complaints')
            .select()
            .eq('academy_id', widget.academyId)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'অভিযোগগুলো লোড করতে সমস্যা হচ্ছে।\n\nত্রুটি: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            );
          }

          final allComplaints = snapshot.data ?? [];

          final pendingList = allComplaints
              .where((item) => (item['status'] ?? 'Pending') == 'Pending')
              .toList();

          final resolvedList = allComplaints
              .where((item) => item['status'] == 'Resolved')
              .toList();

          if (allComplaints.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.check_circle_outline,
                    size: 60,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'কোনো অভিযোগ পাওয়া যায়নি!',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ১. পেন্ডিং সেকশন (উপরে)
                const Row(
                  children: [
                    Icon(Icons.pending_actions, color: Colors.orange, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'পেন্ডিং অভিযোগসমূহ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  flex: 1,
                  child: pendingList.isEmpty
                      ? const Center(
                          child: Text(
                            'কোনো পেন্ডিং অভিযোগ নেই।',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: pendingList.length,
                          itemBuilder: (context, index) {
                            return _buildComplaintCard(
                              pendingList[index],
                              true,
                            );
                          },
                        ),
                ),

                const Divider(height: 24, thickness: 1.5),

                // ২. সমাধানকৃত সেকশন (নিচে)
                const Row(
                  children: [
                    Icon(Icons.task_alt, color: Colors.green, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'সমাধানকৃত অভিযোগসমূহ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  flex: 1,
                  child: resolvedList.isEmpty
                      ? const Center(
                          child: Text(
                            'এখনো কোনো অভিযোগ সমাধান করা হয়নি।',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: resolvedList.length,
                          itemBuilder: (context, index) {
                            return _buildComplaintCard(
                              resolvedList[index],
                              false,
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
