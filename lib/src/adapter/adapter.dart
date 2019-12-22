/**
 * adapter.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *    16/02/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */
import 'dart:async';
import 'package:socket_io/src/namespace.dart';
import 'package:socket_io_common/src/parser/parser.dart';
import 'package:socket_io/src/util/event_emitter.dart';

abstract class Adapter {
  Map nsps = {};
  Map<String, _Room> rooms;
  Map<String, Map> sids;

  add(String id, String room, [fn([_])]);
  del(String id, String room, [fn([_])]);
  delAll(String id, [fn([_])]);
  broadcast(Map packet, [Map opts]);
  clients(List rooms, [fn([_])]);
  clientRooms(String id, [fn(err, [_])]);

  static Adapter newInstance(String key, Namespace nsp) {
    if ('default' == key) {
      return _MemoryStoreAdapter(nsp);
    }
    throw UnimplementedError('not supported other adapter yet.');
  }
}

class _MemoryStoreAdapter extends EventEmitter implements Adapter {
  @override
  Map nsps = {};
  @override
  Map<String, _Room> rooms;
  @override
  Map<String, Map> sids;
  Encoder encoder;
  Namespace nsp;
  _MemoryStoreAdapter(nsp) {
    this.nsp = nsp;
    rooms = {};
    sids = {};
    encoder = nsp.server.encoder;
  }

  /// Adds a socket to a room.
  ///
  /// @param {String} socket id
  /// @param {String} room name
  /// @param {Function} callback
  /// @api public

  @override
  add(String id, String room, [fn([_])]) {
    sids[id] = sids[id] ?? {};
    sids[id][room] = true;
    rooms[room] = rooms[room] ?? _Room();
    rooms[room].add(id);
    if (fn != null) scheduleMicrotask(() => fn(null));
  }

  /// Removes a socket from a room.
  ///
  /// @param {String} socket id
  /// @param {String} room name
  /// @param {Function} callback
  /// @api public
  @override
  del(String id, String room, [fn([_])]) {
    sids[id] = sids[id] ?? {};
    sids[id].remove(room);
    if (rooms.containsKey(room)) {
      rooms[room].del(id);
      if (rooms[room].length == 0) rooms.remove(room);
    }

    if (fn != null) scheduleMicrotask(() => fn(null));
  }

  /// Removes a socket from all rooms it's joined.
  ///
  /// @param {String} socket id
  /// @param {Function} callback
  /// @api public
  @override
  delAll(String id, [fn([_])]) {
    var rooms = sids[id];
    if (rooms != null) {
      for (var room in rooms.keys) {
        if (rooms.containsKey(room)) {
          rooms[room].del(id);
          if (rooms[room].length == 0) rooms.remove(room);
        }
      }
    }
    sids.remove(id);

    if (fn != null) scheduleMicrotask(() => fn(null));
  }

  /// Broadcasts a packet.
  ///
  /// Options:
  ///  - `flags` {Object} flags for this packet
  ///  - `except` {Array} sids that should be excluded
  ///  - `rooms` {Array} list of rooms to broadcast to
  ///
  /// @param {Object} packet object
  /// @api public
  @override
  broadcast(Map packet, [Map opts]) {
    opts = opts ?? {};
    List rooms = opts['rooms'] ?? [];
    List except = opts['except'] ?? [];
    Map flags = opts['flags'] ?? {};
    var packetOpts = {
      'preEncoded': true,
      'volatile': flags['volatile'],
      'compress': flags['compress']
    };
    var ids = {};
    var socket;

    packet['nsp'] = nsp.name;
    encoder.encode(packet, (encodedPackets) {
      if (rooms.isNotEmpty) {
        for (var i = 0; i < rooms.length; i++) {
          var room = rooms[rooms[i]];
          if (room == null) continue;
          var sockets = room.sockets;
          for (var id in sockets.keys) {
            if (sockets.containsKey(id)) {
              if (ids[id] != null || except.indexOf(id) >= 0) continue;
              socket = nsp.connected[id];
              if (socket != null) {
                socket.packet(encodedPackets, packetOpts);
                ids[id] = true;
              }
            }
          }
        }
      } else {
        for (var id in sids.keys) {
          if (except.indexOf(id) >= 0) continue;
          socket = nsp.connected[id];
          if (socket != null) socket.packet(encodedPackets, packetOpts);
        }
      }
    });
  }

  /// Gets a list of clients by sid.
  ///
  /// @param {Array} explicit set of rooms to check.
  /// @param {Function} callback
  /// @api public
  @override
  clients(List rooms, [fn([_])]) {
    rooms = rooms ?? [];

    var ids = {};
    var sids = [];
    var socket;

    if (rooms.isNotEmpty) {
      for (var i = 0; i < rooms.length; i++) {
        var room = rooms[rooms[i]];
        if (room == null) continue;
        var sockets = room.sockets;
        for (var id in sockets.keys) {
          if (sockets.containsKey(id)) {
            if (ids[id] != null) continue;
            socket = nsp.connected[id];
            if (socket != null) {
              sids.add(id);
              ids[id] = true;
            }
          }
        }
      }
    } else {
      for (var id in this.sids.keys) {
        socket = nsp.connected[id];
        if (socket != null) sids.add(id);
      }
    }

    if (fn != null) scheduleMicrotask(() => fn(sids));
  }

  /// Gets the list of rooms a given client has joined.
  ///
  /// @param {String} socket id
  /// @param {Function} callback
  /// @api public
  @override
  clientRooms(String id, [fn(err, [_])]) {
    var rooms = sids[id];
    if (fn != null) scheduleMicrotask(() => fn(null, rooms?.keys));
  }
}


/// Room constructor.
///
/// @api private
class _Room {
  Map<String, bool> sockets;
  int length;
  _Room() {
    sockets = {};
    length = 0;
  }

  /// Adds a socket to a room.
  ///
  /// @param {String} socket id
  /// @api private
  add(String id) {
    if (!sockets.containsKey(id)) {
      sockets[id] = true;
      length++;
    }
  }

  /// Removes a socket from a room.
  ///
  /// @param {String} socket id
  /// @api private
  del(String id) {
    if (sockets.containsKey(id)) {
      sockets.remove(id);
      length--;
    }
  }
}
