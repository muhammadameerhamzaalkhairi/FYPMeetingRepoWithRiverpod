import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/meeting_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    'Active snapshot loads once, groups students and protects cached data',
    () async {
      service.rows = [rowFixture(), rowFixture(reg: 'R2')];
      final provider = activeMeetingProvider(Object());
      container.listen(provider, (_, _) {});
      await container.read(provider.notifier).load();
      expect(service.calls, ['clock', 'active', 'rows:1']);
      final state = container.read(provider);
      expect(state.data.groups[1], hasLength(2));
      expect(state.isLoading, isFalse);
      expect(() => state.data.groups[1]!.clear(), throwsUnsupportedError);
      expect(
        () => state.data.groups[1]!.first['status'] = 'done',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'Silent attendance refresh keeps the prior snapshot and busy lock',
    () async {
      final provider = activeMeetingProvider(Object());
      container.listen(provider, (_, _) {});
      final controller = container.read(provider.notifier);
      await controller.load();
      controller.setBusy(true);
      final pending = Completer<Meeting?>();
      service.activeLoader = () => pending.future;
      final loading = controller.load(silent: true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).isLoading, isFalse);
      expect(container.read(provider).busy, isTrue);
      expect(container.read(provider).data.meeting?.id, 1);
      pending.complete(meetingFixture(id: 2));
      await loading;
      expect(container.read(provider).data.meeting?.id, 2);
      expect(container.read(provider).busy, isTrue);
    },
  );

  test('Database errors keep data and replace untrusted messages', () async {
    final provider = activeMeetingProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await controller.load();
    service.activeLoader = () =>
        Future.error(const PostgrestException(message: 'Meeting is locked'));
    await controller.load();
    expect(container.read(provider).data.meeting?.id, 1);
    expect(
      container.read(provider).errorMessage,
      'Unable to load groups. Please try again.',
    );
    expect(container.read(provider).isLoading, isFalse);
    expect(service.calls.where((c) => c == 'active'), hasLength(2));
  });

  test(
    'Older responses and responses after screen disposal cannot overwrite state',
    () async {
      final provider = activeMeetingProvider(Object());
      container.listen(provider, (_, _) {});
      final controller = container.read(provider.notifier);
      final first = Completer<Meeting?>(), second = Completer<Meeting?>();
      var calls = 0;
      service.activeLoader = () => calls++ == 0 ? first.future : second.future;
      final old = controller.load();
      await Future<void>.delayed(Duration.zero);
      final recent = controller.load();
      await Future<void>.delayed(Duration.zero);
      second.complete(meetingFixture(id: 2));
      await recent;
      first.complete(meetingFixture(id: 1));
      await old;
      expect(container.read(provider).data.meeting?.id, 2);
      expect(service.calls.where((c) => c.startsWith('rows:')), ['rows:2']);
      final pending = Completer<Meeting?>();
      service.activeLoader = () => pending.future;
      final late = controller.load();
      await Future<void>.delayed(Duration.zero);
      controller.cancelLoads();
      pending.complete(meetingFixture(id: 3));
      await late;
      expect(container.read(provider).data.meeting?.id, 2);
      expect(service.calls, isNot(contains('rows:3')));
    },
  );

  test(
    'Meeting list is reloaded for a new screen owner and retains busy state',
    () async {
      final provider = meetingsProvider(Object());
      container.listen(provider, (_, _) {});
      final controller = container.read(provider.notifier);
      controller.setBusy(true);
      await controller.load();
      expect(container.read(provider).data, hasLength(1));
      expect(container.read(provider).busy, isTrue);
      final fresh = meetingsProvider(Object());
      container.listen(fresh, (_, _) {});
      expect(container.read(fresh).data, isEmpty);
      expect(container.read(fresh).busy, isFalse);
      await container.read(fresh.notifier).load();
      expect(service.calls.where((c) => c == 'meetings'), hasLength(2));
    },
  );
}
