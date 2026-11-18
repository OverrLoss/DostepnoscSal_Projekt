class RoomSession {
  final String id;
  final String startedAt;
  final int durationSeconds;
  final int alertLimitSeconds;
  final bool alertDue;
  final String? alertTriggeredAt;

  /// Nick / nazwa osoby, która zajęła salę (może być pusta).
  final String? occupantName;

  RoomSession({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    required this.alertLimitSeconds,
    this.alertDue = false,
    this.alertTriggeredAt,
    this.occupantName,
  });

  factory RoomSession.fromMap(Map<String, dynamic> map) {
    return RoomSession(
      id: map['id']?.toString() ?? '',
      startedAt: map['started_at']?.toString() ?? '',
      durationSeconds: (map['duration_seconds'] is num) ? (map['duration_seconds'] as num).toInt() : 0,
      alertLimitSeconds: (map['alert_limit_seconds'] is num) ? (map['alert_limit_seconds'] as num).toInt() : 900,
      alertDue: map['alert_due'] == true,
      alertTriggeredAt: map['alert_triggered_at']?.toString(),
      occupantName: (map['occupant_name']?.toString().trim().isNotEmpty ?? false)
          ? map['occupant_name'].toString().trim()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'started_at': startedAt,
      'duration_seconds': durationSeconds,
      'alert_limit_seconds': alertLimitSeconds,
      'alert_due': alertDue,
      if (alertTriggeredAt != null) 'alert_triggered_at': alertTriggeredAt,
      if (occupantName != null) 'occupant_name': occupantName,
    };
  }
}

class Room {
  final int? id;
  final String number;
  final String name;
  final String floor;
  final bool isAvailable;
  final String status; // 'free' or 'occupied'
  /// Przerwa: sala niedostępna (status occupied), ale bez sesji i bez timera.
  final bool isBreak;

  /// Blokady ustawiane przez admina: chronią status, informacje/timer i układ na mapie.
  final bool lockStatus;
  final bool lockInfo;
  final bool lockLayout;
  final String category;
  final String description;
  final int capacity;
  final String customNote;
  final String updatedAt;

  final double? posX;
  final double? posY;
  final int sortOrder;

  /// Rozmiar sali na planie (1.0 = domyślny) i obrót w stopniach.
  final double? layoutScale;
  final double? layoutAngle;

  /// ID pokoju z SVG (np. room-1-41), do którego sala jest przylepiona na planie.
  final String? svgId;

  final RoomSession? activeSession;
  final int? defaultAlertLimitSeconds;
  final String? operatorId;
  final String? deviceId;

  Room({
    this.id,
    required this.number,
    required this.name,
    required this.floor,
    bool isAvailable = true,
    String? status,
    this.isBreak = false,
    this.lockStatus = false,
    this.lockInfo = false,
    this.lockLayout = false,
    this.category = 'Laboratorium',
    this.description = '',
    this.capacity = 30,
    this.customNote = '',
    String? updatedAt,
    this.posX,
    this.posY,
    this.sortOrder = 0,
    this.layoutScale,
    this.layoutAngle,
    this.svgId,
    this.activeSession,
    this.defaultAlertLimitSeconds,
    this.operatorId,
    this.deviceId,
  })  : isAvailable = isBreak ? false : isAvailable,
        status = status ?? (isBreak ? 'occupied' : (isAvailable ? 'free' : 'occupied')),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  String get displayName => number == name ? number : '$number - $name';

  String get statusText => isBreak
      ? 'Niedostępna (Przerwa)'
      : (status == 'free' || isAvailable) ? 'Dostępna (Wolna)' : 'Niedostępna (Zajęta)';

  bool get isAlertDue => activeSession?.alertDue ?? false;

  /// Kto obecnie zajmuje salę (tylko gdy sala jest zajęta i nick jest znany).
  String? get occupantName => isAvailable ? null : activeSession?.occupantName;

