import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../../providers/project_provider.dart';

/// What the user chose when asked about unsaved changes.
enum UnsavedChoice {
  /// Persist the project, then continue with the pending action.
  save,

  /// Throw the changes away and continue.
  discard,

  /// Abandon the pending action and stay in the editor.
  cancel,
}

/// Maps the raw dialog result onto an [UnsavedChoice].
///
/// Split out from the dialog so the decision table is unit-testable without
/// booting a widget tree (and easy_localization).
UnsavedChoice resolveUnsavedChoice(String? dialogResult) {
  switch (dialogResult) {
    case 'save':
      return UnsavedChoice.save;
    case 'discard':
      return UnsavedChoice.discard;
    default:
      // Dismissed or explicitly cancelled: stay put so nothing is lost.
      return UnsavedChoice.cancel;
  }
}

/// Whether a resolved choice permits the pending navigation to continue.
bool choiceAllowsNavigation(UnsavedChoice choice) => choice != UnsavedChoice.cancel;

/// Asks the user what to do about unsaved changes before a destructive
/// navigation (leaving the editor, opening another file, starting a new one).
///
/// Returns [UnsavedChoice.save] immediately when there is nothing to lose, so
/// callers can always `await` this and then test for [UnsavedChoice.cancel].
Future<UnsavedChoice> confirmUnsavedChanges(BuildContext context) async {
  final pp = context.read<ProjectProvider>();
  if (!pp.hasUnsavedChanges) return UnsavedChoice.save;

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('unsaved.title'.tr()),
      content: Text('unsaved.body'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('cancel'),
          child: Text('unsaved.cancel'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('discard'),
          child: Text('unsaved.discard'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop('save'),
          child: Text('unsaved.save'.tr()),
        ),
      ],
    ),
  );

  final choice = resolveUnsavedChoice(result);
  if (choice == UnsavedChoice.save) {
    await pp.saveProject();
  }
  return choice;
}

/// Convenience wrapper: returns `true` when the pending action may proceed,
/// and `false` when the user chose to stay in the editor.
Future<bool> mayLeaveWithUnsavedChanges(BuildContext context) async {
  return choiceAllowsNavigation(await confirmUnsavedChanges(context));
}
