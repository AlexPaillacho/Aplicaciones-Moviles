import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/room.dart';
import '../models/user_location.dart';

/// Fuente de datos local de salas (rooms): caché SQLite + cola de
/// operaciones offline (taller Semana 12).
///
/// Taller Semana 13 (Bloque 6): capa "local" de la nueva arquitectura de
/// datos (remoto / local / repositorio). Antes de este bloque se llamaba
/// `LocalDbService`; el nombre cambió para que las tres capas compartan
/// el mismo prefijo (`Rooms...Source`/`RoomsRepository`) y quede claro
/// que es la contraparte local de `RoomsRemoteSource`. Solo sabe leer y
/// escribir SQLite — no llama al backend ni decide cuándo sincronizar
/// (eso vive en `RoomsRepository`).
///
/// Cuatro tablas, con datos no sensibles (nombre de sala, estado
/// activo/inactivo, timestamps) y, desde el Taller Semana 14, la
/// ubicación APROXIMADA del usuario (redondeada a ~1 km, ver
/// `UserLocation`), que se borra por completo en el logout. El token
/// JWT NUNCA pasa por acá, sigue viviendo exclusivamente en
/// `TokenStorage` (`flutter_secure_storage`), como exige el taller.
///
/// - `rooms_cache`: última copia conocida de cada sala, para lectura sin
///   conexión. Incluye tanto salas confirmadas por el servidor como
///   salas creadas localmente todavía sin sincronizar (con un id
///   temporal negativo).
/// - `pending_room_ops`: cola de escrituras pendientes (crear/editar),
///   cada una con un id de cliente único (`client_op_id`), para poder
///   reenviarlas sin duplicarlas al recuperar la conexión.
/// - `sync_meta`: pares clave/valor; hoy solo se usa para
///   `last_synced_at` (cuándo fue el último `GET /rooms/list` exitoso),
///   que alimenta el indicador de "actualizado hace X" en la UI.
/// - `last_location` (Semana 14, Fase 4): UNA sola fila (`id = 1`) con la
///   última posición aproximada conocida (`status = 'available'`) o el
///   estado "sin ubicación" (`status = 'unavailable'`, sin
///   coordenadas) cuando el permiso no está concedido. Es lo que
///   `RoomsRepository` envía al backend al listar/crear salas.
///   `pending_room_ops` guarda además `latitude`/`longitude` de las
///   creaciones encoladas, para enviar la ubicación del momento en que
///   se creó la sala aunque se sincronice mucho después.
class RoomsLocalSource {
  RoomsLocalSource._internal();
  static final RoomsLocalSource instance = RoomsLocalSource._internal();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'speak_english_local.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE rooms_cache (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            active INTEGER NOT NULL,
            host_id INTEGER,
            host_username TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_room_ops (
            client_op_id TEXT PRIMARY KEY,
            op_type TEXT NOT NULL,
            room_id INTEGER,
            local_temp_id INTEGER,
            name TEXT,
            active INTEGER,
            base_updated_at TEXT,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL,
            latitude REAL,
            longitude REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await _createLastLocationTable(db);
      },
      // v1 -> v2 (Taller Semana 14, Fase 4): agrega la ubicación SIN
      // borrar la caché ni la cola pendiente que ya tenga el dispositivo.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE pending_room_ops ADD COLUMN latitude REAL');
          await db.execute(
              'ALTER TABLE pending_room_ops ADD COLUMN longitude REAL');
          await _createLastLocationTable(db);
        }
      },
    );
  }

  Future<void> _createLastLocationTable(Database db) {
    // CHECK (id = 1): la tabla nunca tiene más de una fila.
    return db.execute('''
      CREATE TABLE last_location (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        status TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        captured_at TEXT NOT NULL
      )
    ''');
  }

  // ===== rooms_cache =====

  /// Guarda/actualiza salas que vienen confirmadas del servidor
  /// (`GET /rooms/list`). No toca las filas con id temporal negativo
  /// (creaciones locales todavía no sincronizadas) ni las que tengan una
  /// edición pendiente en cola: si el servidor todavía no vio esa
  /// edición, sobreescribirla haría "parpadear" la UI de vuelta al
  /// valor viejo.
  Future<void> upsertServerRooms(List<Room> rooms) async {
    final db = await _database;
    final pendingRoomIds = await _roomIdsWithPendingUpdate();

    final batch = db.batch();
    for (final room in rooms) {
      if (pendingRoomIds.contains(room.id)) continue;
      batch.insert('rooms_cache', room.toCacheMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Set<int>> _roomIdsWithPendingUpdate() async {
    final db = await _database;
    final rows = await db.query(
      'pending_room_ops',
      columns: ['room_id'],
      where: "op_type = 'update' AND room_id IS NOT NULL",
    );
    return rows.map((r) => r['room_id'] as int).toSet();
  }

  Future<void> upsertRoom(Room room) async {
    final db = await _database;
    await db.insert('rooms_cache', room.toCacheMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteRoom(int id) async {
    final db = await _database;
    await db.delete('rooms_cache', where: 'id = ?', whereArgs: [id]);
  }

  /// Reemplaza el id temporal (negativo) de una sala creada offline por
  /// el id real que asignó el servidor tras sincronizar.
  Future<void> replaceTempRoomId(int tempId, Room realRoom) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('rooms_cache', where: 'id = ?', whereArgs: [tempId]);
      await txn.insert('rooms_cache', realRoom.toCacheMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Salas cacheadas, con `pendingSync=true` para las que tienen una
  /// operación en cola (crear o editar) todavía sin confirmar.
  Future<List<Room>> getCachedRooms() async {
    final db = await _database;
    final rows = await db.query('rooms_cache', orderBy: 'updated_at DESC');
    final pendingRoomIds = await _roomIdsWithPendingUpdate();
    final pendingTempIds = await _tempIdsWithPendingCreate();

    return rows.map((row) {
      final room = Room.fromCacheMap(row);
      final isPending =
          pendingRoomIds.contains(room.id) || pendingTempIds.contains(room.id);
      return room.copyWith(pendingSync: isPending);
    }).toList();
  }

  Future<Set<int>> _tempIdsWithPendingCreate() async {
    final db = await _database;
    final rows = await db.query(
      'pending_room_ops',
      columns: ['local_temp_id'],
      where: "op_type = 'create' AND local_temp_id IS NOT NULL",
    );
    return rows.map((r) => r['local_temp_id'] as int).toSet();
  }

  // ===== pending_room_ops =====

  /// [latitude]/[longitude] (Fase 4): ubicación aproximada del usuario al
  /// momento de crear la sala, o `null` si no hay ubicación disponible.
  Future<String> enqueueCreate({
    required String clientOpId,
    required int localTempId,
    required String name,
    double? latitude,
    double? longitude,
  }) async {
    final db = await _database;
    await db.insert('pending_room_ops', {
      'client_op_id': clientOpId,
      'op_type': 'create',
      'room_id': null,
      'local_temp_id': localTempId,
      'name': name,
      'active': 1,
      'base_updated_at': null,
      'attempt_count': 0,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    });
    return clientOpId;
  }

  Future<String> enqueueUpdate({
    required String clientOpId,
    required int roomId,
    String? name,
    bool? active,
    required String baseUpdatedAt,
  }) async {
    final db = await _database;
    await db.insert('pending_room_ops', {
      'client_op_id': clientOpId,
      'op_type': 'update',
      'room_id': roomId,
      'local_temp_id': null,
      'name': name,
      'active': active == null ? null : (active ? 1 : 0),
      'base_updated_at': baseUpdatedAt,
      'attempt_count': 0,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
    return clientOpId;
  }

  /// Cola en orden de creación (FIFO), incluyendo las marcadas `failed`
  /// (para reintentarlas manualmente desde la UI si el usuario lo pide).
  Future<List<Map<String, Object?>>> getPendingOperations() async {
    final db = await _database;
    return db.query('pending_room_ops', orderBy: 'created_at ASC');
  }

  Future<int> countPending() async {
    final db = await _database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as c FROM pending_room_ops WHERE status != 'failed'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteOperation(String clientOpId) async {
    final db = await _database;
    await db.delete('pending_room_ops',
        where: 'client_op_id = ?', whereArgs: [clientOpId]);
  }

  Future<void> markAttempt(String clientOpId, {required bool failed}) async {
    final db = await _database;
    await db.rawUpdate(
      "UPDATE pending_room_ops SET attempt_count = attempt_count + 1, status = ? "
      "WHERE client_op_id = ?",
      [failed ? 'failed' : 'pending', clientOpId],
    );
  }

  // ===== sync_meta =====

  Future<void> setLastSyncedAt(DateTime dt) async {
    final db = await _database;
    await db.insert(
      'sync_meta',
      {'key': 'last_synced_at', 'value': dt.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DateTime?> getLastSyncedAt() async {
    final db = await _database;
    final rows = await db.query('sync_meta',
        where: 'key = ?', whereArgs: ['last_synced_at'], limit: 1);
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  // ===== last_location (Taller Semana 14, Fase 4) =====

  /// Guarda la última posición aproximada conocida (reemplaza la fila
  /// anterior, sea una posición o el estado "sin ubicación").
  Future<void> saveLocation(UserLocation location) async {
    final db = await _database;
    await db.insert(
      'last_location',
      {
        'id': 1,
        'status': 'available',
        'latitude': location.latitude,
        'longitude': location.longitude,
        'captured_at': location.capturedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Guarda el estado "sin ubicación" y BORRA las coordenadas
  /// anteriores: si el permiso ya no está concedido, no se conserva ni
  /// se vuelve a enviar una posición vieja.
  Future<void> saveLocationUnavailable() async {
    final db = await _database;
    await db.insert(
      'last_location',
      {
        'id': 1,
        'status': 'unavailable',
        'latitude': null,
        'longitude': null,
        'captured_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lo último guardado sobre la ubicación, o `null` si nunca se guardó
  /// nada (ej. el usuario todavía no interactuó con "salas cercanas").
  Future<CachedLocation?> getCachedLocation() async {
    final db = await _database;
    final rows = await db.query('last_location',
        where: 'id = ?', whereArgs: [1], limit: 1);
    if (rows.isEmpty) return null;

    final row = rows.first;
    final savedAt =
        DateTime.tryParse(row['captured_at'] as String? ?? '') ?? DateTime.now();

    if (row['status'] == 'available') {
      final latitude = (row['latitude'] as num?)?.toDouble();
      final longitude = (row['longitude'] as num?)?.toDouble();
      if (latitude != null && longitude != null) {
        return CachedLocation(
          location: UserLocation(
            latitude: latitude,
            longitude: longitude,
            capturedAt: savedAt,
          ),
          updatedAt: savedAt,
        );
      }
    }
    return CachedLocation(updatedAt: savedAt);
  }

  // ===== Cierre de sesión =====

  /// Borra por completo el almacén local (las 4 tablas). Se llama desde
  /// el logout: el taller exige no dejar datos de sesiones anteriores en
  /// el dispositivo, incluida cualquier operación offline sin enviar y
  /// la ubicación del usuario.
  Future<void> clearAll() async {
    final db = await _database;
    final batch = db.batch();
    batch.delete('rooms_cache');
    batch.delete('pending_room_ops');
    batch.delete('sync_meta');
    batch.delete('last_location');
    await batch.commit(noResult: true);
  }
}
