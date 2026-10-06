import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AcademyRegisterView extends StatefulWidget {
  const AcademyRegisterView({super.key});

  @override
  State<AcademyRegisterView> createState() => _AcademyRegisterViewState();
}

class _AcademyRegisterViewState extends State<AcademyRegisterView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController academyNameController = TextEditingController();
  final TextEditingController addressController =
      TextEditingController(); // ঠিকানার জন্য কন্ট্রোলার
  final TextEditingController adminNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true; // পাসওয়ার্ড হাইড বা শো করার স্টেট

  // প্রতিষ্ঠান তাদের ইচ্ছামমতো ক্লাস নাম ও ক্রম যোগ করার জন্য কন্ট্রোলার লিস্ট
  final List<TextEditingController> classControllers = [
    TextEditingController(text: 'ষষ্ঠ শ্রেণি'),
    TextEditingController(text: 'সপ্তম শ্রেণি'),
    TextEditingController(text: 'অষ্টম শ্রেণি'),
    TextEditingController(text: 'নবম শ্রেণি'),
    TextEditingController(text: 'দশম শ্রেণি'),
  ];

  bool isLoading = false;

  // নতুন ক্লাস ফিল্ড যোগ করার ফাংশন
  void addClassField() {
    setState(() {
      classControllers.add(TextEditingController());
    });
  }

  // ক্লাস ফিল্ড রিমুভ করার ফাংশন
  void removeClassField(int index) {
    if (classControllers.length > 1) {
      setState(() {
        classControllers[index].dispose();
        classControllers.removeAt(index);
      });
    } else {
      Get.snackbar(
        "সতর্কতা",
        "কমপক্ষে একটি ক্লাস থাকতেই হবে।",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
  }

  @override
  void dispose() {
    academyNameController.dispose();
    addressController.dispose(); // কন্ট্রোলার ডিসপোজ করা হলো
    adminNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    for (var controller in classControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // একাডেমি ও সুপার অ্যাডমিন রেজিস্ট্রেশন লজিক
  Future<void> registerAcademy() async {
    if (!_formKey.currentState!.validate()) return;

    // খালি ফিল্ড বাদ দিয়ে ক্লাসের নামগুলো নেওয়া
    List<String> validClasses = classControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (validClasses.isEmpty) {
      Get.snackbar(
        "ত্রুটি!",
        "অনুগ্রহ করে কমপক্ষে একটি ক্লাস যুক্ত করুন।",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;

      // ১. সুপাবেস অথ-এ অ্যাকাউন্ট তৈরি
      final AuthResponse authResponse = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (authResponse.user != null) {
        // ২. academies টেবিলে নতুন একাডেমির তথ্য ও ঠিকানা সেভ করা[cite: 3]
        final academyResponse = await supabase
            .from('academies')
            .insert({
              'academy_name': academyNameController.text.trim(),
              'address': addressController.text
                  .trim(), // ঠিকানা যুক্ত করা হয়েছে
              'admin_email': emailController.text.trim(),
            })
            .select()
            .single();

        String academyId = academyResponse['id'];

        // ৩. users টেবিলে প্রধান শিক্ষকের তথ্য ও role হিসেবে 'super_admin' সেভ করা[cite: 3]
        await supabase.from('users').insert({
          'academy_id': academyId,
          'email': emailController.text.trim(),
          'full_name': adminNameController.text.trim(),
          'role': 'super_admin',
        });

        // ৪. ক্লাসের তালিকা এবং সিরিয়াল সুপাবেসের 'classes' টেবিলে সেভ করা[cite: 3]
        for (int i = 0; i < validClasses.length; i++) {
          await supabase.from('classes').insert({
            'academy_id': academyId,
            'class_name': validClasses[i],
            'class_order': i + 1,
          });
        }

        Get.snackbar(
          "সফল হয়েছে!",
          "একাডেমি এবং ক্লাসের তালিকা সফলভাবে রেজিস্টার্ড হয়েছে। এখন লগইন করুন।",
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        "ত্রুটি!",
        e.toString(),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Academy Registration'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.school, size: 80, color: Colors.teal),
                  const SizedBox(height: 20),
                  const Text(
                    'আপনার একাডেমির জন্য অ্যাকাউন্ট খুলুন',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),

                  // একাডেমির নাম
                  TextFormField(
                    controller: academyNameController,
                    decoration: InputDecoration(
                      labelText: 'একাডেমির নাম',
                      prefixIcon: const Icon(Icons.business),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'একাডেমির নাম দিন' : null,
                  ),
                  const SizedBox(height: 15),

                  // প্রতিষ্ঠানের ঠিকানা (নতুন ফিল্ড)
                  TextFormField(
                    controller: addressController,
                    decoration: InputDecoration(
                      labelText: 'প্রতিষ্ঠানের ঠিকানা',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'প্রতিষ্ঠানের ঠিকানা দিন' : null,
                  ),
                  const SizedBox(height: 15),

                  // প্রধান শিক্ষক বা অ্যাডমিনের নাম
                  TextFormField(
                    controller: adminNameController,
                    decoration: InputDecoration(
                      labelText: 'প্রধান শিক্ষক / অ্যাডমিনের নাম',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'অ্যাডমিনের নাম দিন' : null,
                  ),
                  const SizedBox(height: 15),

                  // ইমেইল
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'অফিসিয়াল ইমেইল',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'সঠিক ইমেইল দিন' : null,
                  ),
                  const SizedBox(height: 15),

                  // পাসওয়ার্ড (এখানে পাসওয়ার্ড শো/হাইড করার আইকন যুক্ত করা হয়েছে)
                  TextFormField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.teal,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) => value!.length < 6
                        ? 'কমপক্ষে ৬ অক্ষরের পাসওয়ার্ড দিন'
                        : null,
                  ),
                  const SizedBox(height: 25),

                  const Divider(thickness: 1.5),
                  const SizedBox(height: 10),
                  const Text(
                    'একাডেমির ক্লাসসমূহ (নিচ থেকে ওপরের সিরিয়াল অনুযায়ী সাজান)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'আপনার প্রতিষ্ঠানের পছন্দমতো ক্লাসের নাম দিন (যেমন: নূরানী, প্লে, ষষ্ঠ ইত্যাদি)। নতুন বছর আসলে সিস্টেম এই সিরিয়াল অনুযায়ী অটোমেটিক ক্লাস আপডেট করবে।',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 15),

                  // ডায়নামিক ক্লাস লিস্ট ভিউ
                  ListView.builder(
                    shrinkWrap: andShrinkWrapIfNeeded(),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: classControllers.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.teal.shade100,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: classControllers[index],
                                decoration: InputDecoration(
                                  labelText: 'ক্লাসের নাম লিখুন',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                validator: (value) =>
                                    value!.isEmpty ? 'ক্লাসের নাম দিন' : null,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => removeClassField(index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // ক্লাস বাড়ানোর বাটন
                  OutlinedButton.icon(
                    onPressed: addClassField,
                    icon: const Icon(Icons.add, color: Colors.teal),
                    label: const Text(
                      'আরেকটি ক্লাস যোগ করুন',
                      style: TextStyle(color: Colors.teal),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // সাবমিট বাটন
                  ElevatedButton(
                    onPressed: isLoading ? null : registerAcademy,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'রেজিস্ট্রেশন করুন',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool andShrinkWrapIfNeeded() => true;
}
