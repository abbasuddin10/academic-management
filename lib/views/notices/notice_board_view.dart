import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/controllers/app_state_controller.dart';
import 'package:academy_management/models/notice.dart';
import 'package:academy_management/repositories/notice_repository.dart';
import 'package:academy_management/repositories/student_repository.dart';
import 'package:academy_management/services/ad_service.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:academy_management/widgets/async_state_view.dart';
import 'package:academy_management/widgets/theme_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'create_notice_view.dart';

enum _NoticeFilter { all, unread }

class NoticeBoardView extends StatefulWidget {
  final String academyId;
  final String userRole; // 'super_admin', 'teacher', 'student', ...

  const NoticeBoardView({
    super.key,
    required this.academyId,
    required this.userRole,
  });

  @override
  State<NoticeBoardView> createState() => _NoticeBoardViewState();
}

class _NoticeBoardViewState extends State<NoticeBoardView> {
  final supabase = Supabase.instance.client;
  final NoticeRepository _noticeRepository = NoticeRepository();

  bool isLoading = true;
  String? _errorMessage;
  List<Notice> _notices = [];
  List<String> availableClasses = [];

  String _readerKey = '';
  String _className = '';
  _NoticeFilter _filter = _NoticeFilter.all;

  RealtimeChannel? _channel;

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  AppStateController? get _appState =>
      Get.isRegistered<AppStateController>() ? AppStateController.to : null;

  bool get _isAdmin => widget.userRole == 'super_admin';

  List<Notice> get _visibleNotices => _filter == _NoticeFilter.unread
      ? _notices.where((notice) => !notice.isRead).toList()
      : _notices;

  @override
  void initState() {
    super.initState();
    _initBannerAd();
    _initializeContext();
    if (_isAdmin) _fetchClasses();
  }

