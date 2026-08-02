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
                  Navigator.pop(dialogContext);
                },
                child: const Text('BỎ QUA'),
              ),
              FilledButton(
                onPressed: () {
                  if (step == steps.length - 1) {
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
        '• Người bị BANG có 10 giây để dùng NÉ hoặc kỹ năng né.',
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
    String playerId, [
    String? preselectedTargetId,
    bool skipConfirmation = false,
  ]) async {
    String? targetPlayerId = preselectedTargetId;
    final needsTarget =
        cardId.startsWith('bang_') ||
        (cardId.startsWith('dodge_') &&
            room.memberFor(playerId)?.characterId == 'calamity_janet') ||
        cardId.startsWith('jail_') ||
        cardId.startsWith('panico_') ||
        cardId.startsWith('cat_balou_') ||
        cardId.startsWith('duello_');
    if (needsTarget && targetPlayerId == null) {
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
        if (skipConfirmation) {
          equipmentCardId = target.cardCount == 0
              ? target.equipment.first
              : null;
        } else {
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
    }
    if (!context.mounted) return;
    final isEquipment = _isEquipmentCard(cardId);
    final actionLabel = isEquipment ? 'ĐẶT BÀI' : 'ĐÁNH';
    final confirmed = preselectedTargetId != null || skipConfirmation
        ? true
        : await showDialog<bool>(
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

  // ignore: unused_element
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
    String? characterId, [
    String? jesseTargetId,
  ]) async {
    var action = 'drawTurnCards';
    String? targetPlayerId = jesseTargetId;
    if (characterId == 'kit_carlson') {
      action = 'openKitCarlson';
    } else if (characterId == 'black_jack' || characterId == 'pedro_ramirez') {
      action = 'drawCharacterTurnCards';
    } else if (characterId == 'jesse_jones') {
      action = 'drawJesseJones';
    }
    if (!context.mounted) return;
    await _callPayload(context, action, {
      'actionId': 'draw_${DateTime.now().microsecondsSinceEpoch}',
      if (targetPlayerId?.isNotEmpty == true) 'targetPlayerId': targetPlayerId,
    });
  }

  // ignore: unused_element
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

  // ignore: unused_element
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

  // ignore: unused_element
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

  Widget _pendingActionDock(
    BuildContext context,
    String? playerId,
  ) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: repository.watchPendingActions(room.id),
    builder: (context, snapshot) {
      final action = (snapshot.data ?? const []).firstOrNull;
      if (action == null) return const SizedBox.shrink();
      final opened = List<String>.from(
        action['openedCardIds'] as List? ?? const [],
      );
      final choices = List<String>.from(action['choices'] as List? ?? const []);
      final responsePlayerId =
          action['currentTargetId'] as String? ??
          action['targetPlayerId'] as String?;
      final isMyResponse = playerId != null && responsePlayerId == playerId;
      final isMyActor = playerId != null && action['actorPlayerId'] == playerId;
      final isMyPicker =
          playerId != null && action['currentPickerId'] == playerId;
      final type = action['actionType'] as String? ?? 'action';

      return Container(
        width: double.infinity,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xdd24140d),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xff9a6a35)),
        ),
        child: StreamBuilder<List<String>>(
          stream: repository.watchHand(room.id),
          builder: (context, handSnapshot) {
            final hand = handSnapshot.data ?? const <String>[];
            final dodges = hand
                .where((card) => card.startsWith('dodge_'))
                .toList();
            final bangs = hand
                .where((card) => card.startsWith('bang_'))
                .toList();
            final requiredDodges = (action['requiredDodges'] as num? ?? 1)
                .toInt();
            final buttons = <Widget>[
              if (type == 'bang' && isMyResponse)
                FilledButton.tonal(
                  onPressed: () => _callPayload(context, 'acceptBangDamage', {
                    'pendingActionId': action['id'],
                  }),
                  child: const Text('NHAN DAN'),
                ),
              if (type == 'bang' && isMyResponse && requiredDodges == 2)
                FilledButton(
                  onPressed: dodges.length >= 2
                      ? () => _callPayload(context, 'resolveSlabDodge', {
                          'pendingActionId': action['id'],
                          'cardIds': dodges.take(2).toList(),
                        })
                      : null,
                  child: const Text('DUNG 2 NE'),
                ),
              if (type == 'bang' && isMyResponse && requiredDodges < 2)
                ...dodges.map(
                  (cardId) => FilledButton(
                    onPressed: () => _callPayload(context, 'respondToAction', {
                      'pendingActionId': action['id'],
                      'responseType': 'missed',
                      'cardId': cardId,
                    }),
                    child: const Text('NE'),
                  ),
                ),
              if (type == 'bang' &&
                  isMyResponse &&
                  room.memberFor(playerId)?.characterId == 'calamity_janet')
                ...bangs.map(
                  (cardId) => OutlinedButton(
                    onPressed: () => _callPayload(
                      context,
                      'useCalamityJanetDodge',
                      {'pendingActionId': action['id'], 'cardId': cardId},
                    ),
                    child: const Text('BANG->NE'),
                  ),
                ),
              if (isMyResponse &&
                  (type == 'gatling' || type == 'indiani' || type == 'duello'))
                ...hand
                    .where(
                      (card) => card.startsWith(
                        type == 'gatling' ? 'dodge_' : 'bang_',
                      ),
                    )
                    .map(
                      (cardId) => FilledButton(
                        onPressed: () => _callPayload(
                          context,
                          type == 'duello'
                              ? 'respondDuel'
                              : 'respondMultiAttack',
                          {'actionId': action['id'], 'cardId': cardId},
                        ),
                        child: Text(type == 'gatling' ? 'NE' : 'BANG'),
                      ),
                    ),
              if (type == 'general_store' && opened.isNotEmpty)
                ...opened.map(
                  (cardId) => OutlinedButton(
                    onPressed: isMyPicker
                        ? () => _callPayload(
                            context,
                            'chooseGeneralStoreCard',
                            {'actionId': action['id'], 'cardId': cardId},
                          )
                        : null,
                    child: Text(cardId.split('_').first.toUpperCase()),
                  ),
                ),
              if (type == 'lucky_duke_judgment' && choices.isNotEmpty)
                ...choices.map(
                  (cardId) => FilledButton.tonal(
                    onPressed: isMyActor
                        ? () => _callPayload(
                            context,
                            'chooseLuckyDukeJudgment',
                            {'actionId': action['id'], 'resultCardId': cardId},
                          )
                        : null,
                    child: Text(cardId.split('_').first.toUpperCase()),
                  ),
                ),
              if (type == 'kit_carlson' && choices.length == 3)
                ...choices.map(
                  (returnedCard) => OutlinedButton(
                    onPressed: isMyActor
                        ? () => _callPayload(context, 'chooseKitCarlson', {
                            'actionId': action['id'],
                            'cardIds': choices
                                .where((card) => card != returnedCard)
                                .toList(),
                          })
                        : null,
                    child: Text('TRA ${_cardLabel(returnedCard)}'),
                  ),
                ),
            ];
            return Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _actionLabel(type),
                  style: const TextStyle(
                    color: Color(0xffffd272),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (isMyResponse)
                  _ResponseCountdown(
                    deadline: action['responseDeadlineAt'],
                    onExpired: () {},
                  ),
                ...buttons,
              ],
            );
          },
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final playerId =
        room.members
            .where((member) => member.isHost)
            .map((member) => member.id)
            .firstOrNull ??
        room.hostUid;
    final activePlayer = room.memberFor(room.currentTurnPlayerId ?? '');
    final isMyTurn = playerId == room.currentTurnPlayerId;
    final canDraw = isMyTurn && room.phase == 'turn_start';
    final canPlay = isMyTurn && room.phase == 'play_phase';
    return _RoundBattleTable(
      repository: repository,
      room: room,
      playerId: playerId,
      activePlayer: activePlayer,
      canDraw: canDraw,
      canPlay: canPlay,
      onDraw: () => _drawTurn(context, playerId, activePlayer?.characterId),
      onEndTurn: canPlay ? () => _call(context, 'requestEndTurn') : null,
      onPlay: !canPlay
          ? null
          : (cardId) => _playCard(context, cardId, playerId, null, true),
      onTargetedPlay: !canPlay
          ? null
          : (cardId, targetId) =>
                _playCard(context, cardId, playerId, targetId),
      onJesseDraw: canDraw && activePlayer?.characterId == 'jesse_jones'
          ? (targetId) => _drawTurn(
              context,
              playerId,
              activePlayer?.characterId,
              targetId,
            )
          : null,
      pendingDock: _pendingActionDock(context, playerId),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyTable(BuildContext context) {
    // The waiting room has already authenticated and marks the local
    // member as host in every authoritative room snapshot.  Building the
    // table from that snapshot avoids a second async gate that can leave an
    // otherwise valid match as a blank brown page on device.
    final playerId =
        room.members
            .where((member) => member.isHost)
            .map((member) => member.id)
            .firstOrNull ??
        room.hostUid;
    final activePlayer = room.memberFor(room.currentTurnPlayerId ?? '');
    final currentPlayer = room.memberFor(playerId);
    final isMyTurn = playerId == room.currentTurnPlayerId;
    final canPlay = isMyTurn && room.phase == 'play_phase';
    final phase = room.phase;
    // The authoritative Worker resolves Dynamite/Jail during the draw
    // command. Do not keep the old Firebase-only gate here, otherwise the
    // player can be stuck at TURN_START forever.
    final canDraw = isMyTurn && phase == 'turn_start';
    return Scaffold(
      backgroundColor: const Color(0xff160c08),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/wild_west_town.png'),
                  fit: BoxFit.cover,
                  opacity: .92,
                ),
              ),
            ),
          ),
          const Positioned.fill(child: ColoredBox(color: Color(0x42160c08))),
          Positioned(
            left: 4,
            top: 4,
            child: _TinyTableButton(
              icon: Icons.pause,
              onPressed: () => _showFirstTimeTutorial(context),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (room.publicLog.isNotEmpty)
                  _TinyTableButton(
                    icon: Icons.history,
                    onPressed: () => _showActionLog(context),
                  ),
                if (room.settings.chatEnabled && GameVoiceChat.isAvailable)
                  _TinyTableButton(
                    icon: Icons.forum_outlined,
                    onPressed: () => _showChat(context),
                  ),
                _TinyTableButton(
                  icon: Icons.help_outline,
                  onPressed: () => _showGuide(context, phase, isMyTurn),
                ),
                if (room.settings.voiceEnabled && GameVoiceChat.isAvailable)
                  _TinyTableButton(
                    icon: Icons.mic_none,
                    onPressed: () => _showVoice(context),
                  ),
              ],
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 30, 8, 112),
              child: _CentralActionArea(
                repository: repository,
                room: room,
                playerId: playerId,
              ),
            ),
          ),
          Positioned(
            left: 42,
            top: 4,
            right: 120,
            child: _BattleStatusStrip(
              title: activePlayer == null
                  ? _phaseLabel(phase)
                  : isMyTurn
                  ? 'DEN LUOT CUA BAN'
                  : activePlayer.displayName,
              phase: phase,
              deadline: room.turnDeadlineAt,
              isMyTurn: isMyTurn,
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 4,
            child: _BattleBottomRail(
              equipment: _EquipmentBar(
                equipment: currentPlayer?.equipment ?? const [],
              ),
              role: currentPlayer?.revealedRole,
              handDock: _BattleHandDock(
                repository: repository,
                room: room,
                isMyTurn: isMyTurn,
                canPlay: canPlay,
                activePlayer: activePlayer,
                onPlay: (cardId) => _playCard(context, cardId, playerId),
              ),
              pending: _pendingActionDock(context, playerId),
              log: room.publicLog.isEmpty
                  ? null
                  : _publicLogLabel(room, room.publicLog.last),
              actions: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canDraw)
                    FilledButton(
                      onPressed: () => _drawTurn(
                        context,
                        playerId,
                        activePlayer?.characterId,
                      ),
                      child: const Text('RUT 2'),
                    ),
                  if (canPlay)
                    FilledButton.tonal(
                      onPressed: () => _call(context, 'requestEndTurn'),
                      child: const Text('HET LUOT'),
                    ),
                ],
              ),
            ),
          ),
          _TurnTimeoutDriver(
            roomId: room.id,
            phase: phase,
            deadline: room.turnDeadlineAt,
            isMyTurn: isMyTurn,
            onTurnStartExpired: canDraw
                ? () => _drawTurn(context, playerId, activePlayer?.characterId)
                : null,
            onPlayExpired: canPlay
                ? () => _call(context, 'requestEndTurn')
                : null,
          ),
        ],
      ),
    );
  }
}

