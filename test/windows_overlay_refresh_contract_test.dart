import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows overlay refresh retains candidates for the same executable and PID', () {
    final source = File('tool/windows-overlay/Program.cs').readAsStringSync();

    // Source-level regression guard for the native WinForms overlay.
    // Windows compilation is separately covered by the CI build.
    expect(source, contains('if (!_refreshingProcessList) ClearSearch();'));
    expect(source, contains('_refreshingProcessList = true;'));
    expect(source, contains('finally { _refreshingProcessList = false; }'));
    expect(source, contains('var oldGame = _games.SelectedItem as GameItem;'));
    expect(source, contains('candidate.Pid == oldPid.Value &&'));
    expect(source, contains('string.Equals(candidate.Name, oldGame!.Name,'));
    expect(source, contains('StringComparison.OrdinalIgnoreCase'));
    expect(source, contains('if (oldGame != null && _games.SelectedItem is not GameItem) ClearSearch();'));
    expect(source, contains('_games.SelectedIndex = i;'));
  });
}
