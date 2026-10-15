import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionPlanView extends StatefulWidget {
  const SubscriptionPlanView({super.key});

  @override
  State<SubscriptionPlanView> createState() => _SubscriptionPlanViewState();
}

class _SubscriptionPlanViewState extends State<SubscriptionPlanView> {
  String _selectedPlan = 'premium';
  final supabase = Supabase.instance.client;

  void _showBasicPlanNotice() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.info_outline, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text(
              'বেসিক প্ল্যান স্থগিত',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'দুঃখিত! বেসিক (মাসিক) প্ল্যানটি আপাতত চালু নেই।\n\nআপনি নিশ্চিন্তে লাইফটাইম অ্যাক্সেসের জন্য "প্রিমিয়াম" প্ল্যানটি সিলেক্ট করতে পারেন।',
          style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _selectedPlan = 'premium';
              });
            },
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
    );
  }

  void _showPaymentBottomSheet() {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController txnController = TextEditingController();
    String selectedMethod = 'bKash';
    bool isLoading = false;
    const String paymentNumber = '01883073202';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Icon(
                          Icons.payment_rounded,
                          color: Colors.teal,
                          size: 26,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'পেমেন্ট তথ্য প্রদান করুন',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.teal.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'টাকা পাঠানোর নম্বর (Send Money):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                paymentNumber,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.teal,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                    const ClipboardData(text: paymentNumber),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: const [
                                          Icon(
                                            Icons.check_circle,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text('নম্বর সফলভাবে কপি করা হয়েছে!'),
                                        ],
                                      ),
                                      backgroundColor: Colors.teal.shade700,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                    color: Colors.teal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'bKash / Nagad / Rocket / Upay',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                          const Divider(height: 14),
                          const Text(
                            'পরিমাণ: ৳ ১,০০০ (লাইফটাইম)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'পেমেন্ট মাধ্যম সিলেক্ট করুন:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: selectedMethod,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: ['bKash', 'Nagad', 'Rocket', 'Upay']
                          .map(
                            (method) => DropdownMenuItem(
                              value: method,
                              child: Text(method),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setBottomSheetState(() {
                            selectedMethod = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'যে নম্বর থেকে টাকা পাঠিয়েছেন:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '০17xxxxxxxx',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ট্রানজেকশন আইডি (TxnID):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: txnController,
                      decoration: InputDecoration(
                        hintText: 'যেমন: 9J87X10A2P',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isLoading
                            ? null
                            : () async {
                                final phone = phoneController.text.trim();
                                final txnId = txnController.text.trim();

                                if (phone.isEmpty || txnId.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'দয়া করে আপনার নম্বর এবং TxnID উভয় তথ্যই প্রদান করুন!',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                setBottomSheetState(() {
                                  isLoading = true;
                                });

                                try {
                                  final currentUserEmail =
                                      supabase.auth.currentUser?.email;
                                  if (currentUserEmail == null) {
                                    throw 'ইউজার ইমেইল পাওয়া যায়নি!';
                                  }

                                  // ১. users টেবิล থেকে academy_id বের করা
                                  final userResponse = await supabase
                                      .from('users')
                                      .select('academy_id')
                                      .eq('email', currentUserEmail)
                                      .maybeSingle();

                                  final academyId = userResponse?['academy_id']
                                      ?.toString();

                                  String? academyName;
                                  // ২. academies টেবিল থেকে academy_id দিয়ে প্রতিষ্ঠানের নাম (academy_name) আনা[cite: 7]
                                  if (academyId != null) {
                                    final academyResponse = await supabase
                                        .from('academies')
                                        .select('academy_name')
                                        .eq('id', academyId)
                                        .maybeSingle();

                                    academyName =
                                        academyResponse?['academy_name']
                                            ?.toString();
                                  }

                                  // ৩. subscription_requests টেবিলে প্রতিষ্ঠানের নামসহ ডাটা সেভ করা
                                  await supabase
                                      .from('subscription_requests')
                                      .insert({
                                        'user_email': currentUserEmail,
                                        'academy_id': academyId,
                                        'academy_name':
                                            academyName, // অটো যুক্ত হলো
                                        'plan_type': 'premium_lifetime',
                                        'amount': 1000,
                                        'payment_method': selectedMethod,
                                        'sender_number': phone,
                                        'transaction_id': txnId,
                                        'status': 'pending',
                                      });

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showSuccessThanksDialog();
                                  }
                                } catch (e) {
                                  setBottomSheetState(() {
                                    isLoading = false;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'সাবমিট করতে সমস্যা হয়েছে: $e',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'সাবমিট করুন',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSuccessThanksDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 55),
            SizedBox(height: 8),
            Text(
              'ধন্যবাদ!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
        content: const Text(
          'আপনার পেমেন্ট তথ্য সফলভাবে জমা নেওয়া হয়েছে।\n\nসার্ভারের কাজের জন্য একটু লেট হতে পারে। ভেরিফিকেশন সম্পন্ন হওয়া মাত্রই আপনার প্রিমিয়াম ফিচার চালু হয়ে যাবে।',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('ঠিক আছে'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'সাবস্ক্রিপশন প্ল্যান',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                size: 60,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'আপনার একাডেমি পরিচালনা করুন আরও সহজে!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'আপনার পছন্দ অনুযায়ী প্ল্যান বেছে নিয়ে সকল প্রিমিয়াম ফিচার আনলক করুন।',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPlan = 'premium';
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _selectedPlan == 'premium'
                          ? Colors.teal.shade50
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _selectedPlan == 'premium'
                            ? Colors.teal
                            : Colors.grey.shade300,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Radio<String>(
                              value: 'premium',
                              groupValue: _selectedPlan,
                              activeColor: Colors.teal,
                              onChanged: (value) {
                                setState(() {
                                  _selectedPlan = value!;
                                });
                              },
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'প্রিমিয়াম প্ল্যান (Premium)',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'এককালীন পেমেন্ট • নিশ্চিন্তে লাইফটাইম!',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Text(
                              '৳ ১,০০০\n/লাইফটাইম',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -10,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'BEST VALUE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                _showBasicPlanNotice();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: Row(
                  children: [
                    Radio<String>(
                      value: 'basic',
                      groupValue: _selectedPlan,
                      activeColor: Colors.teal,
                      onChanged: (value) {
                        _showBasicPlanNotice();
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'বেসিক প্ল্যান (Basic)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'সাময়িক স্থগিত',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'প্রতি মাসে রিনিউযোগ্য (মাসিক)',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      '৳ ৯৯\n/মাস',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    color: Colors.blue.shade700,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '১০০% মানি-ব্যাক গ্যারান্টি সুবিধা!',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'পেমেন্ট সম্পর্কিত কোনো সমস্যা হলে বা সার্ভিস পছন্দ না হলে ২৪ ঘণ্টার মধ্যে রিফান্ড রিকোয়েস্ট করতে পারবেন।',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade900.withOpacity(0.8),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (_selectedPlan == 'basic') {
                    _showBasicPlanNotice();
                  } else {
                    _showPaymentBottomSheet();
                  }
                },
                child: const Text(
                  'পেমেন্ট সম্পন্ন করুন (৳ ১,০০০)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 13, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  'ম্যানুয়াল ভেরিফিকেশন ও সুরক্ষিত সার্ভিস',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
