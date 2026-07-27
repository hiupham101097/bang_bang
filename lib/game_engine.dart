import 'dart:math';

enum PlayerRole { sheriff, deputy, outlaw, renegade }

enum CardType {
  bang,
  dodge,
  heal,
  doubleBang,
  scope,
  horse,
  steal,
  destroy,
  smoke,
  duel,
  explosion,
  bounty,
}

enum GamePhase { drawing, action, gameOver }

enum RoundEvent { none, sandstorm, rushHour, gunBan, raid, goldVault, mayhem }

class GameCard {
  const GameCard(this.type);
  final CardType type;
  String get name => switch (type) {
    CardType.bang => 'BANG!',
    CardType.dodge => 'NÉ',
    CardType.heal => 'HỒI PHỤC',
    CardType.doubleBang => 'HAI NÒNG',
    CardType.scope => 'KÍNH NGẮM',
    CardType.horse => 'NGỰA',
    CardType.steal => 'CƯỚP BÀI',
    CardType.destroy => 'PHÁ ĐỒ',
    CardType.smoke => 'LỰU ĐẠN KHÓI',
    CardType.duel => 'ĐẤU SÚNG',
    CardType.explosion => 'NỔ KHO THUỐC',
    CardType.bounty => 'TRUY NÃ',
  };
  bool get needsTarget => ![
    CardType.heal,
    CardType.doubleBang,
    CardType.scope,
    CardType.horse,
    CardType.smoke,
    CardType.explosion,
  ].contains(type);
}

class GamePlayer {
  GamePlayer({
    required this.id,
    required this.name,
    required this.role,
    required this.maxHealth,
    this.isHuman = false,
  }) : health = maxHealth;
  final String id, name;
  final PlayerRole role;
  final int maxHealth;
  final bool isHuman;
  int health;
  bool alive = true;
  final List<GameCard> hand = [];
  final Set<CardType> equipment = {};
  int smokeUntilRound = 0;
  int get range => 1 + (equipment.contains(CardType.scope) ? 1 : 0);
  bool get doubleBang => equipment.contains(CardType.doubleBang);
}

class GameEngine {
  GameEngine._(this.players, this._random) {
    _buildDeck();
  }
  factory GameEngine.offline({int? seed, int playerCount = 4}) {
    final random = Random(seed);
    final roles = buildRoles(playerCount)..shuffle(random);
    final names = [
      'Lucky Joe',
      'Iron Rose',
      'Quick Jack',
      'Doctor Lee',
      'Silent Bill',
      'Ruby Jane',
      'Dusty Pete',
      'Belle Starr',
    ];
    final players = List.generate(
      playerCount,
      (i) => GamePlayer(
        id: 'p$i',
        name: names[i],
        role: roles[i],
        maxHealth: roles[i] == PlayerRole.sheriff ? 5 : 4,
        isHuman: i == 0,
      ),
    );
    final engine = GameEngine._(players, random);
    for (final p in players) {
      engine._draw(p, 4);
    }
    engine.phase = GamePhase.action;
    return engine;
  }

  static List<PlayerRole> buildRoles(int playerCount) {
    if (playerCount < 4 || playerCount > 8) {
      throw ArgumentError('Phong chi ho tro tu 4 den 8 nguoi.');
    }

    if (playerCount == 4) {
      return [
        PlayerRole.sheriff,
        PlayerRole.deputy,
        PlayerRole.outlaw,
        PlayerRole.outlaw,
      ];
    }

    const renegadeCount = 1;
    final mainFactionPlayers = playerCount - renegadeCount;
    final policeCount = mainFactionPlayers ~/ 2;
    final deputyCount = policeCount - 1;
    final outlawCount = mainFactionPlayers - policeCount;

    return [
      PlayerRole.sheriff,
      ...List<PlayerRole>.filled(deputyCount, PlayerRole.deputy),
      ...List<PlayerRole>.filled(outlawCount, PlayerRole.outlaw),
      PlayerRole.renegade,
    ];
  }
  final Random _random;
  final List<GamePlayer> players;
  final List<GameCard> deck = [], discard = [];
  GamePhase phase = GamePhase.drawing;
  RoundEvent event = RoundEvent.none;
  int round = 1, current = 0, bangsThisTurn = 0;
  String log = '';
  String? winner;
  GamePlayer? bountyTarget;
  GamePlayer get human => players.firstWhere((p) => p.isHuman);
  GamePlayer get currentPlayer => players[current];
  bool get isOver => phase == GamePhase.gameOver;
  String get eventLabel => switch (event) {
    RoundEvent.none => 'Không có sự kiện',
    RoundEvent.sandstorm => 'Bão cát: tầm bắn giảm 1',
    RoundEvent.rushHour => 'Giờ cao điểm: rút thêm 1 lá',
    RoundEvent.gunBan => 'Cấm súng: không được BANG',
    RoundEvent.raid => 'Truy quét: người nhiều bài bỏ 2',
    RoundEvent.goldVault => 'Kho vàng mở cửa: người ít máu hồi phục',
    RoundEvent.mayhem => 'Hỗn chiến: dùng tối đa 2 BANG',
  };

