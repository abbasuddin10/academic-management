import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import 'package:get/get.dart';

class AcademyQRCodeView extends StatefulWidget {
  final String academyId;
  final String securityToken;
  final String academyName;

  const AcademyQRCodeView({
    super.key,
    required this.academyId,
    required this.securityToken,
    required this.academyName,
  });

  @override
  State<AcademyQRCodeView> createState() => _AcademyQRCodeViewState();
}

class _AcademyQRCodeViewState extends State<AcademyQRCodeView> {
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  Widget build(BuildContext context) {
    String qrData =
        "ACADEMY_ID:${widget.academyId}|TOKEN:${widget.securityToken}";

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '${widget.academyName} - উপস্থিতি কিউআর কোড',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'এই কিউআর কোডটি প্রিন্ট করে প্রতিষ্ঠানের দেওয়ালে টাঙিয়ে দিন। শিক্ষকরা শুধুমাত্র এর সামনে এসে স্ক্যান করতে পারবেন।',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Screenshot(
              controller: _screenshotController,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.academyName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        gapless: false,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'উপস্থিতি স্ক্যানার কিউআর কোড',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('বন্ধ করুন', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('ডাউনলোড করুন'),
          onPressed: () async {
            try {
              final imageBytes = await _screenshotController.capture();

              if (imageBytes != null) {
                if (!await Gal.hasAccess()) {
                  await Gal.requestAccess();
                }

                await Gal.putImageBytes(imageBytes);

                Get.snackbar(
                  "সফল",
                  "কিউআর কোডটি সফলভাবে গ্যালারিতে সেভ হয়েছে!",
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              }
            } catch (e) {
              Get.snackbar(
                "ত্রুটি",
                "ডাউনলোড করতে সমস্যা হয়েছে: $e",
                backgroundColor: Colors.red,
                colorText: Colors.white,
              );
            }
          },
        ),
      ],
    );
  }
}
