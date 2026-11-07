import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/models/meeting_draft.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/editor_provider.dart';
import 'support/fake_meeting_service.dart';

void main() {
  late FakeMeetingService service;
  late ProviderContainer container;
  setUp(() {
    service = FakeMeetingService();
    container = ProviderContainer.test(
      overrides: [meetingServiceProvider.overrideWithValue(service)],
    );
  });

  test(
    'Load separates locked groups and preserves numbering and time gaps',
    () async {
      service.rows = [
        rowFixture(status: 'done'),
        {...rowFixture(group: 2, reg: 'R2'), 'meeting_time': '09:15:00'},
      ];
      final provider = editorProvider(Object());
      container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier);
      await editor.load(1);
      final state = container.read(provider);
      expect(state.locked.single.no, 1);
      expect(state.groups.single.students.single.reg, 'R2');
      expect(state.slots, [555]);
      expect(state.gap, 15);
      expect(editor.numberOf(0), 2);
      expect(editor.regsExcept(null), {'r1', 'r2'});
      expect(
        () => state.groups.single.students.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'Reorder, deletion, undo and redo keep positional slots and snapshots',
    () async {
      service.rows = [
        rowFixture(),
        {...rowFixture(group: 2, reg: 'R2'), 'meeting_time': '09:15:00'},
      ];
      final provider = editorProvider(Object());
      container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier);
      await editor.load(1);
      editor.reorder(0, 2);
      expect(container.read(provider).groups.first.project, 'Project 2');
      expect(container.read(provider).slots, [540, 555]);
      editor.deleteGroup(0);
      expect(container.read(provider).groups.single.project, 'Project 1');
      expect(container.read(provider).slots, [540]);
      editor.undo();
      expect(container.read(provider).groups.first.project, 'Project 2');
      editor.undo();
      expect(container.read(provider).groups.first.project, 'Project 1');
      editor.redo();
      expect(container.read(provider).groups.first.project, 'Project 2');
      editor.replaceGroup(
        0,
        DraftGroup(
          uid: container.read(provider).groups.first.uid,
          project: 'Changed',
          supervisor: 'Supervisor',
          students: [DraftStudent('Name', 'R2', 'Flutter')],
        ),
      );
      expect(container.read(provider).redoStack, isEmpty);
      editor.undo();
      expect(container.read(provider).groups.first.project, 'Project 2');
    },
  );

  test(
    'Clipboard survives route disposal; paste has a new ID and unique registrations',
    () async {
      final owner = Object(), provider = editorProvider(owner);
      final sub = container.listen(provider, (_, _) {});
      var editor = container.read(provider.notifier);
      await editor.load(1);
      final original = container.read(provider).groups.first;
      editor.copyGroup(0);
      final pasted = editor.paste()!;
      expect(pasted.group.uid, isNot(original.uid));
      expect(pasted.renamed, isTrue);
      expect(pasted.group.students.single.reg, 'R1-copy');
      expect(container.read(provider).slots.last, 555);
      editor.setBusy(true);
      expect(editor.paste(), isNull);
      final count = container.read(provider).undoStack.length;
      editor.undo();
      expect(container.read(provider).undoStack, hasLength(count));
      sub.close();
      await container.pump();
      final next = editorProvider(Object());
      container.listen(next, (_, _) {});
      editor = container.read(next.notifier);
      await editor.load(2);
      expect(container.read(next).undoStack, isEmpty);
      expect(editor.paste()!.group.students.single.reg, 'R1-copy');
    },
  );

  test(
    'Adding after locked groups uses their last slot and keeps locked progress',
    () async {
      service.rows = [
        {
          ...rowFixture(status: 'paused'),
          'meeting_time': '10:00:00',
          'duration_sec': 60,
        },
      ];
      final provider = editorProvider(Object());
      container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier);
      await editor.load(1);
      editor.addGroup(
        DraftGroup(
          project: 'New',
          supervisor: 'Supervisor',
          students: [DraftStudent('New', 'R2', 'Flutter')],
        ),
      );
      expect(container.read(provider).slots, [615]);
      expect(editor.numberOf(0), 2);
      expect(container.read(provider).locked.single.status, 'paused');
      editor.undo();
      expect(container.read(provider).groups, isEmpty);
      expect(container.read(provider).locked.single.status, 'paused');
    },
  );

  test('Late editor loads cannot replace a closed route draft', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    service.rowsLoader = (_) => pending.future;
    final provider = editorProvider(Object());
    container.listen(provider, (_, _) {});
    final editor = container.read(provider.notifier);
    final loading = editor.load(1);
    editor.cancelLoads();
    pending.complete([rowFixture()]);
    await loading;
    expect(container.read(provider).groups, isEmpty);
  });
}
