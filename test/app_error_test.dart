import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/utils/app_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  String message(Object error, [ErrorAction action = ErrorAction.save]) =>
      AppError.message(error, action: action);

  test('Network and timeout failures give a connection correction', () {
    for (final error in [
      const SocketException('host lookup failed: private-host'),
      const HandshakeException('TLS failure'),
      const HttpException('connection closed'),
      TimeoutException('private RPC timed out'),
      AuthRetryableFetchException(message: 'failed to fetch'),
    ]) {
      expect(message(error), AppError.connection);
    }
  });

  test('Authentication maps codes without exposing server text', () {
    expect(
      message(const AuthException('private', code: 'invalid_credentials')),
      contains('email or password is incorrect'),
    );
    expect(
      message(const AuthException('private', code: 'email_not_confirmed')),
      contains('verify your email'),
    );
    for (final code in [
      'session_expired',
      'session_not_found',
      'refresh_token_not_found',
      'refresh_token_already_used',
      'bad_jwt',
    ]) {
      expect(
        message(AuthException('private', code: code)),
        AppError.sessionExpired,
      );
    }
    expect(message(AuthSessionMissingException()), AppError.sessionExpired);
    expect(
      message(PlatformException(code: 'permission_denied')),
      contains('Allow file access'),
    );
    expect(
      message(const AuthException('private', statusCode: '403')),
      AppError.permission,
    );
    expect(
      message(const AuthException('private', statusCode: '429')),
      contains('Too many'),
    );
    expect(
      message(const AuthException('private', statusCode: '503')),
      contains('temporarily unavailable'),
    );
  });

  test(
    'Database codes map permissions, conflicts, validation and service errors',
    () {
      const expected = {
        '42501': AppError.permission,
        'PGRST301': AppError.sessionExpired,
        'PGRST302': AppError.sessionExpired,
        'PGRST303': AppError.sessionExpired,
        '23505': 'This information already exists.',
        '23503': 'Related meeting information has changed.',
        '23502': 'Some information is missing or invalid.',
        '23514': 'Some information is missing or invalid.',
        '22P02': 'Some information is missing or invalid.',
        '22007': 'Some information is missing or invalid.',
        '57014': 'The request took too long.',
        '503': 'The service is temporarily unavailable.',
        'PGRST000': 'The service is temporarily unavailable.',
      };
      for (final entry in expected.entries) {
        expect(
          message(PostgrestException(message: 'private SQL', code: entry.key)),
          startsWith(entry.value),
        );
      }
      expect(
        message(
          const PostgrestException(
            message: 'duplicate key one_active_meeting',
            code: '23505',
          ),
        ),
        contains('Another meeting is already active'),
      );
      expect(
        message(
          const PostgrestException(
            message: 'Another group is already running',
            code: 'P0001',
          ),
        ),
        contains('End it before starting this group'),
      );
      expect(
        message(
          const PostgrestException(
            message: 'Group 12 cannot be started',
            code: 'P0001',
          ),
        ),
        contains('This group has changed'),
      );
    },
  );

  test(
    'Every operation has a safe fallback for unknown and malformed errors',
    () {
      for (final action in ErrorAction.values) {
        for (final error in [
          Exception('sensitive SQL or exception'),
          const PostgrestException(
            message: 'sensitive SQL or exception',
            details: 'private data',
          ),
          const AuthException('sensitive SQL or exception'),
          const FormatException(
            'sensitive SQL or exception',
            'private workbook',
          ),
          PlatformException(
            code: 'unknown',
            message: 'sensitive SQL or exception',
          ),
        ]) {
          final result = message(error, action);
          expect(result, isNot(contains('sensitive')));
          expect(result, isNot(contains('private')));
          expect(
            result,
            anyOf(
              contains('try again'),
              contains('trying again'),
              contains('restart'),
              contains('Choose'),
            ),
          );
        }
      }
      expect(
        message(const UserMessageException('Row 9 is missing a reg #.')),
        'Row 9 is missing a reg #.',
      );
      expect(
        message(const FormatException('ZIP offset 42'), ErrorAction.preview),
        contains('valid .xlsx'),
      );
    },
  );

  test(
    'Debug logs retain diagnostics and stack while removing secrets and row values',
    () {
      final output = <String>[];
      final previous = debugPrint;
      debugPrint = (String? line, {int? wrapWidth}) => output.add(line ?? '');
      addTearDown(() {
        debugPrint = previous;
        dotenv.clean();
      });
      dotenv.loadFromString(
        envString:
            'SUPABASE_ANON_KEY=test-config-secret\nSUPABASE_URL=https://private.example',
      );
      const error = PostgrestException(
        code: '23505',
        message:
            'duplicate key violates unique constraint "meeting_reg" password=private-password Authorization=Bearer private-bearer',
        details:
            'Key (reg_no)=(private-student) email=student@example.com token=private-token test-config-secret https://private.example?apikey=private-key',
        hint: 'Check duplicate records',
      );
      AppError.handle(
        error,
        StackTrace.fromString('test_failure.dart:42'),
        action: ErrorAction.save,
      );
      final log = output.join('\n');
      expect(log, contains('PostgrestException'));
      expect(log, contains('23505'));
      expect(log, contains('duplicate key'));
      expect(log, contains('Check duplicate records'));
      expect(log, contains('test_failure.dart:42'));
      for (final secret in [
        'private-password',
        'private-bearer',
        'private-student',
        'student@example.com',
        'private-token',
        'test-config-secret',
        'private-key',
      ]) {
        expect(
          log.contains(secret),
          isFalse,
          reason: 'Sensitive values must be redacted',
        );
      }
      output.clear();
      AppError.log(
        const FormatException('Invalid workbook', 'sensitive-file-contents'),
        StackTrace.empty,
        action: ErrorAction.preview,
      );
      expect(output.join(), contains('Invalid workbook'));
      expect(output.join(), isNot(contains('sensitive-file-contents')));
      expect(
        AppError.redact(
          'Authorization: Basic dXNlcjpwYXNz refreshToken=short-secret '
          'Failing row contains (1, private-student, private-name)',
        ),
        isNot(
          anyOf(
            contains('dXNlcjpwYXNz'),
            contains('short-secret'),
            contains('private-student'),
            contains('private-name'),
          ),
        ),
      );
    },
  );
}
