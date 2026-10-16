import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SuperAdminManagementView extends StatefulWidget {
  final String academyId;

  const SuperAdminManagementView({super.key, required this.academyId});

  @override
  State<SuperAdminManagementView> createState() =>
      _SuperAdminManagementViewState();
}

class _SuperAdminManagementViewState extends State<SuperAdminManagementView> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // ফিল্টার ক্যাটাগরি (All, Teachers, Staff)
  String _selectedRoleFilter = 'All';

  @override
  void initState() {
    super.initState();
    _fetchTeachersAndStaff();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTeachersAndStaff() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('users')
          .select('*')
          .eq('academy_id', widget.academyId)
          .inFilter('role', ['teacher', 'super_admin', 'staff']);

      final List<Map<String, dynamic>> loadedData =
          List<Map<String, dynamic>>.from(response);

      if (mounted) {
        setState(() {
          _allUsers = loadedData;
          _isLoading = false;
          _filterUsers();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      _filteredUsers = _allUsers.where((user) {
        // ১. রোল ফিল্টার প্রয়োগ
        String role = (user['role'] ?? '').toString().toLowerCase();
        bool matchesRole = true;
        if (_selectedRoleFilter == 'Teachers') {
          matchesRole = role == 'teacher' || role == 'super_admin';
        } else if (_selectedRoleFilter == 'Staff') {
          matchesRole = role == 'staff';
        }

        // ২. সার্চ কুয়েরি প্রয়োগ (নাম, ইমেইল, ফোন ও রোলের ওপর কাজ করবে)
        String name = (user['full_name'] ?? user['name'] ?? '')
            .toString()
            .toLowerCase();
        String email = (user['email'] ?? '').toString().toLowerCase();
        String phone = (user['phone'] ?? user['phone_number'] ?? '')
            .toString()
            .toLowerCase();

        bool matchesSearch =
            query.isEmpty ||
            name.contains(query) ||
            email.contains(query) ||
            phone.contains(query) ||
            role.contains(query);

        return matchesRole && matchesSearch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'নাম, ইমেইল বা ফোন দিয়ে খুঁজুন...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : const Text('সুপার এডমিন এক্সচেঞ্জ ও তালিকা'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : _errorMessage.isNotEmpty
          ? Center(child: Text('ত্রুটি: $_errorMessage'))
          : Column(
              children: [
                // ডানে-বামে স্ক্রোল করার মত ফিল্টার বাটনসমূহ (Slide / Filter Chips)
                Container(
                  height: 55,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _buildFilterChip('All', 'সকল'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Teachers', 'শিক্ষক'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Staff', 'স্টাফ'),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                Expanded(
                  child: _filteredUsers.isEmpty
                      ? const Center(
                          child: Text(
                            'কোনো ব্যবহারকারী পাওয়া যায়নি!',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredUsers.length,
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            final item = _filteredUsers[index];
                            String name =
                                item['full_name'] ?? item['name'] ?? 'নামহীন';
                            String email = item['email'] ?? 'ইমেইল নেই';
                            String phone =
                                item['phone'] ??
                                item['phone_number'] ??
                                'নম্বর নেই';
                            String role = item['role'] ?? 'teacher';

                            // Supabase থেকে প্রাপ্ত সঠিক 'photo_url' কলাম ব্যবহার করা হয়েছে
                            String? photoUrl = item['photo_url'];

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.teal.shade100,
                                  backgroundImage:
                                      photoUrl != null && photoUrl.isNotEmpty
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child: photoUrl == null || photoUrl.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.teal,
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      'ইমেইল: $email',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'ফোন: $phone',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'রোল: ${role.toUpperCase()}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.swap_horiz_rounded,
                                    color: Colors.teal,
                                    size: 28,
                                  ),
                                  tooltip: 'রোল এক্সচেঞ্জ করুন',
                                  onPressed: () {
                                    _showExchangeDialog(item);
                                  },
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    bool isSelected = _selectedRoleFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.teal,
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _selectedRoleFilter = value;
            _filterUsers();
          });
        }
      },
    );
  }

  void _showExchangeDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // ডায়ালগের নিজস্ব context ব্যবহার করা ভালো
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('সুপার এডমিন এক্সচেঞ্জ'),
          content: Text(
            'আপনি কি ${user['full_name'] ?? user['name'] ?? 'এই ব্যবহারকারী'}-কে সুপার এডমিন রোলে পরিবর্তন করতে চান?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('বাতিল'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext); // ডায়ালগ বন্ধ করা

                // লোডিং ইন্ডিকেটর দেখানো
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (loadingContext) => const Center(
                    child: CircularProgressIndicator(color: Colors.teal),
                  ),
                );

                try {
                  final supabase = Supabase.instance.client;

                  // Supabase এর users টেবিলে রোল 'super_admin' করে আপডেট করা
                  await supabase
                      .from('users')
                      .update({'role': 'super_admin'})
                      .eq('id', user['id']);

                  if (!mounted) return;
                  Navigator.of(context).pop(); // লোডিং ডায়ালগ বন্ধ করা

                  Get.snackbar(
                    'সফল',
                    'সফলভাবে সুপার এডমিন হিসেবে রূপান্তর করা হয়েছে!',
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                  );

                  // পেজটি রিফ্রেশ বা রিলোড করা যাতে লিস্ট আপডেট দেখায়
                  _fetchTeachersAndStaff();
                } catch (e) {
                  if (!mounted) return;
                  Navigator.of(context).pop(); // লোডিং ডায়ালগ বন্ধ করা

                  Get.snackbar(
                    'ত্রুটি',
                    'রোল পরিবর্তন করতে সমস্যা হয়েছে: $e',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                }
              },
              child: const Text('নিশ্চিত করুন'),
            ),
          ],
        );
      },
    );
  }
}
