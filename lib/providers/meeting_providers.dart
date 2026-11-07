import 'package:livemeet/utils/app_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/providers/app_providers.dart';

typedef ScheduleRow = Map<String, dynamic>;

class MeetingLoadState<T> {
  final T data;
  final bool isLoading, busy;
  final String errorMessage;

  const MeetingLoadState({
    required this.data,
    this.isLoading = false,
    this.busy = false,
    this.errorMessage = '',
  });

  MeetingLoadState<T> copyWith({
    T? data,
    bool? isLoading,
    bool? busy,
    String? errorMessage,
  }) => MeetingLoadState(
    data: data ?? this.data,
    isLoading: isLoading ?? this.isLoading,
    busy: busy ?? this.busy,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

class ActiveMeetingData {
  final Meeting? meeting;
  final Map<int, List<ScheduleRow>> groups;
  const ActiveMeetingData({this.meeting, this.groups = const {}});
}

// Owner keys preserve the existing screen lifetime, even on a rapid tab revisit.
final activeMeetingProvider = NotifierProvider.autoDispose
    .family<
      ActiveMeetingController,
      MeetingLoadState<ActiveMeetingData>,
      Object
    >(ActiveMeetingController.new);

class ActiveMeetingController
    extends Notifier<MeetingLoadState<ActiveMeetingData>> {
  ActiveMeetingController(this.owner);
  final Object owner;
  int _request = 0;
  bool _closed = false;

  @override
  MeetingLoadState<ActiveMeetingData> build() {
    ref.onDispose(cancelLoads);
    return const MeetingLoadState(data: ActiveMeetingData(), isLoading: true);
  }

  void cancelLoads() {
    _closed = true;
    _request++;
  }

  bool _current(int request) => !_closed && ref.mounted && request == _request;

  void setBusy(bool busy) => state = state.copyWith(busy: busy);

  Future<bool> load({
    ErrorAction action = ErrorAction.loadGroups,
    bool silent = false,
  }) async {
    final request = ++_request;
    final service = ref.read(meetingServiceProvider);
    final clock = ref.read(serverClockProvider.notifier);
    state = state.copyWith(
      isLoading: silent ? state.isLoading : true,
      errorMessage: '',
    );
    try {
      await clock.sync();
      if (!_current(request)) return false;
      final meeting = await service.fetchActiveMeeting();
      if (!_current(request)) return false;
      final groups = <int, List<ScheduleRow>>{};
      if (meeting != null) {
        final rows = await service.fetchRows(meeting.id);
        if (!_current(request)) return false;
        for (final row in rows) {
          final number = (row['group_no'] as num).toInt();
          groups.putIfAbsent(number, () => []).add(Map.unmodifiable(row));
        }
      }
      state = state.copyWith(
        data: ActiveMeetingData(
          meeting: meeting,
          groups: Map.unmodifiable(
            groups.map(
              (number, rows) =>
                  MapEntry(number, List<ScheduleRow>.unmodifiable(rows)),
            ),
          ),
        ),
      );
      return true;
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: action);
      if (_current(request)) {
        state = state.copyWith(errorMessage: message);
      }
    } finally {
      if (_current(request)) {
        state = state.copyWith(isLoading: false);
      }
    }
    return false;
  }
}

final meetingsProvider = NotifierProvider.autoDispose
    .family<MeetingsController, MeetingLoadState<List<Meeting>>, Object>(
      MeetingsController.new,
    );

class MeetingsController extends Notifier<MeetingLoadState<List<Meeting>>> {
  MeetingsController(this.owner);
  final Object owner;
  int _request = 0;
  bool _closed = false;

  @override
  MeetingLoadState<List<Meeting>> build() {
    ref.onDispose(cancelLoads);
    return const MeetingLoadState(data: [], isLoading: true);
  }

  void cancelLoads() {
    _closed = true;
    _request++;
  }

  bool _current(int request) => !_closed && ref.mounted && request == _request;
  void setBusy(bool busy) => state = state.copyWith(busy: busy);

  Future<void> load() async {
    final request = ++_request;
    final service = ref.read(meetingServiceProvider);
    final clock = ref.read(serverClockProvider.notifier);
    state = state.copyWith(isLoading: true, errorMessage: '');
    try {
      await clock.sync();
      if (!_current(request)) return;
      final meetings = await service.fetchMeetings();
      if (!_current(request)) return;
      state = state.copyWith(data: List.unmodifiable(meetings));
    } catch (e, stack) {
      final message = AppError.handle(
        e,
        stack,
        action: ErrorAction.loadMeetings,
      );
      if (_current(request)) {
        state = state.copyWith(errorMessage: message);
      }
    } finally {
      if (_current(request)) {
        state = state.copyWith(isLoading: false);
      }
    }
  }
}
