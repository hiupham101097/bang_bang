import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/https";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();
const typeOf = (id: string) =>
  [
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
const requireUser = (request: { auth?: { uid: string } }) => {
  if (!request.auth)
    throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  return request.auth.uid;
};
const roomId = (data: { roomId?: unknown }) => {
  if (typeof data.roomId !== "string")
    throw new HttpsError("invalid-argument", "Thiếu roomId.");
  return data.roomId;
};
const remove = (cards: string[], card: string) => {
  const index = cards.indexOf(card);
  if (index < 0)
    throw new HttpsError("permission-denied", "Bạn không sở hữu lá bài này.");
  return [...cards.slice(0, index), ...cards.slice(index + 1)];
};
const appendPublicLog = (
  state: FirebaseFirestore.DocumentSnapshot,
  entry: string,
) => [...(state.get("publicLog") ?? []), entry].slice(-20);

export const drawTurnCards = onCall(async (request) => {
  const uid = requireUser(request);
  const id = roomId(request.data);
  const actionId = String(request.data.actionId ?? "");
  if (!actionId) throw new HttpsError("invalid-argument", "Thiếu actionId.");
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    const player = await tx.get(room.collection("players").doc(uid));
    const privateState = await tx.get(
      room.collection("privateStates").doc(uid),
    );
    const deck = await tx.get(room.collection("serverState").doc("deck"));
    const action = await tx.get(room.collection("actions").doc(actionId));
    if (
      !state.exists ||
      state.get("status") !== "playing" ||
      state.get("currentTurnPlayerId") !== uid ||
      state.get("phase") !== "turn_start" ||
      Number(state.get("judgmentsResolvedForTurn") ?? 0) !==
        Number(state.get("turnNumber") ?? 0) ||
      !player.exists ||
      player.get("isAlive") === false ||
      action.exists
    )
      throw new HttpsError("failed-precondition", "Không thể rút bài.");
    const pile = [...(deck.get("drawPile") ?? [])] as string[];
    const hand = [...(privateState.get("handCardIds") ?? [])] as string[];
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

export const playCard = onCall(async (request) => {
  const uid = requireUser(request);
  const id = roomId(request.data);
  const cardId = String(request.data.cardId ?? "");
  const targetId = request.data.targetPlayerId as string | undefined;
  const actionId = String(request.data.actionId ?? "");
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    const actor = await tx.get(room.collection("players").doc(uid));
    const handState = await tx.get(room.collection("privateStates").doc(uid));
    const deck = await tx.get(room.collection("serverState").doc("deck"));
    const action = await tx.get(room.collection("actions").doc(actionId));
    if (
      !state.exists ||
      state.get("phase") !== "play_phase" ||
      state.get("currentTurnPlayerId") !== uid ||
      !actor.exists ||
      action.exists
    )
      throw new HttpsError("failed-precondition", "Không thể dùng bài.");
    const type = typeOf(cardId);
    const hand = [...(handState.get("handCardIds") ?? [])] as string[];
    const nextHand = remove(hand, cardId);
    const discard = [...(deck.get("discardPile") ?? []), cardId];
    if (type === "beer") {
      if (actor.get("health") >= actor.get("maxHealth"))
        throw new HttpsError("failed-precondition", "Máu đang đầy.");
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
    } else if (type.startsWith("gun_range_")) {
      const old = actor.get("weaponCardId") as string | undefined;
      if (old) discard.push(old);
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
    } else if (type === "bang") {
      if (
        !targetId ||
        (state.get("bangUsedThisTurn") >= 1 &&
          actor.get("characterId") !== "willy_the_kid" &&
          !actor.get("unlimitedBang"))
      )
        throw new HttpsError("failed-precondition", "Bang không hợp lệ.");
      const target = await tx.get(room.collection("players").doc(targetId));
      const all = await tx.get(room.collection("players"));
      const alive = all.docs
        .filter((p) => p.get("isAlive") !== false)
        .sort((a, b) => a.get("seat") - b.get("seat"));
      const a = alive.findIndex((p) => p.id === uid),
        b = alive.findIndex((p) => p.id === targetId);
      const baseDistance = Math.min(
        (b - a + alive.length) % alive.length,
        (a - b + alive.length) % alive.length,
      );
      const distance = Math.max(
        1,
        baseDistance +
          (actor.get("characterId") === "rose_doolan" ? -1 : 0) +
          (target.get("characterId") === "paul_regret" ? 1 : 0) +
          Number(actor.get("distanceToOthersModifier") ?? 0) +
          Number(target.get("distanceFromOthersModifier") ?? 0),
      );
      if (
        !target.exists ||
        targetId === uid ||
        target.get("isAlive") === false ||
        distance > (actor.get("attackRange") ?? 1)
      )
        throw new HttpsError("failed-precondition", "Mục tiêu ngoài tầm.");
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
        responseDeadlineAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + 8000,
        ),
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
    } else
      throw new HttpsError(
        "failed-precondition",
        "Lá này chưa được mở ở Giai đoạn 3.",
      );
    tx.set(action.ref, { uid, type: "play", createdAt: now() });
  });
  return {};
});

