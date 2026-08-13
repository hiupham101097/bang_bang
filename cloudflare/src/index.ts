import { DurableObject } from "cloudflare:workers";

export interface Env {
  MATCH: DurableObjectNamespace<BangBangMatch>;
  DIRECTORY: DurableObjectNamespace<BangBangDirectory>;
  AUTH_SECRET: string;
}

type Role = "sheriff" | "deputy" | "outlaw" | "renegade";
type Phase = "lobby" | "role_selection" | "role_reveal" | "character_selection" | "choosing_character" | "turn_start" | "play_phase" | "waiting_response" | "discard_phase" | "game_over";
type Command =
  | "join"
  | "leave"
  | "ready"
  | "add_bot"
  | "remove_bot"
  | "start"
  | "choose_role"
  | "take_character_card"
  | "choose_character"
  | "draw"
  | "play"
  | "respond_bang"
  | "rescue"
  | "choose_kit_carlson"
  | "choose_lucky_duke"
  | "choose_general_store"
  | "sid_ketchum"
  | "end_turn"
  | "discard";

interface User { id: string; name: string }
interface Player {
  id: string; name: string; seat: number; bot: boolean; ready: boolean;
  alive: boolean; health: number; maxHealth: number; cardCount: number;
  role?: Role; characterId?: string; characterOptions?: string[]; characterChosen?: boolean;
  hand: string[]; equipment: string[]; attackRange: number;
}
interface SetupCard { id: string; value: string; pickedBy?: string }
interface PendingBang {
  id: string; actorId: string; targetId: string; deadline: number; requiredDodges: number;
  cardId?: string;
  actionType?: "bang" | "gatling" | "indiani" | "duello" | "general_store" | "rescue" | "kit_carlson" | "lucky_duke_judgment";
  requiredCardType?: "dodge" | "bang";
  targets?: string[]; targetIndex?: number; duelPlayerA?: string; duelPlayerB?: string;
  openedCardIds?: string[]; pickerOrder?: string[]; pickerIndex?: number; currentPickerId?: string;
  choices?: string[];
  requiredHealth?: number;
  resumePending?: PendingBang;
  resumePhase?: Phase;
  causedByPlayer?: boolean;
  judgmentKind?: "dynamite" | "jail" | "barrel";
  judgmentCardId?: string;
  judgmentAttemptsRemaining?: number;
  judgmentDodgesApplied?: number;
  judgmentsResolved?: boolean;
}
interface MatchState {
  id: string; code: string; hostId: string; maxPlayers: number; turnDurationSeconds: number;
  status: "waiting" | "starting" | "playing" | "finished"; phase: Phase; players: Player[];
  deck: string[]; discard: string[]; currentTurnPlayerId?: string; turnNumber: number;
  turnDeadline?: number;
  characterSelectionDeadline?: number;
  roleDeck?: SetupCard[]; characterDeck?: SetupCard[];
  bangUsedThisTurn: number; publicLog: string[]; pendingBang?: PendingBang; winner?: string;
  turnOrder?: string[]; currentPlayerIndex?: number; roundNumber?: number;
  processedRequestIds?: string[];
  lastPlayedCardId?: string; lastActionActorId?: string; lastActionTargetId?: string;
}

const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*" },
});
const fail = (message: string, status = 400) => json({ error: message }, status);
const code = () => crypto.randomUUID().replaceAll("-", "").slice(0, 6).toUpperCase();
const shuffle = <T>(values: T[]) => {
  const copy = [...values];
  for (let index = copy.length - 1; index > 0; index--) {
    const swap = crypto.getRandomValues(new Uint32Array(1))[0] % (index + 1);
    [copy[index], copy[swap]] = [copy[swap], copy[index]];
  }
  return copy;
};
const typeOf = (card?: string) => {
  const parts = (card ?? "").split("_");
  return parts[0] === "gun" ? parts.slice(0, 3).join("_") : parts[0];
};
const deck = () => {
  // Base-game card composition (80 cards). Physical IDs remain unique while
  // typeOf() still resolves the gameplay name before the card marker.
  const types = [
    ...Array(25).fill("bang"), ...Array(12).fill("dodge"), ...Array(6).fill("beer"),
    ...Array(4).fill("panico"), ...Array(4).fill("cat_balou"), ...Array(2).fill("dilizenza"),
    "wells_fargo", ...Array(2).fill("general_store"), ...Array(3).fill("duello"), "gatling",
    ...Array(2).fill("indiani"), "saloon", ...Array(2).fill("barrel"), ...Array(3).fill("jail"),
    "dynamite", ...Array(2).fill("volcanic"), ...Array(3).fill("gun_range_2"),
    "gun_range_3", "gun_range_4", "gun_range_5", ...Array(2).fill("mustang"), "appaloosa",
  ];
  const ranks = ["ace", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king"];
  const suits = ["spade", "club", "diamond", "heart"];
  return types.map((type, index) => {
    const rank = ranks[Math.floor(index / suits.length) % ranks.length];
    const suit = suits[index % suits.length];
    return `${type}_card${index}_${rank}_${suit}`;
  });
};
const rankValue = (card?: string) => {
  const rank = (card ?? "").split("_").at(-2) ?? "";
  return ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king", "ace"].indexOf(rank) + 2;
};
const roles = (count: number): Role[] => {
  if (count === 4) return ["sheriff", "renegade", "outlaw", "outlaw"];
  // Eight players is the app's Dodge City-inspired room rule.
  if (count === 8) return ["sheriff", "deputy", "deputy", "outlaw", "outlaw", "outlaw", "renegade", "renegade"];
  const police = Math.floor((count - 1) / 2);
  return ["sheriff", ...Array(police - 1).fill("deputy"), ...Array(count - police - 1).fill("outlaw"), "renegade"];
};
const cardSummary = (card?: string) => {
  if (!card) return "không có lá";
  const parts = card.split("_");
  return `${typeOf(card).toUpperCase()} ${parts.at(-2) ?? ""} ${parts.at(-1) ?? ""}`;
};
const roleDeck = (count: number): SetupCard[] => shuffle<Role>(roles(count))
  .slice(0, count)
  .map((value) => ({ id: `role_${crypto.randomUUID()}`, value }));
const characterHealth: Record<string, number> = {
  paul_regret: 3, el_gringo: 3, vulture_sam: 4, calamity_janet: 4,
  black_jack: 4, willy_the_kid: 4, lucky_duke: 4, kit_carlson: 4,
  rose_doolan: 4, suzy_lafayette: 4, bart_cassidy: 4, jesse_jones: 4,
  slab_the_killer: 4, sid_ketchum: 4, jourdonnais: 4, pedro_ramirez: 4,
};
const characters = Object.keys(characterHealth);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "GET,POST,OPTIONS", "access-control-allow-headers": "authorization,content-type" } });
    const url = new URL(request.url);
    if (url.pathname === "/health") return json({ ok: true, service: "blue-frog-fec8" });
    if (request.method === "POST" && url.pathname === "/v1/session") {
      const body = await request.json<{ deviceId?: string; displayName?: string }>();
      if (!body.deviceId || body.deviceId.length < 8) return fail("Thiếu deviceId.");
      const user = { id: body.deviceId, name: (body.displayName || "Cao bồi").slice(0, 24) };
      return json({ token: await sign(user, env.AUTH_SECRET), user });
    }
    const user = await authenticate(request, env.AUTH_SECRET);
    if (!user) return fail("Phiên đăng nhập không hợp lệ.", 401);
    if (request.method === "GET" && url.pathname === "/v1/rooms") {
      return env.DIRECTORY.getByName("lobby").fetch("https://directory/list");
    }
    if (request.method === "POST" && url.pathname === "/v1/rooms") {
      const body = await request.json<{ maxPlayers?: number; turnDurationSeconds?: number }>();
      const roomCode = code();
      const stub = env.MATCH.get(env.MATCH.idFromName(roomCode));
      return stub.fetch(new Request("https://match/internal/create", { method: "POST", body: JSON.stringify({ user, code: roomCode, maxPlayers: body.maxPlayers, turnDurationSeconds: body.turnDurationSeconds }) }));
    }
    const match = url.pathname.match(/^\/v1\/rooms\/([A-Z0-9]+)(?:\/(ws))?$/);
    if (!match) return fail("Không tìm thấy API.", 404);
    const stub = env.MATCH.get(env.MATCH.idFromName(match[1]));
    const headers = new Headers(request.headers);
    headers.set("x-bangbang-user", JSON.stringify(user));
    return stub.fetch(new Request(`https://match/${match[2] === "ws" ? "ws" : "command"}`, { method: request.method, headers, body: request.body }));
  },
};

interface RoomSummary {
  id: string;
  code: string;
  hostId: string;
  maxPlayers: number;
  turnDurationSeconds: number;
  status: MatchState["status"];
  phase: Phase;
  totalCount: number;
  botCount: number;
  updatedAt: number;
}

/// A single lightweight lobby directory. It only stores public room summaries;
/// all authoritative game state remains inside the per-room Durable Object.
export class BangBangDirectory extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === "/upsert" && request.method === "POST") {
      const summary = await request.json<RoomSummary>();
      await this.ctx.storage.put(`room:${summary.id}`, summary);
      return json({ ok: true });
    }
    if (path === "/list") {
      const entries = await this.ctx.storage.list<RoomSummary>({ prefix: "room:" });
      const rooms = [...entries.values()]
          .filter((room) => room.status === "waiting" && room.totalCount < room.maxPlayers)
          .sort((left, right) => right.updatedAt - left.updatedAt)
          .slice(0, 20);
      return json({ rooms });
    }
    return fail("Directory route not found.", 404);
  }
}

