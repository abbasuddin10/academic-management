import 'package:academy_management/models/notice.dart';
import 'package:academy_management/repositories/notice_repository.dart';
import 'package:academy_management/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Notice read state', () {
    test('fromMap reads the merged is_read flag', () {
      final notice = Notice.fromMap(<String, dynamic>{
        'id': 'notice-1',
        'title': 'Hostel closed',
        'is_read': true,
      });

      expect(notice.isRead, isTrue);
      expect(notice.id, 'notice-1');
      expect(notice.title, 'Hostel closed');
    });

    test('copyWith keeps raw Supabase fields and only changes isRead', () {
      final notice = Notice.fromMap(<String, dynamic>{
        'id': 'notice-2',
        'academy_id': 'academy-1',
        'target_type': 'class',
        'target_class': '9',
      });

      final read = notice.copyWith(isRead: true);

      expect(notice.isRead, isFalse);
      expect(read.isRead, isTrue);
      expect(read.raw['academy_id'], 'academy-1');
      expect(read.raw['target_type'], 'class');
      expect(read.targetClass, '9');
      expect(read.toMap()['is_read'], isTrue);
    });
  });

  group('Audience targeting', () {
    const academyNotice = <String, dynamic>{'target_type': 'everyone'};
    const studentNotice = <String, dynamic>{'target_type': 'all_students'};
    const classNine = <String, dynamic>{
      'target_type': 'class',
      'target_class': '9',
    };
    const teacherNotice = <String, dynamic>{'target_type': 'teachers'};

    test('students only see academy-wide and own-class notices', () {
      expect(
        NoticeRepository.isTargeted(
          academyNotice,
          role: 'student',
          className: '10',
        ),
        isTrue,
      );
      expect(
        NoticeRepository.isTargeted(
          studentNotice,
          role: 'student',
          className: '10',
        ),
        isTrue,
      );
      expect(
        NoticeRepository.isTargeted(classNine, role: 'student', className: '9'),
        isTrue,
      );
      expect(
        NoticeRepository.isTargeted(
          classNine,
          role: 'student',
          className: '10',
        ),
        isFalse,
      );
      expect(
        NoticeRepository.isTargeted(
          teacherNotice,
          role: 'student',
          className: '9',
        ),
        isFalse,
      );
    });

    test('teachers and admins see every notice in their academy', () {
      for (final notice in <Map<String, dynamic>>[
        academyNotice,
        studentNotice,
        classNine,
        teacherNotice,
      ]) {
        expect(NoticeRepository.isTargeted(notice, role: 'teacher'), isTrue);
        expect(
          NoticeRepository.isTargeted(notice, role: 'super_admin'),
          isTrue,
        );
      }
    });
  });

  group('Reader keys', () {
    test('admins use their auth uid directly', () {
      expect(
        SessionService.readerKeyFor(role: 'super_admin', userId: 'uid-123'),
        'uid-123',
      );
    });

    test('teachers and students are namespaced', () {
      expect(
        SessionService.readerKeyFor(role: 'teacher', userId: 't-1'),
        'teacher:t-1',
      );
      expect(
        SessionService.readerKeyFor(role: 'staff', userId: 't-2'),
        'teacher:t-2',
      );
      expect(
        SessionService.readerKeyFor(role: 'student', userId: 's-1'),
        'student:s-1',
      );
    });
  });
}