export const respondToAction = onCall(async (request) => {
  const uid = requireUser(request);
  const id = roomId(request.data);
  const pendingId = String(request.data.pendingActionId ?? "");
  const response = String(request.data.responseType ?? "damage");
  const cardId = request.data.cardId as string | undefined;
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    const pending = await tx.get(
      room.collection("pendingActions").doc(pendingId),
    );
    const target = await tx.get(room.collection("players").doc(uid));
    const privateState = await tx.get(
      room.collection("privateStates").doc(uid),
    );
    const deck = await tx.get(room.collection("serverState").doc("deck"));
    if (
      !pending.exists ||
      pending.get("targetPlayerId") !== uid ||
      pending.get("status") !== "waiting"
    )
      throw new HttpsError("failed-precondition", "Phản ứng không hợp lệ.");
    if (response === "missed" && Number(pending.get("requiredDodges") ?? 1) > 1)
      throw new HttpsError(
        "failed-precondition",
        "Bang này cần 2 lá Né để tránh.",
      );
    let health = target.get("health");
    if (response === "missed") {
      if (!cardId || typeOf(cardId) !== "dodge")
        throw new HttpsError("invalid-argument", "Cần lá Né.");
      const hand = remove([...(privateState.get("handCardIds") ?? [])], cardId);
      tx.update(privateState.ref, { handCardIds: hand });
      tx.update(target.ref, { cardCount: hand.length });
      tx.update(deck.ref, {
        discardPile: [...(deck.get("discardPile") ?? []), cardId],
      });
    } else health--;
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
    } else {
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

const nextAlive = (
  players: FirebaseFirestore.QueryDocumentSnapshot[],
  current: string,
) => {
  const alive = players
    .filter((p) => p.get("isAlive") !== false)
    .sort((a, b) => a.get("seat") - b.get("seat"));
  const at = alive.findIndex((p) => p.id === current);
  return alive[(at + 1) % alive.length];
};
export const requestEndTurn = onCall(async (request) => {
  const uid = requireUser(request);
  const id = roomId(request.data);
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    const player = await tx.get(room.collection("players").doc(uid));
    const hand = await tx.get(room.collection("privateStates").doc(uid));
    if (
      !state.exists ||
      state.get("phase") !== "play_phase" ||
      state.get("currentTurnPlayerId") !== uid ||
      !state.get("hasDrawnThisTurn")
    )
      throw new HttpsError("failed-precondition", "Không thể kết thúc lượt.");
    const excess =
      (hand.get("handCardIds") ?? []).length - player.get("health");
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
      turnDeadlineAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000,
      ),
      updatedAt: now(),
    });
  });
  return {};
});
export const discardCards = onCall(async (request) => {
  const uid = requireUser(request);
  const id = roomId(request.data);
  const ids = request.data.cardIds as string[];
  if (!Array.isArray(ids) || new Set(ids).size !== ids.length)
    throw new HttpsError("invalid-argument", "Bài bỏ không hợp lệ.");
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    const player = await tx.get(room.collection("players").doc(uid));
    const privateState = await tx.get(
      room.collection("privateStates").doc(uid),
    );
    const deck = await tx.get(room.collection("serverState").doc("deck"));
    const hand = [...(privateState.get("handCardIds") ?? [])] as string[];
    if (
      !state.exists ||
      state.get("phase") !== "discard_phase" ||
      state.get("currentTurnPlayerId") !== uid ||
      ids.length !== hand.length - player.get("health") ||
      !ids.every((card) => hand.includes(card))
    )
      throw new HttpsError("failed-precondition", "Số bài bỏ không đúng.");
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
      turnDeadlineAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000,
      ),
      updatedAt: now(),
    });
  });
  return {};
});

