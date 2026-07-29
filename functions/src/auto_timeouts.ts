import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated, onDocumentWritten } from "firebase-functions/firestore";

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();
const appendPublicLog = (
  state: FirebaseFirestore.DocumentSnapshot,
  entry: string,
) => [...(state.get("publicLog") ?? []), entry].slice(-20);

const nextAlive = (
  players: FirebaseFirestore.QueryDocumentSnapshot[],
  currentId: string,
) => {
  const alive = players
    .filter((player) => player.get("isAlive") !== false)
    .sort((a, b) => Number(a.get("seat")) - Number(b.get("seat")));
  const index = alive.findIndex((player) => player.id === currentId);
  return alive[(index + 1) % alive.length];
};

/// Server-owned timeout for a pending BANG response. The final transaction is
/// idempotent: a manual NÉ or damage response wins if it arrives first.
export const expireBangResponse = onDocumentCreated(
  {
    document: "rooms/{roomId}/pendingActions/{actionId}",
    timeoutSeconds: 60,
  },
  async (event) => {
    const created = event.data?.data();
    if (!created || created.actionType !== "bang") return;
    const deadline = created.responseDeadlineAt as
      | admin.firestore.Timestamp
      | undefined;
    if (!deadline) return;

    const delay = Math.max(0, deadline.toMillis() - Date.now());
    if (delay > 0) await new Promise<void>((resolve) => setTimeout(resolve, delay));

    const room = db.doc(`rooms/${event.params.roomId}`);
    const pendingRef = room.collection("pendingActions").doc(event.params.actionId);
    await db.runTransaction(async (tx) => {
      const [state, pending] = await Promise.all([tx.get(room), tx.get(pendingRef)]);
      if (!state.exists || !pending.exists || pending.get("status") !== "waiting") return;
      const currentDeadline = pending.get("responseDeadlineAt") as
        | admin.firestore.Timestamp
        | undefined;
      if (!currentDeadline || currentDeadline.toMillis() > Date.now()) return;

      const targetId = String(pending.get("targetPlayerId") ?? "");
      const target = await tx.get(room.collection("players").doc(targetId));
      if (!target.exists || target.get("isAlive") === false) {
        tx.delete(pendingRef);
        tx.update(room, { phase: "play_phase", updatedAt: now() });
        return;
      }
      const health = Number(target.get("health") ?? 0) - 1;
      tx.update(target.ref, {
        health,
        lastDamageBy: String(pending.get("actorPlayerId") ?? ""),
      });
      tx.delete(pendingRef);
      tx.update(room, {
        phase: health <= 0 ? "dying" : "play_phase",
        dyingPlayerId:
          health <= 0 ? targetId : admin.firestore.FieldValue.delete(),
        publicLog: appendPublicLog(
          state,
          `damage:${targetId}:bang:${pending.get("actorPlayerId") ?? ""}`,
        ),
        updatedAt: now(),
      });
    });
  },
);

/// Re-arms on every target/responder change for Gatling, Indians and Duel.
export const expireSequentialResponse = onDocumentWritten(
  { document: "rooms/{roomId}/pendingActions/{actionId}", timeoutSeconds: 60 },
  async (event) => {
    const action = event.data?.after.data();
    const type = String(action?.actionType ?? "");
    if (!action || !["gatling", "indiani", "duello"].includes(type)) return;
    const deadline = action.responseDeadlineAt as admin.firestore.Timestamp | undefined;
    if (!deadline) return;
    const delay = Math.max(0, deadline.toMillis() - Date.now());
    if (delay > 0) await new Promise<void>((resolve) => setTimeout(resolve, delay));
    const room = db.doc(`rooms/${event.params.roomId}`);
    const ref = room.collection("pendingActions").doc(event.params.actionId);
    await db.runTransaction(async (tx) => {
      const [state, pending] = await Promise.all([tx.get(room), tx.get(ref)]);
      if (!state.exists || !pending.exists) return;
      const currentDeadline = pending.get("responseDeadlineAt") as admin.firestore.Timestamp | undefined;
      if (!currentDeadline || currentDeadline.toMillis() > Date.now()) return;
      const isDuel = pending.get("actionType") === "duello";
      const targetId = String(pending.get(isDuel ? "currentResponderId" : "currentTargetId") ?? "");
      const target = await tx.get(room.collection("players").doc(targetId));
      if (!target.exists) return;
      const health = Number(target.get("health") ?? 0) - 1;
      tx.update(target.ref, { health, lastDamageBy: pending.get("actorPlayerId") ?? "" });
      if (isDuel || health <= 0) {
        tx.delete(ref);
        tx.update(room, { phase: health <= 0 ? "dying" : "play_phase", dyingPlayerId: health <= 0 ? targetId : admin.firestore.FieldValue.delete(), updatedAt: now() });
        return;
      }
      const order = pending.get("targetOrder") as string[];
      const nextIndex = Number(pending.get("targetIndex") ?? 0) + 1;
      const next = order[nextIndex];
      if (!next) {
        tx.delete(ref); tx.update(room, { phase: "play_phase", updatedAt: now() }); return;
      }
      tx.update(ref, { targetIndex: nextIndex, currentTargetId: next, responseDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + 8000) });
    });
  },
);

/// Server-owned turn timeout. It is only armed when a new deadline is written.
export const expireTurn = onDocumentUpdated(
  { document: "rooms/{roomId}", timeoutSeconds: 120 },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const deadline = after?.turnDeadlineAt as admin.firestore.Timestamp | undefined;
    const oldDeadline = before?.turnDeadlineAt as admin.firestore.Timestamp | undefined;
    if (
      !after ||
      after.status !== "playing" ||
      !deadline ||
      deadline.toMillis() === oldDeadline?.toMillis()
    ) {
      return;
    }
    const delay = Math.max(0, deadline.toMillis() - Date.now());
    if (delay > 0) await new Promise<void>((resolve) => setTimeout(resolve, delay));

    const room = db.doc(`rooms/${event.params.roomId}`);
    await db.runTransaction(async (tx) => {
      const state = await tx.get(room);
      if (!state.exists || state.get("status") !== "playing") return;
      const currentDeadline = state.get("turnDeadlineAt") as
        | admin.firestore.Timestamp
        | undefined;
      const phase = String(state.get("phase") ?? "");
      if (
        !currentDeadline ||
        currentDeadline.toMillis() > Date.now() ||
        !["turn_start", "play_phase", "discard_phase"].includes(phase)
      ) {
        return;
      }
      const currentId = String(state.get("currentTurnPlayerId") ?? "");
      const player = await tx.get(room.collection("players").doc(currentId));
      const privateState = await tx.get(room.collection("privateStates").doc(currentId));
      const deck = await tx.get(room.collection("serverState").doc("deck"));
      if (!player.exists || player.get("isAlive") === false) return;

      const pile = [...(deck.get("drawPile") ?? [])] as string[];
      const discard = [...(deck.get("discardPile") ?? [])] as string[];
      let hand = [...(privateState.get("handCardIds") ?? [])] as string[];
      if (phase === "turn_start") hand = [...hand, ...pile.splice(0, 2)];
      while (hand.length > Number(player.get("health") ?? 0)) discard.push(hand.pop()!);

      const players = (await tx.get(room.collection("players"))).docs;
      const next = nextAlive(players, currentId);
      if (!next) return;
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
        publicLog: appendPublicLog(state, `timeout:${currentId}`),
        turnStartedAt: now(),
        turnDeadlineAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000,
        ),
        updatedAt: now(),
      });
    });
  },
);
