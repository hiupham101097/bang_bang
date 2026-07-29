import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'domain/online_models.dart';

/// Audio-only WebRTC mesh. Realtime Database carries only temporary SDP/ICE
/// signaling; microphone audio is sent peer-to-peer and is never stored.
class GameVoiceChat extends ChangeNotifier {
  GameVoiceChat._();

  static final GameVoiceChat instance = GameVoiceChat._();

  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, RTCDataChannel> _chatChannels = {};
  final List<RoomChatMessage> _messages = [];
  final _messagesChanged = StreamController<List<RoomChatMessage>>.broadcast();
  StreamSubscription<DatabaseEvent>? _participantsAdded;
  StreamSubscription<DatabaseEvent>? _participantsRemoved;
  StreamSubscription<DatabaseEvent>? _signals;
  MediaStream? _localStream;
  DatabaseReference? _participantsRef;
  DatabaseReference? _mySignalsRef;
  String? _roomId;
  String? _uid;
  bool _isJoining = false;
  bool _isJoined = false;
  bool _isMuted = false;
  int _participantCount = 0;

  bool get isJoining => _isJoining;
  bool get isJoined => _isJoined;
  bool get isMuted => _isMuted;
  int get participantCount => _participantCount;
  String? get roomId => _roomId;
  List<RoomChatMessage> get messages => List.unmodifiable(_messages);
  Stream<List<RoomChatMessage>> get messageStream => _messagesChanged.stream;

