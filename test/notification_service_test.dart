import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livemeet/models/notification_message.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:livemeet/utils/app_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_client.dart';

class StaffTestService extends MeetingService {
  StaffTestService(super.client);
  @override
  bool get canSendNotifications => true;
}

/// Exercises the real Supabase query builders against an in-memory HTTP server.
class NotificationServer {
  final requests = <http.Request>[];
  final notifications = <Map<String, dynamic>>[];
  bool started = false;
  bool failStart = false, failInsert = false, runningMeeting = true;

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/rpc/group_start')) {
      if (failStart || started) return failure();
      started = true;
      return http.Response('null', 200);
    }
    if (path.endsWith('/meetings')) {
      expect(request.url.queryParameters['status'], 'eq.running');
      return http.Response(runningMeeting ? '[{"id":42}]' : '[]', 200);
    }
    if (path.endsWith('/notifications')) {
      if (failInsert) return failure();
      notifications.add({
        ...jsonDecode(request.body) as Map<String, dynamic>,
        'id': notifications.length + 1,
      });
      return http.Response('', 201);
    }
    return http.Response('null', 200);
  }

  http.Response failure() => http.Response(
    jsonEncode({'code': 'XX000', 'message': 'private database failure'}),
    400,
    headers: {'content-type': 'application/json'},
  );

  SupabaseClient client() {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      accessToken: () async => 'existing-operator-session',
      httpClient: MockClient((request) async {
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    return client;
  }
}

void main() {
  test('Manual notifications require a signed-in staff session', () async {
    final auth = FakeAuthClient();
    final service = MeetingService(FakeAuthSupabaseClient(auth));
    expect(service.canSendNotifications, isFalse);
    await expectLater(
      service.sendCustomNotification('Test'),
      throwsA(isA<UserMessageException>()),
    );
    auth.currentSession = Session(
      accessToken: 'test',
      tokenType: 'bearer',
      user: const User(
        id: 'staff',
        aud: 'authenticated',
        createdAt: '',
        appMetadata: {},
        userMetadata: {},
      ),
    );
    expect(service.canSendNotifications, isTrue);
  });

  test(
    'Custom announcement uses the supplied authenticated client and payload',
    () async {
      final server = NotificationServer();
      final service = StaffTestService(server.client());
      await service.sendCustomNotification('  Please join.  ');
      final request = server.requests.last;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/notifications');
      expect(
        request.headers['Authorization'],
        'Bearer existing-operator-session',
      );
      expect(jsonDecode(request.body), {
        'meeting_id': null,
        'group_no': null,
        'kind': 'custom',
        'message': 'Please join.',
      });
    },
  );

  test(
    'All six presets can be inserted as general custom announcements',
    () async {
      final server = NotificationServer();
      final service = StaffTestService(server.client());
      expect(NotificationPreset.values.map((p) => p.message), [
        'Meeting is about to start.',
        'Meeting will start in 5 minutes.',
        'Meeting will start in 10 minutes.',
        'Please be ready for your meeting.',
        'The next group is requested to join.',
        'Meeting has been delayed.',
      ]);
      for (final preset in NotificationPreset.values) {
        await service.sendCustomNotification(preset.message);
        expect(server.notifications.last['kind'], 'custom');
        expect(server.notifications.last['message'], preset.message);
      }
    },
  );

  test(
    'Empty and overlength messages never reach Supabase; 200 is accepted',
    () async {
      final server = NotificationServer();
      final service = StaffTestService(server.client());
      for (final value in ['', ' \n\t ', 'x' * 201, '😀' * 201, '👩‍💻' * 67]) {
        await expectLater(
          service.sendCustomNotification(value),
          throwsA(isA<UserMessageException>()),
        );
      }
      expect(server.requests, isEmpty);
      for (final value in ['x' * 200, '😀' * 200]) {
        await service.sendCustomNotification(value);
        expect(server.notifications.last['message'], value);
      }
    },
  );

  test(
    'Custom insert failures propagate so the dialog can offer retry',
    () async {
      final server = NotificationServer()..failInsert = true;
      final service = StaffTestService(server.client());
      await expectLater(
        service.sendCustomNotification('Hello'),
        throwsA(isA<PostgrestException>()),
      );
      expect(server.notifications, isEmpty);
      server.failInsert = false;
      await service.sendCustomNotification('Hello');
      expect(server.notifications, hasLength(1));
    },
  );

  test('Starting a group never reads or writes notifications', () async {
    final server = NotificationServer();
    final service = StaffTestService(server.client());
    await service.startGroup(42, 3, present: ['R3']);
    await expectLater(
      service.startGroup(42, 3),
      throwsA(isA<PostgrestException>()),
    );
    expect(
      server.requests.map((r) => r.url.path),
      everyElement('/rest/v1/rpc/group_start'),
    );
    expect(jsonDecode(server.requests.first.body), {
      'p_meeting': 42,
      'p_group': 3,
      'p_present': ['R3'],
    });
  });

  test('Send checks the current running state before inserting', () async {
    final server = NotificationServer()..runningMeeting = false;
    final service = StaffTestService(server.client());
    await expectLater(
      service.sendCustomNotification('Important update'),
      throwsA(isA<UserMessageException>()),
    );
    expect(server.notifications, isEmpty);
    expect(server.requests.single.url.path, '/rest/v1/meetings');
  });

  test(
    'Pause, resume, end and restart retain RPCs and never send notifications',
    () async {
      final server = NotificationServer();
      final service = StaffTestService(server.client());
      await service.pauseGroup(9, 2);
      await service.resumeGroup(9, 2);
      await service.endGroup(9, 2);
      await service.pauseMeeting(9);
      await service.resumeMeeting(9);
      await service.endMeeting(9);
      await service.restartMeeting(9);
      expect(server.requests.map((r) => r.url.path.split('/').last), [
        'group_pause',
        'group_resume',
        'group_end',
        'pause_meeting',
        'resume_meeting',
        'end_meeting',
        'restart_meeting',
      ]);
      expect(server.notifications, isEmpty);
    },
  );
}
