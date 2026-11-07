import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'network_error_stub.dart' if (dart.library.io) 'network_error_io.dart';

enum ErrorAction {
  signIn,
  signOut,
  loadMeeting,
  loadMeetings,
  loadGroups,
  meeting,
  group,
  attendance,
  preview,
  importSchedule,
  save,
  delete,
  download,
  startup,
}

/// Only app-authored corrections belong here. Never wrap a server/parser
/// message in this type: those errors must go through the safe fallback.
class UserMessageException implements Exception {
  const UserMessageException(this.message);
  final String message;

  @override
  String toString() => 'UserMessageException: $message';
}

class AppError {
  AppError._();

  static const connection =
      'Unable to connect. Please check your internet connection and try again.';
  static const sessionExpired =
      'Your session has expired. Please sign in again.';
  static const permission = "You don't have permission to perform this action.";

  /// Logs before returning, including when the originating screen was disposed.
  static String handle(
    Object error,
    StackTrace stack, {
    required ErrorAction action,
  }) {
    log(error, stack, action: action);
    return message(error, action: action);
  }

  static String message(Object error, {required ErrorAction action}) {
    if (error is UserMessageException) return error.message;
    if (isNetworkError(error) ||
        error is TimeoutException ||
        error is AuthRetryableFetchException ||
        const {
          'SocketException',
          'ClientException',
          'HandshakeException',
          'HttpException',
        }.contains(error.runtimeType.toString())) {
      return connection;
    }
    if (error is AuthException) {
      if (error is AuthSessionMissingException) return sessionExpired;
      if (error is AuthUnknownException &&
          isNetworkError(error.originalError)) {
        return connection;
      }
      switch (error.code) {
        case 'invalid_credentials':
          return 'The email or password is incorrect. Please check both and try again.';
        case 'email_not_confirmed':
          return 'Please verify your email before signing in. Check your inbox for the confirmation email.';
        case 'user_banned':
          return 'Your account is unavailable. Please contact your administrator.';
        case 'session_expired':
        case 'session_not_found':
        case 'refresh_token_not_found':
        case 'refresh_token_already_used':
        case 'bad_jwt':
          return sessionExpired;
      }
      if (error.statusCode == '429' ||
          error.code == 'over_request_rate_limit' ||
          error.code == 'over_email_send_rate_limit') {
        return 'Too many attempts. Please wait a few minutes and try again.';
      }
      if (error.statusCode == '401') return sessionExpired;
      if (error.statusCode == '403') return permission;
      if (int.tryParse(error.statusCode ?? '') case final status?
          when status >= 500) {
        return 'The service is temporarily unavailable. Please try again later.';
      }
    }
    if (error is PostgrestException) {
      switch (error.code) {
        case 'PGRST301':
        case 'PGRST302':
        case 'PGRST303':
        case '401':
          return sessionExpired;
        case '42501':
        case '403':
          return permission;
        case '23505':
          // This constraint represents a competing meeting start, not a
          // duplicate imported student or schedule.
          if ('${error.message} ${error.details}'.contains(
            'one_active_meeting',
          )) {
            return 'Another meeting is already active. End it before starting this meeting.';
          }
          return 'This information already exists. Check for duplicates and try again.';
        case '23503':
          return 'Related meeting information has changed. Refresh and try again.';
        case '23502':
        case '23514':
        case '22P02':
        case '22007':
          return 'Some information is missing or invalid. Check the required fields and try again.';
        case '57014':
        case '504':
          return 'The request took too long. Please try again.';
        case '429':
          return 'Too many requests. Please wait a few minutes and try again.';
        case '502':
        case '503':
        case 'PGRST000':
        case 'PGRST001':
        case 'PGRST002':
          return 'The service is temporarily unavailable. Please try again later.';
      }
      // Exact known business failures only. Never display arbitrary server text.
      final known = switch (error.message) {
        'Another meeting is already running' =>
          'Another meeting is already active. End it before starting this meeting.',
        'Another group is already running' =>
          'Another group is already running. End it before starting this group.',
        'Meeting is not running' =>
          'This meeting is no longer running. Refresh to see its current status.',
        'Meeting is not paused' =>
          'This meeting is no longer paused. Refresh to see its current status.',
        'This meeting cannot be started' =>
          'This meeting cannot be started in its current state. Refresh and try again.',
        'Only finished meetings can be restarted' =>
          'Only finished meetings can be restarted. Refresh to see the current status.',
        'No rows to import' =>
          'There are no schedule rows to import. Choose a file with student rows, dates and times.',
        _ => null,
      };
      if (known != null) return known;
      if (RegExp(
        r'^Group \d+ (cannot be started|is not running)$',
      ).hasMatch(error.message)) {
        return 'This group has changed. Refresh to see its current status and try again.';
      }
    }
    if (error is FormatException && action == ErrorAction.preview) {
      return 'Unable to read this Excel file. Choose a valid .xlsx file and try again.';
    }
    if (error is PlatformException &&
        const {
          'permission_denied',
          'access_denied',
          'storage_permission_denied',
        }.contains(error.code)) {
      return 'Unable to access the file. Allow file access in your device settings and try again.';
    }
    return switch (action) {
      ErrorAction.signIn => 'Unable to sign in. Please try again.',
      ErrorAction.signOut => 'Unable to complete sign out. Please try again.',
      ErrorAction.loadMeeting =>
        'Unable to load the meeting. Please try again.',
      ErrorAction.loadMeetings => 'Unable to load meetings. Please try again.',
      ErrorAction.loadGroups => 'Unable to load groups. Please try again.',
      ErrorAction.meeting =>
        'Unable to update the meeting. Refresh and try again.',
      ErrorAction.group => 'Unable to update the group. Refresh and try again.',
      ErrorAction.attendance => 'Unable to save attendance. Please try again.',
      ErrorAction.preview =>
        'Unable to open this file. Choose a valid .xlsx file and try again.',
      ErrorAction.importSchedule =>
        'Unable to import the schedule. Refresh and check the meetings before trying again.',
      ErrorAction.save => 'Unable to save your changes. Please try again.',
      ErrorAction.delete =>
        'Unable to delete the meeting. Refresh and try again.',
      ErrorAction.download =>
        'Unable to download the meeting PDF. Please try again.',
      ErrorAction.startup =>
        'Unable to start Live Meet. Please restart the app. If the problem continues, contact your administrator.',
    };
  }

