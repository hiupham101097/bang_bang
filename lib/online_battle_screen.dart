import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'audio_service.dart';
import 'card_effect_overlay.dart';
import 'data/online_room_repository.dart';
import 'domain/online_models.dart';
import 'game_card_widget.dart';
import 'game_engine.dart';
import 'ui/bang_ui.dart';
import 'voice_chat_service.dart';

/// Minimal authoritative online table. Card effects stay in Cloud Functions;
/// this screen only asks the server to advance the currently visible phase.
class OnlineBattleScreen extends StatelessWidget {
  const OnlineBattleScreen({
    super.key,
    required this.repository,
    required this.room,
  });

  final OnlineRoomRepository repository;
  final OnlineRoom room;
  static bool _firstTutorialHandled = false;
  static bool _hideTutorialForSession = false;
  // The hand is fed by a stream and this keeps the selected card stable while
  // the player decides whether to play it.  A tap must never play a card
  // immediately: the player confirms with the action button below the hand.
  static final Map<String, ValueNotifier<String?>> _selectedHandCards = {};

  static ValueNotifier<String?> _selectedHandCard(String roomId) {
    return _selectedHandCards.putIfAbsent(roomId, () => ValueNotifier(null));
  }

  void _showFirstTimeTutorial(BuildContext context) {
    var step = 0;
    var dontShowAgain = false;
    const steps = [
      (
        'AI ĐANG TỚI LƯỢT?',
        'Ghế có viền vàng là người đang chơi. Đồng hồ phía trên cho biết thời gian còn lại.',
        Icons.person_pin_circle_outlined,
      ),
      (
        'RÚT 2 LÁ',
        'Khi đến lượt bạn, hãy hoàn thành phán xét đầu lượt rồi rút 2 lá.',
        Icons.style_outlined,
      ),
      (
        'CHỌN LÁ VÀ MỤC TIÊU',
        'Chạm lá bài để xem chức năng. Khi cần mục tiêu, hãy chọn người chơi hợp lệ.',
        Icons.ads_click_outlined,
      ),
      (
        'LÁ ĐANG ĐÁNH',
        'Lá vừa dùng và nhật ký hành động được công khai để mọi người theo dõi.',
        Icons.visibility_outlined,
      ),
      (
        'PHẢN ỨNG PHÒNG THỦ',
        'Khi bị BANG, bạn có thời gian dùng NÉ hoặc chọn nhận sát thương.',
        Icons.shield_outlined,
      ),
      (
        'KẾT THÚC LƯỢT',
        'Trước khi kết thúc, số lá giữ lại không được vượt quá số máu hiện tại.',
        Icons.flag_outlined,
      ),
    ];
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final item = steps[step];
          return AlertDialog(
            title: Text('${step + 1}/${steps.length} · ${item.$1}'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.$3, size: 48, color: const Color(0xffffc451)),
                  const SizedBox(height: 14),
                  Text(item.$2, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (value) =>
                        setDialogState(() => dontShowAgain = value ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Không hiển thị lại trong phiên này',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _hideTutorialForSession = dontShowAgain;
                  Navigator.pop(dialogContext);
                },
                child: const Text('BỎ QUA'),
              ),
              FilledButton(
                onPressed: () {
                  if (step == steps.length - 1) {
                    _hideTutorialForSession = dontShowAgain;
                    Navigator.pop(dialogContext);
                    return;
                  }
                  setDialogState(() => step++);
                },
                child: Text(
                  step == steps.length - 1 ? 'HOÀN TẤT' : 'TIẾP THEO',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGuide(BuildContext context, String phase, bool isMyTurn) {
    final title = switch (phase) {
      'turn_start' => isMyTurn ? 'BẮT ĐẦU LƯỢT CỦA BẠN' : 'ĐANG CHỜ LƯỢT',
      'play_phase' => isMyTurn ? 'ĐÁNH BÀI' : 'ĐANG CHỜ NGƯỜI CHƠI',
      'discard_phase' => 'BỎ BÀI DƯ',
      'waiting_response' => 'PHẢN ỨNG VỚI BANG!',
      'waiting_multi_response' => 'PHẢN ỨNG TẤN CÔNG DIỆN RỘNG',
      'waiting_duel_response' => 'PHẢN ỨNG ĐẤU SÚNG',
      _ => 'HƯỚNG DẪN TRONG TRẬN',
    };
    final lines = switch (phase) {
      'turn_start' =>
        isMyTurn
            ? const [
                '• Phán xét trước nếu bạn có Dynamite hoặc Jail.',
                '• Sau đó rút 2 lá để vào bước đánh bài.',
              ]
            : const [
                '• Ghế viền vàng là người đang tới lượt.',
                '• Chờ họ rút bài hoặc hết giờ.',
              ],
      'play_phase' =>
        isMyTurn
            ? const [
                '• Chạm lá bài để xem chức năng và chọn mục tiêu.',
                '• BANG chỉ bắn mục tiêu trong tầm; mục tiêu có thể dùng NÉ.',
                '• Bấm KẾT THÚC LƯỢT khi không dùng thêm bài.',
              ]
            : const [
                '• Theo dõi lá đang đánh ở giữa bàn.',
                '• Bạn chỉ thao tác khi được yêu cầu phản ứng.',
              ],
      'discard_phase' => const [
        '• Số lá giữ lại không được vượt quá số máu hiện tại.',
        '• Chọn các lá cần bỏ; lượt chỉ chuyển sau khi bỏ đủ.',
      ],
      'waiting_response' => const [
        '• Người bị BANG có 8 giây để dùng NÉ hoặc nhận sát thương.',
        '• Barrel hoặc kỹ năng nhân vật có thể tạo thêm cách né.',
      ],
      'waiting_multi_response' => const [
        '• Gatling cần NÉ; Indians cần BANG để chống trả.',
        '• Hết thời gian sẽ tự nhận sát thương.',
      ],
      'waiting_duel_response' => const [
        '• Lần lượt dùng BANG để đáp trả.',
        '• Không có BANG thì mất 1 máu.',
      ],
      _ => const ['• Theo dõi thông báo giữa bàn để biết bước tiếp theo.'],
    };
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines
              .map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(line),
                ),
              )
              .toList(),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ĐÃ HIỂU'),
          ),
        ],
      ),
    );
  }

  void _showActionLog(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('NHẬT KÝ HÀNH ĐỘNG'),
      content: SizedBox(
        width: 380,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: room.publicLog.reversed.take(20).length,
          separatorBuilder: (_, _) => const Divider(height: 10),
          itemBuilder: (_, index) => Text(
            _publicLogLabel(room, room.publicLog.reversed.elementAt(index)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('ĐÓNG'),
        ),
      ],
    ),
  );

  Future<void> _call(BuildContext context, String name) async {
    try {
      await repository.runGameAction(name, {
        'roomId': room.id,
        'actionId': '${name}_${DateTime.now().microsecondsSinceEpoch}',
      });
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _callPayload(
    BuildContext context,
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final cardId = payload['cardId'] as String? ?? '';
      if (cardId.startsWith('bang_')) {
        GameAudio.instance.playSfx('bang_shot');
      } else if (cardId.startsWith('gatling_')) {
        GameAudio.instance.playSfx('bang_shot');
      } else if (cardId.startsWith('dodge_')) {
        GameAudio.instance.playSfx('dodge');
      } else if (cardId.startsWith('beer_') || cardId.startsWith('saloon_')) {
        GameAudio.instance.playSfx('win');
      } else if (name == 'drawTurnCards' || name == 'drawCharacterTurnCards') {
        GameAudio.instance.playSfx('card_draw');
      } else if (name == 'acceptBangDamage') {
        GameAudio.instance.playSfx('damage');
      } else {
        GameAudio.instance.playSfx('card_play');
      }
      await repository.runGameAction(name, {'roomId': room.id, ...payload});
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _showChat(BuildContext context) async {
    final controller = TextEditingController();
    final voice = GameVoiceChat.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.forum_outlined),
                  title: Text('CHAT PHÒNG'),
                  subtitle: Text('Tin nhắn tối đa 140 ký tự.'),
                ),
                Expanded(
                  child: StreamBuilder<List<RoomChatMessage>>(
                    stream: voice.messageStream,
                    initialData: voice.messages,
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? const [];
                      if (messages.isEmpty) {
                        return const Center(child: Text('Chưa có tin nhắn.'));
                      }
                      return ListView.builder(
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final time = message.sentAt == null
                              ? ''
                              : TimeOfDay.fromDateTime(
                                  message.sentAt!,
                                ).format(context);
                          return ListTile(
                            dense: true,
                            title: Text(message.authorName),
                            subtitle: Text(message.text),
                            trailing: Text(
                              time,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          maxLength: 140,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (text) async {
                            if (text.trim().isEmpty) return;
                            try {
                              await voice.sendText(text, authorName: 'Cao bồi');
                              controller.clear();
                            } catch (error) {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(content: Text('$error')),
                                );
                              }
                            }
                          },
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'Nhập tin nhắn…',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Gửi',
                        icon: const Icon(Icons.send),
                        onPressed: () async {
                          final text = controller.text;
                          if (text.trim().isEmpty) return;
                          try {
                            await voice.sendText(text, authorName: 'Cao bồi');
                            controller.clear();
                          } catch (error) {
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(
                                sheetContext,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showVoice(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: AnimatedBuilder(
        animation: GameVoiceChat.instance,
        builder: (context, _) {
          final voice = GameVoiceChat.instance;
          final joinedThisRoom = voice.isJoined && voice.roomId == room.id;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  joinedThisRoom ? Icons.record_voice_over : Icons.mic_none,
                  size: 44,
                  color: const Color(0xffffc451),
                ),
                const SizedBox(height: 8),
                const Text(
                  'VOICE PHÒNG',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  joinedThisRoom
                      ? 'Đang kết nối ${voice.participantCount} người chơi khác.'
                      : 'Voice đang chờ signaling realtime qua Cloudflare.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                if (!joinedThisRoom)
                  FilledButton.icon(
                    onPressed: voice.isJoining
                        ? null
                        : () async {
                            try {
                              await voice.join(room.id);
                            } catch (error) {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(content: Text('$error')),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.mic),
                    label: Text(
                      voice.isJoining ? 'ĐANG KẾT NỐI…' : 'THAM GIA VOICE',
                    ),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => voice.setMuted(!voice.isMuted),
                        icon: Icon(voice.isMuted ? Icons.mic_off : Icons.mic),
                        label: Text(voice.isMuted ? 'BẬT MIC' : 'TẮT MIC'),
                      ),
                      OutlinedButton.icon(
                        onPressed: voice.leave,
                        icon: const Icon(Icons.call_end),
                        label: const Text('RỜI VOICE'),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Future<void> _playCard(
    BuildContext context,
    String cardId,
    String playerId,
  ) async {
    String? targetPlayerId;
    final needsTarget =
        cardId.startsWith('bang_') ||
        (cardId.startsWith('dodge_') &&
            room.memberFor(playerId)?.characterId == 'calamity_janet') ||
        cardId.startsWith('jail_') ||
        cardId.startsWith('panico_') ||
        cardId.startsWith('cat_balou_') ||
        cardId.startsWith('duello_');
    if (needsTarget) {
      final actor = room.memberFor(playerId);
      targetPlayerId = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text('CHỌN MỤC TIÊU · ${_cardLabel(cardId)}'),
                subtitle: Text(
                  cardId.startsWith('bang_')
                      ? 'Tầm súng hiện tại: ${actor?.attackRange ?? 1}'
                      : 'Mục tiêu hợp lệ được làm sáng.',
                ),
              ),
              for (final member in room.members.where((member) {
                if (member.id == playerId || !member.isAlive) return false;
                if (!cardId.startsWith('bang_') &&
                    !cardId.startsWith('dodge_')) {
                  return true;
                }
                final distance = _distanceBetween(room, playerId, member.id);
                return _targetBlockedReason(
                      room: room,
                      cardId: cardId,
                      actor: actor,
                      target: member,
                      distance: distance,
                    ) ==
                    null;
              }))
                Builder(
                  builder: (context) {
                    final distance = _distanceBetween(
                      room,
                      playerId,
                      member.id,
                    );
                    final reason = _targetBlockedReason(
                      room: room,
                      cardId: cardId,
                      actor: actor,
                      target: member,
                      distance: distance,
                    );
                    final enabled = reason == null;
                    return ListTile(
                      enabled: enabled,
                      leading: Icon(
                        member.isBot ? Icons.smart_toy : Icons.person,
                        color: enabled
                            ? const Color(0xffffc451)
                            : Colors.white38,
                      ),
                      title: Text(member.displayName),
                      subtitle: Text(
                        enabled
                            ? 'Khoảng cách: $distance · Có thể chọn'
                            : 'Khoảng cách: $distance · $reason',
                        style: TextStyle(
                          color: enabled ? Colors.white70 : Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        enabled ? Icons.check_circle : Icons.block,
                        color: enabled ? Colors.greenAccent : Colors.redAccent,
                      ),
                      onTap: enabled
                          ? () => Navigator.pop(sheetContext, member.id)
                          : null,
                    );
                  },
                ),
            ],
          ),
        ),
      );
      if (targetPlayerId == null) return;
    }
    if (!context.mounted) return;
    String? equipmentCardId;
    if ((cardId.startsWith('panico_') || cardId.startsWith('cat_balou_')) &&
        targetPlayerId != null) {
      final target = room.memberFor(targetPlayerId);
      if (target != null && target.equipment.isNotEmpty) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('CHỌN LÁ BÀI')),
                if (target.cardCount > 0)
                  ListTile(
                    leading: Icon(Icons.style),
                    title: Text('LẤY NGẪU NHIÊN TRÊN TAY'),
                    onTap: () => Navigator.pop(sheetContext, '__hand__'),
                  ),
                for (final equipment in target.equipment)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(_cardLabel(equipment)),
                    onTap: () => Navigator.pop(sheetContext, equipment),
                  ),
              ],
            ),
          ),
        );
        if (choice == null) return;
        equipmentCardId = choice == '__hand__' ? null : choice;
      }
    }
    if (!context.mounted) return;
    final isEquipment = _isEquipmentCard(cardId);
    final actionLabel = isEquipment ? 'ĐẶT BÀI' : 'ĐÁNH';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(actionLabel),
        content: Text(
          targetPlayerId == null
              ? 'Dùng ${_cardLabel(cardId)}?'
              : 'Dùng ${_cardLabel(cardId)} vào ${room.memberFor(targetPlayerId)?.displayName ?? 'mục tiêu này'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final actionName =
        cardId.startsWith('jail_') ||
            cardId.startsWith('dilizenza_') ||
            cardId.startsWith('wells_fargo_') ||
            cardId.startsWith('saloon_') ||
            cardId.startsWith('barrel_') ||
            cardId.startsWith('mustang_') ||
            cardId.startsWith('appaloosa_') ||
            cardId.startsWith('volcanic_') ||
            cardId.startsWith('dynamite_')
        ? 'playSpecialCard'
        : cardId.startsWith('duello_')
        ? 'startDuel'
        : cardId.startsWith('panico_') || cardId.startsWith('cat_balou_')
        ? 'resolveTargetCard'
        : cardId.startsWith('general_store_')
        ? 'openGeneralStore'
        : cardId.startsWith('gatling_') || cardId.startsWith('indiani_')
        ? 'startMultiAttack'
        : 'playCard';
    await _callPayload(context, actionName, {
      'cardId': cardId,
      'targetPlayerId': targetPlayerId,
      'equipmentCardId': equipmentCardId,
      'actionId': 'play_${DateTime.now().microsecondsSinceEpoch}',
    });
  }

  Future<void> _chooseKitCarlson(
    BuildContext context,
    String actionId,
    List<String> choices,
  ) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('KIT CARLSON — CHỌN 2 LÁ')),
                Wrap(
                  spacing: 8,
                  children: choices
                      .map(
                        (cardId) => FilterChip(
                          label: Text(cardId.split('_').first.toUpperCase()),
                          selected: picks.contains(cardId),
                          onSelected: (checked) => setSheetState(() {
                            if (checked && picks.length < 2) picks.add(cardId);
                            if (!checked) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == 2
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('LẤY 2 LÁ'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'chooseKitCarlson', {
      'actionId': actionId,
      'cardIds': selected,
    });
  }

  Future<void> _drawTurn(
    BuildContext context,
    String playerId,
    String? characterId,
  ) async {
    var action = 'drawTurnCards';
    String? targetPlayerId;
    if (characterId == 'kit_carlson') {
      action = 'openKitCarlson';
    } else if (characterId == 'black_jack' || characterId == 'pedro_ramirez') {
      action = 'drawCharacterTurnCards';
    } else if (characterId == 'jesse_jones') {
      targetPlayerId = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.style),
                title: const Text('RÚT 2 LÁ TỪ BỘ BÀI'),
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
              for (final member in room.members.where(
                (member) =>
                    member.id != playerId &&
                    member.isAlive &&
                    member.cardCount > 0,
              ))
                ListTile(
                  leading: const Icon(Icons.person_search),
                  title: Text('LẤY 1 LÁ TỪ ${member.displayName}'),
                  onTap: () => Navigator.pop(sheetContext, member.id),
                ),
            ],
          ),
        ),
      );
      if (targetPlayerId == null) return;
      action = 'drawJesseJones';
    }
    if (!context.mounted) return;
    await _callPayload(context, action, {
      'actionId': 'draw_${DateTime.now().microsecondsSinceEpoch}',
      if (targetPlayerId?.isNotEmpty == true) 'targetPlayerId': targetPlayerId,
    });
  }

  Future<void> _useSidKetchum(BuildContext context, List<String> hand) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('SID KETCHUM'),
                  subtitle: Text('Chọn 2 lá để hồi 1 máu.'),
                ),
                Wrap(
                  spacing: 8,
                  children: hand
                      .map(
                        (cardId) => FilterChip(
                          label: Text(_cardLabel(cardId)),
                          selected: picks.contains(cardId),
                          onSelected: (selected) => setSheetState(() {
                            if (selected && picks.length < 2) picks.add(cardId);
                            if (!selected) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == 2
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('BỎ 2 LÁ VÀ HỒI MÁU'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'useSidKetchum', {'cardIds': selected});
  }

  Future<void> _discardExcessCards(
    BuildContext context,
    List<String> hand,
    int required,
  ) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('BỎ BÀI DƯ'),
                  subtitle: Text('Chọn đúng $required lá để bỏ.'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: hand
                      .map(
                        (cardId) => FilterChip(
                          label: Text(_cardLabel(cardId)),
                          selected: picks.contains(cardId),
                          onSelected: (selected) => setSheetState(() {
                            if (selected && picks.length < required) {
                              picks.add(cardId);
                            }
                            if (!selected) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == required
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('BỎ BÀI VÀ CHUYỂN LƯỢT'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'discardCards', {'cardIds': selected});
  }

  Future<void> _resolveSlabDodge(
    BuildContext context,
    String actionId,
    List<String> dodges,
  ) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('SLAB THE KILLER'),
                  subtitle: Text('Cần dùng 2 lá Né để tránh phát Bang này.'),
                ),
                Wrap(
                  spacing: 8,
                  children: dodges
                      .map(
                        (cardId) => FilterChip(
                          label: Text(_cardLabel(cardId)),
                          selected: picks.contains(cardId),
                          onSelected: (selected) => setSheetState(() {
                            if (selected && picks.length < 2) picks.add(cardId);
                            if (!selected) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == 2
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('DÙNG 2 LÁ NÉ'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'resolveSlabDodge', {
      'pendingActionId': actionId,
      'cardIds': selected,
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlayerProfile>(
    future: repository.ensureSignedIn(),
    builder: (context, profileSnapshot) {
      if (profileSnapshot.hasData &&
          !_firstTutorialHandled &&
          !_hideTutorialForSession) {
        _firstTutorialHandled = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showFirstTimeTutorial(context),
        );
      }
      final playerId = profileSnapshot.data?.uid;
      final activePlayer = room.memberFor(room.currentTurnPlayerId ?? '');
      final currentPlayer = playerId == null ? null : room.memberFor(playerId);
      final isMyTurn = playerId != null && playerId == room.currentTurnPlayerId;
      final canPlay = isMyTurn && room.phase == 'play_phase';
      final phase = room.phase;
      // The authoritative Worker resolves Dynamite/Jail during the draw
      // command. Do not keep the old Firebase-only gate here, otherwise the
      // player can be stuck at TURN_START forever.
      final canDraw = isMyTurn && phase == 'turn_start';
      return Scaffold(
        backgroundColor: const Color(0xff160c08),
        appBar: AppBar(
          toolbarHeight: 38,
          titleSpacing: 8,
          title: const Text('BANG BANG — Bàn đấu'),
          actions: [
            if (room.settings.voiceEnabled && GameVoiceChat.isAvailable)
              AnimatedBuilder(
                animation: GameVoiceChat.instance,
                builder: (context, _) {
                  final voice = GameVoiceChat.instance;
                  final joinedThisRoom =
                      voice.isJoined && voice.roomId == room.id;
                  return IconButton(
                    tooltip: joinedThisRoom ? 'Voice đang bật' : 'Voice phòng',
                    onPressed: () => _showVoice(context),
                    icon: Icon(
                      voice.isMuted
                          ? Icons.mic_off
                          : joinedThisRoom
                          ? Icons.mic
                          : Icons.mic_none,
                      color: joinedThisRoom ? const Color(0xffffc451) : null,
                    ),
                  );
                },
              ),
            if (room.settings.chatEnabled && GameVoiceChat.isAvailable)
              IconButton(
                tooltip: 'Chat phòng',
                onPressed: () => _showChat(context),
                icon: const Icon(Icons.forum_outlined),
              ),
            IconButton(
              tooltip: 'Nhật ký hành động',
              onPressed: room.publicLog.isEmpty
                  ? null
                  : () => _showActionLog(context),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: 'Hướng dẫn',
              onPressed: () => _showGuide(context, phase, isMyTurn),
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
        bottomNavigationBar: _BattleHandDock(
          repository: repository,
          room: room,
          isMyTurn: isMyTurn,
          canPlay: canPlay,
          activePlayer: activePlayer,
          onPlay: (cardId) => _playCard(context, cardId, playerId),
        ),
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/wild_west_town.png'),
                    fit: BoxFit.cover,
                    opacity: .48,
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: ColoredBox(color: Color(0xa9160c08)),
            ),
            SafeArea(
              top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: ListView(
              children: [
                BangStatusPill(
                  label: isMyTurn ? 'LƯỢT CỦA BẠN' : 'ĐANG THEO DÕI',
                  color: isMyTurn ? bangGold : Colors.white70,
                  icon: isMyTurn
                      ? Icons.local_fire_department_outlined
                      : Icons.visibility_outlined,
                ),
                const SizedBox(height: 7),
                Text(
                  activePlayer == null
                      ? _phaseLabel(phase)
                      : isMyTurn
                      ? 'ĐẾN LƯỢT CỦA BẠN'
                      : 'ĐANG CHỜ ${activePlayer.displayName.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 17,
                    color: Color(0xffffc451),
                  ),
                ),
                const SizedBox(height: 4),
                _TurnCountdown(
                  deadline: room.turnDeadlineAt,
                  isMyTurn: isMyTurn,
                  // Timeout resolution is server-authoritative. The client only
                  // paints the remaining time and waits for the next snapshot.
                  onExpired: () {},
                ),
                if (isMyTurn && room.phase == 'play_phase')
                  Text(
                    'Bạn có thể dùng thẻ chức năng/trang bị; BANG bị giới hạn theo kỹ năng và súng.',
                    style: const TextStyle(color: Color(0xffffd272)),
                  ),
                const SizedBox(height: 10),
                _TurnSteps(phase: phase),
                const SizedBox(height: 8),
                _CentralActionArea(
                  repository: repository,
                  room: room,
                  playerId: playerId,
                ),
                if (room.publicLog.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: room.publicLog.reversed
                          .take(2)
                          .map(
                            (entry) => Text(
                              _publicLogLabel(room, entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _EquipmentBar(equipment: currentPlayer?.equipment ?? const []),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'BÀI TRÊN TAY',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<String>>(
                  stream: repository.watchHand(room.id),
                  builder: (context, snapshot) {
                    final cards = snapshot.data ?? const <String>[];
                    final discardRequired =
                        (activePlayer == null
                                ? 0
                                : cards.length - activePlayer.health)
                            .clamp(0, cards.length)
                            .toInt();
                    if (cards.isEmpty) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Chưa có bài hoặc đang chờ đồng bộ.'),
                      );
                    }
                    final selectedNotifier = _selectedHandCard(room.id);
                    if (selectedNotifier.value != null &&
                        !cards.contains(selectedNotifier.value)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!cards.contains(selectedNotifier.value)) {
                          selectedNotifier.value = null;
                        }
                      });
                    }
                    return ValueListenableBuilder<String?>(
                      valueListenable: selectedNotifier,
                      builder: (context, selectedCardId, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 112,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: cards.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 7),
                              itemBuilder: (context, index) {
                                final cardId = cards[index];
                                final canDiscard =
                                    isMyTurn &&
                                    phase == 'discard_phase' &&
                                    discardRequired > 0;
                                final isBang = cardId.startsWith('bang_');
                                final unlimitedBang =
                                    activePlayer?.characterId ==
                                        'willy_the_kid' ||
                                    activePlayer?.equipment.any(
                                          (card) =>
                                              card.startsWith('volcanic_'),
                                        ) ==
                                        true;
                                final bangBlocked =
                                    isBang &&
                                    room.bangUsedThisTurn >= 1 &&
                                    !unlimitedBang;
                                final enabled =
                                    (canPlay && !bangBlocked) || canDiscard;
                                final actionLabel = bangBlocked
                                    ? 'ĐÃ DÙNG BANG'
                                    : phase == 'discard_phase'
                                    ? 'BỎ'
                                    : _isEquipmentCard(cardId)
                                    ? 'ĐẶT'
                                    : 'ĐÁNH';
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    GameCardWidget(
                                      card: _publicGameCard(cardId),
                                      width: 70,
                                      isSelected: selectedCardId == cardId,
                                      isEnabled: enabled,
                                      onTap: !enabled
                                          ? null
                                          : () => selectedNotifier.value =
                                                selectedCardId == cardId
                                                ? null
                                                : cardId,
                                    ),
                                    Positioned(
                                      left: 4,
                                      right: 4,
                                      bottom: 3,
                                      child: IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: const Color(0xaa211109),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              actionLabel,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (selectedCardId == null)
                            const Text(
                              'Chạm một lá bài để chọn, sau đó xác nhận hành động.',
                              style: TextStyle(color: Colors.white70),
                            )
                          else
                            Builder(
                              builder: (context) {
                                final isBang = selectedCardId.startsWith(
                                  'bang_',
                                );
                                final unlimitedBang =
                                    activePlayer?.characterId ==
                                        'willy_the_kid' ||
                                    activePlayer?.equipment.any(
                                          (card) =>
                                              card.startsWith('volcanic_'),
                                        ) ==
                                        true;
                                final bangBlocked =
                                    isBang &&
                                    room.bangUsedThisTurn >= 1 &&
                                    !unlimitedBang;
                                final canDiscard =
                                    isMyTurn &&
                                    phase == 'discard_phase' &&
                                    discardRequired > 0;
                                final canConfirm =
                                    canDiscard || (canPlay && !bangBlocked);
                                final actionLabel = canDiscard
                                    ? 'BỎ BÀI'
                                    : _isEquipmentCard(selectedCardId)
                                    ? 'ĐẶT THẺ'
                                    : 'ĐÁNH';
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 7),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xff2b170e),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xff76502e),
                                        ),
                                      ),
                                      child: Text(
                                        '${_cardLabel(selectedCardId)} · ${_cardDescription(selectedCardId)}',
                                        style: const TextStyle(
                                          color: Color(0xffffe3a5),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () =>
                                                selectedNotifier.value = null,
                                            child: const Text('HỦY'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: FilledButton.icon(
                                            onPressed: !canConfirm
                                                ? null
                                                : () async {
                                                    final card = selectedCardId;
                                                    if (canDiscard) {
                                                      await _discardExcessCards(
                                                        context,
                                                        cards,
                                                        discardRequired,
                                                      );
                                                    } else {
                                                      await _playCard(
                                                        context,
                                                        card,
                                                        playerId,
                                                      );
                                                    }
                                                    selectedNotifier.value =
                                                        null;
                                                  },
                                            icon: Icon(
                                              canDiscard
                                                  ? Icons.delete_outline
                                                  : Icons.play_arrow_rounded,
                                            ),
                                            label: Text(actionLabel),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isBang) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        bangBlocked
                                            ? 'Mỗi lượt chỉ dùng 1 BANG, trừ khi có kỹ năng hoặc Volcanic.'
                                            : 'Bấm ĐÁNH để chọn mục tiêu trong tầm bắn.',
                                        style: const TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
                if (phase == 'dying' && room.dyingPlayerId != null)
                  StreamBuilder<List<String>>(
                    stream: repository.watchHand(room.id),
                    builder: (context, snapshot) {
                      final hand = snapshot.data ?? const <String>[];
                      final beer = hand
                          .where((card) => card.startsWith('beer_'))
                          .firstOrNull;
                      final dying = room.memberFor(room.dyingPlayerId!);
                      final isDyingPlayer = playerId == room.dyingPlayerId;
                      final requiredBeers = math.max(
                        1,
                        1 - (dying?.health ?? 0),
                      );
                      final canSelfSave =
                          hand
                              .where((card) => card.startsWith('beer_'))
                              .length >=
                          requiredBeers;
                      return Card(
                        color: const Color(0xff5a1b15),
                        child: ListTile(
                          leading: const Icon(
                            Icons.favorite,
                            color: Colors.redAccent,
                          ),
                          title: Text(
                            '${dying?.displayName ?? 'Người chơi'} đang hấp hối',
                          ),
                          subtitle: const Text(
                            'Dùng Beer để cứu họ trước khi bị loại.',
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isDyingPlayer)
                                FilledButton.tonal(
                                  onPressed: canSelfSave
                                      ? () => _callPayload(
                                          context,
                                          'resolveDying',
                                          {'useBeer': true},
                                        )
                                      : null,
                                  child: Text('TỰ CỨU ($requiredBeers BEER)'),
                                ),
                              if (isDyingPlayer) const SizedBox(height: 6),
                              if (isDyingPlayer)
                                OutlinedButton(
                                  onPressed: () => _callPayload(
                                    context,
                                    'resolveDying',
                                    {'useBeer': false},
                                  ),
                                  child: const Text('BỊ LOẠI'),
                                )
                              else
                                FilledButton(
                                  onPressed: beer == null || playerId == null
                                      ? null
                                      : () => _callPayload(
                                          context,
                                          'saveDyingPlayer',
                                          {
                                            'targetPlayerId':
                                                room.dyingPlayerId,
                                            'cardId': beer,
                                          },
                                        ),
                                  child: const Text('DÙNG BEER'),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (isMyTurn &&
                    activePlayer?.characterId == 'sid_ketchum' &&
                    activePlayer!.health < activePlayer.maxHealth)
                  StreamBuilder<List<String>>(
                    stream: repository.watchHand(room.id),
                    builder: (context, snapshot) {
                      final hand = snapshot.data ?? const <String>[];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: hand.length >= 2
                              ? () => _useSidKetchum(context, hand)
                              : null,
                          icon: const Icon(Icons.favorite_outline),
                          label: const Text('SID KETCHUM: BỎ 2 HỒI 1'),
                        ),
                      );
                    },
                  ),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: repository.watchPendingActions(room.id),
                  builder: (context, snapshot) {
                    final action = (snapshot.data ?? const []).firstOrNull;
                    if (action == null) return const SizedBox.shrink();
                    final opened = List<String>.from(
                      action['openedCardIds'] as List? ?? const [],
                    );
                    final judgmentChoices = List<String>.from(
                      action['choices'] as List? ?? const [],
                    );
                    final responsePlayerId =
                        action['currentTargetId'] as String? ??
                        action['targetPlayerId'] as String?;
                    final isMyResponse =
                        playerId != null && responsePlayerId == playerId;
                    final isMyActor =
                        playerId != null && action['actorPlayerId'] == playerId;
                    final isMyGeneralStorePicker =
                        playerId != null &&
                        action['currentPickerId'] == playerId;
                    return Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: action['actionType'] == 'bang'
                                ? _ResponseCountdown(
                                    deadline: action['responseDeadlineAt'],
                                    // Cloud Functions resolve an expired
                                    // response. Never apply combat from a
                                    // widget timer, otherwise reconnects can
                                    // resolve the same action twice.
                                    onExpired: () {},
                                  )
                                : null,
                            title: Text(
                              'Đang chờ: ${action['actionType'] ?? 'phản ứng'}',
                            ),
                            subtitle: Text(_actionSummary(room, action)),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                if (action['actionType'] == 'bang')
                                  FilledButton.tonal(
                                    onPressed: isMyResponse
                                        ? () => _callPayload(
                                            context,
                                            'acceptBangDamage',
                                            {'pendingActionId': action['id']},
                                          )
                                        : null,
                                    child: const Text('NHẬN ĐẠN'),
                                  ),
                                if (isMyResponse)
                                  OutlinedButton(
                                    onPressed: () => _callPayload(
                                      context,
                                      'resolveExpiredResponse',
                                      {'pendingActionId': action['id']},
                                    ),
                                    child: const Text('CHẤP NHẬN'),
                                  ),
                              ],
                            ),
                          ),
                          if (action['actionType'] == 'general_store' &&
                              opened.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Wrap(
                                spacing: 8,
                                children: opened
                                    .map(
                                      (cardId) => OutlinedButton(
                                        onPressed: isMyGeneralStorePicker
                                            ? () => _callPayload(
                                                context,
                                                'chooseGeneralStoreCard',
                                                {
                                                  'actionId': action['id'],
                                                  'cardId': cardId,
                                                },
                                              )
                                            : null,
                                        child: Text(
                                          cardId.split('_').first.toUpperCase(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          if (action['actionType'] == 'lucky_duke_judgment' &&
                              judgmentChoices.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Wrap(
                                spacing: 8,
                                children: judgmentChoices
                                    .map(
                                      (cardId) => FilledButton.tonal(
                                        onPressed: isMyActor
                                            ? () => _callPayload(
                                                context,
                                                'chooseLuckyDukeJudgment',
                                                {
                                                  'actionId': action['id'],
                                                  'resultCardId': cardId,
                                                },
                                              )
                                            : null,
                                        child: Text(
                                          cardId.split('_').first.toUpperCase(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          if (action['actionType'] == 'kit_carlson' &&
                              judgmentChoices.length == 3)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: FilledButton.tonal(
                                onPressed: isMyActor
                                    ? () => _chooseKitCarlson(
                                        context,
                                        action['id'] as String,
                                        judgmentChoices,
                                      )
                                    : null,
                                child: const Text('KIT CARLSON: CHỌN 2 LÁ'),
                              ),
                            ),
                          if (isMyResponse &&
                              (action['actionType'] == 'duello' ||
                                  action['actionType'] == 'gatling' ||
                                  action['actionType'] == 'indiani'))
                            StreamBuilder<List<String>>(
                              stream: repository.watchHand(room.id),
                              builder: (context, handSnapshot) {
                                final requiredType =
                                    action['actionType'] == 'gatling'
                                    ? 'dodge_'
                                    : 'bang_';
                                final usable =
                                    (handSnapshot.data ?? const <String>[])
                                        .where(
                                          (card) =>
                                              card.startsWith(requiredType),
                                        )
                                        .toList();
                                final functionName =
                                    action['actionType'] == 'duello'
                                    ? 'respondDuel'
                                    : 'respondMultiAttack';
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    12,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    children: usable
                                        .map(
                                          (cardId) => FilledButton.tonal(
                                            onPressed: () => _callPayload(
                                              context,
                                              functionName,
                                              {
                                                'actionId': action['id'],
                                                'cardId': cardId,
                                              },
                                            ),
                                            child: Text(
                                              'DÙNG ${cardId.split('_').first.toUpperCase()}',
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                );
                              },
                            ),
                          if (action['actionType'] == 'bang' && isMyResponse)
                            const Center(child: BangEffectOverlay(size: 130)),
                          if (action['actionType'] == 'gatling' ||
                              action['actionType'] == 'indiani')
                            const Center(
                              child: AreaAttackEffectOverlay(size: 150),
                            ),
                          if (action['actionType'] == 'bang' && isMyResponse)
                            StreamBuilder<List<String>>(
                              stream: repository.watchHand(room.id),
                              builder: (context, handSnapshot) {
                                final hand =
                                    handSnapshot.data ?? const <String>[];
                                final dodges = hand
                                    .where((card) => card.startsWith('dodge_'))
                                    .toList();
                                final requiresTwoDodges =
                                    (action['requiredDodges'] as num? ?? 1) ==
                                    2;
                                final bangs = hand
                                    .where((card) => card.startsWith('bang_'))
                                    .toList();
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    12,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (requiresTwoDodges)
                                        FilledButton.tonal(
                                          onPressed: dodges.length >= 2
                                              ? () => _resolveSlabDodge(
                                                  context,
                                                  action['id'] as String,
                                                  dodges,
                                                )
                                              : null,
                                          child: const Text('DÙNG 2 LÁ NÉ'),
                                        )
                                      else
                                        ...dodges.map(
                                          (cardId) => FilledButton.tonal(
                                            onPressed: () => _callPayload(
                                              context,
                                              'respondToAction',
                                              {
                                                'pendingActionId': action['id'],
                                                'responseType': 'missed',
                                                'cardId': cardId,
                                              },
                                            ),
                                            child: const Text('NÉ'),
                                          ),
                                        ),
                                      if (!requiresTwoDodges &&
                                          room
                                                  .memberFor(playerId)
                                                  ?.characterId ==
                                              'calamity_janet')
                                        ...bangs.map(
                                          (cardId) => OutlinedButton(
                                            onPressed: () => _callPayload(
                                              context,
                                              'useCalamityJanetDodge',
                                              {
                                                'pendingActionId': action['id'],
                                                'cardId': cardId,
                                              },
                                            ),
                                            child: const Text('BANG → NÉ'),
                                          ),
                                        ),
                                      if (!requiresTwoDodges &&
                                          (room
                                                      .memberFor(playerId)
                                                      ?.characterId ==
                                                  'jourdonnais' ||
                                              room
                                                  .memberFor(playerId)!
                                                  .equipment
                                                  .any(
                                                    (card) => card.startsWith(
                                                      'barrel_',
                                                    ),
                                                  )))
                                        OutlinedButton(
                                          onPressed: () => _callPayload(
                                            context,
                                            'resolveJourdonnais',
                                            {'pendingActionId': action['id']},
                                          ),
                                          child: const Text('PHÁN XÉT NÉ'),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (canDraw)
                  FilledButton(
                    onPressed: () =>
                        _drawTurn(context, playerId, activePlayer?.characterId),
                    child: const Text('RÚT 2 LÁ'),
                  ),
                if (canPlay)
                  FilledButton.tonal(
                    onPressed: () => _call(context, 'requestEndTurn'),
                    child: const Text('KẾT THÚC LƯỢT'),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String? _latestPublicCardId(OnlineRoom room) {
  if (room.publicLog.isNotEmpty) {
    final parts = room.publicLog.last.split(':');
    if (parts.length > 2 && parts[2].isNotEmpty) return parts[2];
  }
  return room.discardTopCardId;
}

/// The centre of the table is deliberately separate from the hand and the
/// equipment row.  It is the public, transient area: everybody can see the
/// action card, who played it, who must respond, the draw pile and discard.
class _CentralActionArea extends StatelessWidget {
  const _CentralActionArea({
    required this.repository,
    required this.room,
    required this.playerId,
  });

  final OnlineRoomRepository repository;
  final OnlineRoom room;
  final String? playerId;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: repository.watchPendingActions(room.id),
    builder: (context, snapshot) {
      final action =
          (snapshot.data ?? const <Map<String, dynamic>>[]).firstOrNull;
      final actionCardId =
          action?['cardId'] as String? ?? _latestPublicCardId(room);
      final actionType = action?['actionType'] as String?;
      final actor = room.memberFor(action?['actorPlayerId'] as String? ?? '');
      final target = room.memberFor(
        action?['currentTargetId'] as String? ??
            action?['targetPlayerId'] as String? ??
            '',
      );
      final summary = action == null
          ? (room.publicLog.isEmpty
                ? 'Chờ hành động đầu tiên của trận đấu.'
                : _publicLogLabel(room, room.publicLog.last))
          : target == null
          ? '${actor?.displayName ?? 'Người chơi'} đang dùng ${_actionLabel(actionType)}.'
          : '${actor?.displayName ?? 'Người chơi'} dùng ${_actionLabel(actionType)} vào ${target.displayName}.';

      return Column(
        children: [
          _PlayerTable(
            members: room.members,
            currentTurnPlayerId: room.currentTurnPlayerId,
            latestPublicLog: room.publicLog.isEmpty
                ? null
                : room.publicLog.last,
            turnDeadlineAt: room.turnDeadlineAt,
            pendingAction: action,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PileMarker(
                icon: Icons.layers_outlined,
                label: 'BỘ RÚT',
                detail: 'Úp',
              ),
              const SizedBox(width: 12),
              if (actionCardId != null)
                _PublicCardStage(cardId: actionCardId, summary: summary)
              else
                _EmptyActionStage(summary: summary),
              const SizedBox(width: 12),
              _PileMarker(
                icon: Icons.delete_sweep_outlined,
                label: 'BÀI BỎ',
                detail: room.discardTopCardId == null
                    ? 'Trống'
                    : _cardLabel(room.discardTopCardId!),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 5),
            _PublicResponseLine(
              action: action,
              actorName: actor?.displayName,
              targetName: target?.displayName,
            ),
          ],
        ],
      );
    },
  );
}

class _PileMarker extends StatelessWidget {
  const _PileMarker({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 62,
    child: Column(
      children: [
        Container(
          width: 42,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xff311b10),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xff9a6a35)),
          ),
          child: Icon(icon, color: const Color(0xffffd272), size: 22),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
        ),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 7, color: Colors.white60),
        ),
      ],
    ),
  );
}

class _EmptyActionStage extends StatelessWidget {
  const _EmptyActionStage({required this.summary});
  final String summary;

  @override
  Widget build(BuildContext context) => Container(
    width: 255,
    height: 80,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xff2b170e),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff6e492a)),
    ),
    child: Text(
      summary,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white70, fontSize: 11),
    ),
  );
}

class _PublicResponseLine extends StatelessWidget {
  const _PublicResponseLine({
    required this.action,
    required this.actorName,
    required this.targetName,
  });

  final Map<String, dynamic> action;
  final String? actorName;
  final String? targetName;

  @override
  Widget build(BuildContext context) {
    final type = action['actionType'] as String? ?? 'action';
    final waitingFor = targetName ?? 'người chơi';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xff4c1d16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withValues(alpha: .65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 15, color: Colors.redAccent),
          const SizedBox(width: 5),
          Text(
            type == 'bang'
                ? 'Đang chờ $waitingFor phản ứng · 8 giây'
                : '${actorName ?? 'Người chơi'} đang xử lý ${_actionLabel(type)}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EquipmentBar extends StatelessWidget {
  const _EquipmentBar({required this.equipment});
  final List<String> equipment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'TRANG BỊ / THẺ ĐÃ ĐẶT',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xffffd272),
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 54,
        child: equipment.isEmpty
            ? const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Chưa có trang bị được đặt.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: equipment.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final cardId = equipment[index];
                  return Tooltip(
                    message: _cardLabel(cardId),
                    child: GameCardWidget(
                      card: _publicGameCard(cardId),
                      width: 38,
                      isEnabled: false,
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

String _actionLabel(String? actionType) => switch (actionType) {
  'bang' => 'BANG!',
  'gatling' => 'GATLING',
  'indiani' => 'INDIANS',
  'duello' => 'ĐẤU SÚNG',
  'general_store' => 'CỬA HÀNG',
  'judgment' => 'PHÁN XÉT',
  _ => 'HÀNH ĐỘNG',
};

class _PlayerTable extends StatelessWidget {
  const _PlayerTable({
    required this.members,
    required this.currentTurnPlayerId,
    required this.latestPublicLog,
    required this.turnDeadlineAt,
    this.pendingAction,
  });

  final List<RoomMember> members;
  final String? currentTurnPlayerId;
  final String? latestPublicLog;
  final DateTime? turnDeadlineAt;
  final Map<String, dynamic>? pendingAction;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 186,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final seatWidth = (constraints.maxWidth / 4.25).clamp(92.0, 138.0);
        final seatHeight = 60.0;
        final centerX = constraints.maxWidth / 2;
        final centerY = 93.0;
        final radiusX = math.max(
          0.0,
          constraints.maxWidth / 2 - seatWidth / 2 - 5,
        );
        const radiusY = 58.0;
        final bang = _bangEvent(latestPublicLog);
        final pendingBang = pendingAction?['actionType'] == 'bang';
        final pendingActorId = pendingAction == null
            ? null
            : pendingAction!['actorPlayerId'] as String?;
        final pendingTargetId = pendingAction == null
            ? null
            : pendingAction!['currentTargetId'] as String?;
        final pendingActionId = pendingAction == null
            ? null
            : pendingAction!['id'] as String?;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: constraints.maxWidth * .18,
              right: constraints.maxWidth * .18,
              top: 42,
              bottom: 32,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff3a1e10),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xff85552d), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0xaa080402), blurRadius: 12),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'BÀN ĐẤU',
                    style: TextStyle(
                      color: Color(0xffffd272),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            for (var index = 0; index < members.length; index++)
              () {
                final angle =
                    -math.pi / 2 + (2 * math.pi * index / members.length);
                final x = centerX + math.cos(angle) * radiusX - seatWidth / 2;
                final y = centerY + math.sin(angle) * radiusY - seatHeight / 2;
                final member = members[index];
                return Positioned(
                  left: x.clamp(0.0, constraints.maxWidth - seatWidth),
                  top: y.clamp(0.0, 186 - seatHeight),
                  width: seatWidth,
                  height: seatHeight,
                  child: _PlayerSeat(
                    member: member,
                    isCurrent: member.id == currentTurnPlayerId,
                    isBangShooter: pendingBang
                        ? member.id == pendingActorId
                        : member.id == bang?.shooterId,
                    isBangTarget: pendingBang
                        ? member.id == pendingTargetId
                        : member.id == bang?.targetId,
                    bangEventId: pendingBang ? pendingActionId : bang?.id,
                    turnDeadlineAt: turnDeadlineAt,
                  ),
                );
              }(),
          ],
        );
      },
    ),
  );
}

class _PlayerSeat extends StatefulWidget {
  const _PlayerSeat({
    required this.member,
    required this.isCurrent,
    required this.isBangShooter,
    required this.isBangTarget,
    required this.turnDeadlineAt,
    this.bangEventId,
  });

  final RoomMember member;
  final bool isCurrent;
  final bool isBangShooter;
  final bool isBangTarget;
  final DateTime? turnDeadlineAt;
  final String? bangEventId;

  @override
  State<_PlayerSeat> createState() => _PlayerSeatState();
}

class _PlayerSeatState extends State<_PlayerSeat> {
  Timer? _pulse;
  Timer? _deathEffectTimer;
  Timer? _bangEffectTimer;
  bool _bright = true;
  bool _showDeathEffect = false;
  bool _showBangEffect = false;

  @override
  void initState() {
    super.initState();
    _pulse = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted && widget.isCurrent) setState(() => _bright = !_bright);
    });
  }

  @override
  void didUpdateWidget(covariant _PlayerSeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isCurrent) _bright = true;
    if (oldWidget.member.isAlive && !widget.member.isAlive) {
      GameAudio.instance.playSfx('lose');
      _showDeathEffect = true;
      _deathEffectTimer?.cancel();
      _deathEffectTimer = Timer(const Duration(milliseconds: 1250), () {
        if (mounted) setState(() => _showDeathEffect = false);
      });
    }
    if (widget.isBangTarget && oldWidget.bangEventId != widget.bangEventId) {
      _showBangEffect = true;
      _bangEffectTimer?.cancel();
      _bangEffectTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _showBangEffect = false);
      });
    }
  }

  @override
  void dispose() {
    _pulse?.cancel();
    _deathEffectTimer?.cancel();
    _bangEffectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final active = widget.isCurrent;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: member.isAlive
                ? active
                      ? Color.lerp(
                          const Color(0xff5a3116),
                          const Color(0xff8a521d),
                          _bright ? 1 : .25,
                        )
                      : const Color(0xff2a1811)
                : const Color(0xff16100d),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0xffffc451) : const Color(0xff63432e),
              width: active ? 2 : 1,
            ),
            boxShadow: active && _bright
                ? const [BoxShadow(color: Color(0x99ffb12e), blurRadius: 10)]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                member.isBot ? Icons.smart_toy : Icons.person,
                size: 18,
                color: member.isAlive
                    ? const Color(0xffffd272)
                    : Colors.white38,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      active ? 'ĐANG TỚI LƯỢT' : member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: active ? 9 : 10,
                        fontWeight: FontWeight.w800,
                        color: member.isAlive ? Colors.white : Colors.white38,
                      ),
                    ),
                    Text(
                      member.isAlive
                          ? '${member.health}/${member.maxHealth} máu · ${member.cardCount} bài'
                          : 'ĐÃ BỊ LOẠI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.white70,
                      ),
                    ),
                    if (active)
                      Text(
                        _seatCountdown(widget.turnDeadlineAt),
                        style: const TextStyle(
                          color: Color(0xffffd272),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (member.equipment.isNotEmpty)
                      Text(
                        member.equipment.take(2).map(_cardLabel).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xffffd272),
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_showDeathEffect)
          const Positioned.fill(
            child: IgnorePointer(child: DeathEffectOverlay()),
          ),
        if (widget.isBangShooter)
          const Positioned(
            right: -14,
            top: -24,
            child: IgnorePointer(child: BangEffectOverlay(size: 62)),
          ),
        if (_showBangEffect)
          const Positioned.fill(
            child: IgnorePointer(child: BangEffectOverlay(size: 82)),
          ),
      ],
    );
  }
}

class _BangEvent {
  const _BangEvent({
    required this.id,
    required this.shooterId,
    required this.targetId,
  });

  final String id;
  final String shooterId;
  final String targetId;
}

_BangEvent? _bangEvent(String? log) {
  if (log == null) return null;
  final parts = log.split(':');
  if (parts.length >= 4 && parts[0] == 'play' && parts[2].startsWith('bang_')) {
    return _BangEvent(id: log, shooterId: parts[1], targetId: parts[3]);
  }
  if (parts.length >= 4 && parts[0] == 'damage' && parts[2] == 'bang') {
    return _BangEvent(id: log, shooterId: parts[3], targetId: parts[1]);
  }
  return null;
}

class _PublicCardStage extends StatelessWidget {
  const _PublicCardStage({required this.cardId, required this.summary});

  final String cardId;
  final String summary;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 350),
    transitionBuilder: (child, animation) => ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: Container(
      key: ValueKey(cardId),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xff2b170e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffffc451), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x883c1707), blurRadius: 12)],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GameCardWidget(card: _publicGameCard(cardId), width: 72),
              const SizedBox(width: 10),
              SizedBox(
                width: 180,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LÁ VỪA ĐÁNH',
                      style: TextStyle(
                        color: Color(0xffffd272),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _cardLabel(cardId),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cardId.startsWith('bang_'))
            const Positioned(
              left: 22,
              top: -18,
              child: IgnorePointer(child: BangEffectOverlay(size: 70)),
            ),
          if (cardId.startsWith('dodge_'))
            const Positioned(
              left: 18,
              top: -10,
              child: IgnorePointer(child: DodgeEffectOverlay(size: 76)),
            ),
          if (cardId.startsWith('beer_') || cardId.startsWith('saloon_'))
            const Positioned(
              left: 2,
              top: -16,
              child: IgnorePointer(child: HealEffectOverlay(size: 82)),
            ),
        ],
      ),
    ),
  );
}

GameCard _publicGameCard(String cardId) {
  final parts = cardId.split('_');
  final rankIndex = parts.indexWhere(
    (part) => CardRank.values.any((rank) => rank.name == part),
  );
  final rank = rankIndex < 0
      ? CardRank.ace
      : CardRank.values.firstWhere((value) => value.name == parts[rankIndex]);
  final suit = CardSuit.values.firstWhere(
    (value) => value.name == parts.last,
    orElse: () => CardSuit.spade,
  );
  final type = rankIndex < 0 ? parts.first : parts.take(rankIndex).join('_');
  const assets = <String, String>{
    'bang': 'bang.png',
    'dodge': 'ne.png',
    'beer': 'beer.png',
    'gatling': 'gatling.png',
    'indiani': 'indiani.png',
    'panico': 'panico.png',
    'cat_balou': 'cat_balou.png',
    'dilizenza': 'dilizenza.png',
    'wells_fargo': 'wells_fargo.png',
    'general_store': 'general_store.png',
    'duello': 'duello.png',
    'saloon': 'saloon.png',
    'barrel': 'barrel.png',
    'jail': 'jail.png',
    'dynamite': 'dynamite.png',
    'volcanic': 'volcanic.png',
    'mustang': 'mustang.png',
    'appaloosa': 'appaloosa.png',
    'gun_range_2': 'gun_range_2.png',
    'gun_range_3': 'gun_range_3.png',
    'gun_range_4': 'gun_range_4.png',
    'gun_range_5': 'gun_range_5.png',
  };
  return GameCard(
    CardType.bang,
    id: cardId,
    rank: rank,
    suit: suit,
    imageAsset: 'assets/images/cards/${assets[type] ?? 'bang.png'}',
  );
}

String _phaseLabel(String phase) => switch (phase) {
  'turn_start' => 'BẮT ĐẦU LƯỢT · RÚT 2 LÁ',
  'play_phase' => 'ĐÁNH BÀI HOẶC KẾT THÚC LƯỢT',
  'discard_phase' => 'BỎ BÀI DƯ',
  'waiting_response' => 'ĐANG CHỜ PHẢN ỨNG',
  'waiting_multi_response' => 'ĐANG CHỜ MỌI NGƯỜI PHẢN ỨNG',
  'waiting_duel_response' => 'ĐANG ĐẤU SÚNG',
  _ => 'ĐANG XỬ LÝ: ${phase.toUpperCase()}',
};

String _cardLabel(String cardId) => cardId
    .split('_')
    .takeWhile((part) => part != 'ace' && part != 'two' && part != 'three')
    .join(' ')
    .replaceAll('DILIZENZA', 'DILIGENZA')
    .toUpperCase();

String _cardDescription(String cardId) {
  if (cardId.startsWith('bang_')) {
    return 'Bắn một mục tiêu trong tầm.';
  }
  if (cardId.startsWith('dodge_')) {
    return 'Né một đòn BANG! đang nhắm vào bạn.';
  }
  if (cardId.startsWith('beer_')) {
    return 'Hồi 1 máu, không vượt máu tối đa.';
  }
  if (cardId.startsWith('gatling_')) {
    return 'Mọi đối thủ phải dùng NÉ hoặc mất máu.';
  }
  if (cardId.startsWith('indiani_')) {
    return 'Mọi đối thủ dùng BANG hoặc mất máu.';
  }
  if (cardId.startsWith('duello_')) {
    return 'Chọn đối thủ để luân phiên dùng BANG.';
  }
  if (cardId.startsWith('jail_')) {
    return 'Nhốt một người chơi không phải Cảnh sát trưởng.';
  }
  if (cardId.startsWith('dynamite_')) {
    return 'Đặt trước mặt bạn, phán xét ở đầu lượt.';
  }
  if (cardId.startsWith('barrel_')) {
    return 'Phán xét Cơ để tự động né BANG.';
  }
  if (cardId.startsWith('mustang_')) {
    return 'Người khác tính xa bạn thêm 1.';
  }
  if (cardId.startsWith('appaloosa_')) {
    return 'Bạn tính gần mọi mục tiêu hơn 1.';
  }
  if (cardId.startsWith('panico_')) {
    return 'Lấy ngẫu nhiên bài tay hoặc trang bị.';
  }
  if (cardId.startsWith('cat_balou_')) {
    return 'Hủy bài tay hoặc trang bị của mục tiêu.';
  }
  if (cardId.startsWith('dilizenza_')) {
    return 'Rút thêm 2 lá.';
  }
  if (cardId.startsWith('wells_fargo_')) {
    return 'Rút thêm 3 lá.';
  }
  if (cardId.startsWith('general_store_')) {
    return 'Mỗi người lần lượt chọn một lá.';
  }
  if (cardId.startsWith('saloon_')) {
    return 'Hồi 1 máu cho mọi người còn sống.';
  }
  if (_isEquipmentCard(cardId)) {
    return 'Đặt công khai vào thanh trang bị.';
  }
  return 'Dùng theo hiệu ứng của lá bài.';
}

bool _isEquipmentCard(String cardId) => [
  'gun_range_',
  'volcanic_',
  'mustang_',
  'appaloosa_',
  'barrel_',
  'dynamite_',
  'jail_',
].any(cardId.startsWith);

String _actionSummary(OnlineRoom room, Map<String, dynamic> action) {
  final actor = room.memberFor(action['actorPlayerId'] as String? ?? '');
  final target = room.memberFor(
    action['currentTargetId'] as String? ??
        action['targetPlayerId'] as String? ??
        '',
  );
  final actorName = actor?.displayName ?? 'Một người chơi';
  final targetName = target?.displayName;
  return targetName == null
      ? '$actorName đang xử lý hành động.'
      : '$actorName nhắm tới $targetName.';
}

String _publicLogLabel(OnlineRoom room, String entry) {
  // Durable Objects already write a complete Vietnamese sentence. Older
  // Firebase events used colon-delimited records, which are kept below for
  // backward compatibility only.
  if (!entry.contains(':')) return entry;
  final parts = entry.split(':');
  final actor = room.memberFor(parts.length > 1 ? parts[1] : '');
  final actorName = actor?.displayName ?? 'Một người chơi';

  if (parts.first == 'draw') {
    return '$actorName đã rút bài.';
  }
  if (parts.first == 'bot') {
    return '$actorName đã hoàn tất lượt.';
  }
  if (parts.first == 'dodge') {
    final attacker = room.memberFor(parts.length > 3 ? parts[3] : '');
    return attacker == null
        ? '$actorName đã dùng NÉ.'
        : '$actorName dùng NÉ, tránh được BANG của ${attacker.displayName}.';
  }
  if (parts.first == 'damage') {
    final attacker = room.memberFor(parts.length > 3 ? parts[3] : '');
    return attacker == null
        ? '$actorName mất 1 máu.'
        : '$actorName mất 1 máu vì BANG của ${attacker.displayName}.';
  }
  if (parts.first == 'save') {
    final target = room.memberFor(parts.length > 3 ? parts[3] : '');
    return target == null
        ? '$actorName đã dùng BEER để cứu người chơi.'
        : '$actorName dùng BEER cứu ${target.displayName}.';
  }
  if (parts.first == 'judgment') {
    final context = parts.length > 3 ? parts[3] : '';
    final result = parts.length > 4 ? parts[4] : '';
    final card = parts.length > 2 ? _cardLabel(parts[2]) : 'một lá bài';
    if (context == 'dynamite') {
      return result == 'explode'
          ? '$actorName phán xét $card: DYNAMITE phát nổ, mất 3 máu.'
          : '$actorName phán xét $card: DYNAMITE không nổ và chuyển đi.';
    }
    if (context == 'jail') {
      return result == 'skip'
          ? '$actorName phán xét $card: bị JAIL, mất lượt.'
          : '$actorName phán xét $card: thoát JAIL, chơi lượt bình thường.';
    }
  }

  final card = parts.length > 2 ? _cardLabel(parts[2]) : 'một lá bài';
  if (parts.first == 'equip') {
    return '$actorName đã đặt $card.';
  }

  final target = room.memberFor(parts.length > 3 ? parts[3] : '');
  return target == null
      ? '$actorName đã dùng $card.'
      : '$actorName dùng $card vào ${target.displayName}.';
}

String _seatCountdown(DateTime? deadline) {
  if (deadline == null) return 'ĐANG ĐỒNG BỘ...';
  final seconds = deadline.difference(DateTime.now()).inSeconds.clamp(0, 99);
  return '⏱ ${seconds}s';
}

int _distanceBetween(OnlineRoom room, String actorId, String targetId) {
  final alive = room.members.where((member) => member.isAlive).toList()
    ..sort((a, b) => a.seat.compareTo(b.seat));
  final actorIndex = alive.indexWhere((member) => member.id == actorId);
  final targetIndex = alive.indexWhere((member) => member.id == targetId);
  if (actorIndex < 0 || targetIndex < 0 || alive.length < 2) return 999;

  final actor = alive[actorIndex];
  final target = alive[targetIndex];
  final base = (targetIndex - actorIndex).abs();
  final baseDistance = base < alive.length - base ? base : alive.length - base;
  final actorHasAppaloosa = actor.equipment.any(
    (cardId) => cardId.startsWith('appaloosa_'),
  );
  final targetHasMustang = target.equipment.any(
    (cardId) => cardId.startsWith('mustang_'),
  );
  return (baseDistance +
          (actor.characterId == 'rose_doolan' ? -1 : 0) +
          (target.characterId == 'paul_regret' ? 1 : 0) +
          (actorHasAppaloosa ? -1 : 0) +
          (targetHasMustang ? 1 : 0))
      .clamp(1, 99)
      .toInt();
}

String? _targetBlockedReason({
  required OnlineRoom room,
  required String cardId,
  required RoomMember? actor,
  required RoomMember target,
  required int distance,
}) {
  if (cardId.startsWith('bang_') && distance > (actor?.attackRange ?? 1)) {
    return 'Ngoài tầm súng ${actor?.attackRange ?? 1}';
  }
  if (cardId.startsWith('jail_') && target.id == room.sheriffPlayerId) {
    return 'Không thể nhốt Cảnh sát trưởng';
  }
  if (cardId.startsWith('panico_')) {
    if (distance > 1) return 'Cướp bài chỉ dùng ở khoảng cách 1';
    if (target.cardCount == 0 && target.equipment.isEmpty) {
      return 'Mục tiêu không có bài hoặc trang bị';
    }
  }
  if (cardId.startsWith('cat_balou_') &&
      target.cardCount == 0 &&
      target.equipment.isEmpty) {
    return 'Mục tiêu không có bài hoặc trang bị';
  }
  return null;
}

class _TurnCountdown extends StatefulWidget {
  const _TurnCountdown({
    required this.deadline,
    required this.isMyTurn,
    required this.onExpired,
  });

  final DateTime? deadline;
  final bool isMyTurn;
  final VoidCallback onExpired;

  @override
  State<_TurnCountdown> createState() => _TurnCountdownState();
}

class _TurnSteps extends StatelessWidget {
  const _TurnSteps({required this.phase});

  final String phase;

  @override
  Widget build(BuildContext context) {
    final step = phase == 'turn_start'
        ? 0
        : phase == 'play_phase'
        ? 1
        : 2;
    const labels = ['1. RÚT BÀI', '2. ĐÁNH BÀI', '3. KẾT THÚC'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0)
            Container(width: 20, height: 1, color: const Color(0xff8b6339)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: index == step
                  ? const Color(0xffffc451)
                  : const Color(0xff392016),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              labels[index],
              style: TextStyle(
                color: index == step ? const Color(0xff2b160b) : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TurnCountdownState extends State<_TurnCountdown> {
  late final Timer _timer;
  bool _expiredSent = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _TurnCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) _expiredSent = false;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.deadline
        ?.difference(DateTime.now())
        .inSeconds
        .clamp(0, 60);
    final color = seconds == null || seconds > 20
        ? Colors.white
        : seconds > 10
        ? const Color(0xffffc451)
        : Colors.redAccent;
    final text = seconds == null
        ? 'Đang đồng bộ lượt...'
        : 'Còn $seconds giây${widget.isMyTurn ? ' · Hành động của bạn' : ''}';
    if (seconds == 0 && !_expiredSent) {
      _expiredSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onExpired());
    }
    return Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
  }
}

class _ResponseCountdown extends StatefulWidget {
  const _ResponseCountdown({required this.deadline, required this.onExpired});
  final dynamic deadline;
  final VoidCallback onExpired;

  @override
  State<_ResponseCountdown> createState() => _ResponseCountdownState();
}

class _ResponseCountdownState extends State<_ResponseCountdown> {
  late final Timer _timer;
  int _seconds = 0;
  bool _expiredSent = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _ResponseCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) {
      _expiredSent = false;
      _tick();
    }
  }

  void _tick() {
    final value = widget.deadline;
    final date = switch (value) {
      DateTime value => value,
      num value => DateTime.fromMillisecondsSinceEpoch(value.toInt()),
      _ => value == null ? null : value.toDate() as DateTime,
    };
    final seconds = date == null
        ? 0
        : (date.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(
            0,
            10,
          );
    if (mounted) setState(() => _seconds = seconds);
    if (seconds == 0 && !_expiredSent) {
      _expiredSent = true;
      widget.onExpired();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('Phản ứng: $_seconds giây');
}
