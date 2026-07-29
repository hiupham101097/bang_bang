var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/index.ts
import { DurableObject } from "cloudflare:workers";
var json = /* @__PURE__ */ __name((value, status = 200) => new Response(JSON.stringify(value), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*" }
}), "json");
var fail = /* @__PURE__ */ __name((message, status = 400) => json({ error: message }, status), "fail");
var code = /* @__PURE__ */ __name(() => crypto.randomUUID().replaceAll("-", "").slice(0, 6).toUpperCase(), "code");
var shuffle = /* @__PURE__ */ __name((values) => {
  const copy = [...values];
  for (let index = copy.length - 1; index > 0; index--) {
    const swap = crypto.getRandomValues(new Uint32Array(1))[0] % (index + 1);
    [copy[index], copy[swap]] = [copy[swap], copy[index]];
  }
  return copy;
}, "shuffle");
var typeOf = /* @__PURE__ */ __name((card) => card.split("_")[0] === "gun" ? card.split("_").slice(0, 3).join("_") : card.split("_")[0], "typeOf");
var deck = /* @__PURE__ */ __name(() => {
  const types = [
    ...Array(12).fill("bang"),
    ...Array(8).fill("dodge"),
    ...Array(5).fill("beer"),
    ...Array(3).fill("panico"),
    ...Array(3).fill("cat_balou"),
    ...Array(2).fill("dilizenza"),
    "wells_fargo",
    ...Array(2).fill("general_store"),
    ...Array(2).fill("duello"),
    "gatling",
    ...Array(2).fill("indiani"),
    "saloon",
    "barrel",
    "jail",
    "dynamite",
    "volcanic",
    "gun_range_2",
    "gun_range_3",
    "gun_range_4",
    "gun_range_5",
    "mustang",
    "appaloosa"
  ];
  const ranks = ["ace", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king"];
  const suits = ["spade", "club", "diamond", "heart"];
  let index = 0;
  return suits.flatMap((suit) => ranks.map((rank) => `${types[index++]}_${rank}_${suit}`));
}, "deck");
var roles = /* @__PURE__ */ __name((count) => {
  if (count === 4) return ["sheriff", "deputy", "outlaw", "outlaw"];
  const police = Math.floor((count - 1) / 2);
  return ["sheriff", ...Array(police - 1).fill("deputy"), ...Array(count - police - 1).fill("outlaw"), "renegade"];
}, "roles");
var src_default = {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "GET,POST,OPTIONS", "access-control-allow-headers": "authorization,content-type" } });
    const url = new URL(request.url);
    if (url.pathname === "/health") return json({ ok: true, service: "bangbang-match-server" });
    if (request.method === "POST" && url.pathname === "/v1/session") {
      const body = await request.json();
      if (!body.deviceId || body.deviceId.length < 8) return fail("Thi\u1EBFu deviceId.");
      const user2 = { id: body.deviceId, name: (body.displayName || "Cao b\u1ED3i").slice(0, 24) };
      return json({ token: await sign(user2, env.AUTH_SECRET), user: user2 });
    }
    const user = await authenticate(request, env.AUTH_SECRET);
    if (!user) return fail("Phi\xEAn \u0111\u0103ng nh\u1EADp kh\xF4ng h\u1EE3p l\u1EC7.", 401);
    if (request.method === "POST" && url.pathname === "/v1/rooms") {
      const body = await request.json();
      const roomCode = code();
      const stub2 = env.MATCH.get(env.MATCH.idFromName(roomCode));
      return stub2.fetch(new Request("https://match/internal/create", { method: "POST", body: JSON.stringify({ user, code: roomCode, maxPlayers: body.maxPlayers, turnDurationSeconds: body.turnDurationSeconds }) }));
    }
    const match = url.pathname.match(/^\/v1\/rooms\/([A-Z0-9]+)(?:\/(ws))?$/);
    if (!match) return fail("Kh\xF4ng t\xECm th\u1EA5y API.", 404);
    const stub = env.MATCH.get(env.MATCH.idFromName(match[1]));
    const headers = new Headers(request.headers);
    headers.set("x-bangbang-user", JSON.stringify(user));
    return stub.fetch(new Request(`https://match/${match[2] === "ws" ? "ws" : "command"}`, { method: request.method, headers, body: request.body }));
  }
};
var BangBangMatch = class extends DurableObject {
  static {
    __name(this, "BangBangMatch");
  }
  stateData;
  constructor(ctx, env) {
    super(ctx, env);
  }
  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path === "/internal/create") return this.create(request);
    const user = JSON.parse(request.headers.get("x-bangbang-user") || "null");
    if (!user) return fail("Unauthorized", 401);
    if (path === "/ws") return this.websocket(request, user);
    if (path !== "/command" || request.method !== "POST") return fail("Not found", 404);
    return this.command(user, await request.json());
  }
  async webSocketMessage(ws, message) {
    if (typeof message !== "string") return;
    const user = ws.deserializeAttachment();
    if (!user) return;
    try {
      await this.apply(user, JSON.parse(message));
    } catch (error) {
      ws.send(JSON.stringify({ type: "error", error: error instanceof Error ? error.message : "L\u1ED7i m\xE1y ch\u1EE7" }));
    }
  }
  webSocketClose(ws) {
    ws.close();
  }
  async alarm() {
    const state = await this.load();
    if (state.phase === "waiting_response" && state.pendingBang && Date.now() >= state.pendingBang.deadline) {
      this.damage(state, state.pendingBang.targetId, state.pendingBang.actorId, "Kh\xF4ng N\xE9 k\u1ECBp");
      state.pendingBang = void 0;
      if (state.status === "playing") state.phase = "play_phase";
      await this.save(state);
    } else if (state.status === "playing" && state.phase !== "waiting_response") {
      await this.advanceTurn(state, "H\u1EBFt gi\u1EDD");
    }
  }
  async create(request) {
    const data = await request.json();
    const existing = await this.load(false);
    if (existing) return fail("M\xE3 ph\xF2ng tr\xF9ng, h\xE3y t\u1EA1o l\u1EA1i.", 409);
    const maxPlayers = Math.max(4, Math.min(8, Number(data.maxPlayers || 4)));
    const host = { id: data.user.id, name: data.user.name, seat: 0, bot: false, ready: false, alive: true, health: 0, maxHealth: 0, cardCount: 0, hand: [], equipment: [], attackRange: 1 };
    const state = { id: data.code, code: data.code, hostId: host.id, maxPlayers, turnDurationSeconds: Math.max(20, Number(data.turnDurationSeconds || 45)), status: "waiting", phase: "lobby", players: [host], deck: [], discard: [], turnNumber: 0, bangUsedThisTurn: 0, publicLog: ["Ph\xF2ng \u0111\xE3 \u0111\u01B0\u1EE3c t\u1EA1o."] };
    await this.save(state);
    return json({ room: this.snapshot(state, data.user.id) }, 201);
  }
  async command(user, command) {
    try {
      const state = await this.apply(user, command);
      return json({ room: this.snapshot(state, user.id) });
    } catch (error) {
      return fail(error instanceof Error ? error.message : "L\u1ED7i m\xE1y ch\u1EE7");
    }
  }
  async apply(user, command) {
    const state = await this.load();
    const payload = command.payload ?? {};
    if (command.action === "join") {
      if (state.status !== "waiting" || state.players.length >= state.maxPlayers) throw Error("Ph\xF2ng \u0111\xE3 \u0111\u1EA7y ho\u1EB7c \u0111\xE3 b\u1EAFt \u0111\u1EA7u.");
      if (!state.players.some((player) => player.id === user.id)) state.players.push({ id: user.id, name: user.name, seat: state.players.length, bot: false, ready: false, alive: true, health: 0, maxHealth: 0, cardCount: 0, hand: [], equipment: [], attackRange: 1 });
    } else {
      const player = state.players.find((item) => item.id === user.id);
      if (!player) throw Error("B\u1EA1n ch\u01B0a \u1EDF trong ph\xF2ng n\xE0y.");
      if (command.action === "ready") {
        if (state.status !== "waiting") throw Error("Tr\u1EADn \u0111\xE3 b\u1EAFt \u0111\u1EA7u.");
        player.ready = Boolean(payload.ready);
      } else if (command.action === "add_bot") {
        if (user.id !== state.hostId || state.status !== "waiting" || state.players.length >= state.maxPlayers) throw Error("Kh\xF4ng th\u1EC3 th\xEAm bot.");
        const seat = state.players.length;
        state.players.push({ id: `bot_${crypto.randomUUID()}`, name: `Bot ${seat}`, seat, bot: true, ready: true, alive: true, health: 0, maxHealth: 0, cardCount: 0, hand: [], equipment: [], attackRange: 1 });
      } else if (command.action === "start") this.start(state, user.id);
      else if (command.action === "draw") this.draw(state, user.id);
      else if (command.action === "play") this.play(state, user.id, String(payload.cardId || ""), String(payload.targetPlayerId || ""));
      else if (command.action === "respond_bang") this.respondBang(state, user.id, String(payload.response || "damage"), String(payload.cardId || ""));
      else if (command.action === "end_turn") await this.endTurn(state, user.id);
      else if (command.action === "discard") this.discardCards(state, user.id, Array.isArray(payload.cardIds) ? payload.cardIds.map(String) : []);
    }
    await this.save(state);
    return state;
  }
  start(state, userId) {
    if (state.hostId !== userId || state.status !== "waiting") throw Error("Ch\u1EC9 ch\u1EE7 ph\xF2ng \u0111\u01B0\u1EE3c b\u1EAFt \u0111\u1EA7u.");
    if (state.players.length < 4) throw Error("C\u1EA7n \u0111\u1EE7 4\u20138 ng\u01B0\u1EDDi ch\u01A1i.");
    if (state.players.some((player) => !player.bot && player.id !== userId && !player.ready)) throw Error("Kh\xE1ch ch\u01B0a s\u1EB5n s\xE0ng.");
    const assigned = shuffle(roles(state.players.length));
    const cards = shuffle(deck());
    let cursor = 0;
    state.players.forEach((player, index) => {
      player.role = assigned[index];
      player.characterId = void 0;
      player.maxHealth = player.role === "sheriff" ? 5 : 4;
      player.health = player.maxHealth;
      player.hand = cards.slice(cursor, cursor += player.health);
      player.cardCount = player.hand.length;
      player.alive = true;
      player.attackRange = 1;
      player.equipment = [];
    });
    state.deck = cards.slice(cursor);
    state.discard = [];
    state.status = "playing";
    state.phase = "turn_start";
    state.currentTurnPlayerId = state.players.find((player) => player.role === "sheriff").id;
    state.turnNumber = 1;
    state.bangUsedThisTurn = 0;
    state.publicLog.push("Tr\u1EADn \u0111\u1EA5u b\u1EAFt \u0111\u1EA7u.");
    void this.ctx.storage.setAlarm(Date.now() + state.turnDurationSeconds * 1e3);
  }
  draw(state, userId) {
    this.requireTurn(state, userId, "turn_start");
    const player = this.player(state, userId);
    const cards = state.deck.splice(0, 2);
    player.hand.push(...cards);
    player.cardCount = player.hand.length;
    state.phase = "play_phase";
    state.publicLog.push(`${player.name} r\xFAt 2 l\xE1.`);
  }
  play(state, userId, cardId, targetId) {
    this.requireTurn(state, userId, "play_phase");
    const actor = this.player(state, userId);
    const type = typeOf(cardId);
    const at = actor.hand.indexOf(cardId);
    if (at < 0) throw Error("B\u1EA1n kh\xF4ng c\xF3 l\xE1 b\xE0i n\xE0y.");
    if (type === "bang") {
      if (state.bangUsedThisTurn > 0 && !actor.equipment.some((card) => card.startsWith("volcanic"))) throw Error("M\u1ED7i l\u01B0\u1EE3t ch\u1EC9 d\xF9ng 1 BANG.");
      const target = this.player(state, targetId);
      if (!target.alive || target.id === actor.id || this.distance(state, actor, target) > actor.attackRange) throw Error("M\u1EE5c ti\xEAu ngo\xE0i t\u1EA7m b\u1EAFn.");
      actor.hand.splice(at, 1);
      actor.cardCount = actor.hand.length;
      state.discard.push(cardId);
      state.bangUsedThisTurn++;
      state.phase = "waiting_response";
      state.pendingBang = { id: crypto.randomUUID(), actorId: actor.id, targetId: target.id, deadline: Date.now() + 1e4, requiredDodges: actor.characterId === "slab_the_killer" ? 2 : 1 };
      state.publicLog.push(`${actor.name} BANG ${target.name}.`);
      void this.ctx.storage.setAlarm(state.pendingBang.deadline);
    } else if (type === "beer") {
      if (actor.health >= actor.maxHealth) throw Error("M\xE1u \u0111\xE3 \u0111\u1EA7y.");
      actor.hand.splice(at, 1);
      actor.cardCount = actor.hand.length;
      actor.health++;
      state.discard.push(cardId);
      state.publicLog.push(`${actor.name} h\u1ED3i 1 m\xE1u.`);
    } else if (type.startsWith("gun_range")) {
      actor.hand.splice(at, 1);
      actor.cardCount = actor.hand.length;
      actor.equipment = [...actor.equipment.filter((card) => !card.startsWith("gun_range")), cardId];
      actor.attackRange = Number(type.at(-1) || 1);
      state.publicLog.push(`${actor.name} trang b\u1ECB s\xFAng.`);
    } else throw Error("Th\u1EBB n\xE0y s\u1EBD \u0111\u01B0\u1EE3c m\u1EDF \u1EDF b\u01B0\u1EDBc hi\u1EC7u \u1EE9ng n\xE2ng cao.");
  }
  respondBang(state, userId, response, cardId) {
    const pending = state.pendingBang;
    if (!pending || pending.targetId !== userId || state.phase !== "waiting_response") throw Error("Kh\xF4ng c\xF3 BANG c\u1EA7n ph\u1EA3n \u1EE9ng.");
    const target = this.player(state, userId);
    if (response === "dodge") {
      const dodges = target.hand.filter((card) => typeOf(card) === "dodge");
      if (dodges.length < pending.requiredDodges) throw Error("Kh\xF4ng \u0111\u1EE7 l\xE1 N\xE9.");
      const spent = pending.requiredDodges === 1 ? [cardId] : dodges.slice(0, 2);
      if (spent.some((card) => !target.hand.includes(card) || typeOf(card) !== "dodge")) throw Error("L\xE1 N\xE9 kh\xF4ng h\u1EE3p l\u1EC7.");
      target.hand = target.hand.filter((card) => !spent.includes(card));
      target.cardCount = target.hand.length;
      state.discard.push(...spent);
      state.publicLog.push(`${target.name} \u0111\xE3 N\xE9.`);
    } else this.damage(state, target.id, pending.actorId, "BANG tr\xFAng");
    state.pendingBang = void 0;
    if (state.status === "playing") state.phase = "play_phase";
  }
  async endTurn(state, userId) {
    this.requireTurn(state, userId, "play_phase");
    const player = this.player(state, userId);
    if (player.hand.length > player.health) {
      state.phase = "discard_phase";
      return;
    }
    await this.advanceTurn(state, "K\u1EBFt th\xFAc l\u01B0\u1EE3t");
  }
  discardCards(state, userId, cards) {
    this.requireTurn(state, userId, "discard_phase");
    const player = this.player(state, userId);
    const required = player.hand.length - player.health;
    if (cards.length !== required || cards.some((card) => !player.hand.includes(card))) throw Error(`Ph\u1EA3i b\u1ECF \u0111\xFAng ${required} l\xE1.`);
    player.hand = player.hand.filter((card) => !cards.includes(card));
    player.cardCount = player.hand.length;
    state.discard.push(...cards);
    state.phase = "turn_start";
    void this.advanceTurn(state, "B\u1ECF b\xE0i");
  }
  async advanceTurn(state, reason) {
    const alive = state.players.filter((player) => player.alive).sort((a, b) => a.seat - b.seat);
    const index = alive.findIndex((player) => player.id === state.currentTurnPlayerId);
    state.currentTurnPlayerId = alive[(index + 1) % alive.length].id;
    state.turnNumber++;
    state.bangUsedThisTurn = 0;
    state.phase = "turn_start";
    state.publicLog.push(reason);
    void this.ctx.storage.setAlarm(Date.now() + state.turnDurationSeconds * 1e3);
  }
  damage(state, targetId, actorId, log) {
    const target = this.player(state, targetId);
    target.health--;
    state.publicLog.push(`${log}: ${target.name}.`);
    if (target.health > 0) return;
    target.alive = false;
    target.hand = [];
    target.cardCount = 0;
    state.publicLog.push(`${target.name} b\u1ECB lo\u1EA1i.`);
    this.checkWin(state, actorId);
  }
  checkWin(state, actorId) {
    const alive = state.players.filter((player) => player.alive);
    const sheriff = state.players.find((player) => player.role === "sheriff");
    if (!sheriff.alive) {
      const loneRenegade = alive.length === 1 && alive[0].role === "renegade";
      state.winner = loneRenegade ? "renegade" : "outlaws";
    } else if (!state.players.some((player) => player.alive && (player.role === "outlaw" || player.role === "renegade"))) state.winner = "law";
    if (state.winner) {
      state.status = "finished";
      state.phase = "game_over";
      state.publicLog.push(`K\u1EBFt th\xFAc: ${state.winner}.`);
    }
  }
  distance(state, actor, target) {
    const alive = state.players.filter((player) => player.alive);
    const a = alive.indexOf(actor), b = alive.indexOf(target);
    return Math.max(1, Math.min((b - a + alive.length) % alive.length, (a - b + alive.length) % alive.length));
  }
  player(state, id) {
    const player = state.players.find((item) => item.id === id);
    if (!player) throw Error("Kh\xF4ng t\xECm th\u1EA5y ng\u01B0\u1EDDi ch\u01A1i.");
    return player;
  }
  requireTurn(state, userId, phase) {
    if (state.status !== "playing" || state.phase !== phase || state.currentTurnPlayerId !== userId) throw Error("Kh\xF4ng ph\u1EA3i l\u01B0\u1EE3t h\u1EE3p l\u1EC7.");
  }
  async load(required = true) {
    const state = this.stateData ?? await this.ctx.storage.get("match");
    if (!state && required) throw Error("Kh\xF4ng t\xECm th\u1EA5y ph\xF2ng.");
    if (state) this.stateData = state;
    return state;
  }
  async save(state) {
    state.publicLog = state.publicLog.slice(-30);
    this.stateData = state;
    await this.ctx.storage.put("match", state);
    this.broadcast(state);
  }
  websocket(request, user) {
    if (request.headers.get("Upgrade") !== "websocket") return fail("Expected WebSocket", 426);
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.serializeAttachment(user);
    this.ctx.acceptWebSocket(server);
    void this.load().then((state) => server.send(JSON.stringify({ type: "state", room: this.snapshot(state, user.id) })));
    return new Response(null, { status: 101, webSocket: client });
  }
  broadcast(state) {
    for (const ws of this.ctx.getWebSockets()) {
      const user = ws.deserializeAttachment();
      if (user) ws.send(JSON.stringify({ type: "state", room: this.snapshot(state, user.id) }));
    }
  }
  snapshot(state, userId) {
    const me = state.players.find((player) => player.id === userId);
    return { ...state, deck: void 0, players: state.players.map(({ hand, role, ...player }) => ({ ...player, revealedRole: role === "sheriff" ? role : void 0, role: player.id === userId ? role : void 0, hand: player.id === userId ? hand : void 0 })), hand: me?.hand ?? [] };
  }
};
async function sign(user, secret) {
  const payload = btoa(JSON.stringify({ ...user, exp: Date.now() + 1e3 * 60 * 60 * 24 * 30 }));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return `${payload}.${toBase64(new Uint8Array(signature))}`;
}
__name(sign, "sign");
async function authenticate(request, secret) {
  const token = request.headers.get("authorization")?.replace("Bearer ", "") ?? new URL(request.url).searchParams.get("token");
  if (!token) return null;
  const [payload, signature] = token.split(".");
  if (!payload || !signature) return null;
  const expected = await sign(JSON.parse(atob(payload)), secret);
  if (expected !== token) return null;
  const user = JSON.parse(atob(payload));
  return user.exp > Date.now() ? { id: user.id, name: user.name } : null;
}
__name(authenticate, "authenticate");
function toBase64(bytes) {
  let result = "";
  for (const byte of bytes) result += String.fromCharCode(byte);
  return btoa(result);
}
__name(toBase64, "toBase64");

// node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    const body = JSON.stringify(error);
    const headers = {
      "Content-Type": "application/json",
      "MF-Experimental-Error-Stack": "true"
    };
    const encoded = encodeURIComponent(body);
    if (encoded.length <= 8192) {
      headers["MF-Experimental-Error-Stack-Payload"] = encoded;
    }
    return new Response(body, { status: 500, headers });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-awOOgx/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = src_default;

// node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-awOOgx/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class ___Facade_ScheduledController__ {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  scheduledTime;
  cron;
  static {
    __name(this, "__Facade_ScheduledController__");
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof ___Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = /* @__PURE__ */ __name((request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    }, "#fetchDispatcher");
    #dispatcher = /* @__PURE__ */ __name((type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    }, "#dispatcher");
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  BangBangMatch,
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
//# sourceMappingURL=index.js.map
