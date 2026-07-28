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
exports.runBotResponse = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/firestore");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();
/** Resolves public choices and reactions whenever the waiting player is a bot. */
exports.runBotResponse = (0, firestore_1.onDocumentWritten)("rooms/{roomId}/pendingActions/{actionId}", async (event) => {
    const actionData = event.data?.after.data();
    if (!actionData || actionData.status !== "waiting")
        return;
    const room = db.doc(`rooms/${event.params.roomId}`);
    const actionRef = room
        .collection("pendingActions")
        .doc(event.params.actionId);
    await db.runTransaction(async (tx) => {
        const [state, action] = await Promise.all([
            tx.get(room),
            tx.get(actionRef),
        ]);
        if (!state.exists || !action.exists || action.get("status") !== "waiting")
            return;
        const type = String(action.get("actionType") ?? "");
        const responderId = String(type === "general_store"
            ? (action.get("currentPickerId") ?? "")
            : type === "duello"
                ? (action.get("currentResponderId") ?? "")
                : (action.get("currentTargetId") ?? ""));
        if (!responderId)
            return;
        const player = await tx.get(room.collection("players").doc(responderId));
        if (!player.exists || player.get("playerType") !== "bot")
            return;
        const privateState = await tx.get(room.collection("privateStates").doc(responderId));
        if (type === "general_store") {
            if (state.get("phase") !== "waiting_general_store_selection")
                return;
            const opened = [...(action.get("openedCardIds") ?? [])];
            const chosen = opened[0];
            if (!chosen)
                return;
            const hand = [...(privateState.get("handCardIds") ?? []), chosen];
            const remaining = opened.slice(1);
            const order = action.get("playerOrder");
            const nextPicker = order[order.indexOf(responderId) + 1];
            tx.update(privateState.ref, { handCardIds: hand });
            tx.update(player.ref, { cardCount: hand.length });
            if (nextPicker && remaining.length) {
                tx.update(action.ref, {
                    openedCardIds: remaining,
                    currentPickerId: nextPicker,
                });
            }
            else {
                tx.delete(action.ref);
                tx.update(room, { phase: "play_phase", updatedAt: now() });
            }
            return;
        }
        if (type === "gatling" || type === "indiani") {
            if (state.get("phase") !== "waiting_multi_response")
                return;
            const deck = await tx.get(room.collection("serverState").doc("deck"));
            const hand = [...(privateState.get("handCardIds") ?? [])];
            const needed = type === "gatling" ? "dodge_" : "bang_";
            const responseCard = hand.find((card) => card.startsWith(needed)) ?? "";
            const discard = [...(deck.get("discardPile") ?? [])];
            var health = Number(player.get("health") ?? 0);
            if (responseCard) {
                const nextHand = hand.filter((card) => card !== responseCard);
                discard.push(responseCard);
                tx.update(privateState.ref, { handCardIds: nextHand });
                tx.update(player.ref, { cardCount: nextHand.length });
            }
            else {
                health--;
                tx.update(player.ref, { health });
            }
            const order = action.get("targetOrder");
            const nextIndex = Number(action.get("targetIndex") ?? 0) + 1;
            const nextTarget = order[nextIndex];
            tx.update(deck.ref, { discardPile: discard });
            if (health <= 0) {
                tx.delete(action.ref);
                tx.update(room, {
                    phase: "dying",
                    dyingPlayerId: responderId,
                    discardCount: discard.length,
                    discardTopCardId: discard.at(-1) ?? null,
                    updatedAt: now(),
                });
            }
            else if (nextTarget) {
                tx.update(action.ref, {
                    targetIndex: nextIndex,
                    currentTargetId: nextTarget,
                });
            }
            else {
                tx.delete(action.ref);
                tx.update(room, {
                    phase: "play_phase",
                    discardCount: discard.length,
                    discardTopCardId: discard.at(-1) ?? null,
                    updatedAt: now(),
                });
            }
            return;
        }
        if (type !== "duello" || state.get("phase") !== "waiting_duel_response") {
            return;
        }
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        const hand = [...(privateState.get("handCardIds") ?? [])];
        const bang = hand.find((card) => card.startsWith("bang_")) ?? "";
        if (bang) {
            const nextHand = hand.filter((card) => card !== bang);
            const other = action.get("actorPlayerId") === responderId
                ? action.get("opponentPlayerId")
                : action.get("actorPlayerId");
            tx.update(privateState.ref, { handCardIds: nextHand });
            tx.update(player.ref, { cardCount: nextHand.length });
            tx.update(deck.ref, {
                discardPile: [...(deck.get("discardPile") ?? []), bang],
            });
            tx.update(action.ref, { currentResponderId: other });
        }
        else {
            const health = Number(player.get("health") ?? 0) - 1;
            tx.update(player.ref, { health });
            tx.delete(action.ref);
            tx.update(room, {
                phase: health <= 0 ? "dying" : "play_phase",
                dyingPlayerId: health <= 0 ? responderId : admin.firestore.FieldValue.delete(),
                updatedAt: now(),
            });
        }
    });
});
