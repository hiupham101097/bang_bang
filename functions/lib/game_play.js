"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.saveDyingPlayer = exports.resolveDying = exports.resolveTurnTimeout = exports.discardCards = exports.requestEndTurn = exports.respondToAction = exports.playCard = exports.drawTurnCards = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/https");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();
const typeOf = (id) => [
    "gun_range_2",
    "gun_range_3",
    "gun_range_4",
    "gun_range_5",
    "bang",
    "dodge",
    "beer",
    "dilizenza",
    "wells_fargo",
    "saloon",
    "barrel",
    "jail",
    "dynamite",
    "volcanic",
    "mustang",
    "appaloosa",
    "panico",
    "cat_balou",
    "general_store",
    "duello",
    "gatling",
    "indiani",
].find((type) => id === type || id.startsWith("${type}_")) ?? "locked";
const requireUser = (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
    return request.auth.uid;
};
const roomId = (data) => {
    if (typeof data.roomId !== "string")
        throw new https_1.HttpsError("invalid-argument", "Thiếu roomId.");
    return data.roomId;
};
const remove = (cards, card) => {
    const index = cards.indexOf(card);
    if (index < 0)
        throw new https_1.HttpsError("permission-denied", "Bạn không sở hữu lá bài này.");
    return [...cards.slice(0, index), ...cards.slice(index + 1)];
};
const appendPublicLog = (state, entry) => [...(state.get("publicLog") ?? []), entry].slice(-20);
exports.drawTurnCards = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const id = roomId(request.data);
    const actionId = String(request.data.actionId ?? "");
    if (!actionId)
        throw new https_1.HttpsError("invalid-argument", "Thiếu actionId.");
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection("players").doc(uid));
        const privateState = await tx.get(room.collection("privateStates").doc(uid));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        const action = await tx.get(room.collection("actions").doc(actionId));
        if (!state.exists ||
            state.get("status") !== "playing" ||
            state.get("currentTurnPlayerId") !== uid ||
            state.get("phase") !== "turn_start" ||
            Number(state.get("judgmentsResolvedForTurn") ?? 0) !==
                Number(state.get("turnNumber") ?? 0) ||
            !player.exists ||
            player.get("isAlive") === false ||
            action.exists)
            throw new https_1.HttpsError("failed-precondition", "Không thể rút bài.");
        const pile = [...(deck.get("drawPile") ?? [])];
        const hand = [...(privateState.get("handCardIds") ?? [])];
        const drawn = pile.splice(0, 2);
        tx.set(action.ref, { uid, type: "draw", createdAt: now() });
        tx.update(privateState.ref, { handCardIds: [...hand, ...drawn] });
        tx.update(deck.ref, { drawPile: pile });
        tx.update(player.ref, { cardCount: hand.length + drawn.length });
        tx.update(room, {
            phase: "play_phase",
            hasDrawnThisTurn: true,
            cardsDrawnThisTurn: drawn.length,
            bangUsedThisTurn: 0,
            cardsPlayedThisTurn: 0,
            deckRemainingCount: pile.length,
            publicLog: appendPublicLog(state, `draw:${uid}`),
            updatedAt: now(),
        });
    });
    return {};
});
exports.playCard = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const id = roomId(request.data);
    const cardId = String(request.data.cardId ?? "");
    const targetId = request.data.targetPlayerId;
    const actionId = String(request.data.actionId ?? "");
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const actor = await tx.get(room.collection("players").doc(uid));
        const handState = await tx.get(room.collection("privateStates").doc(uid));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        const action = await tx.get(room.collection("actions").doc(actionId));
        if (!state.exists ||
            state.get("phase") !== "play_phase" ||
            state.get("currentTurnPlayerId") !== uid ||
            !actor.exists ||
            action.exists)
            throw new https_1.HttpsError("failed-precondition", "Không thể dùng bài.");
        const type = typeOf(cardId);
        const hand = [...(handState.get("handCardIds") ?? [])];
        const nextHand = remove(hand, cardId);
        const discard = [...(deck.get("discardPile") ?? []), cardId];
        if (type === "beer") {
            if (actor.get("health") >= actor.get("maxHealth"))
                throw new https_1.HttpsError("failed-precondition", "Máu đang đầy.");
            tx.update(actor.ref, {
                health: Math.min(actor.get("health") + 1, actor.get("maxHealth")),
                cardCount: nextHand.length,
            });
            tx.update(handState.ref, { handCardIds: nextHand });
            tx.update(deck.ref, { discardPile: discard });
            tx.update(room, {
                discardCount: discard.length,
                discardTopCardId: cardId,
                cardsPlayedThisTurn: 1,
                publicLog: appendPublicLog(state, `play:${uid}:${cardId}`),
                updatedAt: now(),
            });
        }
        else if (type.startsWith("gun_range_")) {
            const old = actor.get("weaponCardId");
            if (old)
                discard.push(old);
            const range = Number(type.replace("gun_range_", ""));
            tx.update(actor.ref, {
                weaponCardId: cardId,
                attackRange: range,
                cardCount: nextHand.length,
            });
            tx.update(handState.ref, { handCardIds: nextHand });
            tx.update(deck.ref, { discardPile: discard });
            tx.update(room, {
                discardCount: discard.length,
                discardTopCardId: old ?? cardId,
                cardsPlayedThisTurn: 1,
                publicLog: appendPublicLog(state, `equip:${uid}:${cardId}`),
                updatedAt: now(),
            });
        }
        else if (type === "bang") {
            if (!targetId ||
                (state.get("bangUsedThisTurn") >= 1 &&
                    actor.get("characterId") !== "willy_the_kid" &&
                    !actor.get("unlimitedBang")))
                throw new https_1.HttpsError("failed-precondition", "Bang không hợp lệ.");
            const target = await tx.get(room.collection("players").doc(targetId));
            const all = await tx.get(room.collection("players"));
            const alive = all.docs
                .filter((p) => p.get("isAlive") !== false)
                .sort((a, b) => a.get("seat") - b.get("seat"));
            const a = alive.findIndex((p) => p.id === uid), b = alive.findIndex((p) => p.id === targetId);
            const baseDistance = Math.min((b - a + alive.length) % alive.length, (a - b + alive.length) % alive.length);
            const distance = Math.max(1, baseDistance +
                (actor.get("characterId") === "rose_doolan" ? -1 : 0) +
                (target.get("characterId") === "paul_regret" ? 1 : 0) +
                Number(actor.get("distanceToOthersModifier") ?? 0) +
                Number(target.get("distanceFromOthersModifier") ?? 0));
            if (!target.exists ||
                targetId === uid ||
                target.get("isAlive") === false ||
                distance > (actor.get("attackRange") ?? 1))
                throw new https_1.HttpsError("failed-precondition", "Mục tiêu ngoài tầm.");
            tx.update(handState.ref, { handCardIds: nextHand });
            tx.update(actor.ref, { cardCount: nextHand.length });
            tx.update(deck.ref, { discardPile: discard });
            tx.set(room.collection("pendingActions").doc(actionId), {
                actionId,
                actionType: "bang",
                actorPlayerId: uid,
                targetPlayerId: targetId,
                damage: 1,
                requiredDodges: actor.get("characterId") === "slab_the_killer" ? 2 : 1,
                status: "waiting",
                responseDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + 8000),
            });
            tx.update(room, {
                phase: "waiting_response",
                bangUsedThisTurn: Number(state.get("bangUsedThisTurn") ?? 0) + 1,
                cardsPlayedThisTurn: 1,
                discardCount: discard.length,
                discardTopCardId: cardId,
                publicLog: appendPublicLog(state, `play:${uid}:${cardId}:${targetId}`),
                updatedAt: now(),
            });
        }
        else
            throw new https_1.HttpsError("failed-precondition", "Lá này chưa được mở ở Giai đoạn 3.");
        tx.set(action.ref, { uid, type: "play", createdAt: now() });
    });
    return {};
});
exports.respondToAction = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const id = roomId(request.data);
    const pendingId = String(request.data.pendingActionId ?? "");
    const response = String(request.data.responseType ?? "damage");
    const cardId = request.data.cardId;
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const pending = await tx.get(room.collection("pendingActions").doc(pendingId));
        const target = await tx.get(room.collection("players").doc(uid));
        const privateState = await tx.get(room.collection("privateStates").doc(uid));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        if (!pending.exists ||
            pending.get("targetPlayerId") !== uid ||
            pending.get("status") !== "waiting")
            throw new https_1.HttpsError("failed-precondition", "Phản ứng không hợp lệ.");
        if (response === "missed" && Number(pending.get("requiredDodges") ?? 1) > 1)
            throw new https_1.HttpsError("failed-precondition", "Bang này cần 2 lá Né để tránh.");
        let health = target.get("health");
        if (response === "missed") {
            if (!cardId || typeOf(cardId) !== "dodge")
                throw new https_1.HttpsError("invalid-argument", "Cần lá Né.");
            const hand = remove([...(privateState.get("handCardIds") ?? [])], cardId);
            tx.update(privateState.ref, { handCardIds: hand });
            tx.update(target.ref, { cardCount: hand.length });
            tx.update(deck.ref, {
                discardPile: [...(deck.get("discardPile") ?? []), cardId],
            });
        }
        else
            health--;
        tx.delete(pending.ref);
        const outcomeLog = response === "missed"
            ? `dodge:${uid}:${cardId}:${pending.get("actorPlayerId") ?? ""}`
            : `damage:${uid}:bang:${pending.get("actorPlayerId") ?? ""}`;
        if (health <= 0) {
            tx.update(target.ref, {
                health,
                lastDamageBy: String(pending.get("actorPlayerId") ?? ""),
            });
            tx.update(room, {
                phase: "dying",
                dyingPlayerId: uid,
                publicLog: appendPublicLog(state, outcomeLog),
                updatedAt: now(),
            });
        }
        else {
            if (response !== "missed") {
                tx.update(target.ref, {
                    health,
                    lastDamageBy: String(pending.get("actorPlayerId") ?? ""),
                });
            }
            tx.update(room, {
                phase: "play_phase",
                publicLog: appendPublicLog(state, outcomeLog),
                updatedAt: now(),
            });
        }
    });
    return {};
});
const nextAlive = (players, current) => {
    const alive = players
        .filter((p) => p.get("isAlive") !== false)
        .sort((a, b) => a.get("seat") - b.get("seat"));
    const at = alive.findIndex((p) => p.id === current);
    return alive[(at + 1) % alive.length];
};
exports.requestEndTurn = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const id = roomId(request.data);
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection("players").doc(uid));
        const hand = await tx.get(room.collection("privateStates").doc(uid));
        if (!state.exists ||
            state.get("phase") !== "play_phase" ||
            state.get("currentTurnPlayerId") !== uid ||
            !state.get("hasDrawnThisTurn"))
            throw new https_1.HttpsError("failed-precondition", "Không thể kết thúc lượt.");
        const excess = (hand.get("handCardIds") ?? []).length - player.get("health");
        if (excess > 0) {
            tx.update(room, {
                phase: "discard_phase",
                discardRequired: excess,
                updatedAt: now(),
            });
            return;
        }
        const players = (await tx.get(room.collection("players"))).docs;
        const next = nextAlive(players, uid);
        tx.update(room, {
            phase: "turn_start",
            currentTurnPlayerId: next.id,
            turnNumber: Number(state.get("turnNumber") ?? 0) + 1,
            bangUsedThisTurn: 0,
            cardsPlayedThisTurn: 0,
            hasDrawnThisTurn: false,
            turnStartedAt: now(),
            turnDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000),
            updatedAt: now(),
        });
    });
    return {};
});
exports.discardCards = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const id = roomId(request.data);
    const ids = request.data.cardIds;
    if (!Array.isArray(ids) || new Set(ids).size !== ids.length)
        throw new https_1.HttpsError("invalid-argument", "Bài bỏ không hợp lệ.");
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection("players").doc(uid));
        const privateState = await tx.get(room.collection("privateStates").doc(uid));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        const hand = [...(privateState.get("handCardIds") ?? [])];
        if (!state.exists ||
            state.get("phase") !== "discard_phase" ||
            state.get("currentTurnPlayerId") !== uid ||
            ids.length !== hand.length - player.get("health") ||
            !ids.every((card) => hand.includes(card)))
            throw new https_1.HttpsError("failed-precondition", "Số bài bỏ không đúng.");
        const keep = hand.filter((card) => !ids.includes(card));
        const players = (await tx.get(room.collection("players"))).docs;
        const next = nextAlive(players, uid);
        tx.update(privateState.ref, { handCardIds: keep });
        tx.update(player.ref, { cardCount: keep.length });
        tx.update(deck.ref, {
            discardPile: [...(deck.get("discardPile") ?? []), ...ids],
        });
        tx.update(room, {
            phase: "turn_start",
            currentTurnPlayerId: next.id,
            turnNumber: Number(state.get("turnNumber") ?? 0) + 1,
            bangUsedThisTurn: 0,
            cardsPlayedThisTurn: 0,
            hasDrawnThisTurn: false,
            discardRequired: 0,
            turnStartedAt: now(),
            turnDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000),
            updatedAt: now(),
        });
    });
    return {};
});
exports.resolveTurnTimeout = (0, https_1.onCall)(async (request) => {
    requireUser(request);
    const id = roomId(request.data);
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        if (!state.exists || state.get("status") !== "playing")
            return;
        const deadline = state.get("turnDeadlineAt");
        const phase = state.get("phase");
        if (!deadline ||
            deadline.toMillis() > Date.now() ||
            !["turn_start", "play_phase", "discard_phase"].includes(phase))
            return;
        const currentId = String(state.get("currentTurnPlayerId") ?? "");
        const player = await tx.get(room.collection("players").doc(currentId));
        const privateState = await tx.get(room.collection("privateStates").doc(currentId));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        if (!player.exists || player.get("isAlive") === false)
            return;
        const pile = [...(deck.get("drawPile") ?? [])];
        const discard = [...(deck.get("discardPile") ?? [])];
        let hand = [...(privateState.get("handCardIds") ?? [])];
        if (phase === "turn_start")
            hand = [...hand, ...pile.splice(0, 2)];
        while (hand.length > Number(player.get("health") ?? 0))
            discard.push(hand.pop());
        const players = (await tx.get(room.collection("players"))).docs;
        const next = nextAlive(players, currentId);
        tx.update(privateState.ref, { handCardIds: hand });
        tx.update(player.ref, { cardCount: hand.length });
        tx.update(deck.ref, { drawPile: pile, discardPile: discard });
        tx.update(room, {
            phase: "turn_start",
            currentTurnPlayerId: next.id,
            turnNumber: Number(state.get("turnNumber") ?? 0) + 1,
            bangUsedThisTurn: 0,
            cardsPlayedThisTurn: 0,
            hasDrawnThisTurn: false,
            discardRequired: 0,
            deckRemainingCount: pile.length,
            discardCount: discard.length,
            discardTopCardId: discard.at(-1) ?? null,
            turnStartedAt: now(),
            turnDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000),
            updatedAt: now(),
        });
    });
    return {};
});
exports.resolveDying = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const id = roomId(request.data);
    const useBeer = request.data.useBeer === true;
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection("players").doc(uid));
        const privateState = await tx.get(room.collection("privateStates").doc(uid));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        if (!state.exists ||
            state.get("phase") !== "dying" ||
            state.get("dyingPlayerId") !== uid)
            throw new https_1.HttpsError("failed-precondition", "Không hấp hối.");
        const hand = [...(privateState.get("handCardIds") ?? [])];
        const needed = 1 - Number(player.get("health"));
        const beers = hand.filter((card) => typeOf(card) === "beer");
        if (useBeer && beers.length >= needed) {
            const spent = beers.slice(0, needed);
            const keep = hand.filter((card) => !spent.includes(card));
            tx.update(privateState.ref, { handCardIds: keep });
            tx.update(player.ref, { health: 1, cardCount: keep.length });
            tx.update(deck.ref, {
                discardPile: [...(deck.get("discardPile") ?? []), ...spent],
            });
            tx.update(room, {
                phase: "play_phase",
                dyingPlayerId: admin.firestore.FieldValue.delete(),
                updatedAt: now(),
            });
        }
        else
            tx.update(player.ref, { health: 0, isAlive: false });
    });
    return {};
});
/** Any living player may spend a Beer to save the player currently dying. */
exports.saveDyingPlayer = (0, https_1.onCall)(async (request) => {
    const uid = requireUser(request);
    const id = roomId(request.data);
    const targetId = String(request.data.targetPlayerId ?? "");
    const cardId = String(request.data.cardId ?? "");
    if (!targetId || !cardId || typeOf(cardId) !== "beer")
        throw new https_1.HttpsError("invalid-argument", "Cần một lá Beer hợp lệ.");
    const room = db.doc(`rooms/${id}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const helper = await tx.get(room.collection("players").doc(uid));
        const target = await tx.get(room.collection("players").doc(targetId));
        const helperState = await tx.get(room.collection("privateStates").doc(uid));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        if (!state.exists || state.get("phase") !== "dying" || state.get("dyingPlayerId") !== targetId || !helper.exists || helper.get("isAlive") === false || !target.exists)
            throw new https_1.HttpsError("failed-precondition", "Không thể cứu người chơi lúc này.");
        const hand = remove([...(helperState.get("handCardIds") ?? [])], cardId);
        const discard = [...(deck.get("discardPile") ?? []), cardId];
        const health = Number(target.get("health") ?? 0) + 1;
        tx.update(helperState.ref, { handCardIds: hand });
        tx.update(helper.ref, { cardCount: hand.length });
        tx.update(target.ref, { health });
        tx.update(deck.ref, { discardPile: discard });
        tx.update(room, {
            phase: health >= 1 ? "play_phase" : "dying",
            dyingPlayerId: health >= 1 ? admin.firestore.FieldValue.delete() : targetId,
            discardCount: discard.length,
            discardTopCardId: cardId,
            publicLog: appendPublicLog(state, `save:${uid}:${cardId}:${targetId}`),
            updatedAt: now(),
        });
    });
    return {};
});