  void _buildDeck() {
    const types = CardType.values;
    for (final t in types) {
      for (var i = 0; i < (t == CardType.bang ? 12 : 4); i++)
        deck.add(GameCard(t));
    }
    deck.shuffle(_random);
  }

  void _draw(GamePlayer player, int count) {
    for (var i = 0; i < count; i++) {
      if (deck.isEmpty) {
        deck.addAll(discard);
        discard.clear();
        deck.shuffle(_random);
      }
      if (deck.isNotEmpty) player.hand.add(deck.removeLast());
    }
  }

  int distance(GamePlayer from, GamePlayer to) {
    final alive = players.where((p) => p.alive).toList();
    final a = alive.indexOf(from), b = alive.indexOf(to);
    final base = min((a - b).abs(), alive.length - (a - b).abs());
    final penalty = to.equipment.contains(CardType.horse) ? 1 : 0;
    final sand = event == RoundEvent.sandstorm ? 1 : 0;
    return max(1, base + penalty + sand);
  }

  bool canTarget(GamePlayer actor, GamePlayer target) =>
      target.alive &&
      actor != target &&
      distance(actor, target) <= actor.range &&
      !(target.smokeUntilRound >= round && distance(actor, target) > 1);
  void playHumanCard(int index, GamePlayer? target) {
    if (isOver ||
        currentPlayer != human ||
        index < 0 ||
        index >= human.hand.length)
      return;
    final card = human.hand[index];
    if (card.needsTarget && (target == null || !canTarget(human, target))) {
      log = 'Mục tiêu nằm ngoài tầm bắn hoặc không hợp lệ.';
      return;
    }
    if (card.type == CardType.bang &&
        (event == RoundEvent.gunBan ||
            bangsThisTurn >=
                (human.doubleBang || event == RoundEvent.mayhem ? 2 : 1))) {
      log = 'Bạn đã dùng đủ BANG trong lượt này.';
      return;
    }
    human.hand.removeAt(index);
    discard.add(card);
    _resolve(human, card, target);
    _checkWinner();
  }

  void _resolve(GamePlayer actor, GameCard card, GamePlayer? target) {
    switch (card.type) {
      case CardType.bang:
        bangsThisTurn++;
        if (_useDodge(target!)) {
          log = '${target.name} đã NÉ!';
        } else {
          _damage(target, actor);
          log = 'BANG! ${target.name} mất 1 máu.';
        }
      case CardType.dodge:
        log = 'Giữ lá NÉ để phản ứng khi bị tấn công.';
      case CardType.heal:
        actor.health = min(actor.maxHealth, actor.health + 1);
        log = '${actor.name} hồi 1 máu.';
      case CardType.doubleBang:
        actor.equipment.add(card.type);
        log = '${actor.name} trang bị Hai Nòng.';
      case CardType.scope:
        actor.equipment.add(card.type);
        log = '${actor.name} tăng tầm bắn.';
      case CardType.horse:
        actor.equipment.add(card.type);
        log = '${actor.name} cưỡi ngựa, khó bị nhắm hơn.';
      case CardType.steal:
        if (target!.hand.isNotEmpty) {
          actor.hand.add(
            target.hand.removeAt(_random.nextInt(target.hand.length)),
          );
          log = '${actor.name} cướp 1 lá từ ${target.name}.';
        } else {
          log = '${target.name} không còn bài để cướp.';
        }
      case CardType.destroy:
        if (target!.equipment.isNotEmpty) {
          final item = target.equipment.elementAt(
            _random.nextInt(target.equipment.length),
          );
          target.equipment.remove(item);
          log = '${actor.name} phá trang bị của ${target.name}.';
        } else {
          log = '${target.name} không có trang bị.';
        }
      case CardType.smoke:
        actor.smokeUntilRound = round;
        log = '${actor.name} thả lựu đạn khói.';
      case CardType.duel:
        _duel(actor, target!);
      case CardType.explosion:
        for (final p in players.where((p) => p.alive && p != actor)) {
          if (!_useDodge(p)) _damage(p, actor);
        }
        log = 'Nổ kho thuốc! Mọi người phải NÉ hoặc mất máu.';
      case CardType.bounty:
        bountyTarget = target;
        log = '${target!.name} bị TRUY NÃ.';
    }
  }

