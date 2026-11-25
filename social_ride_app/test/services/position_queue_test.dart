import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/services/position_queue.dart';

void main() {
  test('enqueue and dequeue preserve order (FIFO)', () {
    final q = PositionQueue(maxSize: 5);
    q.enqueue(1, 1);
    q.enqueue(2, 2);
    q.enqueue(3, 3);

    expect(q.length, 3);
    final first = q.dequeue();
    expect(first!.lat, 1);
    expect(first.lng, 1);
    expect(q.length, 2);
  });

  test('maxSize drops oldest entries', () {
    final q = PositionQueue(maxSize: 2);
    q.enqueue(1, 1);
    q.enqueue(2, 2);
    q.enqueue(3, 3);

    expect(q.length, 2);
    final first = q.dequeue();
    expect(first!.lat, 2); // 1 was dropped
  });

  test('peekAll does not mutate the queue', () {
    final q = PositionQueue();
    q.enqueue(10, 20);
    final snapshot = q.peekAll();
    expect(snapshot.length, 1);
    expect(q.length, 1);
    expect(snapshot.first.lat, 10);
  });

  test('clear empties the queue', () {
    final q = PositionQueue();
    q.enqueue(1, 1);
    q.clear();
    expect(q.isEmpty, isTrue);
  });
}
