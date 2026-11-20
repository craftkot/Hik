import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows overlay refresh retains candidates for the same PID', () {
    final source = File('tool/windows-overlay/Program.cs').readAsStringSync();

    // Source-level regression guard for the native WinForms overlay.
    // Windows compilation is separately covered by the CI build.
    expect(source, contains('if (!_refreshingProcessList) ClearSearch();'));
    expect(source, contains('_refreshingProcessList = true;'));
    expect(source, contains('finally { _refreshingProcessList = false; }'));
    expect(source, contains('if (oldPid != Pid) ClearSearch();'));
    expect(source, contains('if ((_games.Items[i] as GameItem)?.Pid == oldPid.Value)'));
  });
}
