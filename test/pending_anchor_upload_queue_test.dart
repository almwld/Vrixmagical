import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reality/managers/pending_anchor_upload_queue.dart';

class _FakeAnchor {
  const _FakeAnchor(this.name);
  final String name;
}

void main() {
  group('PendingAnchorUploadQueue', () {
    test('registers before awaiting and consumes an early native completion', () {
      final items = <_FakeAnchor>[];
      final queue = PendingAnchorUploadQueue<_FakeAnchor>(items);
      const anchor = _FakeAnchor('plane-1');

      expect(queue.add(anchor, nameOf: (value) => value.name), isTrue);
      expect(items, contains(anchor));

      // Models the native callback arriving before uploadAnchor Future resolves.
      expect(queue.take('plane-1', nameOf: (value) => value.name), anchor);
      expect(items, isEmpty);
      expect(
        queue.remove('plane-1', nameOf: (value) => value.name),
        isFalse,
      );
    });

    test('rejects duplicate pending names', () {
      final items = <_FakeAnchor>[];
      final queue = PendingAnchorUploadQueue<_FakeAnchor>(items);
      const first = _FakeAnchor('plane-1');
      const duplicate = _FakeAnchor('plane-1');

      expect(queue.add(first, nameOf: (value) => value.name), isTrue);
      expect(queue.add(duplicate, nameOf: (value) => value.name), isFalse);
      expect(items, hasLength(1));
      expect(items.single, first);
    });

    test('removal makes a late callback harmless', () {
      final items = <_FakeAnchor>[];
      final queue = PendingAnchorUploadQueue<_FakeAnchor>(items);
      const anchor = _FakeAnchor('plane-2');

      expect(queue.add(anchor, nameOf: (value) => value.name), isTrue);
      expect(queue.remove('plane-2', nameOf: (value) => value.name), isTrue);
      expect(queue.take('plane-2', nameOf: (value) => value.name), isNull);
      expect(items, isEmpty);
    });

    test('ignores unknown and empty names', () {
      final items = <_FakeAnchor>[];
      final queue = PendingAnchorUploadQueue<_FakeAnchor>(items);

      expect(queue.add(const _FakeAnchor(''), nameOf: (value) => value.name), isFalse);
      expect(queue.take('missing', nameOf: (value) => value.name), isNull);
      expect(items, isEmpty);
    });
  });
}
