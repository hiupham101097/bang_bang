import * as admin from "firebase-admin";
import { onDocumentUpdated } from "firebase-functions/firestore";
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

export const resolveElimination = onDocumentUpdated(
  "rooms/{roomId}/players/{playerId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (
      !before ||
      !after ||
      before.isAlive === false ||
      after.isAlive !== false
    )
      return;
    const roomRef = db.doc(`rooms/${event.params.roomId}`);
    const eliminatedId = event.params.playerId;
    await db.runTransaction(async (tx) => {
      const room = await tx.get(roomRef);
      if (!room.exists || room.get("status") !== "playing") return;
      const eliminated = await tx.get(
        roomRef.collection("players").doc(eliminatedId),
      );
      const privateState = await tx.get(
        roomRef.collection("privateStates").doc(eliminatedId),
      );
      const deck = await tx.get(roomRef.collection("serverState").doc("deck"));
      const role = privateState.get("role") as string | undefined;
      const hand = [...(privateState.get("handCardIds") ?? [])] as string[];
      const equipment = [
        eliminated.get("weaponCardId"),
        eliminated.get("barrelCardId"),
        eliminated.get("mustangCardId"),
        eliminated.get("appaloosaCardId"),
        eliminated.get("dynamiteCardId"),
        eliminated.get("jailCardId"),
        ...(eliminated.get("equipmentCardIds") ?? []),
      ].filter(Boolean) as string[];
      const players = (await tx.get(roomRef.collection("players"))).docs;
      const states = await Promise.all(
        players.map((p) =>
          tx.get(roomRef.collection("privateStates").doc(p.id)),
        ),
      );
      const vulture = players.find(
        (p, i) =>
          p.get("isAlive") !== false &&
          states[i].get("selectedCharacterId") === "vulture_sam",
      );
      if (vulture) {
        const vs = states[players.findIndex((p) => p.id === vulture.id)];
        tx.update(vs.ref, {
          handCardIds: [
            ...(vs.get("handCardIds") ?? []),
            ...hand,
            ...equipment,
          ],
        });
        tx.update(vulture.ref, {
          cardCount:
            (vs.get("handCardIds") ?? []).length +
            hand.length +
            equipment.length,
        });
      } else
        tx.update(deck.ref, {
          discardPile: [
            ...(deck.get("discardPile") ?? []),
            ...hand,
            ...equipment,
          ],
        });
      tx.update(eliminated.ref, {
        health: 0,
        revealedRole: role ?? "unknown",
        cardCount: 0,
        weaponCardId: admin.firestore.FieldValue.delete(),
        barrelCardId: admin.firestore.FieldValue.delete(),
        mustangCardId: admin.firestore.FieldValue.delete(),
        appaloosaCardId: admin.firestore.FieldValue.delete(),
        dynamiteCardId: admin.firestore.FieldValue.delete(),
        jailCardId: admin.firestore.FieldValue.delete(),
        equipmentCardIds: [],
      });
      tx.update(privateState.ref, { handCardIds: [] });
      const alive = players.filter(
        (p) => p.id !== eliminatedId && p.get("isAlive") !== false,
      );
      const roles = new Map<string, string>();
      states.forEach((s, i) => roles.set(players[i].id, s.get("role")));
      const sheriffAlive = alive.some((p) => roles.get(p.id) === "sheriff");
      const outlaws = alive.filter((p) => roles.get(p.id) === "outlaw");
      const renegades = alive.filter((p) => roles.get(p.id) === "renegade");
      let winner: string | null = null;
      if (alive.length === 1 && roles.get(alive[0].id) === "renegade")
        winner = "Kẻ phản bội";
      else if (sheriffAlive && !outlaws.length && !renegades.length)
        winner = "Phe Cảnh sát";
      else if (!sheriffAlive) winner = "Phe Kẻ cướp";
      const eliminatedSeat = Number(eliminated.get("seat") ?? 0);
      const orderedAlive = [...alive].sort(
        (a, b) => Number(a.get("seat")) - Number(b.get("seat")),
      );
      const nextPlayer =
        orderedAlive.find(
          (player) => Number(player.get("seat")) > eliminatedSeat,
        ) ?? orderedAlive.at(0);
      const eliminatedWasCurrent =
        room.get("currentTurnPlayerId") === eliminatedId;
      tx.update(
        roomRef,
        winner
          ? { status: "finished", phase: "game_over", winner, endedAt: now() }
          : eliminatedWasCurrent && nextPlayer
            ? {
                phase: "turn_start",
                currentTurnPlayerId: nextPlayer.id,
                turnNumber: Number(room.get("turnNumber") ?? 0) + 1,
                bangUsedThisTurn: 0,
                cardsPlayedThisTurn: 0,
                hasDrawnThisTurn: false,
                discardRequired: 0,
                turnStartedAt: now(),
                turnDeadlineAt: admin.firestore.Timestamp.fromMillis(
                  Date.now() +
                    Number(room.get("turnDurationSeconds") ?? 60) * 1000,
                ),
                updatedAt: now(),
              }
            : { phase: "play_phase", updatedAt: now() },
      );
    });
  },
);
