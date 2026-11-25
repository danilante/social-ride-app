import 'dart:collection';

/// Lightweight in-memory queue of GPS positions that failed to upload
/// (typically because of temporary network loss). The caller is responsible
/// for flushing when connectivity returns; this class only stores and
/// de-duplicates by keeping the most recent N points.
class PositionQueue {
  PositionQueue({this.maxSize = 30});

  final int maxSize;
  final Queue<_QueuedPosition> _queue = Queue<_QueuedPosition>();

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  void enqueue(double lat, double lng) {
    _queue.addLast(_QueuedPosition(lat, lng, DateTime.now()));
    while (_queue.length > maxSize) {
      _queue.removeFirst();
    }
  }

  /// Returns a snapshot of the current queue (oldest first) without clearing.
  List<({double lat, double lng, DateTime at})> peekAll() {
    return _queue
        .map((p) => (lat: p.lat, lng: p.lng, at: p.at))
        .toList(growable: false);
  }

  /// Removes and returns the oldest entry, or null if empty.
  ({double lat, double lng, DateTime at})? dequeue() {
    if (_queue.isEmpty) return null;
    final p = _queue.removeFirst();
    return (lat: p.lat, lng: p.lng, at: p.at);
  }

  void clear() => _queue.clear();
}

class _QueuedPosition {
  final double lat;
  final double lng;
  final DateTime at;
  _QueuedPosition(this.lat, this.lng, this.at);
}