class _RoundBattleTable extends StatefulWidget {
  const _RoundBattleTable({
    required this.repository,
    required this.room,
    required this.playerId,
    required this.activePlayer,
    required this.canDraw,
    required this.canPlay,
    required this.onDraw,
    required this.onEndTurn,
    required this.onPlay,
    required this.onTargetedPlay,
    required this.onJesseDraw,
    required this.pendingDock,
  });

  final OnlineRoomRepository repository;
  final OnlineRoom room;
  final String? playerId;
  final RoomMember? activePlayer;
  final bool canDraw;
  final bool canPlay;
  final VoidCallback? onDraw;
  final VoidCallback? onEndTurn;
  final ValueChanged<String>? onPlay;
  final void Function(String cardId, String targetId)? onTargetedPlay;
  final ValueChanged<String>? onJesseDraw;
  final Widget pendingDock;

  @override
  State<_RoundBattleTable> createState() => _RoundBattleTableState();
}

class _RoundBattleTableState extends State<_RoundBattleTable> {
  String? _selectedCardId;
  bool _choosingJesseTarget = false;

  bool get _isTargeting {
    final cardId = _selectedCardId;
    if (cardId == null) return false;
    return cardId.startsWith('bang_') ||
        cardId.startsWith('jail_') ||
        cardId.startsWith('panico_') ||
        cardId.startsWith('cat_balou_') ||
        cardId.startsWith('duello_') ||
        (cardId.startsWith('dodge_') &&
            widget.room.memberFor(widget.playerId ?? '')?.characterId ==
                'calamity_janet');
  }