  /// Keep diagnostics in debug builds only. Do not log request headers,
  /// credentials, workbook contents, or FormatException.source.
  static void log(
    Object error,
    StackTrace stack, {
    required ErrorAction action,
  }) {
    if (!kDebugMode) return;
    final String details;
    if (error is PostgrestException) {
      details =
          'code=${error.code}; message=${error.message}; '
          'details=${error.details}; hint=${error.hint}';
    } else if (error is AuthException) {
      details =
          'code=${error.code}; status=${error.statusCode}; message=${error.message}';
    } else if (error is FormatException) {
      details = 'message=${error.message}; offset=${error.offset}';
    } else if (error is PlatformException) {
      details = 'code=${error.code}; message=${error.message}';
    } else {
      details = error.toString();
    }
    debugPrint(
      '[Live Meet/${action.name}] ${error.runtimeType}: ${redact(details)}\n'
      '${redact(stack.toString(), stackTrace: true)}',
    );
  }

  @visibleForTesting
  static String redact(String text, {bool stackTrace = false}) {
    var safe = text;
    if (dotenv.isInitialized) {
      for (final value in dotenv.env.values.where((v) => v.isNotEmpty)) {
        safe = safe.replaceAll(value, '[redacted]');
      }
    }
    for (final pattern in [
      r'''\b(?:(?:bearer|basic)\s+\S+|(?:password|passwd|access[_-]?token|refresh[_-]?token|token|api[_-]?key|authorization|secret|credential|cookie|set-cookie)\s*[=:]\s*(?:(?:bearer|basic)\s+)?[^\s,;]+)''',
      r'''https?://[^\s,)]+''',
      r'''\bFailing row contains\s*\([^\r\n]*\)''',
      r'''\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b''',
      r'''\([^()]*\)=\([^()]*\)''',
      r'''["'][^"'\r\n]*["']''',
      if (!stackTrace) r'''\b[A-Za-z0-9_+/=-]{24,}(?:\.[A-Za-z0-9_+/=-]+)*\b''',
    ]) {
      safe = safe.replaceAll(
        RegExp(pattern, caseSensitive: false),
        '[redacted]',
      );
    }
    return safe;
  }
}