  int get currentDurationSeconds {
    if (activeSession == null) return 0;
    if (activeSession!.startedAt.isNotEmpty) {
      try {
        final start = DateTime.parse(activeSession!.startedAt);
        final diff = DateTime.now().toUtc().difference(start.toUtc()).inSeconds;
        if (diff >= 0) return diff;
      } catch (_) {}
    }
    return activeSession!.durationSeconds;
  }

  String get durationFormatted {
    if (isBreak) return ''; // przerwa nie ma licznika czasu
    final s = currentDurationSeconds;
    if (s <= 0) return '';
    final m = s ~/ 60;
    final sec = s % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final remM = m % 60;
      return '${h}h ${remM}m';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'number': number,
      'name': name,
      'floor': floor,
      'isAvailable': isAvailable ? 1 : 0,
      'is_break': isBreak ? 1 : 0,
      'lock_status': lockStatus ? 1 : 0,
      'lock_info': lockInfo ? 1 : 0,
      'lock_layout': lockLayout ? 1 : 0,
      'category': category,
      'description': description,
      'capacity': capacity,
      'customNote': customNote,
      'updatedAt': updatedAt,
      'posX': posX,
      'posY': posY,
      'sortOrder': sortOrder,
      if (layoutScale != null) 'layout_scale': layoutScale,
      if (layoutAngle != null) 'layout_angle': layoutAngle,
      'svg_id': svgId,
      if (defaultAlertLimitSeconds != null) 'default_alert_limit_seconds': defaultAlertLimitSeconds,
      if (operatorId != null) 'operator_id': operatorId,
      if (deviceId != null) 'device_id': deviceId,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': number,
      'number': number,
      'name': name,
      'floor': floor,
      'isAvailable': isAvailable,
      'status': isAvailable ? 'free' : 'occupied',
      'is_break': isBreak,
      'lock_status': lockStatus,
      'lock_info': lockInfo,
      'lock_layout': lockLayout,
      'category': category,
      'description': description,
      'capacity': capacity,
      'customNote': customNote,
      'updatedAt': updatedAt,
      'posX': posX,
      'posY': posY,
      'sortOrder': sortOrder,
      if (layoutScale != null) 'layout_scale': layoutScale,
      if (layoutAngle != null) 'layout_angle': layoutAngle,
      'svg_id': svgId,
      if (activeSession != null) 'active_session': activeSession!.toMap(),
      if (defaultAlertLimitSeconds != null) 'default_alert_limit_seconds': defaultAlertLimitSeconds,
      if (operatorId != null) 'operator_id': operatorId,
      if (deviceId != null) 'device_id': deviceId,
    };
  }

  factory Room.fromMap(Map<String, dynamic> map) {
    final statusStr = map['status'] as String?;
    final rawAvail = map['isAvailable'];
    final rawBreak = map['is_break'];
    final bool isBreak = rawBreak == true || rawBreak == 1 || rawBreak == '1';
    bool rawLock(dynamic v) => v == true || v == 1 || v == '1';
    final bool lockStatus = rawLock(map['lock_status']);
    final bool lockInfo = rawLock(map['lock_info']);
    final bool lockLayout = rawLock(map['lock_layout']);
    final bool isAvailable = !isBreak && (statusStr != null
        ? (statusStr == 'free')
        : (rawAvail is bool
            ? rawAvail
            : (rawAvail is int
                ? rawAvail == 1
                : (rawAvail == '1' || rawAvail == 'true'))));

    final rawPosX = map['posX'];
    final double? posX = rawPosX != null ? (rawPosX as num).toDouble() : null;

    final rawPosY = map['posY'];
    final double? posY = rawPosY != null ? (rawPosY as num).toDouble() : null;

    final rawSortOrder = map['sortOrder'];
    final int sortOrder = rawSortOrder != null ? (rawSortOrder as num).toInt() : 0;

    int? numericId;
    if (map['id'] is int) {
      numericId = map['id'] as int;
    } else if (map['id'] is String) {
      numericId = int.tryParse(map['id'] as String);
    }

    RoomSession? session;
    if (map['active_session'] is Map) {
      final sMap = map['active_session'] is Map<String, dynamic>
          ? map['active_session'] as Map<String, dynamic>
          : Map<String, dynamic>.from(map['active_session'] as Map);
      session = RoomSession.fromMap(sMap);
    }

    return Room(
      id: numericId,
      number: map['number'] as String? ?? (map['id']?.toString() ?? ''),
      name: map['name'] as String? ?? '',
      floor: map['floor'] as String? ?? 'Piętro',
      isAvailable: isAvailable,
      status: isBreak ? 'occupied' : (statusStr ?? (isAvailable ? 'free' : 'occupied')),
      isBreak: isBreak,
      lockStatus: lockStatus,
      lockInfo: lockInfo,
      lockLayout: lockLayout,
      category: map['category'] as String? ?? 'Laboratorium',
      description: map['description'] as String? ?? '',
      capacity: (map['capacity'] is int)
          ? map['capacity'] as int
          : int.tryParse(map['capacity']?.toString() ?? '30') ?? 30,
      customNote: map['customNote'] as String? ?? '',
      updatedAt: map['updatedAt'] as String? ?? (map['updated_at'] as String? ?? ''),
      posX: posX,
      posY: posY,
      sortOrder: sortOrder,
      layoutScale: (map['layout_scale'] as num?)?.toDouble(),
      layoutAngle: (map['layout_angle'] as num?)?.toDouble(),
      svgId: ((map['svg_id'] as String?) ?? '').isEmpty ? null : map['svg_id'] as String,
      activeSession: session,
      defaultAlertLimitSeconds: map['default_alert_limit_seconds'] as int?,
      operatorId: map['operator_id'] as String?,
      deviceId: map['device_id'] as String?,
    );
  }

  Room copyWith({
    int? id,
    String? number,
    String? name,
    String? floor,
    bool? isAvailable,
    String? status,
    bool? isBreak,
    bool? lockStatus,
    bool? lockInfo,
    bool? lockLayout,
    String? category,
    String? description,
    int? capacity,
    String? customNote,
    String? updatedAt,
    double? posX,
    double? posY,
    int? sortOrder,
    bool resetPosition = false,
    double? layoutScale,
    double? layoutAngle,
    String? svgId,
    bool clearSvgId = false,
    RoomSession? activeSession,
    int? defaultAlertLimitSeconds,
    String? operatorId,
    String? deviceId,
  }) {
    final nextBreak = isBreak ?? this.isBreak;
    final nextAvailable = nextBreak
        ? false
        : (isAvailable ?? (status != null ? (status == 'free') : this.isAvailable));
    return Room(
      id: id ?? this.id,
      number: number ?? this.number,
      name: name ?? this.name,
      floor: floor ?? this.floor,
      isAvailable: nextAvailable,
      status: status ?? (nextAvailable ? 'free' : 'occupied'),
      isBreak: nextBreak,
      lockStatus: lockStatus ?? this.lockStatus,
      lockInfo: lockInfo ?? this.lockInfo,
      lockLayout: lockLayout ?? this.lockLayout,
      category: category ?? this.category,
      description: description ?? this.description,
      capacity: capacity ?? this.capacity,
      customNote: customNote ?? this.customNote,
      updatedAt: updatedAt ?? DateTime.now().toIso8601String(),
      posX: resetPosition ? null : (posX ?? this.posX),
      posY: resetPosition ? null : (posY ?? this.posY),
      sortOrder: sortOrder ?? this.sortOrder,
      layoutScale: resetPosition ? null : (layoutScale ?? this.layoutScale),
      layoutAngle: resetPosition ? null : (layoutAngle ?? this.layoutAngle),
      svgId: clearSvgId ? null : (svgId ?? this.svgId),
      activeSession: activeSession ?? this.activeSession,
      defaultAlertLimitSeconds: defaultAlertLimitSeconds ?? this.defaultAlertLimitSeconds,
      operatorId: operatorId ?? this.operatorId,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
