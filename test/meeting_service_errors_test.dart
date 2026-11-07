import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RpcClient implements SupabaseClient {
  Object? result;
  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    dynamic get = false,
  }) => RpcResult<T>(result);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RpcResult<T> implements PostgrestFilterBuilder<T> {
  RpcResult(this.result);
  final Object? result;

  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) =>
      Future<T>.value(result as T).then(onValue, onError: onError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Malformed save responses propagate a failure instead of an empty success',
    () async {
      final client = RpcClient(), rows = <Map<String, dynamic>>[];
      final service = MeetingService(client);
      for (final result in [
        null,
        [],
        {},
        {'updated': 2},
        {'updated': '2', 'added': 0, 'removed': 0},
      ]) {
        client.result = result;
        await expectLater(service.saveSchedule(1, rows), throwsStateError);
      }
      client.result = {'updated': 2, 'added': 0, 'removed': 0};
      expect(await service.saveSchedule(1, rows), client.result);
    },
  );

  test(
    'Malformed attendance responses fail while a valid unchanged count stays zero',
    () async {
      final client = RpcClient();
      final service = MeetingService(client);
      for (final result in [null, {}, '0']) {
        client.result = result;
        await expectLater(service.setAttendance(1, 1, []), throwsStateError);
        await expectLater(service.markAttendance(1, 1, []), throwsStateError);
      }
      client.result = 0;
      expect(await service.setAttendance(1, 1, []), 0);
      expect(await service.markAttendance(1, 1, []), 0);
    },
  );
}
