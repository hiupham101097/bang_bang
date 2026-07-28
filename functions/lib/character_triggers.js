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
exports.applySuzyLafayette = exports.applyBartCassidyDamage = exports.setBangResponseDeadline = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/firestore");
const firestore_2 = require("firebase-functions/firestore");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
/** Bang reactions always receive a full ten-second decision window. */
exports.setBangResponseDeadline = (0, firestore_2.onDocumentCreated)('rooms/{roomId}/pendingActions/{actionId}', async (event) => {
    const action = event.data;
    if (!action?.exists || action.get('actionType') !== 'bang')
        return;
    await action.ref.update({
        responseDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10000),
    });
});
/** Bart Cassidy draws one card per health lost. Event ids make retries safe. */
exports.applyBartCassidyDamage = (0, firestore_1.onDocumentUpdated)('rooms/{roomId}/players/{playerId}', async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before?.exists || !after?.exists || after.get('characterId') !== 'bart_cassidy')
        return;
    const lost = Number(before.get('health') ?? 0) - Number(after.get('health') ?? 0);
    if (lost <= 0)
        return;
    const roomId = event.params.roomId;
    const uid = event.params.playerId;
    const room = db.doc(`rooms/${roomId}`);
    const marker = room.collection('actions').doc(`bart_${event.id}`);
    await db.runTransaction(async (tx) => {
        if ((await tx.get(marker)).exists)
            return;
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        const handState = await tx.get(room.collection('privateStates').doc(uid));
        const player = await tx.get(room.collection('players').doc(uid));
        const pile = [...(deck.get('drawPile') ?? [])];
        const drawn = pile.splice(0, Math.min(lost, pile.length));
        const hand = [...(handState.get('handCardIds') ?? []), ...drawn];
        tx.set(marker, { type: 'bart_damage', createdAt: admin.firestore.FieldValue.serverTimestamp() });
        tx.update(deck.ref, { drawPile: pile });
        tx.update(handState.ref, { handCardIds: hand });
        tx.update(player.ref, { cardCount: hand.length });
        tx.update(room, { deckRemainingCount: pile.length, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    });
});
/** Suzy Lafayette immediately draws one card whenever her hand becomes empty. */
exports.applySuzyLafayette = (0, firestore_1.onDocumentUpdated)('rooms/{roomId}/privateStates/{playerId}', async (event) => {
    const after = event.data?.after;
    if (!after?.exists || (after.get('handCardIds') ?? []).length !== 0)
        return;
    const roomId = event.params.roomId;
    const uid = event.params.playerId;
    const room = db.doc(`rooms/${roomId}`);
    const marker = room.collection('actions').doc(`suzy_${event.id}`);
    await db.runTransaction(async (tx) => {
        if ((await tx.get(marker)).exists)
            return;
        const player = await tx.get(room.collection('players').doc(uid));
        if (!player.exists || player.get('characterId') !== 'suzy_lafayette' || player.get('isAlive') === false)
            return;
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        const pile = [...(deck.get('drawPile') ?? [])];
        if (!pile.length)
            return;
        const card = pile.shift();
        tx.set(marker, { type: 'suzy_empty_hand', createdAt: admin.firestore.FieldValue.serverTimestamp() });
        tx.update(deck.ref, { drawPile: pile });
        tx.update(after.ref, { handCardIds: [card] });
        tx.update(player.ref, { cardCount: 1 });
        tx.update(room, { deckRemainingCount: pile.length, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    });
});
