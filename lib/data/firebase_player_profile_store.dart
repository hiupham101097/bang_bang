import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../config/game_backend.dart';

/// Persistent player data owned by Firebase Authentication + Realtime Database.
///
/// Artwork is never uploaded: [avatarAsset] is a path bundled in the Flutter
/// application. Currency and unlocked titles are deliberately read-only from
/// the app; rewards must be granted by the authoritative game backend.
class FirebasePlayerAccount {
  const FirebasePlayerAccount({
    required this.uid,
    required this.displayName,
    required this.avatarAsset,
    required this.coins,
    required this.titles,
    this.equippedTitle,
  });

  final String uid;
  final String displayName;
  final String avatarAsset;
  final int coins;
  final Set<String> titles;
  final String? equippedTitle;

  static const defaultAvatarAsset = 'assets/images/role_sheriff.png';
}

class FirebasePlayerProfileStore {
  FirebasePlayerProfileStore._();

  static final instance = FirebasePlayerProfileStore._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: firebaseRealtimeDatabaseUrl,
  );

  Future<FirebasePlayerAccount> ensureAccount() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
    if (user == null) {
      throw StateError('Không thể tạo tài khoản Firebase.');
    }

    final reference = _database.ref('users/${user.uid}');
    final snapshot = await reference.get();
    if (!snapshot.exists) {
      final defaultName = 'Cao bồi ${user.uid.substring(0, 5)}';
      // Only write paths that the client owns. Wallet and titles begin empty
      // and are later granted by the server-side reward path.
      await reference.child('profile').set({
        'displayName': defaultName,
        'avatarAsset': FirebasePlayerAccount.defaultAvatarAsset,
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });
      return FirebasePlayerAccount(
        uid: user.uid,
        displayName: defaultName,
        avatarAsset: FirebasePlayerAccount.defaultAvatarAsset,
        coins: 0,
        titles: const {},
      );
    }
    return _accountFromSnapshot(user.uid, snapshot);
  }

  Stream<FirebasePlayerAccount> watchAccount() async* {
    final account = await ensureAccount();
    yield account;
    await for (final event in _database.ref('users/${account.uid}').onValue) {
      yield _accountFromSnapshot(account.uid, event.snapshot);
    }
  }

  /// Cosmetic fields are safe for the signed-in player to update.
  Future<void> updateProfile({
    required String displayName,
    required String avatarAsset,
  }) async {
    final account = await ensureAccount();
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty || normalizedName.length > 24) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Tên phải có 1–24 ký tự.',
      );
    }
    if (!avatarAsset.startsWith('assets/images/')) {
      throw ArgumentError.value(
        avatarAsset,
        'avatarAsset',
        'Avatar phải là asset của game.',
      );
    }
    await _database.ref('users/${account.uid}/profile').update({
      'displayName': normalizedName,
      'avatarAsset': avatarAsset,
      'updatedAt': ServerValue.timestamp,
    });
  }

  FirebasePlayerAccount _accountFromSnapshot(
    String uid,
    DataSnapshot snapshot,
  ) {
    final raw = Map<Object?, Object?>.from(snapshot.value as Map? ?? const {});
    final profile = Map<Object?, Object?>.from(
      raw['profile'] as Map? ?? const {},
    );
    final wallet = Map<Object?, Object?>.from(
      raw['wallet'] as Map? ?? const {},
    );
    final rawTitles = Map<Object?, Object?>.from(
      raw['titles'] as Map? ?? const {},
    );
    final titles = rawTitles.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key.toString())
        .toSet();
    final displayName = profile['displayName']?.toString();
    final avatarAsset = profile['avatarAsset']?.toString();
    return FirebasePlayerAccount(
      uid: uid,
      displayName: displayName?.isNotEmpty == true
          ? displayName!
          : 'Cao bồi ${uid.substring(0, 5)}',
      avatarAsset: avatarAsset?.startsWith('assets/images/') == true
          ? avatarAsset!
          : FirebasePlayerAccount.defaultAvatarAsset,
      coins: (wallet['coin'] as num?)?.toInt() ?? 0,
      titles: titles,
      equippedTitle: raw['equippedTitle']?.toString(),
    );
  }
}
