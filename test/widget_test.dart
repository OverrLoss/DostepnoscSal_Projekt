import 'package:flutter_test/flutter_test.dart';
import 'package:pw180088/models/room_model.dart';

void main() {
  test('Room model serialization and 1-tap availability toggle test', () {
    final room = Room(
      id: 1,
      number: '112',
      name: 'Druk 3D',
      floor: 'Piętro',
      category: 'Laboratorium',
      description: 'Warsztaty druku przyrostowego 3D',
      capacity: 20,
      isAvailable: true,
    );

    expect(room.displayName, '112 - Druk 3D');
    expect(room.isAvailable, true);
    expect(room.statusText, 'Dostępna (Wolna)');

    final map = room.toMap();
    expect(map['number'], '112');
    expect(map['isAvailable'], 1);
    expect(map['floor'], 'Piętro');

    final fromMap = Room.fromMap(map);
    expect(fromMap.number, '112');
    expect(fromMap.name, 'Druk 3D');
    expect(fromMap.isAvailable, true);

    // Test 1-tap toggle via copyWith
    final toggled = room.copyWith(isAvailable: !room.isAvailable);
    expect(toggled.isAvailable, false);
    expect(toggled.statusText, 'Niedostępna (Zajęta)');
    expect(toggled.toMap()['isAvailable'], 0);
  });

  test('Przerwa jest niedostępna, ale nie ma timera', () {
    final room = Room(number: '112', name: 'Druk 3D', floor: 'Piętro', isBreak: true);
    expect(room.isBreak, true);
    expect(room.isAvailable, false);
    expect(room.status, 'occupied');
    expect(room.statusText, 'Niedostępna (Przerwa)');
    expect(room.durationFormatted, '');

    expect(room.toMap()['is_break'], 1);
    final restored = Room.fromMap(room.toMap());
    expect(restored.isBreak, true);
    expect(restored.isAvailable, false);
    expect(restored.statusText, 'Niedostępna (Przerwa)');

    final ended = room.copyWith(isBreak: false, isAvailable: true);
    expect(ended.isBreak, false);
    expect(ended.isAvailable, true);
    expect(ended.statusText, 'Dostępna (Wolna)');
  });
}
