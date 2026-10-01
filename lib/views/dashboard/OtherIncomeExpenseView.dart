import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OtherIncomeExpenseView extends StatefulWidget {
  final String academyId;

  const OtherIncomeExpenseView({super.key, required this.academyId});

  @override
  State<OtherIncomeExpenseView> createState() => _OtherIncomeExpenseViewState();
}

class _OtherIncomeExpenseViewState extends State<OtherIncomeExpenseView> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  bool isSearching = false; // সার্চ মোড ট্র্যাক করার জন্য
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> filteredTransactions = [];

  final TextEditingController searchController = TextEditingController();

  double totalIncome = 0.0;
  double totalExpense = 0.0;

  final List<String> defaultExpenseCategories = [
    'বিদ্যুৎ বিল',
    'ইন্টারনেট বিল',
    'ঘর ভাড়া',
    'অফিস স্টেশনারি',
    'মেরামত ও রক্ষণাবেক্ষণ',
    'অন্যান্য ব্যয়',
  ];

  final List<String> defaultIncomeCategories = [
    'অনুদান বা স্পন্সরশিপ',
    'অন্যান্য আয়',
  ];

  List<String> customExpenseCategories = [];
  List<String> customIncomeCategories = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
    searchController.addListener(_filterTransactions);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    setState(() => isLoading = true);
    try {
      final response = await supabase
          .from('other_income_expenses')
          .select('*')
          .eq('academy_id', widget.academyId)
          .order('date', ascending: false)
          .order('created_at', ascending: false);

      transactions = List<Map<String, dynamic>>.from(response);
      filteredTransactions = transactions;

      double income = 0.0;
      double expense = 0.0;
      Set<String> expCustomSet = {};
      Set<String> incCustomSet = {};

      for (var item in transactions) {
        double amt = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
        String type = item['type'] ?? '';
        String cat = item['category']?.toString() ?? '';

        if (type == 'income') {
          income += amt;
          if (cat.isNotEmpty && !defaultIncomeCategories.contains(cat)) {
            incCustomSet.add(cat);
          }
        } else if (type == 'expense') {
          expense += amt;
          if (cat.isNotEmpty && !defaultExpenseCategories.contains(cat)) {
            expCustomSet.add(cat);
          }
        }
      }

      totalIncome = income;
      totalExpense = expense;
      customExpenseCategories = expCustomSet.toList();
      customIncomeCategories = incCustomSet.toList();

      _filterTransactions();
    } catch (e) {
      Get.snackbar(
        "ত্রুটি",
        "ডেটা লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _filterTransactions() {
    String query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        filteredTransactions = transactions;
      });
    } else {
      setState(() {
        filteredTransactions = transactions.where((tx) {
          String date = tx['date']?.toString().toLowerCase() ?? '';
          String category = tx['category']?.toString().toLowerCase() ?? '';
          String note = tx['note']?.toString().toLowerCase() ?? '';

          return date.contains(query) ||
              category.contains(query) ||
              note.contains(query);
        }).toList();
      });
    }
  }

  void _showAddTransactionDialog() {
    String type = 'expense';
    String? selectedCategory;
    final TextEditingController amountController = TextEditingController();
    final TextEditingController noteController = TextEditingController();
    final TextEditingController newCategoryController = TextEditingController();
    bool isAddingNewCategory = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<String> currentCategories = (type == 'expense')
                ? [...defaultExpenseCategories, ...customExpenseCategories]
                : [...defaultIncomeCategories, ...customIncomeCategories];

            if (selectedCategory == null ||
                !currentCategories.contains(selectedCategory)) {
              selectedCategory = currentCategories.isNotEmpty
                  ? currentCategories[0]
                  : null;
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'নতুন হিসাব যোগ করুন',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(
                                child: Text('ব্যয় (Expense)'),
                              ),
                              selected: type == 'expense',
                              selectedColor: Colors.red.shade100,
                              labelStyle: TextStyle(
                                color: type == 'expense'
                                    ? Colors.red.shade900
                                    : Colors.black,
                              ),
                              onSelected: (val) {
                                setModalState(() {
                                  type = 'expense';
                                  selectedCategory = null;
                                  isAddingNewCategory = false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('আয় (Income)')),
                              selected: type == 'income',
                              selectedColor: Colors.green.shade100,
                              labelStyle: TextStyle(
                                color: type == 'income'
                                    ? Colors.green.shade900
                                    : Colors.black,
                              ),
                              onSelected: (val) {
                                setModalState(() {
                                  type = 'income';
                                  selectedCategory = null;
                                  isAddingNewCategory = false;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),

                      isAddingNewCategory
                          ? Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newCategoryController,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: 'নতুন খাতের নাম লিখুন',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 30,
                                  ),
                                  onPressed: () {
                                    String newCat = newCategoryController.text
                                        .trim();
                                    if (newCat.isNotEmpty) {
                                      setModalState(() {
                                        if (type == 'expense') {
                                          if (!customExpenseCategories.contains(
                                            newCat,
                                          )) {
                                            customExpenseCategories.add(newCat);
                                          }
                                        } else {
                                          if (!customIncomeCategories.contains(
                                            newCat,
                                          )) {
                                            customIncomeCategories.add(newCat);
                                          }
                                        }
                                        selectedCategory = newCat;
                                        isAddingNewCategory = false;
                                        newCategoryController.clear();
                                      });
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.cancel,
                                    color: Colors.red,
                                    size: 30,
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      isAddingNewCategory = false;
                                    });
                                  },
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: selectedCategory,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'খাত বা ক্যাটাগরি নির্বাচন করুন',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: currentCategories.map((cat) {
                                      return DropdownMenuItem(
                                        value: cat,
                                        child: Text(cat),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null)
                                        setModalState(
                                          () => selectedCategory = val,
                                        );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'নতুন খাত যোগ করুন',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.blueGrey.shade50,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.add,
                                    color: Colors.blueGrey,
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      isAddingNewCategory = true;
                                    });
                                  },
                                ),
                              ],
                            ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'টাকার পরিমাণ (৳)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(
                          labelText: 'বিবরণ বা নোট (ঐচ্ছিক)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            if (isAddingNewCategory) {
                              String typedCat = newCategoryController.text
                                  .trim();
                              if (typedCat.isNotEmpty) {
                                selectedCategory = typedCat;
                                if (type == 'expense') {
                                  if (!customExpenseCategories.contains(
                                    typedCat,
                                  )) {
                                    customExpenseCategories.add(typedCat);
                                  }
                                } else {
                                  if (!customIncomeCategories.contains(
                                    typedCat,
                                  )) {
                                    customIncomeCategories.add(typedCat);
                                  }
                                }
                              }
                            }

                            String amtText = amountController.text.trim();
                            if (amtText.isEmpty ||
                                double.tryParse(amtText) == null) {
                              Get.snackbar(
                                "ত্রুটি",
                                "সঠিক টাকার পরিমাণ লিখুন",
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                              return;
                            }

                            if (selectedCategory == null ||
                                selectedCategory!.isEmpty) {
                              Get.snackbar(
                                "ত্রুটি",
                                "দয়া করে একটি খাত নির্বাচন করুন বা লিখুন",
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                              return;
                            }

                            double amount = double.parse(amtText);
                            String note = noteController.text.trim();
                            String date = DateTime.now().toString().split(
                              ' ',
                            )[0];

                            try {
                              await supabase
                                  .from('other_income_expenses')
                                  .insert({
                                    'academy_id': widget.academyId,
                                    'type': type,
                                    'category': selectedCategory,
                                    'amount': amount,
                                    'note': note,
                                    'date': date,
                                  });

                              Navigator.pop(context);
                              _fetchTransactions();
                              Get.snackbar(
                                "সফল",
                                "হিসাব সফলভাবে যোগ করা হয়েছে",
                                backgroundColor: Colors.green,
                                colorText: Colors.white,
                              );
                            } catch (e) {
                              Get.snackbar(
                                "ত্রুটি",
                                "সংরক্ষণ করা যায়নি: $e",
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            }
                          },
                          child: const Text(
                            'সংরক্ষণ করুন',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteTransaction(String id) async {
    try {
      await supabase.from('other_income_expenses').delete().eq('id', id);
      _fetchTransactions();
      Get.snackbar(
        "সফল",
        "হিসাব ডিলিট করা হয়েছে",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        "ত্রুটি",
        "ডিলিট করা যায়নি: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double netBalance = totalIncome - totalExpense;

    Map<String, List<Map<String, dynamic>>> groupedTransactions = {};
    for (var tx in filteredTransactions) {
      String date = tx['date'] ?? 'অজানা তারিখ';
      if (!groupedTransactions.containsKey(date)) {
        groupedTransactions[date] = [];
      }
      groupedTransactions[date]!.add(tx);
    }

    List<String> sortedDates = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        // অ্যাপবার সার্চ মোডে থাকলে TextField দেখাবে, না থাকলে নরমাল টাইটেল দেখাবে
        title: isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'তারিখ বা খাত দিয়ে খুঁজুন...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : const Text('অন্যান্য আয় ও ব্যয়'),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (isSearching) {
                  searchController.clear();
                }
                isSearching = !isSearching;
              });
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueGrey),
            )
          : Column(
              children: [
                // সামারি কার্ড সেকশন
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryCard(
                        'মোট আয়',
                        '৳ ${totalIncome.toStringAsFixed(0)}',
                        Colors.green,
                      ),
                      _buildSummaryCard(
                        'মোট ব্যয়',
                        '৳ ${totalExpense.toStringAsFixed(0)}',
                        Colors.red,
                      ),
                      _buildSummaryCard(
                        'নেট ব্যালেন্স',
                        '৳ ${netBalance.toStringAsFixed(0)}',
                        Colors.blue,
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // তারিখ অনুযায়ী গ্রুপ করা লিস্ট ভিউ
                Expanded(
                  child: sortedDates.isEmpty
                      ? const Center(
                          child: Text(
                            'কোনো হিসাব পাওয়া যায়নি।',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          itemCount: sortedDates.length,
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            String date = sortedDates[index];
                            List<Map<String, dynamic>> dateTransactions =
                                groupedTransactions[date]!;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // তারিখের হেডার
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                        color: Colors.blueGrey,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        date,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ওই তারিখের আন্ডারে লেনদেনের কার্ডগুলো
                                ...dateTransactions.map((tx) {
                                  bool isIncome = tx['type'] == 'income';
                                  double amt =
                                      double.tryParse(
                                        tx['amount'].toString(),
                                      ) ??
                                      0.0;

                                  return Card(
                                    elevation: 1,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 0,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: isIncome
                                            ? Colors.green.shade100
                                            : Colors.red.shade100,
                                        child: Icon(
                                          isIncome
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          color: isIncome
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                      title: Text(
                                        tx['category'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle:
                                          tx['note'] != null &&
                                              tx['note'].toString().isNotEmpty
                                          ? Text('নোট: ${tx['note']}')
                                          : null,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${isIncome ? '+' : '-'} ৳ ${amt.toStringAsFixed(0)}',
                                            style: TextStyle(
                                              color: isIncome
                                                  ? Colors.green
                                                  : Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.grey,
                                            ),
                                            onPressed: () {
                                              Get.defaultDialog(
                                                title: "ডিলিট নিশ্চিত করুন",
                                                middleText:
                                                    "আপনি কি এই হিসাবটি মুছে ফেলতে চান?",
                                                textConfirm: "হ্যাঁ",
                                                textCancel: "না",
                                                confirmTextColor: Colors.white,
                                                onConfirm: () {
                                                  Get.back();
                                                  _deleteTransaction(tx['id']);
                                                },
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 10),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueGrey,
        onPressed: _showAddTransactionDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'হিসাব যোগ করুন',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
