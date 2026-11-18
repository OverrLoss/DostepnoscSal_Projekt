import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/room_model.dart';
import 'room_sync_service.dart';

class RoomDatabaseHelper {
  static final RoomDatabaseHelper instance = RoomDatabaseHelper._init();
  static Database? _database;

  RoomDatabaseHelper._init();

  static const String tableName = 'rooms';

  // In-memory cache for web fallback
  List<Room>? _webRoomsCache;

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('sqflite cannot be used on Flutter Web. Use remote sync API.');
    }
    if (_database != null) return _database!;
    _database = await _initDB('rooms_availability.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        try { await db.execute('ALTER TABLE $tableName ADD COLUMN posX REAL'); } catch (_) {}
        try { await db.execute('ALTER TABLE $tableName ADD COLUMN posY REAL'); } catch (_) {}
        try { await db.execute('ALTER TABLE $tableName ADD COLUMN sortOrder INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE $tableName ADD COLUMN default_alert_limit_seconds INTEGER'); } catch (_) {}
        try { await db.execute('ALTER TABLE $tableName ADD COLUMN layout_scale REAL'); } catch (_) {}
        try { await db.execute('ALTER TABLE $tableName ADD COLUMN layout_angle REAL'); } catch (_) {}
        try { await db.execute('ALTER TABLE $tableName ADD COLUMN svg_id TEXT'); } catch (_) {}
      },
    );

    try { await db.execute('ALTER TABLE $tableName ADD COLUMN posX REAL'); } catch (_) {}
    try { await db.execute('ALTER TABLE $tableName ADD COLUMN posY REAL'); } catch (_) {}
    try { await db.execute('ALTER TABLE $tableName ADD COLUMN sortOrder INTEGER DEFAULT 0'); } catch (_) {}
    try { await db.execute('ALTER TABLE $tableName ADD COLUMN default_alert_limit_seconds INTEGER'); } catch (_) {}

    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number TEXT NOT NULL,
        name TEXT NOT NULL,
        floor TEXT NOT NULL,
        isAvailable INTEGER NOT NULL,
        category TEXT,
        description TEXT,
        capacity INTEGER,
        customNote TEXT,
        posX REAL,
        posY REAL,
        sortOrder INTEGER DEFAULT 0,
        layout_scale REAL,
        layout_angle REAL,
        svg_id TEXT,
        default_alert_limit_seconds INTEGER,
        updatedAt TEXT
      )
    ''');

    for (final room in _getInitialRooms()) {
      await db.insert(tableName, room.toMap());
    }
  }

  List<Room> _getInitialRooms() {
    return [
      // PIĘTRO
      Room(
        id: 1,
        number: '104',
        name: 'Gwiezdne Wojny',
        floor: 'Piętro',
        category: 'EXTRAS',
        description: 'Pokazy tematyczne Star Wars i robotyki kosmicznej',
        capacity: 25,
        isAvailable: true,
      ),
      Room(
        id: 2,
        number: 'AULA',
        name: 'Aula Wykładowa',
        floor: 'Piętro',
        category: 'Wykładowa',
        description: 'Wykłady i pokazy: Rowerowe show, Naukowcy, Fizyka bez tajemnic',
        capacity: 150,
        isAvailable: true,
      ),
      Room(
        id: 3,
        number: '112',
        name: 'Druk 3D',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Warsztaty i pokazy druku przyrostowego 3D',
        capacity: 20,
        isAvailable: true,
      ),
      Room(
        id: 4,
        number: '113',
        name: 'Mikroświat w powiększeniu',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Mikroskopy elektronowe i optyczne dużej rozdzielczości',
        capacity: 15,
        isAvailable: false,
      ),
      Room(
        id: 5,
        number: '115',
        name: 'Spawać każdy może',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Symulator spawania i technologie łączenia metali',
        capacity: 18,
        isAvailable: true,
      ),
      Room(
        id: 6,
        number: '116',
        name: 'OZE w pigułce',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Odnawialne źródła energii, ogniwa fotowoltaiczne',
        capacity: 20,
        isAvailable: true,
      ),
      Room(
        id: 7,
        number: '117',
        name: 'Chemik czy alchemik?',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Eksperymenty chemiczne i reakcje barwne',
        capacity: 22,
        isAvailable: false,
      ),
      Room(
        id: 8,
        number: '118',
        name: 'Gry internetowe',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Stanowiska sieciowe, tworzenie i testowanie gier',
        capacity: 25,
        isAvailable: true,
      ),
      Room(
        id: 9,
        number: '120',
        name: 'Robota czy roboty?',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Programowanie robotów przemysłowych i ramion chwytnych',
        capacity: 20,
        isAvailable: true,
      ),
      Room(
        id: 10,
        number: '122',
        name: 'Latać każdy może',
        floor: 'Piętro',
        category: 'Laboratorium',
        description: 'Symulatory lotu, aerodynamika i tunel aerodynamiczny',
        capacity: 25,
        isAvailable: true,
      ),

      // PARTER
      Room(
        id: 11,
        number: '9',
        name: 'Bryłki bez kleju',
        floor: 'Parter',
        category: 'EXTRAS',
        description: 'Warsztaty kreatywne dla dzieci i młodzieży',
        capacity: 30,
        isAvailable: true,
      ),
      Room(
        id: 12,
        number: '12',
        name: 'Zagraj w piłkarzyki',
        floor: 'Parter',
        category: 'EXTRAS',
        description: 'Strefa rekreacyjna i mini turnieje piłkarzyków',
        capacity: 20,
        isAvailable: true,
      ),
      Room(
        id: 13,
        number: '14',
        name: 'Wirtualny świat',
        floor: 'Parter',
        category: 'Laboratorium',
        description: 'Gogle VR, interaktywne środowiska wirtualne',
        capacity: 15,
        isAvailable: false,
      ),
      Room(
        id: 14,
        number: 'HOL',
        name: 'Piasek kinetyczny',
        floor: 'Parter',
        category: 'EXTRAS',
        description: 'Główna strefa wejściowa, piasek kinetyczny i punkt informacyjny',
        capacity: 80,
        isAvailable: true,
      ),

      // GARAŻ PODZIEMNY
      Room(
        id: 15,
        number: 'Garaż',
        name: 'Wystawa pojazdów zabytkowych',
        floor: 'Garaż podziemny',
        category: 'Wystawa',
        description: 'Ekspozycja unikalnych pojazdów i motocykli zabytkowych',
        capacity: 100,
        isAvailable: true,
      ),
    ];
  }

  Future<int> insertRoom(Room room) async {
    if (kIsWeb) {
      final created = await RoomSyncService.instance.createRemoteRoom(room);
      if (created != null) {
        _webRoomsCache?.add(created);
        return created.id ?? 1;
      }
      return 1;
    }

    final db = await database;
    final id = await db.insert(tableName, room.toMap());
    final roomWithId = room.copyWith(id: id);
    // Sync with remote server
    RoomSyncService.instance.createRemoteRoom(roomWithId).ignore();
    return id;
  }

  Future<int> updateRoom(Room room) async {
    if (kIsWeb) {
      final updated = await RoomSyncService.instance.updateRemoteRoom(room);
      if (updated != null && _webRoomsCache != null) {
        final idx = _webRoomsCache!.indexWhere((r) => r.id == room.id);
        if (idx != -1) {
          _webRoomsCache![idx] = updated;
        }
      }
      return 1;
    }

    final db = await database;
    final count = await db.update(
      tableName,
      room.toMap(),
      where: 'id = ?',
      whereArgs: [room.id],
    );
    // Sync with remote server
    RoomSyncService.instance.updateRemoteRoom(room).ignore();
    return count;
  }

  Future<int> deleteRoom(int id) async {
    final room = await getRoomById(id);
    final roomIdStr = room?.number ?? id.toString();
    if (kIsWeb) {
      await RoomSyncService.instance.deleteRemoteRoom(roomIdStr);
      _webRoomsCache?.removeWhere((r) => r.id == id);
      return 1;
    }

    final db = await database;
    final count = await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
    RoomSyncService.instance.deleteRemoteRoom(roomIdStr).ignore();
    return count;
  }

  Future<bool> toggleAvailability(int id, bool currentStatus, {String? roomNumber, String? occupantName}) async {
    final effectiveRoomNumber = (roomNumber != null && roomNumber.isNotEmpty)
        ? roomNumber
        : (await getRoomById(id))?.number ?? id.toString();

    final success = await RoomSyncService.instance.toggleRemoteAvailability(
      effectiveRoomNumber,
      currentStatus,
      occupantName: occupantName,
    );

    if (kIsWeb) {
      if (_webRoomsCache != null) {
        final idx = _webRoomsCache!.indexWhere((r) => r.id == id || r.number == effectiveRoomNumber);
        if (idx != -1) {
          final r = _webRoomsCache![idx];
          _webRoomsCache![idx] = r.copyWith(
            isAvailable: !currentStatus,
            status: currentStatus ? 'occupied' : 'free',
          );
        }
      }
      return success;
    }

    final db = await database;
    await db.update(
      tableName,
      {
        'isAvailable': currentStatus ? 0 : 1,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return success;
  }

  Future<int> updateRoomAlertLimit(String roomNumber, int limitSeconds) async {
    // Sync with remote server (both web and mobile)
    await RoomSyncService.instance.setRoomAlertLimit(roomNumber, limitSeconds);

    if (kIsWeb) {
      if (_webRoomsCache != null) {
        final idx = _webRoomsCache!.indexWhere((r) => r.number == roomNumber);
        if (idx != -1) {
          _webRoomsCache![idx] = _webRoomsCache![idx].copyWith(defaultAlertLimitSeconds: limitSeconds);
        }
      }
      return 1;
    }

    final db = await database;
    final count = await db.update(
      tableName,
      {
        'default_alert_limit_seconds': limitSeconds,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'number = ?',
      whereArgs: [roomNumber],
    );
    return count;
  }

  Future<void> setAllAvailabilityForFloor({
    required String floor,
    required bool isAvailable,
  }) async {
    if (kIsWeb) {
      if (_webRoomsCache != null) {
        _webRoomsCache = _webRoomsCache!.map((r) {
          if (r.floor == floor) {
            return r.copyWith(isAvailable: isAvailable);
          }
          return r;
        }).toList();
      }
      return;
    }

    final db = await database;
    await db.update(
      tableName,
      {
        'isAvailable': isAvailable ? 1 : 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'floor = ?',
      whereArgs: [floor],
    );
  }

  /// Zapisuje nowe położenie sali na planie. Szuka sali po numerze (lokalne
  /// i serwerowe id się różnią — wcześniej zapis mógł trafić w inną salę).
  /// Zwraca true, gdy serwer przyjął zmianę.
  Future<bool> updateRoomPosition(Room room, double posX, double posY) async {
    final roomNumber = room.number;
    final updated = await RoomSyncService.instance.updateRoomPosition(roomNumber, posX, posY);

    if (kIsWeb) {
      if (updated != null && _webRoomsCache != null) {
        final idx = _webRoomsCache!.indexWhere((r) => r.number == roomNumber);
        if (idx != -1) {
          _webRoomsCache![idx] = updated;
        }
      }
      return updated != null;
    }

    if (updated != null) {
      try {
        final db = await database;
        await db.update(
          tableName,
          {
            'posX': posX,
            'posY': posY,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'number = ?',
          whereArgs: [roomNumber],
        );
      } catch (_) {}
    }
    return updated != null;
  }

  /// Zapisuje rozmiar (skalę) i obrót sali na planie. Zwraca true po zapisie na serwerze.
  Future<bool> updateRoomLayout(Room room, double scale, double angle) async {
    final roomNumber = room.number;
    final updated = await RoomSyncService.instance.updateRoomLayout(roomNumber, scale, angle);

    if (kIsWeb) {
      if (updated != null && _webRoomsCache != null) {
        final idx = _webRoomsCache!.indexWhere((r) => r.number == roomNumber);
        if (idx != -1) {
          _webRoomsCache![idx] = updated;
        }
      }
      return updated != null;
    }

    if (updated != null) {
      try {
        final db = await database;
        await db.update(
          tableName,
          {
            'layout_scale': scale,
            'layout_angle': angle,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'number = ?',
          whereArgs: [roomNumber],
        );
      } catch (_) {}
    }
    return updated != null;
  }

  Future<void> resetRoomPositions({String? floor}) async {
    if (kIsWeb) {
      final updated = await RoomSyncService.instance.resetPositions(floor: floor);
      if (updated != null) {
        _webRoomsCache = updated;
      }
      return;
    }

    final db = await database;
    if (floor != null && floor.isNotEmpty && floor != 'Wszystkie') {
      await db.update(
        tableName,
        {
          'posX': null,
          'posY': null,
          'layout_scale': null,
          'layout_angle': null,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'floor = ?',
        whereArgs: [floor],
      );
    } else {
      await db.update(
        tableName,
        {
          'posX': null,
          'posY': null,
          'layout_scale': null,
          'layout_angle': null,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
    }
    RoomSyncService.instance.resetPositions(floor: floor).ignore();
  }

  Future<void> updateRoomSortOrder(List<int> roomIds) async {
    final stringIds = roomIds.map((e) => e.toString()).toList();
    if (kIsWeb) {
      final updated = await RoomSyncService.instance.updateRoomSortOrder(stringIds);
      if (updated != null) {
        _webRoomsCache = updated;
      }
      return;
    }

    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (int i = 0; i < roomIds.length; i++) {
      batch.update(
        tableName,
        {
          'sortOrder': i,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [roomIds[i]],
      );
    }
    await batch.commit(noResult: true);
    RoomSyncService.instance.updateRoomSortOrder(stringIds).ignore();
  }

  Future<List<Room>> getRooms({
    String? floor,
    String? searchQuery,
    bool? onlyAvailable,
    bool? onlyOccupied,
  }) async {
    // --- Web: always fetch directly from server ---
    if (kIsWeb) {
      final remoteRooms = await RoomSyncService.instance.fetchRemoteRooms(
        floor: floor,
        searchQuery: searchQuery,
        onlyAvailable: onlyAvailable,
        onlyOccupied: onlyOccupied,
      );

      if (remoteRooms != null) {
        _webRoomsCache = remoteRooms;
        return remoteRooms;
      }

      // Fallback if server is not responding
      var list = _webRoomsCache ?? _getInitialRooms();
      if (floor != null && floor.isNotEmpty && floor != 'Wszystkie') {
        if (floor == 'Parter') {
          list = list.where((r) => r.floor == 'Parter' || r.floor == 'Garaż podziemny').toList();
        } else {
          list = list.where((r) => r.floor == floor).toList();
        }
      }
      if (onlyAvailable == true) {
        list = list.where((r) => r.isAvailable).toList();
      } else if (onlyOccupied == true) {
        list = list.where((r) => !r.isAvailable).toList();
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        list = list.where((r) =>
            r.number.toLowerCase().contains(q) ||
            r.name.toLowerCase().contains(q) ||
            r.description.toLowerCase().contains(q) ||
            r.category.toLowerCase().contains(q)).toList();
      }
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    }

    // --- Mobile: try server first (fresh data), fall back to local SQLite ---
    try {
      final remoteRooms = await RoomSyncService.instance.fetchRemoteRooms(
        floor: floor,
        searchQuery: searchQuery,
        onlyAvailable: onlyAvailable,
        onlyOccupied: onlyOccupied,
      );
      if (remoteRooms != null && remoteRooms.isNotEmpty) {
        // Kopia lokalna na wypadek braku serwera. Pełna lista (bez filtrów)
        // zastępuje całą kopię; lista przefiltrowana tylko ją uzupełnia.
        final isFullSnapshot = (floor == null || floor.isEmpty || floor == 'Wszystkie') &&
            (searchQuery == null || searchQuery.trim().isEmpty) &&
            onlyAvailable != true &&
            onlyOccupied != true;
        _updateLocalDbFromRemote(remoteRooms, fullSnapshot: isFullSnapshot).ignore();
        return remoteRooms;
      }
    } catch (_) {
      // Server unreachable — fall through to local SQLite
    }

    // Offline fallback: read from local SQLite
    try {
      final local = await _queryLocalRooms(
        floor: floor,
        searchQuery: searchQuery,
        onlyAvailable: onlyAvailable,
        onlyOccupied: onlyOccupied,
      );
      if (local.isNotEmpty) return local;
    } catch (_) {}

    // Brak serwera i pustej kopii: pokaż domyślne sale PRz w ich ułożeniu,
    // zamiast pustej mapy.
    var defaults = _getInitialRooms();
    if (floor != null && floor.isNotEmpty && floor != 'Wszystkie') {
      defaults = floor == 'Parter'
          ? defaults.where((r) => r.floor == 'Parter' || r.floor == 'Garaż podziemny').toList()
          : defaults.where((r) => r.floor == floor).toList();
    }
    if (onlyAvailable == true) defaults = defaults.where((r) => r.isAvailable).toList();
    if (onlyOccupied == true) defaults = defaults.where((r) => !r.isAvailable).toList();
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      defaults = defaults.where((r) =>
          r.number.toLowerCase().contains(q) ||
          r.name.toLowerCase().contains(q) ||
          r.description.toLowerCase().contains(q) ||
          r.category.toLowerCase().contains(q)).toList();
    }
    return defaults;
  }

  Future<List<Room>> _queryLocalRooms({
    String? floor,
    String? searchQuery,
    bool? onlyAvailable,
    bool? onlyOccupied,
  }) async {
    final db = await database;

    final conditions = <String>[];
    final List<dynamic> whereArgs = [];

    if (floor != null && floor.isNotEmpty && floor != 'Wszystkie') {
      if (floor == 'Parter') {
        conditions.add("(floor = 'Parter' OR floor = 'Garaż podziemny')");
      } else {
        conditions.add('floor = ?');
        whereArgs.add(floor);
      }
    }

    if (onlyAvailable == true) {
      conditions.add('isAvailable = 1');
    } else if (onlyOccupied == true) {
      conditions.add('isAvailable = 0');
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim().toLowerCase()}%';
      conditions.add(
        '(LOWER(number) LIKE ? OR LOWER(name) LIKE ? OR LOWER(description) LIKE ? OR LOWER(category) LIKE ?)',
      );
      whereArgs.addAll([q, q, q, q]);
    }

    final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;

    final maps = await db.query(
      tableName,
      where: whereClause,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: "CASE floor WHEN 'Piętro' THEN 1 WHEN 'Parter' THEN 2 ELSE 3 END, sortOrder ASC, id ASC",
    );

    return maps.map((m) => Room.fromMap(m)).toList();
  }

  /// Update local SQLite with fresh data from server (background, non-blocking).
  /// Lokalna tabela nie ma kolumn operator_id / device_id — wcześniej przez nie
  /// zapis się nie udawał i kopia offline zostawała pusta.
  Future<void> _updateLocalDbFromRemote(List<Room> remoteRooms, {bool fullSnapshot = false}) async {
    try {
      final db = await database;
      final batch = db.batch();
      if (fullSnapshot) {
        // Sale bez liczbowego id (AULA, HOL, Garaż) dublowały się przy każdym zapisie
        batch.delete(tableName);
      }
      for (final r in remoteRooms) {
        final row = r.toMap()
          ..remove('operator_id')
          ..remove('device_id');
        batch.insert(
          tableName,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }



  Future<Room?> getRoomById(int id) async {
    if (kIsWeb) {
      final rooms = await getRooms();
      try {
        return rooms.firstWhere((r) => r.id == id);
      } catch (_) {
        return null;
      }
    }

    final db = await database;
    final maps = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Room.fromMap(maps.first);
    }
    return null;
  }

  Future<Map<String, int>> getFloorStats(String floor) async {
    if (kIsWeb) {
      final rooms = await getRooms(floor: floor);
      final total = rooms.length;
      final free = rooms.where((r) => r.isAvailable).length;
      return {
        'total': total,
        'free': free,
        'occupied': total - free,
      };
    }

    final db = await database;
    final totalQuery = await db.rawQuery(
      'SELECT COUNT(*) as total, SUM(CASE WHEN isAvailable = 1 THEN 1 ELSE 0 END) as freeCount FROM $tableName WHERE floor = ?',
      [floor],
    );

    if (totalQuery.isNotEmpty) {
      final total = Sqflite.firstIntValue(totalQuery) ?? 0;
      final free = (totalQuery.first['freeCount'] as int?) ?? 0;
      return {
        'total': total,
        'free': free,
        'occupied': total - free,
      };
    }
    return {'total': 0, 'free': 0, 'occupied': 0};
  }

  Future<void> resetToDefaults() async {
    if (kIsWeb) {
      await RoomSyncService.instance.resetRemoteRooms();
      _webRoomsCache = _getInitialRooms();
      return;
    }

    final db = await database;
    await db.delete(tableName);
    for (final room in _getInitialRooms()) {
      await db.insert(tableName, room.toMap());
    }
    RoomSyncService.instance.resetRemoteRooms().ignore();
  }
}
