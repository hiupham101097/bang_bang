import 'dart:async';

import 'package:flutter/material.dart';

import 'card_effect_overlay.dart';
import 'data/online_room_repository.dart';
import 'domain/online_models.dart';

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
      await repository.runGameAction(name, {'roomId': room.id, ...payload});
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _playCard(BuildContext context, String cardId) async {
    String? targetPlayerId;
    final needsTarget =
        cardId.startsWith('bang_') ||
        cardId.startsWith('jail_') ||
        cardId.startsWith('panico_') ||
        cardId.startsWith('cat_balou_') ||
        cardId.startsWith('duello_');
    if (needsTarget) {
      targetPlayerId = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('CHỌN MỤC TIÊU')),
              for (final member in room.members)
                ListTile(
                  leading: Icon(member.isBot ? Icons.smart_toy : Icons.person),
                  title: Text(member.displayName),
                  onTap: () => Navigator.pop(sheetContext, member.id),
                ),
            ],
          ),
        ),
      );
      if (targetPlayerId == null) return;
    }
    if (!context.mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final phase = room.phase;
    final canJudge = phase == 'turn_start';
    return Scaffold(
      backgroundColor: const Color(0xff160c08),
      appBar: AppBar(title: const Text('BANG BANG — Bàn đấu')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                'Lượt ${room.phase}',
                style: const TextStyle(fontSize: 20, color: Color(0xffffc451)),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: room.members
                    .map(
                      (member) => Chip(
                        label: Text(member.displayName),
                        avatar: Icon(
                          member.isBot ? Icons.smart_toy : Icons.person,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
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
                  if (cards.isEmpty) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Chưa có bài hoặc đang chờ đồng bộ.'),
                    );
                  }
                  return SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: cards.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => OutlinedButton(
                        onPressed: () => _playCard(context, cards[index]),
                        child: Text(
                          cards[index].split('_').first.toUpperCase(),
                        ),
                      ),
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
                  return Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: action['actionType'] == 'bang'
                              ? _ResponseCountdown(
                                  deadline: action['responseDeadlineAt'],
                                  onExpired: () => _callPayload(
                                    context,
                                    'resolveExpiredResponse',
                                    {'pendingActionId': action['id']},
                                  ),
                                )
                              : null,
                          title: Text(
                            'Đang chờ: ${action['actionType'] ?? 'phản ứng'}',
                          ),
                          subtitle: Text(
                            'Mục tiêu: ${action['currentTargetId'] ?? action['targetPlayerId'] ?? ''}',
                          ),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              if (action['actionType'] == 'bang')
                                FilledButton.tonal(
                                  onPressed: () => _callPayload(
                                    context,
                                    'acceptBangDamage',
                                    {'pendingActionId': action['id']},
                                  ),
                                  child: const Text('NHẬN ĐẠN'),
                                ),
                              OutlinedButton(
                                onPressed: () => _callPayload(
                                  context,
                                  'resolveExpiredResponse',
                                  {'pendingActionId': action['id']},
                                ),
                                child: const Text('HẾT HẠN'),
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
                                      onPressed: () => _callPayload(
                                        context,
                                        'chooseGeneralStoreCard',
                                        {
                                          'actionId': action['id'],
                                          'cardId': cardId,
                                        },
                                      ),
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
                                      onPressed: () => _callPayload(
                                        context,
                                        'chooseLuckyDukeJudgment',
                                        {
                                          'actionId': action['id'],
                                          'resultCardId': cardId,
                                        },
                                      ),
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
                              onPressed: () => _chooseKitCarlson(
                                context,
                                action['id'] as String,
                                judgmentChoices,
                              ),
                              child: const Text('KIT CARLSON: CHỌN 2 LÁ'),
                            ),
                          ),
                        if (action['actionType'] == 'duello' ||
                            action['actionType'] == 'gatling' ||
                            action['actionType'] == 'indiani')
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
                                        (card) => card.startsWith(requiredType),
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
                        if (action['actionType'] == 'bang')
                          const Center(child: BangEffectOverlay(size: 130)),
                        if (action['actionType'] == 'gatling' ||
                            action['actionType'] == 'indiani')
                          const Center(
                            child: AreaAttackEffectOverlay(size: 150),
                          ),
                        if (action['actionType'] == 'bang')
                          StreamBuilder<List<String>>(
                            stream: repository.watchHand(room.id),
                            builder: (context, handSnapshot) {
                              final hand =
                                  handSnapshot.data ?? const <String>[];
                              final dodges = hand
                                  .where((card) => card.startsWith('dodge_'))
                                  .toList();
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
              StreamBuilder<Map<String, dynamic>?>(
                stream: repository.watchPendingAction(room.id),
                builder: (context, snapshot) {
                  final action = snapshot.data;
                  if (action == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Action: ${action['actionType'] ?? 'đang chờ'}',
                            ),
                            Text(
                              'Mục tiêu: ${action['targetPlayerId'] ?? action['currentTargetId'] ?? 'nhiều người'}',
                            ),
                            if (action['actionType'] == 'bang')
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonal(
                                  onPressed: () => repository
                                      .runGameAction('acceptBangDamage', {
                                        'roomId': room.id,
                                        'pendingActionId': action['actionId'],
                                      }),
                                  child: const Text('NHẬN SÁT THƯƠNG'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              if (canJudge)
                FilledButton(
                  onPressed: () => _call(context, 'resolveTurnJudgments'),
                  child: const Text('PHÁN XÉT ĐẦU LƯỢT'),
                ),
              if (canJudge)
                FilledButton(
                  onPressed: () => _call(context, 'drawTurnCards'),
                  child: const Text('RÚT 2 LÁ'),
                ),
              if (phase == 'play_phase')
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

  void _tick() {
    final value = widget.deadline;
    final date = value == null ? null : value.toDate() as DateTime;
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