  bool _useDodge(GamePlayer p) {
    final i = p.hand.indexWhere((c) => c.type == CardType.dodge);
    if (i < 0) return false;
    discard.add(p.hand.removeAt(i));
    return true;
  }

  void _duel(GamePlayer a, GamePlayer b) {
    var attacker = a, defender = b;
    while (attacker.alive && defender.alive) {
      final bang = defender.hand.indexWhere((c) => c.type == CardType.bang);
      if (bang < 0) {
        _damage(defender, attacker);
        log = '${defender.name} thua Đấu súng!';
        return;
      }
      discard.add(defender.hand.removeAt(bang));
      final t = attacker;
      attacker = defender;
      defender = t;
    }
  }

  void _damage(GamePlayer target, GamePlayer source) {
    target.health--;
    if (target.health <= 0) {
      target.alive = false;
      target.health = 0;
      if (bountyTarget == target) _draw(source, 2);
    }
  }

  void endHumanTurn() {
    if (isOver || currentPlayer != human) return;
    _discardLimit(human);
    _advance();
    while (!isOver && currentPlayer != human) {
      _botTurn(currentPlayer);
      _advance();
    }
    if (!isOver) {
      _startTurn(human);
      log = '$log Đến lượt bạn.';
    }
  }

  void _advance() {
    current = (current + 1) % players.length;
    if (current == 0) {
      round++;
      _rollEvent();
    }
    _checkWinner();
  }

  void _startTurn(GamePlayer p) {
    bangsThisTurn = 0;
    _draw(p, event == RoundEvent.rushHour ? 3 : 2);
  }

  void _botTurn(GamePlayer bot) {
    if (!bot.alive) return;
    _startTurn(bot);
    final target = players.where((p) => p.alive && p != bot).toList()
      ..shuffle(_random);
    final bang = bot.hand.indexWhere((c) => c.type == CardType.bang);
    if (bang >= 0 &&
        target.isNotEmpty &&
        canTarget(bot, target.first) &&
        event != RoundEvent.gunBan) {
      final c = bot.hand.removeAt(bang);
      discard.add(c);
      _resolve(bot, c, target.first);
    }
    final heal = bot.hand.indexWhere((c) => c.type == CardType.heal);
    if (bot.health <= 2 && heal >= 0) {
      final c = bot.hand.removeAt(heal);
      discard.add(c);
      _resolve(bot, c, null);
    }
    _discardLimit(bot);
  }

  void _discardLimit(GamePlayer p) {
    while (p.hand.length > p.health)
      discard.add(p.hand.removeAt(_random.nextInt(p.hand.length)));
  }

  void _rollEvent() {
    event = _random.nextInt(4) == 0
        ? RoundEvent.values[1 + _random.nextInt(RoundEvent.values.length - 1)]
        : RoundEvent.none;
    if (event == RoundEvent.goldVault) {
      final living = players.where((p) => p.alive).toList()
        ..sort((a, b) => a.health.compareTo(b.health));
      if (living.isNotEmpty)
        living.first.health = min(
          living.first.maxHealth,
          living.first.health + 1,
        );
    }
    if (event == RoundEvent.raid) {
      final living = players.where((p) => p.alive).toList()
        ..sort((a, b) => b.hand.length.compareTo(a.hand.length));
      if (living.isNotEmpty)
        for (var i = 0; i < 2 && living.first.hand.isNotEmpty; i++)
          discard.add(living.first.hand.removeLast());
    }
  }

  void _checkWinner() {
    final sheriff = players.firstWhere((p) => p.role == PlayerRole.sheriff);
    final raiders = players
        .where((p) => p.alive && p.role == PlayerRole.raider)
        .toList();
    final traitors = players
        .where((p) => p.alive && p.role == PlayerRole.traitor)
        .toList();
    final living = players.where((p) => p.alive).toList();
    if (!sheriff.alive)
      winner = raiders.isNotEmpty ? 'Phe Kẻ cướp' : 'Kẻ phản bội';
    else if (raiders.isEmpty && traitors.isEmpty)
      winner = 'Cảnh trưởng và Vệ sĩ';
    else if (living.length == 1 && living.single.role == PlayerRole.traitor)
      winner = 'Kẻ phản bội';
    if (winner != null) {
      phase = GamePhase.gameOver;
      log = 'KẾT THÚC VÁN: $winner chiến thắng!';
    }
  }
}
