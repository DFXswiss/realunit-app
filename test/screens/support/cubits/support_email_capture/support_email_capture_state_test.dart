// We deliberately use non-const constructors throughout this file so the
// generative constructor lines get counted as executed in the coverage
// report.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/support/cubits/support_email_capture/support_email_capture_cubit.dart';

void main() {
  group('$SupportEmailCaptureInitial / Loading / Success / MergeRequested', () {
    test('Initial: equal across instances, empty props', () {
      final a = SupportEmailCaptureInitial();
      final b = SupportEmailCaptureInitial();
      expect(a, equals(b));
      expect(a.props, isEmpty);
    });

    test('Loading: equal across instances', () {
      final a = SupportEmailCaptureLoading();
      final b = SupportEmailCaptureLoading();
      expect(a, equals(b));
    });

    test('Success: equal across instances', () {
      final a = SupportEmailCaptureSuccess();
      final b = SupportEmailCaptureSuccess();
      expect(a, equals(b));
    });

    test('MergeRequested: equal across instances', () {
      final a = SupportEmailCaptureMergeRequested();
      final b = SupportEmailCaptureMergeRequested();
      expect(a, equals(b));
    });

    test('Initial / Loading / Success / MergeRequested are all distinct', () {
      final i = SupportEmailCaptureInitial();
      final l = SupportEmailCaptureLoading();
      final s = SupportEmailCaptureSuccess();
      final m = SupportEmailCaptureMergeRequested();
      expect(i, isNot(equals(l)));
      expect(l, isNot(equals(s)));
      expect(s, isNot(equals(m)));
      expect(m, isNot(equals(i)));
    });
  });

  group('$SupportEmailCaptureFailure', () {
    test('same message is equal', () {
      final a = SupportEmailCaptureFailure('x');
      final b = SupportEmailCaptureFailure('x');
      expect(a, equals(b));
    });

    test('different message is unequal', () {
      final a = SupportEmailCaptureFailure('x');
      final b = SupportEmailCaptureFailure('y');
      expect(a, isNot(equals(b)));
    });

    test('is distinct from MergeRequested', () {
      final f = SupportEmailCaptureFailure('x');
      final m = SupportEmailCaptureMergeRequested();
      expect(f, isNot(equals(m)));
    });
  });
}