  void _selectCard(String cardId) {
    if (widget.onPlay == null) return;
    setState(() {
      _selectedCardId = _selectedCardId == cardId ? null : cardId;
    });
  }

  void _playSelected() {
    final cardId = _selectedCardId;
    final callback = widget.onPlay;
    if (cardId == null || callback == null || _isTargeting) return;
    setState(() => _selectedCardId = null);
    callback(cardId);
  }

  bool _canTarget(RoomMember target) {
    final cardId = _selectedCardId;
    final playerId = widget.playerId;
    if (_choosingJesseTarget) {
      return target.id != playerId && target.isAlive && target.cardCount > 0;
    }
    if (!_isTargeting || cardId == null || playerId == null) return false;
    if (target.id == playerId || !target.isAlive) return false;
    final actor = widget.room.memberFor(playerId);
    final distance = _distanceBetween(widget.room, playerId, target.id);
    return _targetBlockedReason(
          room: widget.room,
          cardId: cardId,
          actor: actor,
          target: target,
          distance: distance,
        ) ==
        null;
  }

  void _fireAt(RoomMember target) {
    if (_choosingJesseTarget && _canTarget(target)) {
      setState(() => _choosingJesseTarget = false);
      widget.onJesseDraw?.call(target.id);
      return;
    }
    final cardId = _selectedCardId;
    final callback = widget.onTargetedPlay;
    if (cardId == null || callback == null || !_canTarget(target)) return;
    setState(() => _selectedCardId = null);
    callback(cardId, target.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff160c08),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, size) {
          final localPlayer = widget.room.memberFor(widget.playerId ?? '');
          final opponents =
              widget.room.members
                  .where((member) => member.id != widget.playerId)
                  .toList()
                ..sort((left, right) {
                  final localSeat = localPlayer?.seat ?? 0;
                  final count = widget.room.members.length;
                  final leftOffset = (left.seat - localSeat + count) % count;
                  final rightOffset = (right.seat - localSeat + count) % count;
                  return leftOffset.compareTo(rightOffset);
                });
          const opponentPoints = <Offset>[
            Offset(.89, .43),
            Offset(.88, .16),
            Offset(.69, .14),
            Offset(.47, .14),
            Offset(.25, .14),
            Offset(.03, .16),
            Offset(.02, .43),
          ];
          final center = Offset(size.maxWidth / 2, size.maxHeight * .42);
          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/room_table.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Text(
                  widget.activePlayer?.id == widget.playerId
                      ? 'DEN LUOT CUA BAN'
                      : 'LUOT CUA ${widget.activePlayer?.displayName ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffffd272),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Positioned(
                left: center.dx - 44,
                top: center.dy - 20,
                child: Row(
                  children: const [
                    _TableDeck(label: 'RUT'),
                    SizedBox(width: 4),
                    _TableDeck(label: 'BO'),
                  ],
                ),
              ),
              ...opponents.asMap().entries.map((entry) {
                final point = opponentPoints[entry.key];
                final member = entry.value;
                return Positioned(
                  left: (point.dx * size.maxWidth).clamp(
                    6.0,
                    size.maxWidth - 128,
                  ),
                  top: point.dy * size.maxHeight,
                  child: _RoundSeat(
                    member: member,
                    active: member.id == widget.room.currentTurnPlayerId,
                    canTarget: _canTarget(member),
                    onTarget: () => _fireAt(member),
                  ),
                );
              }),
              if (localPlayer != null)
                Positioned(
                  right: 10,
                  bottom: 8,
                  child: _RoundSeat(
                    member: localPlayer,
                    active: localPlayer.id == widget.room.currentTurnPlayerId,
                    isLocal: true,
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 154,
                child: Text(
                  _choosingJesseTarget
                      ? 'JESSE JONES: CHON NGUOI DE LAY 1 LA'
                      : _isTargeting
                      ? 'CHON MUC TIEU TRONG TAM BAN'
                      : widget.room.publicLog.isEmpty
                      ? _phaseLabel(widget.room.phase)
                      : widget.room.publicLog.last,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Positioned(
                left: size.maxWidth * .25,
                right: size.maxWidth * .25,
                bottom: 8,
                height: 108,
                child: StreamBuilder<List<String>>(
                  stream: widget.repository.watchHand(widget.room.id),
                  builder: (context, snapshot) => _FannedBattleHand(
                    cards: snapshot.data ?? const [],
                    selectedCardId: _selectedCardId,
                    enabled: widget.onPlay != null,
                    onTap: _selectCard,
                  ),
                ),
              ),
              Positioned(
                bottom: 116,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(74, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.canDraw ? widget.onDraw : null,
                      child: const Text('RUT 2'),
                    ),
                    if (widget.onJesseDraw != null) ...[
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(76, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(
                          () => _choosingJesseTarget = !_choosingJesseTarget,
                        ),
                        icon: const Icon(Icons.person_search, size: 16),
                        label: const Text('CUOP 1'),
                      ),
                    ],
                    const SizedBox(width: 10),
                    if (_selectedCardId != null && !_isTargeting) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(78, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _playSelected,
                        icon: Icon(
                          _isEquipmentCard(_selectedCardId!)
                              ? Icons.add_to_photos_outlined
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          _isEquipmentCard(_selectedCardId!)
                              ? 'DAT BAI'
                              : 'DANH',
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(86, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.canPlay ? widget.onEndTurn : null,
                      child: const Text('HET LUOT'),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: size.maxWidth * .28,
                right: size.maxWidth * .28,
                bottom: 140,
                child: widget.pendingDock,
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _FannedBattleHand extends StatelessWidget {
  const _FannedBattleHand({
    required this.cards,
    required this.selectedCardId,
    required this.enabled,
    required this.onTap,
  });

  final List<String> cards;
  final String? selectedCardId;
  final bool enabled;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (cards.isEmpty) return const SizedBox.shrink();
      const cardWidth = 54.0;
      final availableStep = cards.length <= 1
          ? cardWidth
          : (constraints.maxWidth - cardWidth) / (cards.length - 1);
      final step = availableStep.clamp(24.0, 39.0);
      final fanWidth = cardWidth + step * (cards.length - 1);
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: fanWidth + 12,
          height: 108,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < cards.length; index++)
                Positioned(
                  left: index * step,
                  bottom: cards[index] == selectedCardId ? 10 : 0,
                  child: AnimatedScale(
                    scale: cards[index] == selectedCardId ? 1.1 : 1,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: GameCardWidget(
                      card: _publicGameCard(cards[index]),
                      width: cardWidth,
                      height: 96,
                      isSelected: cards[index] == selectedCardId,
                      isEnabled: enabled,
                      onTap: enabled ? () => onTap(cards[index]) : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _TableDeck extends StatelessWidget {
  const _TableDeck({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 60,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xff3b2014),
      border: Border.all(color: const Color(0xffffc451), width: 2),
      borderRadius: BorderRadius.circular(5),
      image: const DecorationImage(
        image: AssetImage('assets/images/bang_bang_logo.png'),
        fit: BoxFit.contain,
        opacity: .32,
      ),
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xaa160c08),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xffffd272),
            fontWeight: FontWeight.w900,
            fontSize: 10,
          ),
        ),
      ),
    ),
  );
}

class _RoundSeat extends StatelessWidget {
  const _RoundSeat({
    required this.member,
    required this.active,
    this.isLocal = false,
    this.canTarget = false,
    this.onTarget,
  });
  final RoomMember member;
  final bool active;
  final bool isLocal;
  final bool canTarget;
  final VoidCallback? onTarget;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: canTarget ? onTarget : null,
    child: AnimatedScale(
      scale: active || canTarget ? 1.04 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        width: isLocal ? 160 : 84,
        height: isLocal ? 120 : 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isLocal
                      ? const Color(0xdd2c190f)
                      : const Color(0x992c190f),
                  border: Border.all(
                    color: canTarget
                        ? const Color(0xffff453a)
                        : active
                        ? const Color(0xffffc451)
                        : const Color(0xff8d6236),
                    width: canTarget || active ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: _SeatIdentity(member: member, large: isLocal),
                    ),
                    if (isLocal || member.equipment.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _SeatEquipment(
                        equipment: member.equipment,
                        large: isLocal,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (canTarget)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: isLocal ? 34 : 26,
                  height: isLocal ? 34 : 26,
                  decoration: const BoxDecoration(
                    color: Color(0xffc62828),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                  child: Icon(
                    Icons.gps_fixed,
                    color: Colors.white,
                    size: isLocal ? 24 : 18,
                  ),
                ),
              ),
            if (member.revealedRole == 'sheriff')
              Positioned(
                left: 3,
                top: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffffc451),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 9, color: Color(0xff2a160c)),
                      SizedBox(width: 2),
                      Text(
                        'SHERIFF',
                        style: TextStyle(
                          color: Color(0xff2a160c),
                          fontSize: 6,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SeatIdentity extends StatelessWidget {
  const _SeatIdentity({required this.member, required this.large});

  final RoomMember member;
  final bool large;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: large ? 44 : 24,
          height: large ? 58 : 35,
          child: Image.asset(
            _battleCharacterAsset(member.characterId),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xffc9984d),
              child: Icon(Icons.person, color: Color(0xff26140c)),
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              member.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: large ? 11 : 8,
              ),
            ),
            Text(
              '${member.health}/${member.maxHealth} MAU',
              style: TextStyle(
                color: const Color(0xffffd272),
                fontSize: large ? 9 : 6.5,
              ),
            ),
            Row(
              children: [
                Icon(Icons.style, color: Colors.white70, size: large ? 12 : 8),
                const SizedBox(width: 2),
                Text(
                  '${member.cardCount}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: large ? 10 : 7,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      CircleAvatar(
        radius: large ? 13 : 9,
        backgroundColor: const Color(0xffc9984d),
        child: Text(
          '${member.health}',
          style: TextStyle(
            color: const Color(0xff26140c),
            fontWeight: FontWeight.w900,
            fontSize: large ? 10 : 8,
          ),
        ),
      ),
    ],
  );
}

class _SeatEquipment extends StatelessWidget {
  const _SeatEquipment({required this.equipment, this.large = false});

  final List<String> equipment;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    height: large ? 46 : 24,
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
    decoration: BoxDecoration(
      color: large ? const Color(0x66160c08) : Colors.transparent,
      border: Border.all(
        color: large ? const Color(0xff8d6236) : Colors.transparent,
      ),
      borderRadius: BorderRadius.circular(3),
    ),
    child: equipment.isEmpty
        ? Center(
            child: Text(
              'TRANG BI CUA BAN',
              style: TextStyle(
                color: Colors.white38,
                fontSize: large ? 9 : 6,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: equipment.length,
            separatorBuilder: (_, _) => const SizedBox(width: 3),
            itemBuilder: (context, index) => Tooltip(
              message: _cardLabel(equipment[index]),
              child: GameCardWidget(
                card: _publicGameCard(equipment[index]),
                width: large ? 34 : 17,
                height: large ? 43 : 21,
                isEnabled: false,
              ),
            ),
          ),
  );
}

String _battleCharacterAsset(String? id) => switch (id) {
  null => 'assets/images/bang_bang_logo.png',
  'rose_doolan' => 'assets/images/characters/rose_oolan.png',
  _ => 'assets/images/characters/$id.png',
};

class _TurnTimeoutDriver extends StatefulWidget {
  const _TurnTimeoutDriver({
    required this.roomId,
    required this.phase,
    required this.deadline,
    required this.isMyTurn,
    required this.onTurnStartExpired,
    required this.onPlayExpired,
  });

  final String roomId;
  final String phase;
  final DateTime? deadline;
  final bool isMyTurn;
  final Future<void> Function()? onTurnStartExpired;
  final Future<void> Function()? onPlayExpired;

  @override
  State<_TurnTimeoutDriver> createState() => _TurnTimeoutDriverState();
}

class _TurnTimeoutDriverState extends State<_TurnTimeoutDriver> {
  late final Timer _timer;
  String? _handledKey;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _TurnTimeoutDriver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline ||
        oldWidget.phase != widget.phase ||
        oldWidget.roomId != widget.roomId) {
      _handledKey = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  void _tick() {
    if (!mounted || !widget.isMyTurn || widget.deadline == null) return;
    if (DateTime.now().isBefore(widget.deadline!)) return;
    final key = '${widget.roomId}|${widget.phase}|${widget.deadline}';
    if (_handledKey == key) return;
    _handledKey = key;
    if (widget.phase == 'turn_start') {
      widget.onTurnStartExpired?.call();
    } else if (widget.phase == 'play_phase') {
      widget.onPlayExpired?.call();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _BattleStatusStrip extends StatelessWidget {
  const _BattleStatusStrip({
    required this.title,
    required this.phase,
    required this.deadline,
    required this.isMyTurn,
  });

  final String title;
  final String phase;
  final DateTime? deadline;
  final bool isMyTurn;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMyTurn ? bangGold : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Flexible(
          child: Text(
            _phaseLabel(phase),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 8),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 54,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _TurnCountdown(
              deadline: deadline,
              isMyTurn: isMyTurn,
              onExpired: () {},
            ),
          ),
        ),
      ],
    ),
  );
}

class _TinyTableButton extends StatelessWidget {
  const _TinyTableButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: IconButton.filledTonal(
      padding: EdgeInsets.zero,
      iconSize: 16,
      onPressed: onPressed,
      icon: Icon(icon),
    ),
  );
}

class _BattleBottomRail extends StatelessWidget {
  const _BattleBottomRail({
    required this.equipment,
    required this.role,
    required this.handDock,
    required this.pending,
    required this.log,
    required this.actions,
  });

  final Widget equipment;
  final String? role;
  final Widget handDock;
  final Widget pending;
  final String? log;
  final Widget actions;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 104,
    child: Column(
      children: [
        SizedBox(
          height: 22,
          child: Row(
            children: [
              SizedBox(
                width: 136,
                child: Row(
                  children: [
                    Expanded(child: equipment),
                    if (role != null)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff3a2115),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xffffd44d)),
                        ),
                        child: Text(
                          _battleRoleLabel(role!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xffffd44d),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white70, fontSize: 9),
                  child: Center(
                    child: log == null
                        ? pending
                        : Text(
                            log!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 42),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 40),
              Expanded(child: handDock),
              const SizedBox(width: 6),
              SizedBox(width: 76, child: actions),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Fixed hand dock: the player's cards are always visible, including while
/// the public table is being watched.  The full action panel remains in the
/// scrollable area for special actions, while this dock handles the usual
/// select-and-play flow without hiding the hand below the fold.
class _BattleHandDock extends StatelessWidget {
  const _BattleHandDock({
    required this.repository,
    required this.room,
    required this.isMyTurn,
    required this.canPlay,
    required this.activePlayer,
    required this.onPlay,
  });

  final OnlineRoomRepository repository;
  final OnlineRoom room;
  final bool isMyTurn;
  final bool canPlay;
  final RoomMember? activePlayer;
  final Future<void> Function(String cardId) onPlay;

  @override
  Widget build(BuildContext context) => Container(
    height: 84,
    padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
    decoration: BoxDecoration(
      color: const Color(0x88170d09),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x999a6a35)),
      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8)],
    ),
    child: StreamBuilder<List<String>>(
      stream: repository.watchHand(room.id),
      builder: (context, snapshot) {
        final cards = snapshot.data ?? const <String>[];
        final selectedNotifier = OnlineBattleScreen._selectedHandCard(room.id);
        if (selectedNotifier.value != null &&
            !cards.contains(selectedNotifier.value)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            selectedNotifier.value = null;
          });
        }
        return ValueListenableBuilder<String?>(
          valueListenable: selectedNotifier,
          builder: (context, selectedCardId, _) {
            final selectedIsBang = selectedCardId?.startsWith('bang_') ?? false;
            final unlimitedBang =
                activePlayer?.characterId == 'willy_the_kid' ||
                activePlayer?.equipment.any(
                      (card) => card.startsWith('volcanic_'),
                    ) ==
                    true;
            final bangBlocked =
                selectedIsBang && room.bangUsedThisTurn >= 1 && !unlimitedBang;
            final canConfirm =
                selectedCardId != null && canPlay && !bangBlocked;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'BAI CUA BAN  ${cards.length}',
                      style: const TextStyle(
                        color: Color(0xffffd272),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        !isMyTurn
                            ? 'Dang theo doi luot doi thu'
                            : canPlay
                            ? 'Chon 1 la de danh'
                            : 'Hoan thanh buoc dau luot',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    if (selectedCardId != null)
                      SizedBox(
                        height: 23,
                        child: FilledButton(
                          onPressed: canConfirm
                              ? () async {
                                  final cardId = selectedCardId;
                                  selectedNotifier.value = null;
                                  await onPlay(cardId);
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            textStyle: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          child: Text(bangBlocked ? 'DA DUNG BANG' : 'DANH'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: cards.isEmpty
                      ? const Center(
                          child: Text(
                            'Chua co bai. Den luot hay rut 2 la.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          itemCount: cards.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 5),
                          itemBuilder: (context, index) {
                            final cardId = cards[index];
                            final isBang = cardId.startsWith('bang_');
                            final cardBangBlocked =
                                isBang &&
                                room.bangUsedThisTurn >= 1 &&
                                !unlimitedBang;
                            return GameCardWidget(
                              card: _publicGameCard(cardId),
                              width: 50,
                              isSelected: cardId == selectedCardId,
                              isEnabled: canPlay && !cardBangBlocked,
                              onTap: !canPlay || cardBangBlocked
                                  ? null
                                  : () => selectedNotifier.value =
                                        selectedCardId == cardId
                                        ? null
                                        : cardId,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    ),
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

      return Stack(
        children: [
          Positioned.fill(
            child: _PlayerTable(
              members: room.members,
              currentTurnPlayerId: room.currentTurnPlayerId,
              sheriffPlayerId: room.sheriffPlayerId,
              latestPublicLog: room.publicLog.isEmpty
                  ? null
                  : room.publicLog.last,
              turnDeadlineAt: room.turnDeadlineAt,
              pendingAction: action,
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PileMarker(
                    icon: Icons.layers_outlined,
                    label: 'RUT',
                    detail: 'up',
                  ),
                  const SizedBox(width: 8),
                  if (actionCardId != null)
                    _PublicCardStage(
                      cardId: actionCardId,
                      summary: summary,
                      actorName: actor?.displayName,
                      targetName: target?.displayName,
                    )
                  else
                    _EmptyActionStage(summary: summary),
                  const SizedBox(width: 8),
                  _PileMarker(
                    icon: Icons.delete_sweep_outlined,
                    label: 'BO',
                    detail: room.discardTopCardId == null
                        ? 'trong'
                        : _cardLabel(room.discardTopCardId!),
                  ),
                ],
              ),
            ),
          ),
          if (action != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _PublicResponseLine(
                action: action,
                actorName: actor?.displayName,
                targetName: target?.displayName,
              ),
            ),
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
    width: 48,
    child: Column(
      children: [
        Container(
          width: 34,
          height: 44,
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
    width: 178,
    height: 66,
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
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: equipment.isEmpty
        ? const SizedBox.shrink()
        : ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: equipment.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              final cardId = equipment[index];
              return Tooltip(
                message: _cardLabel(cardId),
                child: GameCardWidget(
                  card: _publicGameCard(cardId),
                  width: 26,
                  isEnabled: false,
                ),
              );
            },
          ),
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

String _battleRoleLabel(String role) => switch (role) {
  'sheriff' => 'SHERIFF',
  'deputy' => 'DEPUTY',
  'guardian' => 'GUARD',
  'outlaw' || 'raider' => 'RAIDER',
  'renegade' || 'traitor' => 'TRAITOR',
  _ => role.toUpperCase(),
};

class _PlayerTable extends StatelessWidget {
  const _PlayerTable({
    required this.members,
    required this.currentTurnPlayerId,
    required this.sheriffPlayerId,
    required this.latestPublicLog,
    required this.turnDeadlineAt,
    this.pendingAction,
  });

  final List<RoomMember> members;
  final String? currentTurnPlayerId;
  final String? sheriffPlayerId;
  final String? latestPublicLog;
  final DateTime? turnDeadlineAt;
  final Map<String, dynamic>? pendingAction;

  static const _seatPoints = <Offset>[
    Offset(.50, .04),
    Offset(.78, .10),
    Offset(.93, .43),
    Offset(.78, .76),
    Offset(.50, .84),
    Offset(.22, .76),
    Offset(.07, .43),
    Offset(.22, .10),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final seatWidth = math
          .min(constraints.maxWidth * .145, constraints.maxHeight * .27)
          .clamp(42.0, 70.0);
      final seatHeight = seatWidth * .96;
      final players = members.take(8).toList()
        ..sort((left, right) => left.seat.compareTo(right.seat));
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
            top: constraints.maxHeight * .17,
            bottom: constraints.maxHeight * .17,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x55315f2e),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x66d8e6a3), width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0xaa071d08), blurRadius: 18),
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
          for (var index = 0; index < players.length; index++)
            () {
              final point = _seatPoints[index];
              final x = point.dx * constraints.maxWidth - seatWidth / 2;
              final y = point.dy * constraints.maxHeight - seatHeight / 2;
              final member = players[index];
              final maxLeft = math.max(0.0, constraints.maxWidth - seatWidth);
              final maxTop = math.max(0.0, constraints.maxHeight - seatHeight);
              return Positioned(
                left: x.clamp(0.0, maxLeft),
                top: y.clamp(0.0, maxTop),
                width: seatWidth,
                height: seatHeight,
                child: _PlayerSeat(
                  member: member,
                  isCurrent: member.id == currentTurnPlayerId,
                  isSheriff: member.id == sheriffPlayerId,
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
  );
}

class _PlayerSeat extends StatefulWidget {
  const _PlayerSeat({
    required this.member,
    required this.isCurrent,
    required this.isSheriff,
    required this.isBangShooter,
    required this.isBangTarget,
    required this.turnDeadlineAt,
    this.bangEventId,
  });

  final RoomMember member;
  final bool isCurrent;
  final bool isSheriff;
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
    final sheriff = widget.isSheriff || member.revealedRole == 'sheriff';
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final avatar = (size * .68).clamp(30.0, 48.0);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (sheriff)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xffffd44d),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xb3ffb52b),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < math.min(member.cardCount, 4); i++)
              Positioned(
                left: constraints.maxWidth * .18 + i * 6,
                bottom: 0,
                child: Transform.rotate(
                  angle: -.25 + i * .15,
                  child: Container(
                    width: size * .34,
                    height: size * .48,
                    decoration: BoxDecoration(
                      color: const Color(0xffc39055),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xff3b1f10)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x77000000), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: avatar,
              height: avatar,
              padding: const EdgeInsets.all(3),
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
                shape: BoxShape.circle,
                border: Border.all(
                  color: sheriff
                      ? const Color(0xffffd44d)
                      : active
                      ? const Color(0xffffc451)
                      : const Color(0xff63432e),
                  width: sheriff || active ? 2.5 : 1,
                ),
                boxShadow: active && _bright
                    ? const [
                        BoxShadow(color: Color(0x99ffb12e), blurRadius: 10),
                      ]
                    : null,
              ),
              child: ClipOval(
                child: Image.asset(
                  _seatAvatarAsset(member),
                  fit: BoxFit.cover,
                  color: member.isAlive ? null : Colors.black54,
                  colorBlendMode: member.isAlive ? null : BlendMode.darken,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    member.isBot ? Icons.smart_toy : Icons.person,
                    size: avatar * .55,
                    color: member.isAlive
                        ? const Color(0xffffd272)
                        : Colors.white38,
                  ),
                ),
              ),
            ),
            if (sheriff)
              Positioned(
                right: -2,
                top: -5,
                child: Tooltip(
                  message: 'CẢNH SÁT TRƯỞNG',
                  child: const Icon(
                    Icons.workspace_premium,
                    size: 24,
                    color: Color(0xffffd44d),
                    shadows: [
                      Shadow(
                        color: Color(0xdd241207),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            if (member.equipment.isNotEmpty)
              Positioned(
                left: 0,
                top: constraints.maxHeight * .12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: member.equipment.take(3).map((cardId) {
                    return Tooltip(
                      message: _cardLabel(cardId),
                      child: Container(
                        width: 16,
                        height: 20,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xffead39b),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xff5a3116)),
                        ),
                        child: Icon(
                          _isGunCard(cardId)
                              ? Icons.gps_fixed
                              : Icons.inventory_2_outlined,
                          size: 11,
                          color: const Color(0xff3a2115),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xcc160c08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x8863432e)),
                ),
                child: Text(
                  member.isAlive
                      ? '${active ? 'LUOT' : member.displayName} ${member.health}/${member.maxHealth} ${member.cardCount}'
                      : '${member.displayName} OUT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 7,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
      },
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

String _seatAvatarAsset(RoomMember member) {
  return switch (member.characterId) {
    'doctor_lee' => 'assets/images/doctor_lee.png',
    'iron_rose' ||
    'rose_doolan' ||
    'rose_oolan' => 'assets/images/iron_rose.png',
    'lucky_duke' => 'assets/images/characters/lucky_duke.png',
    'quick_jack' || 'black_jack' => 'assets/images/quick_jack.png',
    _ => switch (member.revealedRole) {
      'sheriff' => 'assets/images/role_sheriff.png',
      'deputy' => 'assets/images/role_deputy.png',
      'guardian' => 'assets/images/role_guardian.png',
      'outlaw' || 'raider' => 'assets/images/role_raider.png',
      'renegade' || 'traitor' => 'assets/images/role_traitor.png',
      _ =>
        member.isBot
            ? 'assets/images/role_raider.png'
            : 'assets/images/role_deputy.png',
    },
  };
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
  const _PublicCardStage({
    required this.cardId,
    required this.summary,
    required this.actorName,
    required this.targetName,
  });

  final String cardId;
  final String summary;
  final String? actorName;
  final String? targetName;

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
              GameCardWidget(card: _publicGameCard(cardId), width: 52),
              const SizedBox(width: 7),
              SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (actorName != null) ...[
                      Text(
                        targetName == null
                            ? actorName!
                            : '$actorName -> $targetName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xffffd272),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
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
  final rawType = rankIndex < 0 ? parts.first : parts.take(rankIndex).join('_');
  // The online 100-card deck adds a physical-copy marker before rank/suit.
  // It identifies duplicate cards without changing the artwork type.
  final type = rawType.replaceFirst(RegExp(r'_copy\d+$'), '');
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
  final cardType = switch (type) {
    'bang' => CardType.bang,
    'dodge' => CardType.dodge,
    'beer' || 'saloon' => CardType.heal,
    'volcanic' => CardType.doubleBang,
    'gun_range_2' ||
    'gun_range_3' ||
    'gun_range_4' ||
    'gun_range_5' => CardType.scope,
    'mustang' || 'appaloosa' => CardType.horse,
    'panico' => CardType.steal,
    'cat_balou' => CardType.destroy,
    'duello' => CardType.duel,
    'dynamite' => CardType.explosion,
    _ => CardType.smoke,
  };
  return GameCard(
    cardType,
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
    .takeWhile((part) => !CardRank.values.any((rank) => rank.name == part))
    .where((part) => !RegExp(r'^copy\d+$').hasMatch(part))
    .join(' ')
    .replaceAll('DILIZENZA', 'DILIGENZA')
    .toUpperCase();

// ignore: unused_element
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

bool _isGunCard(String cardId) =>
    cardId.startsWith('gun_range_') || cardId.startsWith('volcanic_');

// ignore: unused_element
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

// ignore: unused_element
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

// ignore: unused_element
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
