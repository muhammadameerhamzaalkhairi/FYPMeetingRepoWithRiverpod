import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final meetingServiceProvider = Provider<MeetingService>(
  (ref) => MeetingService(ref.watch(supabaseClientProvider)),
);

final serverClockProvider = NotifierProvider<ServerClock, Duration>(
  ServerClock.new,
);

class ServerClock extends Notifier<Duration> {
  @override
  Duration build() => Duration.zero;

  Future<void> sync() async {
    final serverNow = await ref.read(meetingServiceProvider).fetchServerNow();
    if (!ref.mounted) return;
    state = serverNow.difference(DateTime.now());
  }

  DateTime now() => DateTime.now().add(state);
}

class NavigationState {
  final int index;
  final bool busy;
  const NavigationState({this.index = 0, this.busy = false});
}

// Each shell instance starts at Home, including after logout/login.
final navigationProvider = NotifierProvider.autoDispose
    .family<NavigationController, NavigationState, Object>(
      NavigationController.new,
    );

class NavigationController extends Notifier<NavigationState> {
  NavigationController(this.owner);
  final Object owner;

  @override
  NavigationState build() => const NavigationState();

  void go(int index) {
    if (state.busy) return;
    state = NavigationState(index: index);
  }

  void setBusy(bool value) {
    state = NavigationState(index: state.index, busy: value);
  }
}
