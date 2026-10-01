import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';

class CreateExamRoutinePage extends StatefulWidget {
  final String academyId;
  final String examId;
  final String examTitle;

  const CreateExamRoutinePage({
    Key? key,
    required this.academyId,
    required this.examId,
    required this.examTitle,
  }) : super(key: key);

  @override
  State<CreateExamRoutinePage> createState() => _CreateExamRoutinePageState();
}

class _CreateExamRoutinePageState extends State<CreateExamRoutinePage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> classesList = [];
  bool isLoadingData = true;

  // প্রতিটি দিনের জন্য রুটিন এন্ট্রি লিস্ট
  List<Map<String, dynamic>> routineEntries = [];

  @override
  void initState() {
    super.initState();
    _fetchClassesAndExistingRoutines();
  }

  // ১. ক্লাস এবং পূর্বে সেভ করা রুটিন একসাথে ফেচ করা
  Future<void> _fetchClassesAndExistingRoutines() async {
    try {
      setState(() {
        isLoadingData = true;
      });

      // প্রথমে ক্লাসগুলো ফেচ করা
      final classResponse = await supabase
          .from('classes')
          .select()
          .eq('academy_id', widget.academyId);

      if (classResponse != null) {
        classesList = List<Map<String, dynamic>>.from(classResponse);
      }

      // এরপর এই পরীক্ষার আন্ডারে পূর্বে সেভ করা রুটিনগুলো ফেচ করা
      final routineResponse = await supabase
          .from('exam_routines')
          .select()
          .eq('academy_id', widget.academyId)
          .eq('exam_id', widget.examId);

      List<Map<String, dynamic>> existingRoutines = [];
      if (routineResponse != null) {
        existingRoutines = List<Map<String, dynamic>>.from(routineResponse);
      }

      routineEntries.clear();

      if (existingRoutines.isNotEmpty) {
        // তারিখ অনুযায়ী রুটিনগুলোকে গ্রুপিং করা
        Map<String, List<Map<String, dynamic>>> groupedByDate = {};
        for (var item in existingRoutines) {
          String date = item['exam_date'] ?? '';
          if (!groupedByDate.containsKey(date)) {
            groupedByDate[date] = [];
          }
          groupedByDate[date]!.add(item);
        }

        // প্রতি তারিখের জন্য একটি করে এন্ট্রি তৈরি করা এবং কন্ট্রোলারে ডাটা বসানো
        groupedByDate.forEach((date, items) {
          Map<String, TextEditingController> subjControllers = {};
          Map<String, String> times = {};
          Map<String, bool> errors = {};
          Map<String, bool> noExamStatus = {};

          for (var cls in classesList) {
            String className =
                cls['name'] ?? cls['class_name'] ?? 'অজানা ক্লাস';
            subjControllers[className] = TextEditingController();
            times[className] = '১০:০০ AM';
            errors[className] = false;
            noExamStatus[className] =
                true; // ডিফল্টভাবে ধরে নিচ্ছি ওই দিনে পরীক্ষা নেই, পরে ডাটা পেলে আপডেট হবে
          }

          for (var item in items) {
            String className = item['class_name'] ?? '';
            String subjectName = item['subject_name'] ?? '';
            String examTime = item['exam_time'] ?? '১০:০০ AM';

            if (subjControllers.containsKey(className)) {
              subjControllers[className]!.text = subjectName;
              times[className] = examTime;
              noExamStatus[className] =
                  false; // যেহেতু বিষয় আছে, মানে পরীক্ষা আছে
            }
          }

          routineEntries.add({
            'date_controller': TextEditingController(text: date),
            'subject_controllers': subjControllers,
            'time_values': times,
            'errors': errors,
            'no_exam_status': noExamStatus,
            'is_expanded':
                false, // আগের ডাটা থাকলে ডিফল্টভাবে কোল্যাপ্সড থাকতে পারে, চাইলে true করতে পারেন
          });
        });
      }

      // যদি কোনো আগের রুটিন না থাকে, তবে একটি খালি ব্লক যোগ করা হবে
      if (routineEntries.isEmpty) {
        _addNewRoutineEntry();
      }

      setState(() {
        isLoadingData = false;
      });
    } catch (e) {
      setState(() {
        isLoadingData = false;
      });
      Get.snackbar(
        "ত্রুটি",
        "ডাটা লোড করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // বাংলা সংখ্যায় দিন রূপান্তর করার ফাংশন
  String _getDayNameInBengali(int index) {
    List<String> bengaliDays = [
      'প্রথম দিন',
      'দ্বিতীয় দিন',
      'তৃতীয় দিন',
      'চতুর্থ দিন',
      'পঞ্চম দিন',
      'ষষ্ঠ দিন',
      'সপ্তম দিন',
      'অষ্টম দিন',
      'নবম দিন',
      'দশম দিন',
    ];
    if (index < bengaliDays.length) {
      return bengaliDays[index];
    }
    return '${index + 1} তম দিন';
  }

  // নতুন তারিখের রুটিন ব্লক যোগ করার ফাংশন
  void _addNewRoutineEntry() {
    Map<String, TextEditingController> subjControllers = {};
    Map<String, String> times = {};
    Map<String, bool> errors = {};
    Map<String, bool> noExamStatus = {};

    for (var cls in classesList) {
      String className = cls['name'] ?? cls['class_name'] ?? 'অজানা ক্লাস';
      subjControllers[className] = TextEditingController();
      times[className] = '১০:০০ AM';
      errors[className] = false;
      noExamStatus[className] =
          false; // নতুন ব্লকে ডিফল্ট পরীক্ষা আছে ধরে নেওয়া হয়
    }

    setState(() {
      routineEntries.add({
        'date_controller': TextEditingController(),
        'subject_controllers': subjControllers,
        'time_values': times,
        'errors': errors,
        'no_exam_status': noExamStatus,
        'is_expanded': true,
      });
    });
  }

  // সময় সিলেক্ট করার টাইম পিকার
  Future<void> _pickTime(int entryIndex, String className) async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime != null) {
      setState(() {
        routineEntries[entryIndex]['time_values'][className] = pickedTime
            .format(context);
      });
    }
  }

  // তারিখ সিলেক্ট করার ডেট পিকার
  Future<void> _pickDate(int entryIndex) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (pickedDate != null) {
      setState(() {
        routineEntries[entryIndex]['date_controller'].text = pickedDate
            .toIso8601String()
            .split('T')[0];
      });
    }
  }

  // সব রুটিন ডাটাবেজে সেভ এবং আপডেট করা (Upsert লজিক)
  Future<void> _saveAllRoutines() async {
    bool hasError = false;
    List<Map<String, dynamic>> routinesToUpsert = [];
    List<String> updatedDates = [];

    for (int i = 0; i < routineEntries.length; i++) {
      var entry = routineEntries[i];
      String examDate = entry['date_controller'].text.trim();
      var subjControllers =
          entry['subject_controllers'] as Map<String, TextEditingController>;
      var times = entry['time_values'] as Map<String, String>;
      var errors = entry['errors'] as Map<String, bool>;
      var noExamStatus = entry['no_exam_status'] as Map<String, bool>;

      if (examDate.isEmpty) {
        Get.snackbar(
          "সতর্কতা",
          "${_getDayNameInBengali(i)}-এর পরীক্ষার তারিখ সিলেক্ট করা হয়নি!",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      updatedDates.add(examDate);

      subjControllers.forEach((className, controller) {
        bool isNoExam = noExamStatus[className] ?? false;
        String subText = controller.text.trim();

        // যদি পরীক্ষা থাকে এবং বিষয়ের নাম লেখা থাকে, তবেই সেভ লিস্টে যোগ হবে
        if (!isNoExam && subText.isNotEmpty) {
          errors[className] = false;
          routinesToUpsert.add({
            'academy_id': widget.academyId,
            'exam_id': widget.examId,
            'exam_title': widget.examTitle,
            'class_name': className,
            'subject_name': subText,
            'exam_time': times[className] ?? '১০:০০ AM',
            'exam_date': examDate,
          });
        }
      });

      // ভ্যালিডেশন: যেগুলোতে পরীক্ষা আছে কিন্তু ঘর ফাঁকা, সেগুলোতে লাল বর্ডার দেখাবে
      subjControllers.forEach((className, controller) {
        bool isNoExam = noExamStatus[className] ?? false;
        if (!isNoExam && controller.text.trim().isEmpty) {
          errors[className] = true;
          hasError = true;
          entry['is_expanded'] = true;
        }
      });
    }

    setState(() {});

    if (hasError) {
      Get.snackbar(
        "সতর্কতা",
        "যেসব ক্লাসে পরীক্ষা আছে কিন্তু বিষয় লেখা হয়নি, সেগুলোতে লাল বর্ডার দেওয়া হয়েছে।",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    if (routinesToUpsert.isEmpty) {
      Get.snackbar(
        "সতর্কতা",
        "অন্তত একটি বিষয়ের তথ্য লিখুন!",
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator(color: Colors.teal)),
      );

      // ১. বর্তমান ফর্মে যে তারিখগুলো নিয়ে কাজ করা হচ্ছে, ডাটাবেজ থেকে সেই তারিখগুলোর পুরোনো রুটিন মুছে ফেলা (যাতে আপডেট করলে পুরোনো ডুপ্লিকেট না থাকে)
      for (String date in updatedDates) {
        await supabase
            .from('exam_routines')
            .delete()
            .eq('academy_id', widget.academyId)
            .eq('exam_id', widget.examId)
            .eq('exam_date', date);
      }

      // ২. নতুন বা এডিট করা আপডেট ডাটাগুলো ইনসার্ট করা
      await supabase.from('exam_routines').insert(routinesToUpsert);

      Navigator.pop(context); // লোডিং ডায়ালগ বন্ধ করা

      Get.snackbar(
        "সফল",
        "পরীক্ষার রুটিন সফলভাবে আপডেট ও সেভ হয়েছে!",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );

      // সফলভাবে সেভ হওয়ার পর আবার লেটেস্ট ডাটা রিফ্রেশ করে নেওয়া
      _fetchClassesAndExistingRoutines();
    } catch (e) {
      Navigator.pop(context);
      Get.snackbar(
        "ত্রুটি",
        "সংরক্ষণ করতে সমস্যা হয়েছে: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.examTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.teal,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            tooltip: 'সব রুটিন সেভ করুন',
            onPressed: _saveAllRoutines,
          ),
        ],
      ),
      body: isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : classesList.isEmpty
          ? const Center(child: Text('কোনো ক্লাস পাওয়া যায়নি।'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: routineEntries.length,
                    itemBuilder: (context, entryIndex) {
                      var entry = routineEntries[entryIndex];
                      TextEditingController dateController =
                          entry['date_controller'];
                      var subjControllers =
                          entry['subject_controllers']
                              as Map<String, TextEditingController>;
                      var times = entry['time_values'] as Map<String, String>;
                      var errors = entry['errors'] as Map<String, bool>;
                      var noExamStatus =
                          entry['no_exam_status'] as Map<String, bool>;
                      bool isExpanded = entry['is_expanded'] ?? true;

                      String dayName = _getDayNameInBengali(entryIndex);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.teal.shade200,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // হেডার সেকশন
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.vertical(
                                  top: const Radius.circular(10),
                                  bottom: isExpanded
                                      ? Radius.zero
                                      : const Radius.circular(10),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    dayName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: 34,
                                      child: TextField(
                                        controller: dateController,
                                        readOnly: true,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'তারিখ নির্বাচন করুন',
                                          hintStyle: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.calendar_today,
                                            size: 14,
                                            color: Colors.teal,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            borderSide: BorderSide(
                                              color: Colors.teal.shade200,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            borderSide: BorderSide(
                                              color: Colors.teal.shade200,
                                            ),
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 6,
                                                horizontal: 8,
                                              ),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        onTap: () => _pickDate(entryIndex),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: Colors.teal,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: isExpanded ? 'হাইড করুন' : 'দেখুন',
                                    onPressed: () {
                                      setState(() {
                                        entry['is_expanded'] = !isExpanded;
                                      });
                                    },
                                  ),
                                  if (routineEntries.length > 1) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'ডিলিট করুন',
                                      onPressed: () {
                                        setState(() {
                                          routineEntries.removeAt(entryIndex);
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // ক্লাসের বক্সসমূহ
                            if (isExpanded)
                              Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'শ্রেণিভিত্তিক বিষয় ও সময় (যে ক্লাসে পরীক্ষা নেই তার চেকবক্সে টিক দিন):',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        double spacing = 8;
                                        double itemWidth =
                                            (constraints.maxWidth -
                                                (spacing * 2)) /
                                            3;

                                        return Wrap(
                                          spacing: spacing,
                                          runSpacing: spacing,
                                          children: classesList.map((cls) {
                                            String className =
                                                cls['name'] ??
                                                cls['class_name'] ??
                                                'অজানা ক্লাস';
                                            bool isError =
                                                errors[className] ?? false;
                                            bool isNoExam =
                                                noExamStatus[className] ??
                                                false;

                                            return SizedBox(
                                              width: itemWidth,
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isNoExam
                                                      ? Colors.grey.shade200
                                                      : Colors.grey.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isError
                                                        ? Colors.red
                                                        : Colors.grey.shade300,
                                                    width: isError ? 1.5 : 1,
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            className,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: isNoExam
                                                                  ? Colors.grey
                                                                  : Colors.teal,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          height: 18,
                                                          width: 18,
                                                          child: Checkbox(
                                                            value: isNoExam,
                                                            activeColor:
                                                                Colors.red,
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            onChanged: (val) {
                                                              setState(() {
                                                                noExamStatus[className] =
                                                                    val ??
                                                                    false;
                                                                if (val ==
                                                                    true) {
                                                                  subjControllers[className]
                                                                      ?.clear();
                                                                  errors[className] =
                                                                      false;
                                                                }
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    isNoExam
                                                        ? Container(
                                                            height: 32,
                                                            alignment: Alignment
                                                                .center,
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: Colors
                                                                      .red
                                                                      .shade50,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        4,
                                                                      ),
                                                                ),
                                                            child: const Text(
                                                              'ছুটি / পরীক্ষা নেই',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color:
                                                                    Colors.red,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          )
                                                        : Column(
                                                            children: [
                                                              TextField(
                                                                controller:
                                                                    subjControllers[className],
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                    ),
                                                                decoration: InputDecoration(
                                                                  hintText:
                                                                      'বিষয় লিখুন',
                                                                  hintStyle: TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                    color: Colors
                                                                        .grey
                                                                        .shade400,
                                                                  ),
                                                                  border: OutlineInputBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          5,
                                                                        ),
                                                                    borderSide: BorderSide(
                                                                      color:
                                                                          isError
                                                                          ? Colors.red
                                                                          : Colors.grey.shade300,
                                                                    ),
                                                                  ),
                                                                  enabledBorder: OutlineInputBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          5,
                                                                        ),
                                                                    borderSide: BorderSide(
                                                                      color:
                                                                          isError
                                                                          ? Colors.red
                                                                          : Colors.grey.shade300,
                                                                    ),
                                                                  ),
                                                                  isDense: true,
                                                                  contentPadding:
                                                                      const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            6,
                                                                        vertical:
                                                                            6,
                                                                      ),
                                                                  filled: true,
                                                                  fillColor:
                                                                      Colors
                                                                          .white,
                                                                ),
                                                                onChanged: (val) {
                                                                  if (val
                                                                      .trim()
                                                                      .isNotEmpty) {
                                                                    setState(() {
                                                                      errors[className] =
                                                                          false;
                                                                    });
                                                                  }
                                                                },
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              InkWell(
                                                                onTap: () =>
                                                                    _pickTime(
                                                                      entryIndex,
                                                                      className,
                                                                    ),
                                                                child: Container(
                                                                  width: double
                                                                      .infinity,
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        vertical:
                                                                            4,
                                                                        horizontal:
                                                                            4,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    color: Colors
                                                                        .teal
                                                                        .shade50,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          4,
                                                                        ),
                                                                    border: Border.all(
                                                                      color: Colors
                                                                          .teal
                                                                          .shade200,
                                                                    ),
                                                                  ),
                                                                  child: Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      const Icon(
                                                                        Icons
                                                                            .access_time,
                                                                        size:
                                                                            10,
                                                                        color: Colors
                                                                            .teal,
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            3,
                                                                      ),
                                                                      Text(
                                                                        times[className] ??
                                                                            'সময়',
                                                                        style: const TextStyle(
                                                                          fontSize:
                                                                              10,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          color:
                                                                              Colors.teal,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  // নতুন রুটিন যোগ করুন বাটন
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _addNewRoutineEntry,
                      icon: const Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: Colors.teal,
                      ),
                      label: const Text(
                        'নতুন রুটিন যোগ করুন',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.teal, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}
