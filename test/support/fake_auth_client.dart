import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory auth boundary; no credentials or requests reach a server.
class FakeAuthClient implements GoTrueClient {
  Object? signInError, signOutError;
  int signInCalls = 0, signOutCalls = 0;
  @override
  Session? currentSession;

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    signInCalls++;
    if (signInError case final error?) throw error;
    return AuthResponse();
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutCalls++;
    currentSession = null;
    if (signOutError case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthSupabaseClient implements SupabaseClient {
  FakeAuthSupabaseClient(this.auth);
  @override
  final FakeAuthClient auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
