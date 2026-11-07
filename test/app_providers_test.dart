import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:livemeet/utils/time_utils.dart';

class ClockService implements MeetingService {
  late Future<DateTime> response;

  @override
  Future<DateTime> fetchServerNow() => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Navigation stays locked while busy and a new shell starts at Home', () {
    final container = ProviderContainer.test();
    final owner = Object();
    final provider = navigationProvider(owner);
    container.listen(provider, (_, _) {});
    final navigation = container.read(provider.notifier);
    navigation.go(2);
    navigation.setBusy(true);
    navigation.go(1);
    expect(container.read(provider).index, 2);
    navigation.setBusy(false);
    navigation.go(1);
    expect(container.read(provider).index, 1);
    expect(container.read(navigationProvider(Object())).index, 0);
  });

  test('Clock sync uses the existing server offset calculation', () async {
    final service = ClockService();
    final expected = DateTime.now().add(const Duration(minutes: 5));
    service.response = Future.value(expected);
    final container = ProviderContainer.test(
      overrides: [meetingServiceProvider.overrideWithValue(service)],
    );
    final clock = container.read(serverClockProvider.notifier);
    await clock.sync();
    expect(clock.now().difference(expected).inSeconds.abs(), lessThan(2));
    service.response = Future.error(StateError('offline'));
    final offset = container.read(serverClockProvider);
    await expectLater(clock.sync(), throwsStateError);
    expect(container.read(serverClockProvider), offset);
  });

  test('A late clock response cannot update a disposed container', () async {
    final response = Completer<DateTime>();
    final service = ClockService()..response = response.future;
    final container = ProviderContainer(
      overrides: [meetingServiceProvider.overrideWithValue(service)],
    );
    final syncing = container.read(serverClockProvider.notifier).sync();
    container.dispose();
    response.complete(DateTime.now());
    await syncing;
  });

  test('Timers retain running, paused and ended timestamp semantics', () {
    final start = DateTime.utc(2026, 11, 7, 9);
    expect(
      elapsedSec(
        startedAt: start,
        now: start.add(const Duration(seconds: 90)),
        pausedSeconds: 10,
      ),
      80,
    );
    expect(
      elapsedSec(
        startedAt: start,
        frozenAt: start.add(const Duration(seconds: 30)),
        now: start.add(const Duration(hours: 1)),
        pausedSeconds: 10,
      ),
      20,
    );
    expect(
      elapsedSec(
        startedAt: start,
        endedAt: start.add(const Duration(seconds: 50)),
        frozenAt: start.add(const Duration(seconds: 30)),
        pausedSeconds: 10,
      ),
      40,
    );
    expect(
      elapsedSec(
        startedAt: start,
        now: start.subtract(const Duration(seconds: 5)),
      ),
      0,
    );
  });
}