export const resolveTurnTimeout = onCall(async (request) => {
  requireUser(request);
  const id = roomId(request.data);
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    if (!state.exists || state.get("status") !== "playing") return;
    const deadline = state.get("turnDeadlineAt") as
      admin.firestore.Timestamp | undefined;
    const phase = state.get("phase") as string;
    if (
      !deadline ||
      deadline.toMillis() > Date.now() ||
      !["turn_start", "play_phase", "discard_phase"].includes(phase)
    )
      return;

    const currentId = String(state.get("currentTurnPlayerId") ?? "");
    const player = await tx.get(room.collection("players").doc(currentId));
    const privateState = await tx.get(
      room.collection("privateStates").doc(currentId),
    );
    const deck = await tx.get(room.collection("serverState").doc("deck"));
    if (!player.exists || player.get("isAlive") === false) return;

    const pile = [...(deck.get("drawPile") ?? [])] as string[];
    const discard = [...(deck.get("discardPile") ?? [])] as string[];
    let hand = [...(privateState.get("handCardIds") ?? [])] as string[];
    if (phase === "turn_start") hand = [...hand, ...pile.splice(0, 2)];
    while (hand.length > Number(player.get("health") ?? 0))
      discard.push(hand.pop()!);

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
      turnDeadlineAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000,
      ),
      updatedAt: now(),
    });
  });
  return {};
});

export const resolveDying = onCall(async (request) => {
  const uid = requireUser(request);
  const id = roomId(request.data);
  const useBeer = request.data.useBeer === true;
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    const player = await tx.get(room.collection("players").doc(uid));
    const privateState = await tx.get(
      room.collection("privateStates").doc(uid),
    );
    const deck = await tx.get(room.collection("serverState").doc("deck"));
    if (
      !state.exists ||
      state.get("phase") !== "dying" ||
      state.get("dyingPlayerId") !== uid
    )
      throw new HttpsError("failed-precondition", "Không hấp hối.");
    const hand = [...(privateState.get("handCardIds") ?? [])] as string[];
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
    } else tx.update(player.ref, { health: 0, isAlive: false });
  });
  return {};
});

/** Any living player may spend a Beer to save the player currently dying. */
export const saveDyingPlayer = onCall(async (request) => {
  const uid = requireUser(request);
  const id = roomId(request.data);
  const targetId = String(request.data.targetPlayerId ?? "");
  const cardId = String(request.data.cardId ?? "");
  if (!targetId || !cardId || typeOf(cardId) !== "beer")
    throw new HttpsError("invalid-argument", "Cần một lá Beer hợp lệ.");
  const room = db.doc(`rooms/${id}`);
  await db.runTransaction(async (tx) => {
    const state = await tx.get(room);
    const helper = await tx.get(room.collection("players").doc(uid));
    const target = await tx.get(room.collection("players").doc(targetId));
    const helperState = await tx.get(room.collection("privateStates").doc(uid));
    const deck = await tx.get(room.collection("serverState").doc("deck"));
    if (!state.exists || state.get("phase") !== "dying" || state.get("dyingPlayerId") !== targetId || !helper.exists || helper.get("isAlive") === false || !target.exists)
      throw new HttpsError("failed-precondition", "Không thể cứu người chơi lúc này.");
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
