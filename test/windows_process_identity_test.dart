import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/windows_live_memory.dart';

void main() {
  test('refresh keeps selection only for the same process creation', () {
    const selected = LiveGameProcess(
      pid: 4182, name: 'game.exe', title: 'Game',
      processStartTicks: 638995000000000000,
    );
    const same = LiveGameProcess(
      pid: 4182, name: 'game.exe', title: 'Game - renamed',
      processStartTicks: 638995000000000000,
    );
    const recycledPid = LiveGameProcess(
      pid: 4182, name: 'other.exe', title: 'Other',
      processStartTicks: 638995000000000001,
    );
    const unknownCreation = LiveGameProcess(
      pid: 4182, name: 'game.exe', title: 'Game',
    );
    const differentPid = LiveGameProcess(
      pid: 4183, name: 'game.exe', title: 'Game',
      processStartTicks: 638995000000000000,
    );

    expect(same.isSameInstanceAs(selected), isTrue);
    expect(recycledPid.isSameInstanceAs(selected), isFalse);
    expect(unknownCreation.isSameInstanceAs(selected), isFalse);
    expect(selected.isSameInstanceAs(unknownCreation), isFalse);
    expect(differentPid.isSameInstanceAs(selected), isFalse);
  });
}
