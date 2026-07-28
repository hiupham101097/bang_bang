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
exports.runBotTurn = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/firestore");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();
const rankOf = (cardId) => cardId.split("_").at(-2) ?? "";
const suitOf = (cardId) => cardId.split("_").at(-1) ?? "";
const nextAlive = (players, currentId) => {
    const alive = players
        .filter((player) => player.get("isAlive") !== false)
        .sort((a, b) => Number(a.get("seat")) - Number(b.get("seat")));
    const index = alive.findIndex((player) => player.id === currentId);
    return alive[(index + 1) % alive.length];
};
/** Keeps bot-filled rooms moving without trusting a client to play for a bot. */
exports.runBotTurn = (0, firestore_1.onDocumentUpdated)("rooms/{roomId}", async (event) => {
    const roomId = event.params.roomId;
    const after = event.data?.after.data();
    if (!after ||
        after.status !== "playing" ||
        after.phase !== "turn_start" ||
        !after.currentTurnPlayerId)
        return;
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        if (!state.exists ||
            state.get("status") !== "playing" ||
            state.get("phase") !== "turn_start")
            return;
        const botId = String(state.get("currentTurnPlayerId") ?? "");
        const bot = await tx.get(room.collection("players").doc(botId));
        if (!bot.exists ||
            bot.get("playerType") !== "bot" ||
            bot.get("isAlive") === false)
            return;
        const privateState = await tx.get(room.collection("privateStates").doc(botId));
        const deck = await tx.get(room.collection("serverState").doc("deck"));
        const players = (await tx.get(room.collection("players"))).docs;
        const pile = [...(deck.get("drawPile") ?? [])];
        const discard = [...(deck.get("discardPile") ?? [])];
        if (Number(state.get("judgmentsResolvedForTurn") ?? 0) !==
            Number(state.get("turnNumber") ?? 0)) {
            const dynamite = bot.get("dynamiteCardId");
            if (dynamite && pile.length) {
                const judgment = pile.shift();
                discard.push(judgment);
                const explodes = suitOf(judgment) === "spade" &&
                    [
                        "two",
                        "three",
                        "four",
                        "five",
                        "six",
                        "seven",
                        "eight",
                        "nine",
                    ].includes(rankOf(judgment));
                if (explodes) {
                    const health = Number(bot.get("health") ?? 0) - 3;
                    tx.update(bot.ref, {
                        dynamiteCardId: admin.firestore.FieldValue.delete(),
                        health,
                    });
                    discard.push(dynamite);
                    tx.update(deck.ref, { drawPile: pile, discardPile: discard });
                    tx.update(room, {
                        phase: health <= 0 ? "dying" : "turn_start",
                        dyingPlayerId: health <= 0 ? botId : admin.firestore.FieldValue.delete(),
                        deckRemainingCount: pile.length,
                        discardCount: discard.length,
                        discardTopCardId: dynamite,
                        updatedAt: now(),
                    });
                    return;
                }
                const next = nextAlive(players, botId);
                tx.update(bot.ref, {
                    dynamiteCardId: admin.firestore.FieldValue.delete(),
                });
                if (next)
                    tx.update(next.ref, { dynamiteCardId: dynamite });
            }
            const jail = bot.get("jailCardId");
            if (jail && pile.length) {
                const judgment = pile.shift();
                discard.push(judgment, jail);
                tx.update(bot.ref, { jailCardId: admin.firestore.FieldValue.delete() });
                if (suitOf(judgment) !== "heart") {
                    const next = nextAlive(players, botId);
                    if (!next)
                        return;
                    tx.update(deck.ref, { drawPile: pile, discardPile: discard });
                    tx.update(room, {
                        phase: "turn_start",
                        currentTurnPlayerId: next.id,
                        turnNumber: Number(state.get("turnNumber") ?? 0) + 1,
                        bangUsedThisTurn: 0,
                        cardsPlayedThisTurn: 0,
                        hasDrawnThisTurn: false,
                        deckRemainingCount: pile.length,
                        discardCount: discard.length,
                        discardTopCardId: jail,
                        turnStartedAt: now(),
                        turnDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() +
                            Number(state.get("turnDurationSeconds") ?? 60) * 1000),
                        updatedAt: now(),
                    });
                    return;
                }
            }
            tx.update(deck.ref, { drawPile: pile, discardPile: discard });
            tx.update(room, {
                judgmentsResolvedForTurn: Number(state.get("turnNumber") ?? 0),
                deckRemainingCount: pile.length,
                discardCount: discard.length,
                discardTopCardId: discard.at(-1) ?? null,
                updatedAt: now(),
            });
            return;
        }
        let hand = [...(privateState.get("handCardIds") ?? [])];
        hand = [...hand, ...pile.splice(0, 2)];
        while (hand.length > Number(bot.get("health") ?? 0)) {
            discard.push(hand.pop());
        }
        const next = nextAlive(players, botId);
        if (!next)
            return;
        const publicLog = [...(state.get("publicLog") ?? []), `bot:${botId}`].slice(-20);
        tx.update(privateState.ref, { handCardIds: hand });
        tx.update(bot.ref, { cardCount: hand.length });
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
            publicLog,
            turnStartedAt: now(),
            turnDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + Number(state.get("turnDurationSeconds") ?? 60) * 1000),
            updatedAt: now(),
        });
    });
});
