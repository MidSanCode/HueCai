import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/widgets/dialogs/unsaved_changes.dart';

void main() {
  group('resolveUnsavedChoice', () {
    test('save maps to save', () {
      expect(resolveUnsavedChoice('save'), UnsavedChoice.save);
    });

    test('discard maps to discard', () {
      expect(resolveUnsavedChoice('discard'), UnsavedChoice.discard);
    });

    test('explicit cancel maps to cancel', () {
      expect(resolveUnsavedChoice('cancel'), UnsavedChoice.cancel);
    });

    test('a dismissed dialog maps to cancel, never to discard', () {
      // Critical: a null result must not fall through to "discard", which
      // would silently throw away the user's work.
      expect(resolveUnsavedChoice(null), UnsavedChoice.cancel);
      expect(resolveUnsavedChoice(''), UnsavedChoice.cancel);
      expect(resolveUnsavedChoice('unexpected'), UnsavedChoice.cancel);
    });
  });

  group('choiceAllowsNavigation', () {
    test('save and discard permit navigation', () {
      expect(choiceAllowsNavigation(UnsavedChoice.save), isTrue);
      expect(choiceAllowsNavigation(UnsavedChoice.discard), isTrue);
    });

    test('cancel blocks navigation', () {
      expect(choiceAllowsNavigation(UnsavedChoice.cancel), isFalse);
    });
  });
}
