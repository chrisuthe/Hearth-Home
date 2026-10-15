import 'dart:async';

import '../../services/home_assistant_service.dart';
import '../../utils/logger.dart';
import 'models.dart';

/// Items of one Home Assistant `todo.*` entity.
///
/// Subscribes with `todo/item/subscribe` (HA 2023.12.0+), which pushes the
/// whole list on every change. HA has no other way to read items, so there
/// is no fallback. Writes go through `TodoActions`, not here.
///
/// [dispose] unsubscribes.
class HaTodoList {
  final HomeAssistantService _ha;
  final String entityId;

  final _controller = StreamController<TodoListState>();
  final List<StreamSubscription<void>> _subs = [];
  TodoListState _current = const TodoListState();
  void Function()? _unsubscribe;
  Timer? _connectTimer;
  bool _disposed = false;

  HaTodoList({
    required HomeAssistantService ha,
    required this.entityId,
    Duration connectTimeout = const Duration(seconds: 20),
  }) : _ha = ha {
    _emit(_current);
    _subs.add(_ha.onDisconnected.listen((_) {
      if (_current.status == ListStatus.ok) {
        _emit(_withStatus(ListStatus.stale, 'Lost connection to Home Assistant'));
      }
    }));
    // The service never surfaces a connect that never happens, so time it.
    _connectTimer = Timer(connectTimeout, () {
      if (_current.status == ListStatus.loading) {
        _emit(_withStatus(ListStatus.error, "Can't reach Home Assistant"));
      }
    });
    _unsubscribe = _ha.subscribe(
      {'type': 'todo/item/subscribe', 'entity_id': entityId},
      onEvent: _onPush,
      onError: _onSubscribeError,
    );
  }

  Stream<TodoListState> get stream => _controller.stream;
  TodoListState get current => _current;

  void _onPush(Map<String, dynamic> event) {
    final items = event['items'];
    if (items is! List) {
      _emit(_withStatus(
          ListStatus.stale, 'Home Assistant could not read the list'));
      return;
    }
    _emit(TodoListState(
        items: TodoItem.parseItems(items), status: ListStatus.ok));
  }

  void _onSubscribeError(Map<String, dynamic> error) {
    // Stop the service replaying a subscribe HA refused.
    _unsubscribe?.call();
    _unsubscribe = null;
    final code = error['code'];
    Log.w('Lists', '$entityId: subscribe failed: $code');
    _emit(_withStatus(
      ListStatus.error,
      switch (code) {
        'invalid_entity_id' => 'List not found in Home Assistant',
        'unknown_command' => 'Home Assistant 2023.12 or newer is needed for lists',
        _ => error['message'] as String? ??
            'Home Assistant refused the list subscription',
      },
    ));
  }

  TodoListState _withStatus(ListStatus status, String error) =>
      TodoListState(items: _current.items, status: status, error: error);

  void _emit(TodoListState value) {
    if (_disposed) return;
    _current = value;
    _controller.add(value);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _connectTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _controller.close();
  }
}