  Future<void> _initializeContext() async {
    final context = await SessionService.noticeContext();
    if (!mounted) return;
    setState(() {
      _readerKey = context.readerKey;
      _className = context.className;
    });

    _appState?.startNoticeWatch(
      academyId: widget.academyId,
      role: context.role,
      readerKey: context.readerKey,
      className: context.className,
    );
    _appState?.refreshUnreadNoticeCount();

    await _fetchNotices();
    if (!mounted) return;
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('notice-board-${widget.academyId}-$_readerKey')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'academy_id',
            value: widget.academyId,
          ),
          callback: (_) => _fetchNotices(),
        )
        .subscribe();
  }

  void _initBannerAd() {
    _bannerAd = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) {
          setState(() => _isBannerAdLoaded = true);
        }
      });
  }

  @override
  void dispose() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
    }
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _fetchClasses() async {
    try {
      final classes = await StudentRepository().classesForAcademy(
        widget.academyId,
      );
      if (!mounted) return;
      setState(() => availableClasses = classes);
    } catch (e) {
      debugPrint('Error fetching classes: $e');
    }
  }

  Future<void> _fetchNotices() async {
    try {
      final notices = await _noticeRepository.fetch(
        widget.academyId,
        readerKey: _readerKey,
        role: widget.userRole,
        className: _className,
      );
      if (!mounted) return;
      setState(() {
        _notices = notices;
        _errorMessage = null;
        isLoading = false;
      });
      _appState?.setUnreadNoticeCount(
        notices.where((notice) => !notice.isRead).length,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _errorMessage = e.toString();
      });
      Get.snackbar(
        'ত্রুটি',
        'নোটিশ লোড করতে সমস্যা হয়েছে: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Optimistically flips one notice to read, rolls back on failure.
  Future<void> _markNoticeRead(Notice notice) async {
    if (notice.isRead || _readerKey.isEmpty) return;

    void setRead(bool value) {
      if (!mounted) return;
      setState(() {
        final index = _notices.indexWhere((item) => item.id == notice.id);
        if (index != -1) {
          _notices[index] = _notices[index].copyWith(isRead: value);
        }
      });
    }

    setRead(true);
    _appState?.decrementUnreadNoticeCount();

    try {
      await _noticeRepository.markAsRead(
        notice.id,
        academyId: widget.academyId,
        readerKey: _readerKey,
      );
    } catch (_) {
      setRead(false);
      _appState?.incrementUnreadNoticeCount();
      if (mounted) {
        Get.snackbar(
          'ত্রুটি',
          'পঠিত হিসেবে চিহ্নিত করা যায়নি।',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    final unreadIds = _notices
        .where((notice) => !notice.isRead)
        .map((notice) => notice.id)
        .toList();
    if (unreadIds.isEmpty || _readerKey.isEmpty) return;

    final ids = unreadIds.toSet();
    final state = _appState;
    if (state != null) {
      state.setUnreadNoticeCount(state.unreadNoticeCount.value - ids.length);
    }
    if (mounted) {
      setState(() {
        _notices = _notices
            .map(
              (notice) => ids.contains(notice.id)
                  ? notice.copyWith(isRead: true)
                  : notice,
            )
            .toList();
      });
    }

    try {
      await _noticeRepository.markAllAsRead(
        unreadIds,
        academyId: widget.academyId,
        readerKey: _readerKey,
      );
    } catch (_) {
      await _fetchNotices();
      await state?.refreshUnreadNoticeCount();
      if (mounted) {
        Get.snackbar(
          'ত্রুটি',
          'সব নোটিশ পঠিত হিসেবে চিহ্নিত করা যায়নি।',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  Future<void> _deleteNotice(String noticeId) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('নোটিশ মুছুন'),
        content: const Text('আপনি কি নিশ্চিত যে এই নোটিশটি মুছে ফেলতে চান?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Get.back(result: true),
            child: const Text(
              'মুছে ফেলুন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _noticeRepository.delete(noticeId, widget.academyId);
        _fetchNotices();
        Get.snackbar(
          'সফল',
          'নোটিশটি মুছে ফেলা হয়েছে!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } catch (e) {
        Get.snackbar(
          'ত্রুটি',
          'মুছে ফেলতে সমস্যা হয়েছে: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  void _editNoticeDialog(Notice notice) {
    final titleEditController = TextEditingController(text: notice.title);
    final descEditController = TextEditingController(text: notice.description);

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('নোটিশ এডিট করুন'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleEditController,
                decoration: const InputDecoration(
                  labelText: 'শিরোনাম',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descEditController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'বিবরণ',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('বাতিল')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              if (titleEditController.text.trim().isEmpty ||
                  descEditController.text.trim().isEmpty) {
                Get.snackbar('সতর্কতা', 'শিরোনাম ও বিবরণ দিন!');
                return;
              }
              Get.back();
              try {
                await supabase
                    .from('notices')
                    .update({
                      'title': titleEditController.text.trim(),
                      'description': descEditController.text.trim(),
                    })
                    .eq('id', notice.id);

                _fetchNotices();
                Get.snackbar(
                  'সফল',
                  'নোটিশ সফলভাবে আপডেট করা হয়েছে!',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              } catch (e) {
                Get.snackbar(
                  'ত্রুটি',
                  'আপডেট করতে সমস্যা হয়েছে: $e',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            child: const Text(
              'আপডেট করুন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showNoticeDetailsDialog(
    Notice notice,
    String targetText,
    String? fileUrl,
  ) {
    // Opening a notice (tap or deep link) marks it read for this recipient.
    _markNoticeRead(notice);

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          notice.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notice.description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 14,
                      color: AppTheme.inkOf(context),
                    ),
              ),
              if (fileUrl != null && fileUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.brandOf(context),
                    side: BorderSide(color: AppTheme.brandOf(context)),
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(fileUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('সংযুক্ত ফাইল/ডকুমেন্ট দেখুন'),
                ),
              ],
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    targetText,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.brandOf(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    notice.raw['created_at'] != null
                        ? notice.raw['created_at'].toString().substring(0, 10)
                        : '',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedOf(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  Future<void> _navigateToCreateNotice() async {
    if (!_isAdmin) {
      Get.snackbar(
        'অপারেশন নিষেধ',
        'শুধুমাত্র অ্যাডমিন নোটিশ প্রকাশ করতে পারবেন!',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final result = await Get.to(
      () => CreateNoticeView(
        academyId: widget.academyId,
        userRole: widget.userRole,
        availableClasses: availableClasses,
      ),
    );

    if (result == true) _fetchNotices();
  }

  Widget _buildBannerAdItem() {
    final bannerAd = AdService.createBannerAd()..load();
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: bannerAd.size.width.toDouble(),
      height: bannerAd.size.height.toDouble(),
      child: AdWidget(ad: bannerAd),
    );
  }

  String _targetText(Notice notice) {
    switch (notice.targetType) {
      case 'all_students':
        return 'প্রাপক: সকল ছাত্র-ছাত্রী';
      case 'class':
        return 'প্রাপক ক্লাস: ${notice.targetClass}';
      case 'teachers':
        return 'প্রাপক: সকল শিক্ষক';
      default:
        return 'প্রাপক: সকলের জন্য';
    }
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(_appState?.tr('সব', 'All') ?? 'সব'),
            selected: _filter == _NoticeFilter.all,
            onSelected: (_) => setState(() => _filter = _NoticeFilter.all),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(_appState?.tr('অপঠিত', 'Unread') ?? 'অপঠিত'),
            selected: _filter == _NoticeFilter.unread,
            onSelected: (_) => setState(() => _filter = _NoticeFilter.unread),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notices = _visibleNotices;
    final english = _appState?.isEnglish.value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('নোটিশ বোর্ড'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          const ThemeModeToggle(color: Colors.white),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, color: Colors.white, size: 20),
              label: Text(
                english ? 'Mark all read' : 'সবগুলো পঠিত হিসেবে চিহ্নিত করুন',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              onPressed: _navigateToCreateNotice,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'নোটিশ দিন',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: isLoading
                ? const AppLoadingState(message: 'নোটিশ লোড হচ্ছে...')
                : _errorMessage != null
                ? AppErrorState(
                    message: 'নোটিশ লোড করতে সমস্যা হয়েছে।',
                    onRetry: _fetchNotices,
                  )
                : notices.isEmpty
                ? const AppEmptyState(
                    icon: Icons.campaign_outlined,
                    message: 'এই মুহূর্তে কোনো নোটিশ নেই।',
                  )
                : RefreshIndicator(
                    onRefresh: _fetchNotices,
                    child: ListView.builder(
                      itemCount:
                          notices.length +
                          (notices.isNotEmpty ? notices.length ~/ 4 : 0),
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        int realIndex = index;
                        for (int i = 0; i <= index; i++) {
                          if (i > 0 && (i + 1) % 5 == 0) {
                            if (index == i) return _buildBannerAdItem();
                            realIndex--;
                          }
                        }
                        if (realIndex >= notices.length) {
                          return const SizedBox.shrink();
                        }

                        final notice = notices[realIndex];
                        final fileUrl = notice.raw['file_url']?.toString();
                        final targetText = _targetText(notice);
                        final unread = !notice.isRead;

                        return Card(
                          elevation: unread ? 2 : 1,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          color: unread
                              ? AppTheme.tileOf(
                                  context,
                                  AppTheme.brandOf(context),
                                )
                              : AppTheme.surfaceOf(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: AppTheme.borderOf(context)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showNoticeDetailsDialog(
                              notice,
                              targetText,
                              fileUrl,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.campaign,
                                        color: AppTheme.brandOf(context),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          notice.title,
                                          style: TextStyle(
                                            fontWeight: unread
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 16,
                                            color: AppTheme.inkOf(context),
                                          ),
                                        ),
                                      ),
                                      if (unread)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.brandOf(context),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      if (_isAdmin) ...[
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                            size: 20,
                                          ),
                                          onPressed: () =>
                                              _editNoticeDialog(notice),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                          onPressed: () =>
                                              _deleteNotice(notice.id),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    notice.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontSize: 13,
                                          color: AppTheme.mutedOf(context),
                                        ),
                                  ),
                                  if (fileUrl != null &&
                                      fileUrl.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            AppTheme.brandOf(context),
                                        side: BorderSide(
                                          color: AppTheme.brandOf(context),
                                        ),
                                      ),
                                      onPressed: () async {
                                        final uri = Uri.parse(fileUrl);
                                        try {
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(
                                              uri,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          } else {
                                            Get.snackbar(
                                              'ত্রুটি',
                                              'ফাইলটি ওপেন করা সম্ভব হচ্ছে না!',
                                              backgroundColor: Colors.red,
                                              colorText: Colors.white,
                                            );
                                          }
                                        } catch (e) {
                                          Get.snackbar(
                                            'ত্রুটি',
                                            'সমস্যা হয়েছে: $e',
                                            backgroundColor: Colors.red,
                                            colorText: Colors.white,
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'সংযুক্ত ফাইল/ডকুমেন্ট দেখুন',
                                      ),
                                    ),
                                  ],
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.tileOf(
                                            context,
                                            AppTheme.brandOf(context),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          targetText,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.tileInkOf(
                                              context,
                                              AppTheme.brandOf(context),
                                            ),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        notice.raw['created_at'] != null
                                            ? notice.raw['created_at']
                                                  .toString()
                                                  .substring(0, 10)
                                            : '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.mutedOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (_isBannerAdLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}