export class BangBangMatch extends DurableObject<Env> {
  private stateData?: MatchState;
  constructor(ctx: DurableObjectState, env: Env) { super(ctx, env); }

  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === "/internal/create") return this.create(request);
    const user = JSON.parse(request.headers.get("x-bangbang-user") || "null") as User | null;
    if (!user) return fail("Unauthorized", 401);
    if (path === "/ws") return this.websocket(request, user);
    if (path === "/command" && request.method === "GET") {
      const state = await this.load();
      return json({ room: this.snapshot(state, user.id) });
    }
    if (path !== "/command" || request.method !== "POST") return fail("Not found", 404);
    return this.command(user, await request.json<{ action: Command; payload?: Record<string, unknown> }>());
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    const user = ws.deserializeAttachment() as User | null;
    if (!user) return;
    try { await this.apply(user, JSON.parse(message) as { action: Command; payload?: Record<string, unknown> }); }
    catch (error) { ws.send(JSON.stringify({ type: "error", error: error instanceof Error ? error.message : "Lỗi máy chủ" })); }
  }
  webSocketClose(ws: WebSocket): void { ws.close(); }

  async alarm(): Promise<void> {
    const state = await this.load();
    if (state.status === "starting" && state.phase === "role_selection" && state.characterSelectionDeadline && Date.now() >= state.characterSelectionDeadline) {
      this.fillMissingRoles(state);
      await this.startRoleReveal(state);
      await this.save(state);
    } else if (state.status === "starting" && state.phase === "role_reveal" && state.characterSelectionDeadline && Date.now() >= state.characterSelectionDeadline) {
      await this.startCharacterSelection(state);
      await this.save(state);
    } else if (state.status === "starting" && (state.phase === "character_selection" || state.phase === "choosing_character") && state.characterSelectionDeadline && Date.now() >= state.characterSelectionDeadline) {
      await this.fillMissingCharacters(state);
      state.publicLog.push("Het gio chon nhan vat: he thong da chon ngau nhien.");
      await this.finalizeCharacters(state);
      await this.save(state);
    } else if (state.phase === "waiting_response" && state.pendingBang && Date.now() >= state.pendingBang.deadline) {
      const pending = state.pendingBang;
      if (pending.actionType === "rescue") {
        this.resolveRescue(state, pending.targetId, []);
      } else if (pending.actionType === "kit_carlson") {
        this.chooseKitCarlson(state, pending.actorId, (pending.choices ?? []).slice(0, 2));
      } else if (pending.actionType === "lucky_duke_judgment") {
        await this.chooseLuckyDuke(state, pending.actorId, this.preferredLuckyChoice(pending));
      } else if (pending.actionType === "general_store") {
        const card = pending.openedCardIds?.[0];
        if (card) this.chooseGeneralStore(state, pending.currentPickerId ?? pending.targetId, card);
      } else {
        const waitingForRescue = this.damage(state, pending.targetId, pending.actorId, "Không phản ứng kịp", 1, pending, true);
        if (!waitingForRescue) {
          if (pending.actionType === "duello") this.finishPendingResponse(state, pending);
          else this.advancePendingResponse(state, pending);
        }
      }
      await this.save(state);
    } else if (state.status === "playing" && state.phase !== "waiting_response" && state.turnDeadline && Date.now() >= state.turnDeadline) {
      const current = state.players.find((player) => player.id === state.currentTurnPlayerId);
      if (current?.bot && state.phase === "turn_start") await this.runBotTurn(state);
      else await this.resolveTurnTimeout(state);
      await this.save(state);
    }
  }

  private async create(request: Request): Promise<Response> {
    const data = await request.json<{ user: User; code: string; maxPlayers?: number; turnDurationSeconds?: number }>();
    const existing = await this.load(false);
    if (existing) return fail("Mã phòng trùng, hãy tạo lại.", 409);
    const maxPlayers = Math.max(4, Math.min(8, Number(data.maxPlayers || 4)));
    const host: Player = { id: data.user.id, name: data.user.name, seat: 0, bot: false, ready: false, alive: true, health: 0, maxHealth: 0, cardCount: 0, hand: [], equipment: [], attackRange: 1 };
    const state: MatchState = { id: data.code, code: data.code, hostId: host.id, maxPlayers, turnDurationSeconds: Math.max(20, Number(data.turnDurationSeconds || 60)), status: "waiting", phase: "lobby", players: [host], deck: [], discard: [], turnNumber: 0, bangUsedThisTurn: 0, publicLog: ["Phòng đã được tạo."] };
    await this.save(state);
    return json({ room: this.snapshot(state, data.user.id) }, 201);
  }

  private async command(user: User, command: { action: Command; payload?: Record<string, unknown> }): Promise<Response> {
    try { const state = await this.apply(user, command); return json({ room: this.snapshot(state, user.id) }); }
    catch (error) { return fail(error instanceof Error ? error.message : "Lỗi máy chủ"); }
  }

  private async apply(user: User, command: { action: Command; payload?: Record<string, unknown> }): Promise<MatchState> {
    const state = await this.load();
    const payload = command.payload ?? {};
    const requestKey = payload.requestId ? `${user.id}:${String(payload.requestId)}` : "";
    if (requestKey && state.processedRequestIds?.includes(requestKey)) return state;
    if (command.action === "join") {
      if (state.status !== "waiting" || state.players.length >= state.maxPlayers) throw Error("Phòng đã đầy hoặc đã bắt đầu.");
      if (!state.players.some((player) => player.id === user.id)) state.players.push({ id: user.id, name: user.name, seat: state.players.length, bot: false, ready: false, alive: true, health: 0, maxHealth: 0, cardCount: 0, hand: [], equipment: [], attackRange: 1 });
    } else {
      const player = state.players.find((item) => item.id === user.id);
      if (!player) throw Error("Bạn chưa ở trong phòng này.");
      if (command.action === "leave") {
        if (state.status !== "waiting") throw Error("Không thể rời phòng khi trận đang diễn ra.");
        state.players = state.players.filter((item) => item.id !== user.id);
        state.players.forEach((item, index) => item.seat = index);
        if (state.hostId === user.id && state.players.length > 0) {
          state.hostId = state.players.find((item) => !item.bot)?.id ?? state.players[0].id;
        }
        if (state.players.every((item) => item.bot)) state.status = "finished";
      } else if (command.action === "ready") {
        if (state.status !== "waiting") throw Error("Trận đã bắt đầu.");
        player.ready = Boolean(payload.ready);
      } else if (command.action === "add_bot") {
        if (user.id !== state.hostId || state.status !== "waiting" || state.players.length >= state.maxPlayers) throw Error("Không thể thêm bot.");
        const seat = state.players.length;
        state.players.push({ id: `bot_${crypto.randomUUID()}`, name: `Bot ${seat}`, seat, bot: true, ready: true, alive: true, health: 0, maxHealth: 0, cardCount: 0, hand: [], equipment: [], attackRange: 1 });
      } else if (command.action === "remove_bot") {
        const botId = String(payload.botId || "");
        if (user.id !== state.hostId || state.status !== "waiting") throw Error("Không thể xóa bot.");
        const before = state.players.length;
        state.players = state.players.filter((item) => item.id !== botId || !item.bot);
        if (state.players.length === before) throw Error("Không tìm thấy bot.");
        state.players.forEach((item, index) => item.seat = index);
      } else if (command.action === "start") await this.start(state, user.id);
      else if (command.action === "choose_role") await this.chooseRole(state, user.id, String(payload.cardId || ""));
      else if (command.action === "take_character_card") await this.takeCharacterCard(state, user.id, String(payload.cardId || ""));
      else if (command.action === "choose_character") await this.chooseCharacter(state, user.id, String(payload.characterId || ""));
      else if (command.action === "draw") await this.draw(state, user.id, String(payload.targetPlayerId || ""), String(payload.drawSource || "deck"));
      else if (command.action === "play") this.play(state, user.id, String(payload.cardId || ""), String(payload.targetPlayerId || ""), payload);
      else if (command.action === "respond_bang") this.respondBang(state, user.id, String(payload.response || "damage"), String(payload.cardId || ""), Array.isArray(payload.cardIds) ? payload.cardIds.map(String) : []);
      else if (command.action === "rescue") this.resolveRescue(state, user.id, Array.isArray(payload.cardIds) ? payload.cardIds.map(String) : []);
      else if (command.action === "choose_kit_carlson") this.chooseKitCarlson(state, user.id, Array.isArray(payload.cardIds) ? payload.cardIds.map(String) : []);
      else if (command.action === "choose_lucky_duke") await this.chooseLuckyDuke(state, user.id, String(payload.resultCardId || ""));
      else if (command.action === "choose_general_store") this.chooseGeneralStore(state, user.id, String(payload.cardId || ""));
      else if (command.action === "sid_ketchum") this.useSidKetchum(state, user.id, Array.isArray(payload.cardIds) ? payload.cardIds.map(String) : []);
      else if (command.action === "end_turn") await this.endTurn(state, user.id);
      else if (command.action === "discard") await this.discardCards(state, user.id, Array.isArray(payload.cardIds) ? payload.cardIds.map(String) : []);
    }
    for (const candidate of state.players) this.maybeSuzy(state, candidate);
    if (requestKey) state.processedRequestIds = [...(state.processedRequestIds ?? []), requestKey].slice(-200);
    await this.save(state);
    return state;
  }

  private async start(state: MatchState, userId: string): Promise<void> {
    if (state.hostId !== userId || state.status !== "waiting") throw Error("Chỉ chủ phòng được bắt đầu.");
    if (state.players.length < 4) throw Error("Cần đủ 4–8 người chơi.");
    if (state.players.some((player) => !player.bot && player.id !== userId && !player.ready)) throw Error("Khách chưa sẵn sàng.");
    state.players.forEach((player) => {
      player.role = undefined;
      player.characterOptions = [];
      player.characterId = undefined;
      player.characterChosen = false;
      player.hand = []; player.cardCount = 0; player.equipment = []; player.attackRange = 1;
    });
    state.roleDeck = roleDeck(state.players.length);
    state.characterDeck = [];
    state.status = "starting"; state.phase = "role_selection";
    state.characterSelectionDeadline = Date.now() + 60000;
    state.publicLog.push("Moi nguoi dang chon vai tro.");
    for (const bot of state.players.filter((player) => player.bot)) this.pickRandomRole(state, bot);
    void this.ctx.storage.setAlarm(state.characterSelectionDeadline);
    if (state.players.every((player) => state.roleDeck?.some((card) => card.pickedBy === player.id))) await this.startRoleReveal(state);
  }
  private async chooseRole(state: MatchState, userId: string, cardId: string): Promise<void> {
    if (state.status !== "starting" || state.phase !== "role_selection") throw Error("Khong o giai doan chon vai tro.");
    const player = this.player(state, userId);
    if (state.roleDeck?.some((card) => card.pickedBy === userId)) throw Error("Ban da chon vai tro.");
    const card = state.roleDeck?.find((item) => item.id === cardId && !item.pickedBy);
    if (!card) throw Error("La vai tro khong hop le.");
    card.pickedBy = userId;
    player.role = card.value as Role;
    if (state.players.every((item) => state.roleDeck?.some((card) => card.pickedBy === item.id))) await this.startRoleReveal(state);
  }
  private pickRandomRole(state: MatchState, player: Player): void {
    if (state.roleDeck?.some((card) => card.pickedBy === player.id)) return;
    const card = shuffle(state.roleDeck?.filter((item) => !item.pickedBy) ?? [])[0];
    if (!card) return;
    card.pickedBy = player.id;
    player.role = card.value as Role;
  }
  private fillMissingRoles(state: MatchState): void {
    for (const player of state.players.filter((item) => !state.roleDeck?.some((card) => card.pickedBy === item.id))) this.pickRandomRole(state, player);
  }
  private async startRoleReveal(state: MatchState): Promise<void> {
    this.normalizeRoles(state);
    state.phase = "role_reveal";
    // This is intentionally server-authoritative so every device sees its
    // private role before the character deck becomes selectable.
    state.characterSelectionDeadline = Date.now() + 10_000;
    state.publicLog.push("Vai tro da duoc lat. Chuan bi chon nhan vat sau 10 giay.");
    void this.ctx.storage.setAlarm(state.characterSelectionDeadline);
  }
  private normalizeRoles(state: MatchState): void {
    const required = roles(state.players.length);
    const counts = new Map<Role, number>();
    for (const role of required) counts.set(role, (counts.get(role) ?? 0) + 1);
    for (const player of state.players) {
      const role = player.role;
      const remaining = role ? counts.get(role) ?? 0 : 0;
      if (role && remaining > 0) counts.set(role, remaining - 1);
      else player.role = undefined;
    }
    const missing = [...counts.entries()].flatMap(([role, count]) =>
      Array<Role>(count).fill(role)
    );
    shuffle(state.players.filter((player) => !player.role)).forEach((player, index) => {
      player.role = missing[index];
    });
  }
  private async startCharacterSelection(state: MatchState): Promise<void> {
    this.normalizeRoles(state);
    const offered = shuffle(characters).slice(0, state.players.length * 2);
    state.characterDeck = offered.map((value) => ({ id: `character_${crypto.randomUUID()}`, value }));
    state.players.forEach((player) => {
      player.characterOptions = [];
      player.characterId = undefined;
      player.characterChosen = false;
    });
    state.phase = "character_selection";
    state.characterSelectionDeadline = Date.now() + 60000;
    state.publicLog.push("Moi nguoi dang chon 2 la nhan vat.");
    for (const bot of state.players.filter((player) => player.bot)) {
      await this.takeRandomCharacterCard(state, bot);
      await this.takeRandomCharacterCard(state, bot);
      bot.characterId = bot.characterOptions?.[0];
      bot.characterChosen = Boolean(bot.characterId);
    }
    void this.ctx.storage.setAlarm(state.characterSelectionDeadline);
    await this.finalizeCharacters(state);
  }
  private async takeCharacterCard(state: MatchState, userId: string, cardId: string): Promise<void> {
    if (state.status !== "starting" || state.phase !== "character_selection") throw Error("Khong o giai doan chon nhan vat.");
    const player = this.player(state, userId);
    player.characterOptions ??= [];
    if (player.characterOptions.length >= 2) throw Error("Ban da chon du 2 la.");
    const card = state.characterDeck?.find((item) => item.id === cardId && !item.pickedBy);
    if (!card) throw Error("La nhan vat khong hop le.");
    card.pickedBy = userId;
    player.characterOptions.push(card.value);
    await this.advanceCharacterChoicePhase(state);
  }
  private async takeRandomCharacterCard(state: MatchState, player: Player): Promise<void> {
    player.characterOptions ??= [];
    if (player.characterOptions.length >= 2) return;
    const card = shuffle(state.characterDeck?.filter((item) => !item.pickedBy) ?? [])[0];
    if (!card) return;
    card.pickedBy = player.id;
    player.characterOptions.push(card.value);
    await this.advanceCharacterChoicePhase(state);
  }
  private async advanceCharacterChoicePhase(state: MatchState): Promise<void> {
    if (state.phase === "character_selection" && state.players.every((player) => (player.characterOptions?.length ?? 0) >= 2)) {
      state.phase = "choosing_character";
      state.publicLog.push("Moi nguoi chon 1 trong 2 la nhan vat.");
      if (state.players.every((player) => player.characterChosen && player.characterId)) await this.finalizeCharacters(state);
    }
  }
  private async fillMissingCharacters(state: MatchState): Promise<void> {
    for (const player of state.players) {
      while ((player.characterOptions?.length ?? 0) < 2) await this.takeRandomCharacterCard(state, player);
      if (!player.characterChosen) {
        player.characterId = player.characterOptions?.[0];
        player.characterChosen = Boolean(player.characterId);
      }
    }
  }
  private async chooseCharacter(state: MatchState, userId: string, characterId: string): Promise<void> {
    if (state.status !== "starting" || (state.phase !== "character_selection" && state.phase !== "choosing_character")) throw Error("Khong o giai doan chon nhan vat.");
    const player = this.player(state, userId);
    if ((player.characterOptions?.length ?? 0) < 2) throw Error("Can chon du 2 la nhan vat truoc.");
    if (!player.characterOptions?.includes(characterId)) throw Error("Nhân vật không hợp lệ.");
    // A previous request can have selected the card in memory just before an
    // unexpected failure during game setup. Retrying the same choice must be
    // safe and should finish setup instead of trapping the room.
    if (player.characterChosen) {
      if (player.characterId !== characterId) throw Error("Bạn đã chọn nhân vật khác.");
      await this.finalizeCharacters(state);
      return;
    }
    player.characterId = characterId; player.characterChosen = true;
    await this.finalizeCharacters(state);
  }
  private async finalizeCharacters(state: MatchState): Promise<void> {
    if (state.players.some((player) => !player.characterChosen || !player.characterId)) return;
    state.characterSelectionDeadline = undefined;
    const cards = shuffle(deck());
    for (const player of state.players) {
      player.maxHealth = characterHealth[player.characterId!] + (player.role === "sheriff" ? 1 : 0);
      // BANG starts each player with as many cards as their maximum health.
      // A fixed 7-card hand exhausts a 52-card deck in an eight-player room
      // before the opening high-card draw can happen.
      player.health = player.maxHealth;
      player.hand = cards.splice(0, player.maxHealth);
      player.cardCount = player.hand.length; player.alive = true; player.equipment = []; player.attackRange = 1;
    }
    state.deck = cards;
    state.discard = [];
    state.status = "playing"; state.phase = "turn_start";
    state.turnOrder = state.players.slice().sort((a, b) => a.seat - b.seat).map((player) => player.id);
    const sheriff = state.players.find((player) => player.role === "sheriff")!;
    state.currentPlayerIndex = state.turnOrder.indexOf(sheriff.id);
    state.currentTurnPlayerId = sheriff.id;
    state.roundNumber = 1;
    state.turnNumber = 1; state.bangUsedThisTurn = 0; state.publicLog.push("Trận đấu bắt đầu.");
    state.publicLog.push("Sheriff di luot dau tien.");
    state.turnDeadline = Date.now() + state.turnDurationSeconds * 1000;
    void this.ctx.storage.setAlarm(state.turnDeadline);
    await this.runBotTurn(state);
  }

  private async draw(state: MatchState, userId: string, jesseTargetId = "", drawSource = "deck"): Promise<void> {
    this.requireTurn(state, userId, "turn_start");
    const player = this.player(state, userId);
    if (await this.resolveTurnJudgments(state, player)) return;
    const cards: string[] = [];
    if (player.characterId === "kit_carlson") {
      const peek = this.takeCards(state, 3);
      if (peek.length <= 2) {
        cards.push(...peek);
      } else {
        state.phase = "waiting_response";
        state.pendingBang = {
          id: crypto.randomUUID(), actorId: player.id, targetId: player.id,
          deadline: Date.now() + 30_000, requiredDodges: 0,
          actionType: "kit_carlson", choices: peek,
        };
        state.publicLog.push(`${player.name} đang xem 3 lá của Kit Carlson.`);
        void this.ctx.storage.setAlarm(state.pendingBang.deadline);
        this.runBotResponse(state);
        return;
      }
    } else if (player.characterId === "jesse_jones" && jesseTargetId) {
      const victim = state.players.find((candidate) => candidate.alive && candidate.id === jesseTargetId && candidate.hand.length > 0);
      if (victim) {
        const stolen = victim.hand.splice(crypto.getRandomValues(new Uint32Array(1))[0] % victim.hand.length, 1)[0];
        victim.cardCount = victim.hand.length; cards.push(stolen);
      }
    }
    if (cards.length === 0 && player.characterId === "pedro_ramirez" && drawSource === "discard" && state.discard.length > 0) {
      cards.push(state.discard.pop()!);
      state.publicLog.push(`${player.name} lấy lá đầu từ chồng bài bỏ.`);
    }
    cards.push(...this.takeCards(state, 2 - cards.length));
    if (player.characterId === "black_jack" && cards[1]) {
      state.publicLog.push(`${player.name} lật lá thứ hai: ${cardSummary(cards[1])}.`);
      if (cards[1].endsWith("_heart") || cards[1].endsWith("_diamond")) cards.push(...this.takeCards(state, 1));
    }
    player.hand.push(...cards); player.cardCount = player.hand.length; state.phase = "play_phase"; state.publicLog.push(`${player.name} rút 2 lá.`);
  }

  private chooseKitCarlson(state: MatchState, userId: string, cardIds: string[]): void {
    const pending = state.pendingBang;
    if (!pending || pending.actionType !== "kit_carlson" || pending.actorId !== userId || state.phase !== "waiting_response") throw Error("Không có lựa chọn Kit Carlson hợp lệ.");
    const choices = pending.choices ?? [];
    if (cardIds.length !== 2 || new Set(cardIds).size !== 2 || cardIds.some((card) => !choices.includes(card))) throw Error("Kit Carlson phải chọn đúng 2 trong 3 lá.");
    const returned = choices.find((card) => !cardIds.includes(card));
    const player = this.player(state, userId);
    player.hand.push(...cardIds); player.cardCount = player.hand.length;
    if (returned) state.deck.unshift(returned);
    state.pendingBang = undefined; state.phase = "play_phase";
    state.publicLog.push(`${player.name} đã chọn 2 lá với Kit Carlson.`);
    this.restoreTurnAlarm(state, player);
  }

  private play(state: MatchState, userId: string, cardId: string, targetId: string, payload: Record<string, unknown> = {}): void {
    this.requireTurn(state, userId, "play_phase"); const actor = this.player(state, userId); const type = typeOf(cardId);
    const at = actor.hand.indexOf(cardId); if (at < 0) throw Error("Bạn không có lá bài này.");
    state.lastPlayedCardId = cardId;
    state.lastActionActorId = actor.id;
    state.lastActionTargetId = targetId || undefined;
    if (type === "bang" || (type === "dodge" && actor.characterId === "calamity_janet")) {
      if (state.bangUsedThisTurn > 0 && actor.characterId !== "willy_the_kid" && !actor.equipment.some((card) => card.startsWith("volcanic"))) throw Error("Mỗi lượt chỉ dùng 1 BANG.");
      const target = this.player(state, targetId); if (!target.alive || target.id === actor.id || this.distance(state, actor, target) > actor.attackRange) throw Error("Mục tiêu ngoài tầm bắn.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length; state.discard.push(cardId); state.bangUsedThisTurn++; state.phase = "waiting_response";
      state.pendingBang = { id: crypto.randomUUID(), actorId: actor.id, targetId: target.id, cardId, deadline: Date.now() + 10000, requiredDodges: actor.characterId === "slab_the_killer" ? 2 : 1, actionType: "bang", requiredCardType: "dodge" };
      state.publicLog.push(`${actor.name} BANG ${target.name}.`); void this.ctx.storage.setAlarm(state.pendingBang.deadline);
      this.runBotResponse(state);
    } else if (type === "beer") {
      if (state.players.filter((player) => player.alive).length <= 2) throw Error("Beer không có tác dụng khi chỉ còn 2 người.");
      if (actor.health >= actor.maxHealth) throw Error("Máu đã đầy."); actor.hand.splice(at, 1); actor.cardCount = actor.hand.length; actor.health++; state.discard.push(cardId); state.publicLog.push(`${actor.name} hồi 1 máu.`);
    } else if (type === "dilizenza" || type === "wells") {
      actor.hand.splice(at, 1); state.discard.push(cardId);
      this.drawFor(state, actor, type === "dilizenza" ? 2 : 3);
      state.publicLog.push(`${actor.name} rút thêm bài.`);
    } else if (type === "saloon") {
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length; state.discard.push(cardId);
      for (const player of state.players.filter((player) => player.alive)) player.health = Math.min(player.maxHealth, player.health + 1);
      state.publicLog.push(`${actor.name} dùng Saloon, mọi người hồi 1 máu.`);
    } else if (type === "mustang" || type === "appaloosa") {
      if (actor.equipment.some((card) => typeOf(card) === type)) throw Error("Bạn đã có một lá cùng tên đang đặt.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length;
      actor.equipment.push(cardId); this.refreshAttackRange(actor);
      state.publicLog.push(`${actor.name} trang bị ${type}.`);
    } else if (type === "panico" || type === "cat") {
      const target = this.player(state, targetId);
      if (!targetId || target.id === actor.id || !target.alive) throw Error("Cần chọn mục tiêu còn sống.");
      if (type === "panico" && this.distance(state, actor, target) > 1) throw Error("Panico chỉ dùng ở khoảng cách 1.");
      const equipmentCardId = typeof payload.equipmentCardId === "string" ? payload.equipmentCardId : "";
      let taken: string | undefined;
      if (equipmentCardId) {
        const index = target.equipment.indexOf(equipmentCardId);
        if (index >= 0) taken = target.equipment.splice(index, 1)[0];
      } else if (target.hand.length > 0) {
        taken = target.hand.splice(crypto.getRandomValues(new Uint32Array(1))[0] % target.hand.length, 1)[0];
      }
      if (!taken) throw Error("Mục tiêu không còn bài hoặc trang bị.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length; target.cardCount = target.hand.length; state.discard.push(cardId);
      this.refreshAttackRange(target);
      if (type === "panico") { actor.hand.push(taken); actor.cardCount = actor.hand.length; state.publicLog.push(`${actor.name} cướp 1 lá của ${target.name}.`); }
      else { state.discard.push(taken); state.publicLog.push(`${actor.name} phá 1 lá của ${target.name}.`); }
    } else if (type === "general") {
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length; state.discard.push(cardId);
      const pickerOrder = this.aliveOrderFrom(state, actor.id).map((player) => player.id);
      const openedCardIds = this.takeCards(state, pickerOrder.length);
      if (openedCardIds.length === 0) throw Error("Bộ bài đã hết.");
      state.phase = "waiting_response";
      state.pendingBang = {
        id: crypto.randomUUID(), actorId: actor.id, targetId: actor.id, cardId,
        deadline: Date.now() + 30000, requiredDodges: 0,
        actionType: "general_store", openedCardIds, pickerOrder, pickerIndex: 0,
        currentPickerId: actor.id,
      };
      state.publicLog.push(`${actor.name} mở General Store.`);
      void this.ctx.storage.setAlarm(state.pendingBang.deadline);
      this.runBotResponse(state);
    } else if (type === "gatling" || type === "indiani") {
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length; state.discard.push(cardId);
      const targets = state.players.filter((player) => player.alive && player.id !== actor.id).map((player) => player.id);
      if (targets.length === 0) throw Error("Không có mục tiêu.");
      state.phase = "waiting_response";
      state.pendingBang = { id: crypto.randomUUID(), actorId: actor.id, targetId: targets[0], cardId, deadline: Date.now() + 10000, requiredDodges: 1, actionType: type, requiredCardType: type === "gatling" ? "dodge" : "bang", targets, targetIndex: 0 };
      state.publicLog.push(`${actor.name} dùng ${type}.`); void this.ctx.storage.setAlarm(state.pendingBang.deadline);
      this.runBotResponse(state);
    } else if (type === "duello") {
      const target = this.player(state, targetId);
      if (!targetId || target.id === actor.id || !target.alive) throw Error("Cần chọn mục tiêu còn sống.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length; state.discard.push(cardId);
      state.phase = "waiting_response";
      state.pendingBang = { id: crypto.randomUUID(), actorId: actor.id, targetId: target.id, cardId, deadline: Date.now() + 10000, requiredDodges: 1, actionType: "duello", requiredCardType: "bang", duelPlayerA: actor.id, duelPlayerB: target.id };
      state.publicLog.push(`${actor.name} thách đấu ${target.name}.`); void this.ctx.storage.setAlarm(state.pendingBang.deadline);
      this.runBotResponse(state);
    } else if (this.isWeapon(cardId)) {
      if (actor.equipment.some((card) => typeOf(card) === type)) throw Error("Bạn đã đặt một khẩu súng cùng loại.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length;
      // House rule: different guns may coexist. The farthest range applies,
      // while Volcanic independently allows multiple BANG cards.
      actor.equipment.push(cardId);
      this.refreshAttackRange(actor); state.publicLog.push(`${actor.name} trang bị súng tầm ${actor.attackRange}.`);
    } else if (type === "barrel") {
      if (actor.equipment.some((card) => typeOf(card) === "barrel")) throw Error("Bạn đã có Barrel.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length;
      actor.equipment.push(cardId);
      state.publicLog.push(`${actor.name} đặt Barrel.`);
    } else if (type === "dynamite") {
      if (actor.equipment.some((card) => typeOf(card) === "dynamite")) throw Error("Bạn đã có Dynamite.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length;
      actor.equipment.push(cardId);
      state.publicLog.push(`${actor.name} đặt Dynamite.`);
    } else if (type === "jail") {
      const target = this.player(state, targetId);
      if (!targetId || target.id === actor.id || target.role === "sheriff") throw Error("Jail phải đặt lên người khác, không phải Cảnh sát trưởng.");
      if (target.equipment.some((card) => typeOf(card) === "jail")) throw Error("Mục tiêu đã có Jail.");
      actor.hand.splice(at, 1); actor.cardCount = actor.hand.length;
      target.equipment.push(cardId);
      state.publicLog.push(`${actor.name} nhốt ${target.name}.`);
    } else throw Error("Thẻ này sẽ được mở ở bước hiệu ứng nâng cao.");
  }

  private respondBang(state: MatchState, userId: string, response: string, cardId: string, cardIds: string[] = []): void {
    const pending = state.pendingBang;
    if (!pending || pending.targetId !== userId || state.phase !== "waiting_response") throw Error("Không có phản ứng hợp lệ.");
    const target = this.player(state, userId);
    const required = pending.requiredCardType ?? "dodge";
    if (pending.actionType === "bang" && response !== "dodge" && !pending.judgmentsResolved) {
      const attempts = this.judgmentDodgeAttempts(target);
      if (target.characterId === "lucky_duke" && attempts > 0) {
        this.openLuckyJudgment(state, target, "barrel", undefined, pending, attempts);
        return;
      }
      const automaticDodges = this.heartJudgmentDodges(state, target);
      if (automaticDodges > 0) {
        state.publicLog.push(`${target.name} có ${automaticDodges} lần Né nhờ Barrel/kỹ năng.`);
        if (automaticDodges >= pending.requiredDodges) {
          this.advancePendingResponse(state, pending);
        } else {
          pending.requiredDodges -= automaticDodges;
          pending.judgmentsResolved = true;
          pending.deadline = Date.now() + 10_000;
          state.pendingBang = pending;
          void this.ctx.storage.setAlarm(pending.deadline);
        }
        return;
      }
    }
    if (response === "dodge" || response === "card") {
      const valid = (card: string) => typeOf(card) === required || (required === "dodge" && target.characterId === "calamity_janet" && typeOf(card) === "bang");
      const cards = target.hand.filter(valid);
      if (cards.length < pending.requiredDodges) throw Error("Không đủ bài phản ứng.");
      const spent = pending.requiredDodges === 1 ? [cardId] : cardIds;
      if (spent.length !== pending.requiredDodges || new Set(spent).size !== spent.length) throw Error("Cần chọn đúng số lá phản ứng.");
      if (spent.some((card) => !target.hand.includes(card) || !valid(card))) throw Error("Lá phản ứng không hợp lệ.");
      target.hand = target.hand.filter((card) => !spent.includes(card));
      target.cardCount = target.hand.length; state.discard.push(...spent);
      state.publicLog.push(`${target.name} đã phản ứng.`);
      this.advancePendingResponse(state, pending); return;
    }
    const waitingForRescue = this.damage(state, target.id, pending.actorId, pending.actionType ?? "bang", 1, pending, true);
    if (!waitingForRescue) {
      if (pending.actionType === "duello") this.finishPendingResponse(state, pending);
      else this.advancePendingResponse(state, pending);
    }
  }
  private chooseGeneralStore(state: MatchState, userId: string, cardId: string): void {
    const pending = state.pendingBang;
    if (!pending || pending.actionType !== "general_store" || pending.currentPickerId !== userId) throw Error("Chưa đến lượt chọn ở General Store.");
    const opened = pending.openedCardIds ?? [];
    const cardIndex = opened.indexOf(cardId);
    if (cardIndex < 0) throw Error("Lá này không còn trong General Store.");
    opened.splice(cardIndex, 1);
    const player = this.player(state, userId);
    player.hand.push(cardId); player.cardCount = player.hand.length;
    const nextIndex = (pending.pickerIndex ?? 0) + 1;
    const nextId = pending.pickerOrder?.[nextIndex];
    if (nextId && opened.length > 0) {
      pending.openedCardIds = opened; pending.pickerIndex = nextIndex;
      pending.currentPickerId = nextId; pending.targetId = nextId;
      pending.deadline = Date.now() + 30000; state.pendingBang = pending;
      void this.ctx.storage.setAlarm(pending.deadline); this.runBotResponse(state); return;
    }
    state.discard.push(...opened);
    state.publicLog.push("General Store kết thúc.");
    this.finishPendingResponse(state, pending);
  }
  private advancePendingResponse(state: MatchState, pending: PendingBang): void {
    if (pending.actionType === "duello") {
      const next = pending.targetId === pending.duelPlayerA ? pending.duelPlayerB : pending.duelPlayerA;
      if (next && this.player(state, next).alive) {
        pending.targetId = next; pending.deadline = Date.now() + 10000; state.pendingBang = pending;
        void this.ctx.storage.setAlarm(pending.deadline); this.runBotResponse(state); return;
      }
    }
    if (pending.targets) {
      for (let index = (pending.targetIndex ?? 0) + 1; index < pending.targets.length; index++) {
        const next = this.player(state, pending.targets[index]);
        if (next.alive) { pending.targetIndex = index; pending.targetId = next.id; pending.deadline = Date.now() + 10000; state.pendingBang = pending; void this.ctx.storage.setAlarm(pending.deadline); this.runBotResponse(state); return; }
      }
    }
    this.finishPendingResponse(state, pending);
  }
  private finishPendingResponse(state: MatchState, pending: PendingBang): void {
    state.pendingBang = undefined;
    if (state.status !== "playing") return;
    state.phase = "play_phase";
    const actor = this.player(state, pending.actorId);
    if (actor.bot && state.currentTurnPlayerId === actor.id) {
      // Let the alarm own the async turn transition so it is persisted by
      // the Durable Object alarm transaction instead of a floating promise.
      state.turnDeadline = Date.now() + 100;
      void this.ctx.storage.setAlarm(state.turnDeadline);
    } else if (state.currentTurnPlayerId === actor.id) {
      // A response alarm replaces the turn alarm (one alarm per Durable
      // Object). Restore the active player's deadline after the response so
      // the match can never stall in the middle of a turn.
      state.turnDeadline = Math.max(state.turnDeadline ?? 0, Date.now() + 100);
      void this.ctx.storage.setAlarm(state.turnDeadline);
    }
  }
  private restoreTurnAlarm(state: MatchState, player: Player): void {
    if (state.status !== "playing" || state.currentTurnPlayerId !== player.id) return;
    state.turnDeadline = Math.max(state.turnDeadline ?? 0, Date.now() + 100);
    void this.ctx.storage.setAlarm(state.turnDeadline);
  }
  private runBotResponse(state: MatchState): void {
    const pending = state.pendingBang;
    if (!pending) return;
    const bot = this.player(state, pending.targetId);
    if (!bot.bot) return;
    if (pending.actionType === "kit_carlson") {
      this.chooseKitCarlson(state, bot.id, (pending.choices ?? []).slice(0, 2));
      return;
    }
    if (pending.actionType === "rescue") {
      this.resolveRescue(state, bot.id, this.autoRescueCards(state, bot, pending.requiredHealth ?? 1));
      return;
    }
    if (pending.actionType === "general_store") {
      const card = pending.openedCardIds?.[0];
      if (card) this.chooseGeneralStore(state, bot.id, card);
      return;
    }
    const required = pending.requiredCardType ?? "dodge";
    const cards = bot.hand.filter((card) => typeOf(card) === required || (required === "dodge" && bot.characterId === "calamity_janet" && typeOf(card) === "bang"));
    this.respondBang(state, bot.id, cards.length >= pending.requiredDodges ? "card" : "damage", cards[0] ?? "", cards.slice(0, pending.requiredDodges));
  }
  private useSidKetchum(state: MatchState, userId: string, cardIds: string[]): void {
    const player = this.player(state, userId);
    if (state.status !== "playing" || !player.alive) throw Error("Không thể dùng kỹ năng lúc này.");
    if (player.characterId !== "sid_ketchum" || cardIds.length !== 2 || new Set(cardIds).size !== 2 || cardIds.some((card) => !player.hand.includes(card))) throw Error("Sid Ketchum cần bỏ đúng 2 lá trên tay.");
    if (player.health >= player.maxHealth) throw Error("Máu đã đầy.");
    player.hand = player.hand.filter((card) => !cardIds.includes(card)); player.cardCount = player.hand.length;
    state.discard.push(...cardIds); player.health++; state.publicLog.push(`${player.name} bỏ 2 lá để hồi 1 máu.`);
    this.maybeSuzy(state, player);
  }

  private async endTurn(state: MatchState, userId: string): Promise<void> {
    this.requireTurn(state, userId, "play_phase"); const player = this.player(state, userId);
    if (player.hand.length > player.health) { state.phase = "discard_phase"; return; }
    await this.advanceTurn(state, "Kết thúc lượt");
  }
  private judge(
    state: MatchState,
    player: Player,
    preferred: (card: string) => boolean = () => false,
  ): string | undefined {
    const cards = this.takeCards(state, player.characterId === "lucky_duke" ? 2 : 1);
    if (cards.length === 0) return undefined;
    const chosen = cards.find(preferred) ?? cards[0];
    state.discard.push(...cards);
    if (player.characterId === "lucky_duke" && cards.length === 2) {
      state.publicLog.push(`${player.name} dùng Lucky Duke chọn phán xét.`);
    }
    return chosen;
  }
  private isHeart(card: string | undefined): boolean { return card?.endsWith("_heart") === true; }
  private async resolveTurnJudgments(state: MatchState, player: Player): Promise<boolean> {
    const dynamite = player.equipment.find((card) => typeOf(card) === "dynamite");
    if (dynamite) {
      player.equipment = player.equipment.filter((card) => card !== dynamite);
      if (player.characterId === "lucky_duke") {
        this.openLuckyJudgment(state, player, "dynamite", dynamite);
        return true;
      }
      const card = this.judge(
        state,
        player,
        (value) => !(value.endsWith("_spade") && /_(two|three|four|five|six|seven|eight|nine)_spade$/.test(value)),
      );
      if (card?.endsWith("_spade") && /_(two|three|four|five|six|seven|eight|nine)_spade$/.test(card)) {
        state.discard.push(dynamite);
        const waitingForRescue = this.damage(state, player.id, player.id, "Dynamite nổ, mất 3 máu", 3, undefined, false, "turn_start");
        if (waitingForRescue || !player.alive || state.status !== "playing") return true;
      } else {
        const next = this.nextAlivePlayerWithout(state, player.id, "dynamite");
        if (next) {
          next.equipment.push(dynamite); state.publicLog.push(`Dynamite chuyển sang ${next.name}.`);
        } else {
          state.discard.push(dynamite);
        }
      }
    }
    const jail = player.equipment.find((card) => typeOf(card) === "jail");
    if (jail && player.alive) {
      player.equipment = player.equipment.filter((card) => card !== jail);
      state.discard.push(jail);
      if (player.characterId === "lucky_duke") {
        this.openLuckyJudgment(state, player, "jail", jail);
        return true;
      }
      const card = this.judge(state, player, (value) => this.isHeart(value));
      if (!this.isHeart(card)) {
        state.publicLog.push(`${player.name} không thoát Jail và mất lượt.`);
        await this.advanceTurn(state, "Mất lượt vì Jail");
        return true;
      }
      state.publicLog.push(`${player.name} thoát Jail.`);
    }
    return state.status !== "playing";
  }
  private openLuckyJudgment(
    state: MatchState,
    player: Player,
    kind: "dynamite" | "jail" | "barrel",
    judgmentCardId?: string,
    resumePending?: PendingBang,
    attemptsRemaining?: number,
    dodgesApplied = 0,
  ): void {
    const choices = this.takeCards(state, 2);
    if (choices.length === 0) throw Error("Không còn lá để phán xét.");
    state.phase = "waiting_response";
    state.pendingBang = {
      id: crypto.randomUUID(), actorId: player.id, targetId: player.id,
      deadline: Date.now() + (player.bot ? 100 : 30_000), requiredDodges: 0,
      actionType: "lucky_duke_judgment", choices, judgmentKind: kind, judgmentCardId,
      resumePending, judgmentAttemptsRemaining: attemptsRemaining,
      judgmentDodgesApplied: dodgesApplied,
    };
    state.publicLog.push(`${player.name} chọn 1 trong 2 lá phán xét.`);
    void this.ctx.storage.setAlarm(state.pendingBang.deadline);
  }
  private preferredLuckyChoice(pending: PendingBang): string {
    const choices = pending.choices ?? [];
    if (pending.judgmentKind === "jail" || pending.judgmentKind === "barrel") return choices.find((card) => this.isHeart(card)) ?? choices[0] ?? "";
    if (pending.judgmentKind === "dynamite") {
      return choices.find((card) => !(card.endsWith("_spade") && /_(two|three|four|five|six|seven|eight|nine)_spade$/.test(card))) ?? choices[0] ?? "";
    }
    return choices[0] ?? "";
  }
  private async chooseLuckyDuke(state: MatchState, userId: string, resultCardId: string): Promise<void> {
    const pending = state.pendingBang;
    if (!pending || pending.actionType !== "lucky_duke_judgment" || pending.actorId !== userId || state.phase !== "waiting_response") throw Error("Không có phán xét Lucky Duke hợp lệ.");
    const choices = pending.choices ?? [];
    if (!choices.includes(resultCardId)) throw Error("Lá phán xét không hợp lệ.");
    state.discard.push(...choices);
    state.pendingBang = undefined; state.phase = "turn_start";
    const player = this.player(state, userId);
    if (pending.judgmentKind === "dynamite") {
      const exploded = resultCardId.endsWith("_spade") && /_(two|three|four|five|six|seven|eight|nine)_spade$/.test(resultCardId);
      if (exploded) {
        if (pending.judgmentCardId) state.discard.push(pending.judgmentCardId);
        const waiting = this.damage(state, player.id, player.id, "Dynamite nổ, mất 3 máu", 3, undefined, false, "turn_start");
        if (waiting || !player.alive || state.status !== "playing") return;
      } else if (pending.judgmentCardId) {
        const next = this.nextAlivePlayerWithout(state, player.id, "dynamite");
        if (next) {
          next.equipment.push(pending.judgmentCardId);
          state.publicLog.push(`Dynamite chuyển sang ${next.name}.`);
        } else {
          state.discard.push(pending.judgmentCardId);
        }
      }
      await this.draw(state, userId);
      this.restoreTurnAlarm(state, player);
      return;
    }
    if (pending.judgmentKind === "barrel") {
      const original = pending.resumePending;
      if (!original) throw Error("Thiếu hành động BANG đang chờ.");
      const succeeded = this.isHeart(resultCardId);
      if (succeeded) original.requiredDodges--;
      const applied = (pending.judgmentDodgesApplied ?? 0) + (succeeded ? 1 : 0);
      const attempts = (pending.judgmentAttemptsRemaining ?? 1) - 1;
      if (original.requiredDodges <= 0) {
        state.pendingBang = original;
        this.advancePendingResponse(state, original);
        return;
      }
      if (attempts > 0) {
        this.openLuckyJudgment(state, player, "barrel", undefined, original, attempts, applied);
        return;
      }
      if (applied > 0) {
        original.judgmentsResolved = true;
        original.deadline = Date.now() + 10_000;
        state.pendingBang = original; state.phase = "waiting_response";
        void this.ctx.storage.setAlarm(original.deadline);
        return;
      }
      state.pendingBang = original; state.phase = "waiting_response";
      const waiting = this.damage(state, player.id, original.actorId, original.actionType ?? "bang", 1, original, true);
      if (!waiting) this.advancePendingResponse(state, original);
      return;
    }
    if (pending.judgmentKind === "jail" && !this.isHeart(resultCardId)) {
      state.publicLog.push(`${player.name} không thoát Jail và mất lượt.`);
      await this.advanceTurn(state, "Mất lượt vì Jail");
      return;
    }
    state.publicLog.push(`${player.name} thoát Jail.`);
    await this.draw(state, userId);
    this.restoreTurnAlarm(state, player);
  }
  private judgmentDodgeAttempts(player: Player): number {
    return (player.characterId === "jourdonnais" ? 1 : 0) +
      (player.equipment.some((card) => typeOf(card) === "barrel") ? 1 : 0);
  }
  private heartJudgmentDodges(state: MatchState, player: Player): number {
    const attempts = this.judgmentDodgeAttempts(player);
    let successes = 0;
    for (let index = 0; index < attempts; index++) {
      if (this.isHeart(this.judge(state, player, (value) => this.isHeart(value)))) successes++;
    }
    return successes;
  }
  private async discardCards(state: MatchState, userId: string, cards: string[]): Promise<void> {
    this.requireTurn(state, userId, "discard_phase"); const player = this.player(state, userId); const required = player.hand.length - player.health;
    if (cards.length !== required || cards.some((card) => !player.hand.includes(card))) throw Error(`Phải bỏ đúng ${required} lá.`);
    player.hand = player.hand.filter((card) => !cards.includes(card)); player.cardCount = player.hand.length; state.discard.push(...cards); state.phase = "turn_start"; await this.advanceTurn(state, "Bỏ bài");
  }

  private async resolveTurnTimeout(state: MatchState): Promise<void> {
    const currentId = state.currentTurnPlayerId;
    if (!currentId) return;
    if (state.phase === "turn_start") {
      await this.draw(state, currentId);
      if ((state.phase as Phase) !== "play_phase") return;
    }
    const player = this.player(state, currentId);
    const excess = Math.max(0, player.hand.length - player.health);
    if (excess > 0) {
      const discarded = shuffle(player.hand).slice(0, excess);
      player.hand = player.hand.filter((card) => !discarded.includes(card));
      player.cardCount = player.hand.length;
      state.discard.push(...discarded);
      state.publicLog.push(`${player.name} hết giờ và bỏ ${discarded.length} lá dư.`);
    }
    await this.advanceTurn(state, "Hết giờ");
  }
  private async advanceTurn(state: MatchState, reason: string): Promise<void> {
    const order = state.turnOrder ?? state.players.slice().sort((a, b) => a.seat - b.seat).map((player) => player.id);
    if (!order.length || state.status !== "playing") return;
    const startIndex = state.currentPlayerIndex ?? Math.max(0, order.indexOf(state.currentTurnPlayerId ?? ""));
    let nextIndex = startIndex;
    for (let offset = 1; offset <= order.length; offset++) {
      const candidateIndex = (startIndex + offset) % order.length;
      const candidate = state.players.find((player) => player.id === order[candidateIndex]);
      if (candidate?.alive) { nextIndex = candidateIndex; break; }
    }
    if (nextIndex <= startIndex) state.roundNumber = (state.roundNumber ?? 1) + 1;
    state.turnOrder = order; state.currentPlayerIndex = nextIndex; state.currentTurnPlayerId = order[nextIndex];
    state.turnNumber++; state.bangUsedThisTurn = 0; state.phase = "turn_start"; state.pendingBang = undefined;
    state.publicLog.push(reason);
    const nextPlayer = this.player(state, state.currentTurnPlayerId);
    state.turnDeadline = Date.now() + (nextPlayer.bot ? 850 : state.turnDurationSeconds * 1000);
    void this.ctx.storage.setAlarm(state.turnDeadline);
  }
  private async runBotTurn(state: MatchState): Promise<void> {
    const bot = state.players.find((player) => player.id === state.currentTurnPlayerId);
    if (!bot?.bot || state.status !== "playing" || state.phase !== "turn_start") return;
    await this.draw(state, bot.id);
    if (String(state.phase) !== "play_phase" || !bot.alive) return;

    const opponents = shuffle(state.players.filter((player) => player.alive && player.id !== bot.id));
    const targetsInRange = opponents.filter((player) => this.distance(state, bot, player) <= bot.attackRange);
    const adjacentTargets = opponents.filter((player) => this.distance(state, bot, player) <= 1);
    const beer = bot.hand.find((card) => typeOf(card) === "beer");
    const bang = bot.hand.find((card) => typeOf(card) === "bang");
    const areaAttack = bot.hand.find((card) => typeOf(card) === "gatling" || typeOf(card) === "indiani");
    const duel = bot.hand.find((card) => typeOf(card) === "duello");
    const targetCard = bot.hand.find((card) => typeOf(card) === "panico" || typeOf(card) === "cat");
    const equipment = bot.hand.find((card) => {
      const type = typeOf(card);
      return type === "mustang" || type === "appaloosa" || type === "volcanic" || type === "barrel" || type === "dynamite" || type.startsWith("gun_range");
    });
    const drawCard = bot.hand.find((card) => typeOf(card) === "dilizenza" || typeOf(card) === "wells");

    if (beer && bot.health < bot.maxHealth) {
      this.play(state, bot.id, beer, "");
    } else if (bang && targetsInRange[0]) {
      this.play(state, bot.id, bang, targetsInRange[0].id);
    } else if (areaAttack && opponents.length > 1) {
      this.play(state, bot.id, areaAttack, "");
    } else if (duel && opponents[0]) {
      this.play(state, bot.id, duel, opponents[0].id);
    } else if (targetCard) {
      const type = typeOf(targetCard);
      const candidates = (type === "panico" ? adjacentTargets : opponents).filter((player) => player.hand.length > 0 || player.equipment.length > 0);
      if (candidates[0]) this.play(state, bot.id, targetCard, candidates[0].id);
    } else if (equipment) {
      this.play(state, bot.id, equipment, "");
    } else if (drawCard) {
      this.play(state, bot.id, drawCard, "");
    }
    if (String(state.phase) === "play_phase") await this.endTurn(state, bot.id);
    if (String(state.phase) === "discard_phase" && state.currentTurnPlayerId === bot.id) {
      const excess = Math.max(0, bot.hand.length - bot.health);
      await this.discardCards(state, bot.id, bot.hand.slice(0, excess));
    }
  }
  private damage(
    state: MatchState,
    targetId: string,
    actorId: string,
    log: string,
    amount = 1,
    resumePending?: PendingBang,
    causedByPlayer = true,
    resumePhase: Phase = "play_phase",
  ): boolean {
    const target = this.player(state, targetId);
    const actor = state.players.find((player) => player.id === actorId);
    target.health -= amount;
    if (target.characterId === "bart_cassidy") this.drawFor(state, target, amount);
    if (causedByPlayer && target.characterId === "el_gringo" && actor) {
      for (let index = 0; index < amount && actor.hand.length > 0; index++) {
        const stolen = actor.hand.splice(crypto.getRandomValues(new Uint32Array(1))[0] % actor.hand.length, 1)[0];
        target.hand.push(stolen);
      }
      actor.cardCount = actor.hand.length; target.cardCount = target.hand.length;
    }
    state.publicLog.push(`${log}: ${target.name}.`);
    if (target.health > 0) return false;
    const requiredHealth = 1 - target.health;
    if (this.availableRescueHealing(state, target) >= requiredHealth) {
      state.phase = "waiting_response";
      state.pendingBang = {
        id: crypto.randomUUID(), actorId, targetId,
        deadline: Date.now() + 10_000, requiredDodges: 0,
        actionType: "rescue", requiredHealth, resumePending, resumePhase,
        causedByPlayer,
      };
      state.publicLog.push(`${target.name} có 10 giây để tự cứu.`);
      void this.ctx.storage.setAlarm(state.pendingBang.deadline);
      this.runBotResponse(state);
      return true;
    }
    this.eliminate(state, target, actor, causedByPlayer);
    return false;
  }

  private availableRescueHealing(state: MatchState, player: Player): number {
    const beerHealing = state.players.filter((candidate) => candidate.alive).length > 2
      ? player.hand.filter((card) => typeOf(card) === "beer").length
      : 0;
    const sidHealing = player.characterId === "sid_ketchum" ? Math.floor(player.hand.length / 2) : 0;
    return Math.max(beerHealing, sidHealing, player.characterId === "sid_ketchum" ? beerHealing + Math.floor(player.hand.filter((card) => typeOf(card) !== "beer").length / 2) : beerHealing);
  }

  private autoRescueCards(state: MatchState, player: Player, requiredHealth: number): string[] {
    const selected: string[] = [];
    let healing = 0;
    if (state.players.filter((candidate) => candidate.alive).length > 2) {
      for (const card of player.hand.filter((item) => typeOf(item) === "beer")) {
        selected.push(card); healing++;
        if (healing >= requiredHealth) return selected;
      }
    }
    if (player.characterId === "sid_ketchum") {
      const remaining = player.hand.filter((card) => !selected.includes(card));
      while (healing < requiredHealth && remaining.length >= 2) {
        selected.push(remaining.shift()!, remaining.shift()!); healing++;
      }
    }
    return healing >= requiredHealth ? selected : [];
  }

  private resolveRescue(state: MatchState, userId: string, cardIds: string[]): void {
    const pending = state.pendingBang;
    if (!pending || pending.actionType !== "rescue" || pending.targetId !== userId || state.phase !== "waiting_response") throw Error("Không có tình huống cứu mạng hợp lệ.");
    const player = this.player(state, userId);
    if (new Set(cardIds).size !== cardIds.length || cardIds.some((card) => !player.hand.includes(card))) throw Error("Lá cứu mạng không hợp lệ.");
    const beerAllowed = state.players.filter((candidate) => candidate.alive).length > 2;
    const beers = beerAllowed ? cardIds.filter((card) => typeOf(card) === "beer") : [];
    const sidCards = cardIds.filter((card) => !beers.includes(card));
    const healing = beers.length + (player.characterId === "sid_ketchum" ? Math.floor(sidCards.length / 2) : 0);
    const required = pending.requiredHealth ?? 1;
    if (player.characterId === "sid_ketchum" && sidCards.length % 2 !== 0) throw Error("Sid Ketchum phải bỏ bài theo từng cặp.");
    if (cardIds.length > 0 && healing !== required) throw Error(`Phải hồi đúng ${required} máu để sống.`);
    if (cardIds.length > 0) {
      player.hand = player.hand.filter((card) => !cardIds.includes(card));
      player.cardCount = player.hand.length;
      state.discard.push(...cardIds);
      player.health += healing;
      state.publicLog.push(`${player.name} tự cứu và còn ${player.health} máu.`);
    } else {
      const actor = state.players.find((candidate) => candidate.id === pending.actorId);
      this.eliminate(state, player, actor, pending.causedByPlayer === true);
    }
    this.resumeAfterRescue(state, pending);
  }

  private eliminate(state: MatchState, target: Player, actor: Player | undefined, causedByPlayer: boolean): void {
    const loot = [...target.hand, ...target.equipment];
    target.alive = false; target.health = 0; target.hand = []; target.equipment = []; target.cardCount = 0;
    const vulture = state.players.find((player) => player.alive && player.characterId === "vulture_sam");
    if (vulture && loot.length > 0) {
      vulture.hand.push(...loot); vulture.cardCount = vulture.hand.length;
    } else {
      state.discard.push(...loot);
    }
    state.publicLog.push(`${target.name} bị loại và lật vai trò ${target.role}.`);
    if (causedByPlayer && actor) {
      if (target.role === "outlaw") {
        this.drawFor(state, actor, 3);
        state.publicLog.push(`${actor.name} nhận thưởng 3 lá vì hạ Cướp.`);
      } else if (actor.role === "sheriff" && target.role === "deputy") {
        state.discard.push(...actor.hand, ...actor.equipment);
        actor.hand = []; actor.equipment = []; actor.cardCount = 0; this.refreshAttackRange(actor);
        state.publicLog.push(`${actor.name} mất toàn bộ bài vì hạ Phó cảnh sát.`);
      }
    }
    this.checkWin(state, actor?.id ?? target.id);
  }

  private resumeAfterRescue(state: MatchState, rescue: PendingBang): void {
    const original = rescue.resumePending;
    state.pendingBang = undefined;
    if (state.status !== "playing") return;
    state.pendingBang = original;
    if (original) {
      if (original.actionType === "duello") this.finishPendingResponse(state, original);
      else this.advancePendingResponse(state, original);
      return;
    }
    state.pendingBang = undefined;
    state.phase = rescue.resumePhase ?? "play_phase";
    const current = state.players.find((player) => player.id === state.currentTurnPlayerId);
    if (current) this.restoreTurnAlarm(state, current);
  }
  private takeCards(state: MatchState, amount: number): string[] {
    const cards: string[] = [];
    while (cards.length < amount) {
      if (state.deck.length === 0) {
        if (state.discard.length === 0) break;
        state.deck = shuffle(state.discard);
        state.discard = [];
        state.publicLog.push("Chồng bài bỏ đã được xáo lại thành chồng bài rút.");
      }
      const card = state.deck.shift();
      if (card) cards.push(card);
    }
    return cards;
  }
  private drawFor(state: MatchState, player: Player, amount: number): void { const cards = this.takeCards(state, amount); player.hand.push(...cards); player.cardCount = player.hand.length; }
  private maybeSuzy(state: MatchState, player: Player): void {
    if (player.alive && player.characterId === "suzy_lafayette" && player.hand.length === 0 && (state.deck.length > 0 || state.discard.length > 0)) {
      this.drawFor(state, player, 1); state.publicLog.push(`${player.name} kích hoạt Suzy Lafayette.`);
    }
  }
  private checkWin(state: MatchState, actorId: string): void {
    const alive = state.players.filter((player) => player.alive); const sheriff = state.players.find((player) => player.role === "sheriff")!;
    if (!sheriff.alive) { const loneRenegade = alive.length === 1 && alive[0].role === "renegade"; state.winner = loneRenegade ? "renegade" : "outlaws"; }
    else if (!state.players.some((player) => player.alive && (player.role === "outlaw" || player.role === "renegade"))) state.winner = "law";
    if (state.winner) { state.status = "finished"; state.phase = "game_over"; state.publicLog.push(`Kết thúc: ${state.winner}.`); }
  }
  private nextAlivePlayer(state: MatchState, currentId: string): Player {
    const alive = state.players.filter((player) => player.alive).sort((a, b) => a.seat - b.seat);
    const index = alive.findIndex((player) => player.id === currentId);
    return alive[(index + 1) % alive.length];
  }
  private aliveOrderFrom(state: MatchState, firstId: string): Player[] {
    const alive = state.players.filter((player) => player.alive).sort((a, b) => a.seat - b.seat);
    const index = alive.findIndex((player) => player.id === firstId);
    if (index < 0) return alive;
    return [...alive.slice(index), ...alive.slice(0, index)];
  }
  private isWeapon(cardId: string): boolean {
    const type = typeOf(cardId);
    return type === "volcanic" || type.startsWith("gun_range");
  }
  private refreshAttackRange(player: Player): void {
    const ranges = player.equipment
      .filter((card) => typeOf(card).startsWith("gun_range"))
      .map((card) => Number(typeOf(card).at(-1) || 1));
    player.attackRange = Math.max(1, ...ranges);
  }
  private nextAlivePlayerWithout(state: MatchState, currentId: string, equipmentType: string): Player | undefined {
    const alive = state.players.filter((player) => player.alive).sort((a, b) => a.seat - b.seat);
    const index = alive.findIndex((player) => player.id === currentId);
    for (let offset = 1; offset < alive.length; offset++) {
      const candidate = alive[(index + offset) % alive.length];
      if (!candidate.equipment.some((card) => typeOf(card) === equipmentType)) return candidate;
    }
    return undefined;
  }
  private distance(state: MatchState, actor: Player, target: Player): number {
    const alive = state.players.filter((player) => player.alive);
    const a = alive.indexOf(actor), b = alive.indexOf(target);
    const base = Math.min((b - a + alive.length) % alive.length, (a - b + alive.length) % alive.length);
    const modifier =
      (actor.characterId === "rose_doolan" ? -1 : 0) +
      (target.characterId === "paul_regret" ? 1 : 0) +
      (actor.equipment.some((card) => typeOf(card) === "appaloosa") ? -1 : 0) +
      (target.equipment.some((card) => typeOf(card) === "mustang") ? 1 : 0);
    return Math.max(1, base + modifier);
  }
  private player(state: MatchState, id: string): Player { const player = state.players.find((item) => item.id === id); if (!player) throw Error("Không tìm thấy người chơi."); return player; }
  private requireTurn(state: MatchState, userId: string, phase: Phase): void { if (state.status !== "playing" || state.phase !== phase || state.currentTurnPlayerId !== userId) throw Error("Không phải lượt hợp lệ."); }
  private async load(required = true): Promise<MatchState> { const state = this.stateData ?? await this.ctx.storage.get<MatchState>("match"); if (!state && required) throw Error("Không tìm thấy phòng."); if (state) this.stateData = state; return state!; }
  private async save(state: MatchState): Promise<void> {
    state.publicLog = state.publicLog.slice(-100);
    this.stateData = state;
    await this.ctx.storage.put("match", state);
    const summary: RoomSummary = {
      id: state.id,
      code: state.code,
      hostId: state.hostId,
      maxPlayers: state.maxPlayers,
      turnDurationSeconds: state.turnDurationSeconds,
      status: state.status,
      phase: state.phase,
      totalCount: state.players.length,
      botCount: state.players.filter((player) => player.bot).length,
      updatedAt: Date.now(),
    };
    await this.env.DIRECTORY.getByName("lobby").fetch(
      new Request("https://directory/upsert", {
        method: "POST",
        body: JSON.stringify(summary),
      }),
    );
    this.broadcast(state);
  }
  private websocket(request: Request, user: User): Response { if (request.headers.get("Upgrade") !== "websocket") return fail("Expected WebSocket", 426); const pair = new WebSocketPair(); const [client, server] = Object.values(pair); server.serializeAttachment(user); this.ctx.acceptWebSocket(server); void this.load().then((state) => server.send(JSON.stringify({ type: "state", room: this.snapshot(state, user.id) }))); return new Response(null, { status: 101, webSocket: client }); }
  private broadcast(state: MatchState): void { for (const ws of this.ctx.getWebSockets()) { const user = ws.deserializeAttachment() as User | null; if (user) ws.send(JSON.stringify({ type: "state", room: this.snapshot(state, user.id) })); } }
  private setupDeckFor(cards: SetupCard[] | undefined, userId: string): SetupCard[] | undefined {
    return cards?.map((card) => ({
      id: card.id,
      value: card.pickedBy === userId ? card.value : "",
      pickedBy: card.pickedBy,
    }));
  }
  private snapshot(state: MatchState, userId: string) {
    const me = state.players.find((player) => player.id === userId);
    const sheriffPlayerId = state.players.find((player) => player.role === "sheriff")?.id;
    return {
      ...state,
      deck: undefined,
      sheriffPlayerId,
      roleDeck: this.setupDeckFor(state.roleDeck, userId),
      characterDeck: this.setupDeckFor(state.characterDeck, userId),
      players: state.players.map(({ hand, role, characterOptions, characterChosen, ...player }) => ({
        ...player,
        revealedRole: role === "sheriff" || !player.alive ? role : undefined,
        role: player.id === userId ? role : undefined,
        hand: player.id === userId ? hand : undefined,
        characterOptions: player.id === userId ? characterOptions : undefined,
        characterChosen: player.id === userId ? characterChosen : undefined,
      })),
      hand: me?.hand ?? [],
    };
  }
}

async function sign(user: User, secret: string): Promise<string> { const payload = textToBase64(JSON.stringify({ ...user, exp: Date.now() + 1000 * 60 * 60 * 24 * 30 })); return `${payload}.${await signatureFor(payload, secret)}`; }
async function signatureFor(payload: string, secret: string): Promise<string> { const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]); const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)); return toBase64(new Uint8Array(signature)); }
async function authenticate(request: Request, secret: string): Promise<User | null> { const token = request.headers.get("authorization")?.replace("Bearer ", "") ?? new URL(request.url).searchParams.get("token"); if (!token) return null; const [payload, signature] = token.split("."); if (!payload || !signature || signature !== await signatureFor(payload, secret)) return null; const user = JSON.parse(base64ToText(payload)) as User & { exp: number }; return user.exp > Date.now() ? { id: user.id, name: user.name } : null; }
function toBase64(bytes: Uint8Array): string { let result = ""; for (const byte of bytes) result += String.fromCharCode(byte); return btoa(result); }
function textToBase64(value: string): string { return toBase64(new TextEncoder().encode(value)); }
function base64ToText(value: string): string { return new TextDecoder().decode(Uint8Array.from(atob(value), (char) => char.charCodeAt(0))); }
