import * as admin from 'firebase-admin';
import { onDocumentUpdated } from 'firebase-functions/firestore';
import { onDocumentCreated } from 'firebase-functions/firestore';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

/** Bang reactions always receive a full ten-second decision window. */
export const setBangResponseDeadline = onDocumentCreated(
  'rooms/{roomId}/pendingActions/{actionId}',
  async event => {
    const action = event.data;
    if (!action?.exists || action.get('actionType') !== 'bang') return;
    await action.ref.update({
      responseDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10000),
    });
  },
);

/** Bart Cassidy draws one card per health lost. Event ids make retries safe. */
export const applyBartCassidyDamage = onDocumentUpdated('rooms/{roomId}/players/{playerId}', async event => {
  const before = event.data?.before; const after = event.data?.after;
  if (!before?.exists || !after?.exists || after.get('characterId') !== 'bart_cassidy') return;
  const lost = Number(before.get('health') ?? 0) - Number(after.get('health') ?? 0);
  if (lost <= 0) return;
  const roomId = event.params.roomId; const uid = event.params.playerId; const room = db.doc(`rooms/${roomId}`); const marker = room.collection('actions').doc(`bart_${event.id}`);
  await db.runTransaction(async tx => {
    if ((await tx.get(marker)).exists) return;
    const deck = await tx.get(room.collection('serverState').doc('deck')); const handState = await tx.get(room.collection('privateStates').doc(uid)); const player = await tx.get(room.collection('players').doc(uid));
    const pile = [...(deck.get('drawPile') ?? [])] as string[]; const drawn = pile.splice(0, Math.min(lost, pile.length)); const hand = [...(handState.get('handCardIds') ?? []), ...drawn];
    tx.set(marker, { type: 'bart_damage', createdAt: admin.firestore.FieldValue.serverTimestamp() }); tx.update(deck.ref, { drawPile: pile }); tx.update(handState.ref, { handCardIds: hand }); tx.update(player.ref, { cardCount: hand.length }); tx.update(room, { deckRemainingCount: pile.length, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
});

/** Suzy Lafayette immediately draws one card whenever her hand becomes empty. */
export const applySuzyLafayette = onDocumentUpdated('rooms/{roomId}/privateStates/{playerId}', async event => {
  const after = event.data?.after; if (!after?.exists || (after.get('handCardIds') ?? []).length !== 0) return;
  const roomId = event.params.roomId; const uid = event.params.playerId; const room = db.doc(`rooms/${roomId}`); const marker = room.collection('actions').doc(`suzy_${event.id}`);
  await db.runTransaction(async tx => {
    if ((await tx.get(marker)).exists) return;
    const player = await tx.get(room.collection('players').doc(uid)); if (!player.exists || player.get('characterId') !== 'suzy_lafayette' || player.get('isAlive') === false) return;
    const deck = await tx.get(room.collection('serverState').doc('deck')); const pile = [...(deck.get('drawPile') ?? [])] as string[]; if (!pile.length) return; const card = pile.shift()!;
    tx.set(marker, { type: 'suzy_empty_hand', createdAt: admin.firestore.FieldValue.serverTimestamp() }); tx.update(deck.ref, { drawPile: pile }); tx.update(after.ref, { handCardIds: [card] }); tx.update(player.ref, { cardCount: 1 }); tx.update(room, { deckRemainingCount: pile.length, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
});
