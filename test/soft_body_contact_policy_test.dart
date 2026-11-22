import 'package:flutter_test/flutter_test.dart';
import 'package:virxmagical/domain/soft_body_contact_policy.dart';

void main() {
  group('SoftBodyContactPolicy', () {
    test('accepts the first contact and repeated events from its owner', () {
      expect(
        SoftBodyContactPolicy.shouldAcceptContact(
          currentBodyId: null,
          incomingBodyId: 'rigid-a',
        ),
        isTrue,
      );
      expect(
        SoftBodyContactPolicy.shouldAcceptContact(
          currentBodyId: 'rigid-a',
          incomingBodyId: 'rigid-a',
        ),
        isTrue,
      );
    });

    test('selects one owner deterministically independent of event order', () {
      expect(
        SoftBodyContactPolicy.shouldAcceptContact(
          currentBodyId: 'rigid-b',
          incomingBodyId: 'rigid-a',
        ),
        isTrue,
      );
      expect(
        SoftBodyContactPolicy.shouldAcceptContact(
          currentBodyId: 'rigid-a',
          incomingBodyId: 'rigid-b',
        ),
        isFalse,
      );
    });

    test('rejects empty incoming IDs', () {
      expect(
        SoftBodyContactPolicy.shouldAcceptContact(
          currentBodyId: null,
          incomingBodyId: '',
        ),
        isFalse,
      );
    });
  });
}
