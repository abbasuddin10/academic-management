import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared implementations for app-wide drawer actions.
class AppActions {
  const AppActions._();

  static const String developerEmail = 'abbas.zhsust@gmail.com';

  /// There is no user-configurable settings screen in this release. Say so
  /// explicitly instead of showing a misleading "coming soon" toast.
  static void showSettingsUnavailable() {
    Get.dialog(
      AlertDialog(
        title: const Text('সেটিংস'),
        content: const Text(
          'এই ভার্সনে সেটিংস অপশন উপলব্ধ নেই। ভবিষ্যত রিলিজে যোগ করা হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('বন্ধ করুন'),
          ),
        ],
      ),
    );
  }

  /// Genuine feedback flow: the message is handed to the device mail app.
  static void showFeedbackDialog() {
    final controller = TextEditingController();
    var controllerDisposed = false;

    void closeDialog() {
      try {
        Get.back();
      } catch (_) {
        // No route to pop — nothing else to do.
      }
    }

    void disposeController() {
      if (controllerDisposed) return;
      controllerDisposed = true;
      try {
        controller.dispose();
      } catch (_) {
        // Already disposed; safe to ignore.
      }
    }

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('ফিডব্যাক দিন'),
            content: SizedBox(
              width: 320,
              child: TextField(
                controller: controller,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'আপনার মতামত বা পরামর্শ লিখুন...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  disposeController();
                  closeDialog();
                },
                child: const Text('বাতিল'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final body = controller.text.trim();
                  if (body.isEmpty) {
                    Get.snackbar(
                      'সতর্কতা',
                      'অনুগ্রহ করে কিছু লিখুন।',
                      backgroundColor: Colors.orange,
                      colorText: Colors.white,
                    );
                    return;
                  }

                  final uri = Uri(
                    scheme: 'mailto',
                    path: developerEmail,
                    queryParameters: {
                      'subject': 'Academy Manager - Feedback',
                      'body': body,
                    },
                  );

                  try {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                      disposeController();
                      closeDialog();
                    } else {
                      Get.snackbar(
                        'ত্রুটি',
                        'ইমেইল অ্যাপ খোলা যায়নি।',
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  } catch (e) {
                    Get.snackbar(
                      'ত্রুটি',
                      'ফিডব্যাক পাঠানো যায়নি: $e',
                      backgroundColor: Colors.red,
                      colorText: Colors.white,
                    );
                  }
                },
                child: const Text('পাঠান'),
              ),
            ],
          );
        },
      ),
      barrierDismissible: false,
    );
  }

  /// No public store link is configured for this build, so report that
  /// accurately instead of promising a share option that does not exist.
  static void showShareUnavailable() {
    Get.dialog(
      AlertDialog(
        title: const Text('অ্যাপ শেয়ার করুন'),
        content: const Text(
          'এই রিলিজে পাবলিক শেয়ার লিংক কনফিগার করা হয়নি। '
          'প্লে-স্টোরে অ্যাপটি প্রকাশিত হলে শেয়ার অপশন যোগ করা হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('বন্ধ করুন'),
          ),
        ],
      ),
    );
  }
}