  Future<void> join(String roomId) async {
    if (_isJoined && _roomId == roomId) return;
    await leave();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Bạn cần đăng nhập để dùng voice.');
    _isJoining = true;
    notifyListeners();
    try {
      _roomId = roomId;
      _uid = user.uid;
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      final roomRef = _database.ref('voiceRooms/$roomId');
      _participantsRef = roomRef.child('participants');
      _mySignalsRef = roomRef.child('signals/${user.uid}');
      final myParticipant = _participantsRef!.child(user.uid);
      await myParticipant.set({'joinedAt': ServerValue.timestamp});
      await myParticipant.onDisconnect().remove();
      _signals = _mySignalsRef!.onChildAdded.listen(_handleSignalEvent);
      _participantsAdded = _participantsRef!.onChildAdded.listen((event) {
        final peerId = event.snapshot.key;
        if (peerId == null || peerId == _uid) return;
        _participantCount++;
        notifyListeners();
        if (_uid!.compareTo(peerId) < 0) unawaited(_createOffer(peerId));
      });
      _participantsRemoved = _participantsRef!.onChildRemoved.listen((event) {
        final peerId = event.snapshot.key;
        if (peerId == null || peerId == _uid) return;
        _participantCount = (_participantCount - 1).clamp(0, 99);
        unawaited(_closePeer(peerId));
        notifyListeners();
      });
      final existing = await _participantsRef!.get();
      _participantCount = existing.children
          .where((entry) => entry.key != _uid)
          .length;
      for (final entry in existing.children) {
        final peerId = entry.key;
        if (peerId != null && peerId != _uid && _uid!.compareTo(peerId) < 0) {
          unawaited(_createOffer(peerId));
        }
      }
      _isJoined = true;
    } catch (_) {
      await leave();
      rethrow;
    } finally {
      _isJoining = false;
      notifyListeners();
    }
  }

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    for (final track
        in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> sendText(String text, {required String authorName}) async {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!_isJoined) throw StateError('Hãy tham gia voice trước khi chat.');
    if (clean.isEmpty || clean.length > 150) {
      throw StateError('Tin nhắn phải có từ 1 đến 150 ký tự.');
    }
    final message = RoomChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      authorId: _uid ?? '',
      authorName: authorName,
      text: clean,
      sentAt: DateTime.now(),
    );
    _addMessage(message);
    final encoded = jsonEncode({
      'id': message.id,
      'authorId': message.authorId,
      'authorName': message.authorName,
      'text': message.text,
    });
    for (final channel in _chatChannels.values) {
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        await channel.send(RTCDataChannelMessage(encoded));
      }
    }
  }

  Future<void> leave() async {
    await _participantsAdded?.cancel();
    await _participantsRemoved?.cancel();
    await _signals?.cancel();
    _participantsAdded = null;
    _participantsRemoved = null;
    _signals = null;
    for (final peerId in _peers.keys.toList()) {
      await _closePeer(peerId);
    }
    _messages.clear();
    _messagesChanged.add(const []);
    await _localStream?.dispose();
    _localStream = null;
    if (_participantsRef != null && _uid != null) {
      try {
        await _participantsRef!.child(_uid!).remove();
      } catch (_) {
        // onDisconnect removes stale presence if the app is already offline.
      }
    }
    _participantsRef = null;
    _mySignalsRef = null;
    _roomId = null;
    _uid = null;
    _isJoined = false;
    _isMuted = false;
    _participantCount = 0;
    notifyListeners();
  }

  Future<RTCPeerConnection> _peer(String peerId) async {
    final existing = _peers[peerId];
    if (existing != null) return existing;
    final connection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    for (final track
        in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await connection.addTrack(track, _localStream!);
    }
    connection.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      unawaited(
        _sendSignal(peerId, {
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    };
    connection.onDataChannel = (channel) => _bindChatChannel(peerId, channel);
    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_closePeer(peerId));
      }
    };
    _peers[peerId] = connection;
    return connection;
  }

  Future<void> _createOffer(String peerId) async {
    if (!_isJoined && _isJoining == false) return;
    final connection = await _peer(peerId);
    final channel = await connection.createDataChannel(
      'bangbang_chat',
      RTCDataChannelInit(),
    );
    _bindChatChannel(peerId, channel);
    final offer = await connection.createOffer({'offerToReceiveAudio': true});
    await connection.setLocalDescription(offer);
    await _sendSignal(peerId, {'type': 'offer', 'sdp': offer.sdp});
  }

  Future<void> _handleSignalEvent(DatabaseEvent event) async {
    final signalId = event.snapshot.key;
    final value = event.snapshot.value;
    if (signalId == null || value is! Map) return;
    final data = Map<String, dynamic>.from(value);
    final from = data['from'] as String?;
    if (from == null || from == _uid) return;
    try {
      final type = data['type'] as String?;
      if (type == 'offer') {
        final connection = await _peer(from);
        await connection.setRemoteDescription(
          RTCSessionDescription(data['sdp'] as String?, 'offer'),
        );
        final answer = await connection.createAnswer();
        await connection.setLocalDescription(answer);
        await _sendSignal(from, {'type': 'answer', 'sdp': answer.sdp});
      } else if (type == 'answer') {
        final connection = _peers[from];
        if (connection != null) {
          await connection.setRemoteDescription(
            RTCSessionDescription(data['sdp'] as String?, 'answer'),
          );
        }
      } else if (type == 'candidate') {
        final connection = await _peer(from);
        await connection.addCandidate(
          RTCIceCandidate(
            data['candidate'] as String?,
            data['sdpMid'] as String?,
            (data['sdpMLineIndex'] as num?)?.toInt(),
          ),
        );
      }
    } finally {
      await event.snapshot.ref.remove();
    }
  }

  Future<void> _sendSignal(
    String recipient,
    Map<String, dynamic> signal,
  ) async {
    final ref = _mySignalsRef?.parent?.child(recipient);
    if (ref == null || _uid == null) return;
    await ref.push().set({
      ...signal,
      'from': _uid,
      'createdAt': ServerValue.timestamp,
    });
  }

  void _bindChatChannel(String peerId, RTCDataChannel channel) {
    _chatChannels[peerId] = channel;
    channel.onMessage = (message) {
      if (message.isBinary) return;
      try {
        final data = Map<String, dynamic>.from(jsonDecode(message.text) as Map);
        final text = data['text'] as String? ?? '';
        if (text.isEmpty || text.length > 150) return;
        _addMessage(
          RoomChatMessage(
            id:
                data['id'] as String? ??
                DateTime.now().microsecondsSinceEpoch.toString(),
            authorId: data['authorId'] as String? ?? peerId,
            authorName: data['authorName'] as String? ?? 'Cao bồi',
            text: text,
            sentAt: DateTime.now(),
          ),
        );
      } catch (_) {
        // Ignore malformed peer data without affecting the game connection.
      }
    };
  }

  void _addMessage(RoomChatMessage message) {
    _messages.add(message);
    if (_messages.length > 40) _messages.removeAt(0);
    _messagesChanged.add(messages);
  }

  Future<void> _closePeer(String peerId) async {
    await _chatChannels.remove(peerId)?.close();
    final peer = _peers.remove(peerId);
    await peer?.close();
  }
}
