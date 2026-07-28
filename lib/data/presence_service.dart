import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Ephemeral connection state. It never contains gameplay or private cards.
class PresenceService {
  PresenceService({FirebaseAuth? auth, FirebaseDatabase? database})
    : _auth = auth ?? FirebaseAuth.instance,
      _database = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  DatabaseReference get _status {
    final uid = _auth.currentUser?.uid;
    if (uid == null)
      throw StateError('Cần đăng nhập trước khi cập nhật presence.');
    return _database.ref('status/$uid');
  }

  Future<void> markOnline(String roomId) async {
    final status = _status;
    await status.onDisconnect().set({
      'state': 'offline',
      'roomId': roomId,
      'lastChanged': ServerValue.timestamp,
    });
    await status.set({
      'state': 'online',
      'roomId': roomId,
      'lastChanged': ServerValue.timestamp,
    });
  }

  Future<void> markReconnecting(String roomId) => _status.set({
    'state': 'reconnecting',
    'roomId': roomId,
    'lastChanged': ServerValue.timestamp,
  });

  Future<void> clear() async {
    final status = _status;
    await status.onDisconnect().cancel();
    await status.remove();
  }
}
