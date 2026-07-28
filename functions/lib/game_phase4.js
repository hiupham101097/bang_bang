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
exports.resolveExpiredResponse = exports.triggerSuzyLafayette = exports.acceptBangDamage = exports.resolveSlabDodge = exports.useCalamityJanetDodge = exports.resolveJourdonnais = exports.chooseLuckyDukeJudgment = exports.openLuckyDukeJudgment = exports.chooseKitCarlson = exports.openKitCarlson = exports.drawJesseJones = exports.drawCharacterTurnCards = exports.useSidKetchum = exports.respondDuel = exports.startDuel = exports.respondMultiAttack = exports.startMultiAttack = exports.chooseGeneralStoreCard = exports.openGeneralStore = exports.resolveTargetCard = exports.resolveTurnJudgments = exports.playSpecialCard = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/https");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const specialTypes = ['dilizenza', 'wells_fargo', 'saloon', 'barrel', 'mustang', 'appaloosa', 'volcanic', 'jail', 'dynamite'];
const cardType = (id) => specialTypes.find(type => id === type || id.startsWith(`${type}_`));
const serverNow = () => admin.firestore.FieldValue.serverTimestamp();
exports.playSpecialCard = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, cardId, targetPlayerId } = request.data;
    if (!roomId || !cardId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu roomId hoặc cardId.');
    const type = cardType(cardId);
    if (!type)
        throw new https_1.HttpsError('failed-precondition', 'Thẻ này chưa thuộc nhóm hiệu ứng đơn.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const actor = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        if (!state.exists || state.get('status') !== 'playing' || state.get('phase') !== 'play_phase' || state.get('currentTurnPlayerId') !== uid || !actor.exists || actor.get('isAlive') === false)
            throw new https_1.HttpsError('failed-precondition', 'Không thể dùng thẻ lúc này.');
        const hand = [...(privateState.get('handCardIds') ?? [])];
        const index = hand.indexOf(cardId);
        if (index < 0)
            throw new https_1.HttpsError('permission-denied', 'Bạn không sở hữu lá bài này.');
        const nextHand = [...hand.slice(0, index), ...hand.slice(index + 1)];
        const discard = [...(deck.get('discardPile') ?? [])];
        const roomUpdate = { updatedAt: serverNow() };
        if (type === 'dilizenza' || type === 'wells_fargo') {
            const drawCount = type === 'dilizenza' ? 2 : 3;
            const pile = [...(deck.get('drawPile') ?? [])];
            if (pile.length < drawCount)
                throw new https_1.HttpsError('failed-precondition', 'Không đủ bài để rút.');
            const drawn = pile.splice(0, drawCount);
            discard.push(cardId);
            tx.update(privateState.ref, { handCardIds: [...nextHand, ...drawn] });
            tx.update(actor.ref, { cardCount: nextHand.length + drawn.length });
            tx.update(deck.ref, { drawPile: pile, discardPile: discard });
            Object.assign(roomUpdate, { deckRemainingCount: pile.length, discardCount: discard.length, discardTopCardId: cardId });
        }
        else if (type === 'saloon') {
            const players = await tx.get(room.collection('players'));
            players.docs.filter(player => player.get('isAlive') !== false).forEach(player => {
                const health = Number(player.get('health') ?? 0);
                const max = Number(player.get('maxHealth') ?? health);
                tx.update(player.ref, { health: Math.min(max, health + 1) });
            });
            discard.push(cardId);
            tx.update(privateState.ref, { handCardIds: nextHand });
            tx.update(actor.ref, { cardCount: nextHand.length });
            tx.update(deck.ref, { discardPile: discard });
            Object.assign(roomUpdate, { discardCount: discard.length, discardTopCardId: cardId });
        }
        else if (type === 'jail') {
            if (!targetPlayerId || targetPlayerId === state.get('sheriffPlayerId'))
                throw new https_1.HttpsError('failed-precondition', 'Không thể đặt Jail lên Cảnh sát trưởng.');
            const target = await tx.get(room.collection('players').doc(targetPlayerId));
            if (!target.exists || target.get('isAlive') === false)
                throw new https_1.HttpsError('failed-precondition', 'Mục tiêu không hợp lệ.');
            const old = target.get('jailCardId');
            if (old)
                discard.push(old);
            tx.update(target.ref, { jailCardId: cardId });
            tx.update(privateState.ref, { handCardIds: nextHand });
            tx.update(actor.ref, { cardCount: nextHand.length });
            tx.update(deck.ref, { discardPile: discard });
            Object.assign(roomUpdate, { discardCount: discard.length, discardTopCardId: old ?? cardId });
        }
        else {
            const field = type === 'barrel' ? 'barrelCardId' : type === 'mustang' ? 'mustangCardId' : type === 'appaloosa' ? 'appaloosaCardId' : type === 'volcanic' ? 'weaponCardId' : 'dynamiteCardId';
            if (type === 'dynamite' && actor.get(field))
                throw new https_1.HttpsError('failed-precondition', 'Bạn đã có Dynamite.');
            const old = actor.get(field);
            if (old)
                discard.push(old);
            const extra = type === 'mustang' ? { distanceFromOthersModifier: 1 } : type === 'appaloosa' ? { distanceToOthersModifier: -1 } : type === 'volcanic' ? { attackRange: 1, unlimitedBang: true } : {};
            tx.update(actor.ref, { ...extra, [field]: cardId, cardCount: nextHand.length });
            tx.update(privateState.ref, { handCardIds: nextHand });
            tx.update(deck.ref, { discardPile: discard });
            Object.assign(roomUpdate, { discardCount: discard.length, discardTopCardId: old ?? cardId });
        }
        tx.update(room, roomUpdate);
    });
    return {};
});
const rankOf = (cardId) => cardId.split('_').at(-2) ?? '';
const suitOf = (cardId) => cardId.split('_').at(-1) ?? '';
const nextAlive = (players, currentId) => {
    const alive = players.filter(player => player.get('isAlive') !== false).sort((a, b) => Number(a.get('seat')) - Number(b.get('seat')));
    const index = alive.findIndex(player => player.id === currentId);
    return alive[(index + 1) % alive.length];
};
/** Resolves public Jail/Dynamite judgement before the current player draws. */
exports.resolveTurnJudgments = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const roomId = request.data?.roomId;
    if (!roomId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu roomId.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection('players').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        if (!state.exists || state.get('status') !== 'playing' || state.get('phase') !== 'turn_start' || state.get('currentTurnPlayerId') !== uid || !player.exists)
            throw new https_1.HttpsError('failed-precondition', 'Chưa đến bước phán xét.');
        const pile = [...(deck.get('drawPile') ?? [])];
        const discard = [...(deck.get('discardPile') ?? [])];
        if (pile.length === 0)
            throw new https_1.HttpsError('failed-precondition', 'Hết bài để phán xét.');
        const players = (await tx.get(room.collection('players'))).docs;
        const dynamite = player.get('dynamiteCardId');
        if (dynamite) {
            const judgement = pile.shift();
            discard.push(judgement);
            const explodes = suitOf(judgement) === 'spade' && ['two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'].includes(rankOf(judgement));
            if (explodes) {
                discard.push(dynamite);
                const health = Number(player.get('health')) - 3;
                tx.update(player.ref, { dynamiteCardId: admin.firestore.FieldValue.delete(), health });
                tx.update(deck.ref, { drawPile: pile, discardPile: discard });
                tx.update(room, { phase: health <= 0 ? 'dying' : 'turn_start', dyingPlayerId: health <= 0 ? uid : admin.firestore.FieldValue.delete(), deckRemainingCount: pile.length, discardCount: discard.length, discardTopCardId: dynamite, updatedAt: serverNow() });
                return;
            }
            const next = nextAlive(players, uid);
            tx.update(player.ref, { dynamiteCardId: admin.firestore.FieldValue.delete() });
            tx.update(next.ref, { dynamiteCardId: dynamite });
        }
        const jail = player.get('jailCardId');
        if (jail) {
            const judgement = pile.shift();
            discard.push(judgement);
            discard.push(jail);
            tx.update(player.ref, { jailCardId: admin.firestore.FieldValue.delete() });
            if (suitOf(judgement) !== 'heart') {
                const next = nextAlive(players, uid);
                tx.update(deck.ref, { drawPile: pile, discardPile: discard });
                tx.update(room, { phase: 'turn_start', currentTurnPlayerId: next.id, turnNumber: Number(state.get('turnNumber') ?? 0) + 1, deckRemainingCount: pile.length, discardCount: discard.length, discardTopCardId: jail, updatedAt: serverNow() });
                return;
            }
        }
        tx.update(deck.ref, { drawPile: pile, discardPile: discard });
        tx.update(room, { judgmentsResolvedForTurn: Number(state.get('turnNumber') ?? 0), deckRemainingCount: pile.length, discardCount: discard.length, discardTopCardId: discard.at(-1) ?? null, updatedAt: serverNow() });
    });
    return {};
});
const publicEquipmentFields = ['weaponCardId', 'barrelCardId', 'mustangCardId', 'appaloosaCardId', 'jailCardId', 'dynamiteCardId'];
/** Resolves Panic! (steal) and Cat Balou (discard) without exposing another player's hand. */
exports.resolveTargetCard = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, cardId, targetPlayerId, equipmentCardId } = request.data;
    if (!roomId || !cardId || !targetPlayerId || targetPlayerId === uid)
        throw new https_1.HttpsError('invalid-argument', 'Dữ liệu mục tiêu không hợp lệ.');
    const type = cardId.startsWith('panico_') ? 'panico' : cardId.startsWith('cat_balou_') ? 'cat_balou' : null;
    if (!type)
        throw new https_1.HttpsError('failed-precondition', 'Không phải Panic! hoặc Cat Balou.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const actor = await tx.get(room.collection('players').doc(uid));
        const target = await tx.get(room.collection('players').doc(targetPlayerId));
        const actorState = await tx.get(room.collection('privateStates').doc(uid));
        const targetState = await tx.get(room.collection('privateStates').doc(targetPlayerId));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        if (!state.exists || state.get('phase') !== 'play_phase' || state.get('currentTurnPlayerId') !== uid || !actor.exists || !target.exists || target.get('isAlive') === false)
            throw new https_1.HttpsError('failed-precondition', 'Không thể dùng thẻ lúc này.');
        const hand = [...(actorState.get('handCardIds') ?? [])];
        const cardIndex = hand.indexOf(cardId);
        if (cardIndex < 0)
            throw new https_1.HttpsError('permission-denied', 'Bạn không có lá bài này.');
        const targetHand = [...(targetState.get('handCardIds') ?? [])];
        let field;
        let taken;
        if (equipmentCardId) {
            field = publicEquipmentFields.find(name => target.get(name) === equipmentCardId);
            if (!field)
                throw new https_1.HttpsError('failed-precondition', 'Trang bị mục tiêu không hợp lệ.');
            taken = equipmentCardId;
        }
        else if (targetHand.length)
            taken = targetHand[Math.floor(Math.random() * targetHand.length)];
        if (!taken)
            throw new https_1.HttpsError('failed-precondition', 'Mục tiêu không còn bài hoặc trang bị.');
        const nextHand = [...hand.slice(0, cardIndex), ...hand.slice(cardIndex + 1)];
        const nextTargetHand = targetHand.filter(value => value !== taken);
        const discard = [...(deck.get('discardPile') ?? []), cardId];
        if (type === 'panico') {
            tx.update(actorState.ref, { handCardIds: [...nextHand, taken] });
            tx.update(actor.ref, { cardCount: nextHand.length + 1 });
        }
        else {
            discard.push(taken);
            tx.update(actorState.ref, { handCardIds: nextHand });
            tx.update(actor.ref, { cardCount: nextHand.length });
        }
        if (field)
            tx.update(target.ref, { [field]: admin.firestore.FieldValue.delete() });
        else
            tx.update(targetState.ref, { handCardIds: nextTargetHand });
        tx.update(target.ref, { cardCount: field ? target.get('cardCount') : nextTargetHand.length });
        tx.update(deck.ref, { discardPile: discard });
        tx.update(room, { discardCount: discard.length, discardTopCardId: discard.at(-1), updatedAt: serverNow() });
    });
    return {};
});
/** Opens General Store. The opened cards are public; each alive player picks one in turn order. */
exports.openGeneralStore = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, cardId, actionId } = request.data;
    if (!roomId || !cardId || !actionId || !cardId.startsWith('general_store_'))
        throw new https_1.HttpsError('invalid-argument', 'Dữ liệu General Store không hợp lệ.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const actor = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        const action = await tx.get(room.collection('pendingActions').doc(actionId));
        if (!state.exists || state.get('phase') !== 'play_phase' || state.get('currentTurnPlayerId') !== uid || action.exists)
            throw new https_1.HttpsError('failed-precondition', 'Không thể mở General Store.');
        const hand = [...(privateState.get('handCardIds') ?? [])];
        const index = hand.indexOf(cardId);
        if (index < 0)
            throw new https_1.HttpsError('permission-denied', 'Bạn không có lá bài này.');
        const players = (await tx.get(room.collection('players'))).docs.filter(player => player.get('isAlive') !== false).sort((a, b) => Number(a.get('seat')) - Number(b.get('seat')));
        const actorIndex = players.findIndex(player => player.id === uid);
        const order = [...players.slice(actorIndex), ...players.slice(0, actorIndex)].map(player => player.id);
        const pile = [...(deck.get('drawPile') ?? [])];
        if (pile.length < order.length)
            throw new https_1.HttpsError('failed-precondition', 'Không đủ bài để mở cửa hàng.');
        const opened = pile.splice(0, order.length);
        const nextHand = [...hand.slice(0, index), ...hand.slice(index + 1)];
        const discard = [...(deck.get('discardPile') ?? []), cardId];
        tx.update(privateState.ref, { handCardIds: nextHand });
        tx.update(actor.ref, { cardCount: nextHand.length });
        tx.update(deck.ref, { drawPile: pile, discardPile: discard });
        tx.set(action.ref, { actionId, actionType: 'general_store', actorPlayerId: uid, playerOrder: order, currentPickerId: order[0], openedCardIds: opened, status: 'waiting', createdAt: serverNow() });
        tx.update(room, { phase: 'waiting_general_store_selection', deckRemainingCount: pile.length, discardCount: discard.length, discardTopCardId: cardId, updatedAt: serverNow() });
    });
    return {};
});
exports.chooseGeneralStoreCard = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId, cardId } = request.data;
    if (!roomId || !actionId || !cardId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu dữ liệu chọn bài.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const action = await tx.get(room.collection('pendingActions').doc(actionId));
        const player = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        if (!state.exists || state.get('phase') !== 'waiting_general_store_selection' || !action.exists || action.get('status') !== 'waiting' || action.get('currentPickerId') !== uid)
            throw new https_1.HttpsError('failed-precondition', 'Chưa đến lượt chọn bài.');
        const opened = [...(action.get('openedCardIds') ?? [])];
        if (!opened.includes(cardId))
            throw new https_1.HttpsError('failed-precondition', 'Lá bài không còn trên bàn.');
        const remaining = opened.filter(value => value !== cardId);
        const order = action.get('playerOrder');
        const currentIndex = order.indexOf(uid);
        const nextPicker = order[currentIndex + 1];
        const hand = [...(privateState.get('handCardIds') ?? []), cardId];
        tx.update(privateState.ref, { handCardIds: hand });
        tx.update(player.ref, { cardCount: hand.length });
        if (nextPicker && remaining.length)
            tx.update(action.ref, { openedCardIds: remaining, currentPickerId: nextPicker });
        else {
            tx.delete(action.ref);
            tx.update(room, { phase: 'play_phase', updatedAt: serverNow() });
        }
    });
    return {};
});
/** Starts Gatling/Indians!. Targets respond one-by-one so the server owns all damage. */
exports.startMultiAttack = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, cardId, actionId } = request.data;
    const type = cardId?.startsWith('gatling_') ? 'gatling' : cardId?.startsWith('indiani_') ? 'indiani' : null;
    if (!roomId || !cardId || !actionId || !type)
        throw new https_1.HttpsError('invalid-argument', 'Thẻ tấn công nhiều mục tiêu không hợp lệ.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const actor = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        const action = await tx.get(room.collection('pendingActions').doc(actionId));
        if (!state.exists || state.get('phase') !== 'play_phase' || state.get('currentTurnPlayerId') !== uid || action.exists)
            throw new https_1.HttpsError('failed-precondition', 'Không thể dùng thẻ lúc này.');
        const hand = [...(privateState.get('handCardIds') ?? [])];
        const index = hand.indexOf(cardId);
        if (index < 0)
            throw new https_1.HttpsError('permission-denied', 'Bạn không có lá này.');
        const targets = (await tx.get(room.collection('players'))).docs.filter(player => player.id !== uid && player.get('isAlive') !== false).sort((a, b) => Number(a.get('seat')) - Number(b.get('seat'))).map(player => player.id);
        const nextHand = [...hand.slice(0, index), ...hand.slice(index + 1)];
        const discard = [...(deck.get('discardPile') ?? []), cardId];
        tx.update(privateState.ref, { handCardIds: nextHand });
        tx.update(actor.ref, { cardCount: nextHand.length });
        tx.update(deck.ref, { discardPile: discard });
        tx.set(action.ref, { actionId, actionType: type, actorPlayerId: uid, targetOrder: targets, targetIndex: 0, currentTargetId: targets[0] ?? null, status: 'waiting', createdAt: serverNow() });
        tx.update(room, { phase: 'waiting_multi_response', discardCount: discard.length, discardTopCardId: cardId, updatedAt: serverNow() });
    });
    return {};
});
exports.respondMultiAttack = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId, cardId } = request.data;
    if (!roomId || !actionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu actionId.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const action = await tx.get(room.collection('pendingActions').doc(actionId));
        const player = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        if (!state.exists || state.get('phase') !== 'waiting_multi_response' || !action.exists || action.get('currentTargetId') !== uid || !player.exists)
            throw new https_1.HttpsError('failed-precondition', 'Chưa đến lượt phản ứng.');
        const actionType = action.get('actionType');
        const needed = actionType === 'gatling' ? 'dodge' : 'bang';
        const hand = [...(privateState.get('handCardIds') ?? [])];
        const valid = cardId && (cardId === needed || cardId.startsWith(`${needed}_`));
        let nextHand = hand;
        const discard = [...(deck.get('discardPile') ?? [])];
        let health = Number(player.get('health'));
        if (valid) {
            const index = hand.indexOf(cardId);
            if (index < 0)
                throw new https_1.HttpsError('permission-denied', 'Bạn không có lá phản ứng này.');
            nextHand = [...hand.slice(0, index), ...hand.slice(index + 1)];
            discard.push(cardId);
            tx.update(privateState.ref, { handCardIds: nextHand });
            tx.update(player.ref, { cardCount: nextHand.length });
        }
        else {
            health--;
            tx.update(player.ref, { health });
        }
        const order = action.get('targetOrder');
        const nextIndex = Number(action.get('targetIndex')) + 1;
        const next = order[nextIndex];
        tx.update(deck.ref, { discardPile: discard });
        if (health <= 0) {
            tx.delete(action.ref);
            tx.update(room, { phase: 'dying', dyingPlayerId: uid, discardCount: discard.length, discardTopCardId: discard.at(-1) ?? null, updatedAt: serverNow() });
        }
        else if (next)
            tx.update(action.ref, { targetIndex: nextIndex, currentTargetId: next });
        else {
            tx.delete(action.ref);
            tx.update(room, { phase: 'play_phase', discardCount: discard.length, discardTopCardId: discard.at(-1) ?? null, updatedAt: serverNow() });
        }
    });
    return {};
});
exports.startDuel = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, cardId, targetPlayerId, actionId } = request.data;
    if (!roomId || !cardId?.startsWith('duello_') || !targetPlayerId || targetPlayerId === uid || !actionId)
        throw new https_1.HttpsError('invalid-argument', 'Dữ liệu Duel không hợp lệ.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const actor = await tx.get(room.collection('players').doc(uid));
        const target = await tx.get(room.collection('players').doc(targetPlayerId));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        const action = await tx.get(room.collection('pendingActions').doc(actionId));
        if (!state.exists || state.get('phase') !== 'play_phase' || state.get('currentTurnPlayerId') !== uid || !target.exists || target.get('isAlive') === false || action.exists)
            throw new https_1.HttpsError('failed-precondition', 'Không thể đấu súng lúc này.');
        const hand = [...(privateState.get('handCardIds') ?? [])];
        const index = hand.indexOf(cardId);
        if (index < 0)
            throw new https_1.HttpsError('permission-denied', 'Bạn không có lá Duel.');
        const nextHand = [...hand.slice(0, index), ...hand.slice(index + 1)];
        const discard = [...(deck.get('discardPile') ?? []), cardId];
        tx.update(privateState.ref, { handCardIds: nextHand });
        tx.update(actor.ref, { cardCount: nextHand.length });
        tx.update(deck.ref, { discardPile: discard });
        tx.set(action.ref, { actionId, actionType: 'duello', actorPlayerId: uid, opponentPlayerId: targetPlayerId, currentResponderId: targetPlayerId, status: 'waiting', createdAt: serverNow() });
        tx.update(room, { phase: 'waiting_duel_response', discardCount: discard.length, discardTopCardId: cardId, updatedAt: serverNow() });
    });
    return {};
});
exports.respondDuel = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId, cardId } = request.data;
    if (!roomId || !actionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu actionId.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const action = await tx.get(room.collection('pendingActions').doc(actionId));
        const player = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        if (!state.exists || state.get('phase') !== 'waiting_duel_response' || !action.exists || action.get('currentResponderId') !== uid || !player.exists)
            throw new https_1.HttpsError('failed-precondition', 'Chưa đến lượt đáp Duel.');
        const hand = [...(privateState.get('handCardIds') ?? [])];
        const validBang = cardId && (cardId === 'bang' || cardId.startsWith('bang_')) && hand.includes(cardId);
        if (validBang) {
            const index = hand.indexOf(cardId);
            const nextHand = [...hand.slice(0, index), ...hand.slice(index + 1)];
            const other = action.get('actorPlayerId') === uid ? action.get('opponentPlayerId') : action.get('actorPlayerId');
            tx.update(privateState.ref, { handCardIds: nextHand });
            tx.update(player.ref, { cardCount: nextHand.length });
            tx.update(deck.ref, { discardPile: [...(deck.get('discardPile') ?? []), cardId] });
            tx.update(action.ref, { currentResponderId: other });
            return;
        }
        const health = Number(player.get('health')) - 1;
        tx.update(player.ref, { health });
        tx.delete(action.ref);
        tx.update(room, { phase: health <= 0 ? 'dying' : 'play_phase', dyingPlayerId: health <= 0 ? uid : admin.firestore.FieldValue.delete(), updatedAt: serverNow() });
    });
    return {};
});
exports.useSidKetchum = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, cardIds } = request.data;
    if (!roomId || !Array.isArray(cardIds) || cardIds.length !== 2 || new Set(cardIds).size !== 2)
        throw new https_1.HttpsError('invalid-argument', 'Sid Ketchum cần bỏ đúng 2 lá khác nhau.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        if (!state.exists || state.get('status') !== 'playing' || player.get('characterId') !== 'sid_ketchum' || player.get('isAlive') === false || Number(player.get('health')) >= Number(player.get('maxHealth')))
            throw new https_1.HttpsError('failed-precondition', 'Không thể dùng kỹ năng Sid Ketchum.');
        const hand = [...(privateState.get('handCardIds') ?? [])];
        if (!cardIds.every(card => hand.includes(card)))
            throw new https_1.HttpsError('permission-denied', 'Có lá bài không thuộc tay bạn.');
        const nextHand = hand.filter(card => !cardIds.includes(card));
        const discard = [...(deck.get('discardPile') ?? []), ...cardIds];
        tx.update(privateState.ref, { handCardIds: nextHand });
        tx.update(player.ref, { health: Math.min(Number(player.get('maxHealth')), Number(player.get('health')) + 1), cardCount: nextHand.length });
        tx.update(deck.ref, { discardPile: discard });
        tx.update(room, { discardCount: discard.length, discardTopCardId: cardIds[1], updatedAt: serverNow() });
    });
    return {};
});
/** Character-aware replacement for the normal first draw: Pedro and Black Jack. */
exports.drawCharacterTurnCards = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId } = request.data;
    if (!roomId || !actionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu roomId hoặc actionId.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection('players').doc(uid));
        const privateState = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        const action = await tx.get(room.collection('actions').doc(actionId));
        if (!state.exists || state.get('phase') !== 'turn_start' || state.get('currentTurnPlayerId') !== uid || !player.exists || action.exists)
            throw new https_1.HttpsError('failed-precondition', 'Không thể rút bài lúc này.');
        const pile = [...(deck.get('drawPile') ?? [])];
        const discard = [...(deck.get('discardPile') ?? [])];
        const character = player.get('characterId');
        const drawn = [];
        if (character === 'pedro_ramirez' && discard.length)
            drawn.push(discard.pop());
        if (!pile.length || (drawn.length === 0 && pile.length < 2))
            throw new https_1.HttpsError('failed-precondition', 'Không đủ bài để rút.');
        while (drawn.length < 2)
            drawn.push(pile.shift());
        let revealed = null;
        if (character === 'black_jack') {
            revealed = drawn[1];
            const suit = suitOf(revealed);
            if ((suit === 'heart' || suit === 'diamond') && pile.length)
                drawn.push(pile.shift());
        }
        const hand = [...(privateState.get('handCardIds') ?? []), ...drawn];
        tx.set(action.ref, { uid, type: 'draw_character', createdAt: serverNow() });
        tx.update(privateState.ref, { handCardIds: hand });
        tx.update(player.ref, { cardCount: hand.length });
        tx.update(deck.ref, { drawPile: pile, discardPile: discard });
        tx.update(room, { phase: 'play_phase', hasDrawnThisTurn: true, cardsDrawnThisTurn: drawn.length, bangUsedThisTurn: 0, deckRemainingCount: pile.length, discardCount: discard.length, lastPublicDrawCardId: revealed, updatedAt: serverNow() });
    });
    return {};
});
/** Jesse Jones may take the first draw randomly from one opponent, then draws one deck card. */
exports.drawJesseJones = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, targetPlayerId, actionId } = request.data;
    if (!roomId || !actionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu dữ liệu rút bài.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const state = await tx.get(room);
        const player = await tx.get(room.collection('players').doc(uid));
        const own = await tx.get(room.collection('privateStates').doc(uid));
        const deck = await tx.get(room.collection('serverState').doc('deck'));
        const action = await tx.get(room.collection('actions').doc(actionId));
        if (!state.exists || state.get('phase') !== 'turn_start' || state.get('currentTurnPlayerId') !== uid || player.get('characterId') !== 'jesse_jones' || action.exists)
            throw new https_1.HttpsError('failed-precondition', 'Không thể dùng Jesse Jones lúc này.');
        const pile = [...(deck.get('drawPile') ?? [])];
        if (!pile.length)
            throw new https_1.HttpsError('failed-precondition', 'Hết bài.');
        const drawn = [];
        if (targetPlayerId && targetPlayerId !== uid) {
            const target = await tx.get(room.collection('players').doc(targetPlayerId));
            const targetState = await tx.get(room.collection('privateStates').doc(targetPlayerId));
            const targetHand = [...(targetState.get('handCardIds') ?? [])];
            if (!target.exists || target.get('isAlive') === false || !targetHand.length)
                throw new https_1.HttpsError('failed-precondition', 'Mục tiêu không có bài.');
            const stolen = targetHand[Math.floor(Math.random() * targetHand.length)];
            drawn.push(stolen);
            const rest = targetHand.filter(card => card !== stolen);
            tx.update(targetState.ref, { handCardIds: rest });
            tx.update(target.ref, { cardCount: rest.length });
        }
        while (drawn.length < 2) {
            if (!pile.length)
                throw new https_1.HttpsError('failed-precondition', 'Không đủ bài.');
            drawn.push(pile.shift());
        }
        const hand = [...(own.get('handCardIds') ?? []), ...drawn];
        tx.set(action.ref, { uid, type: 'draw_jesse', createdAt: serverNow() });
        tx.update(own.ref, { handCardIds: hand });
        tx.update(player.ref, { cardCount: hand.length });
        tx.update(deck.ref, { drawPile: pile });
        tx.update(room, { phase: 'play_phase', hasDrawnThisTurn: true, cardsDrawnThisTurn: 2, bangUsedThisTurn: 0, deckRemainingCount: pile.length, updatedAt: serverNow() });
    });
    return {};
});
/** Kit Carlson sees three cards, then submits exactly two; the other remains on top. */
exports.openKitCarlson = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId } = request.data;
    if (!roomId || !actionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu dữ liệu.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const state = await tx.get(room); const player = await tx.get(room.collection('players').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); const action = await tx.get(room.collection('pendingActions').doc(actionId)); const pile = [...(deck.get('drawPile') ?? [])]; if (!state.exists || state.get('phase') !== 'turn_start' || state.get('currentTurnPlayerId') !== uid || player.get('characterId') !== 'kit_carlson' || action.exists || pile.length < 3)
        throw new https_1.HttpsError('failed-precondition', 'Không thể mở kỹ năng Kit Carlson.'); const choices = pile.splice(0, 3); tx.update(deck.ref, { drawPile: pile }); tx.set(action.ref, { actionId, actionType: 'kit_carlson', actorPlayerId: uid, choices, status: 'waiting' }); tx.update(room, { phase: 'character_skill_selection', deckRemainingCount: pile.length, updatedAt: serverNow() }); });
    return {};
});
exports.chooseKitCarlson = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId, cardIds } = request.data;
    if (!roomId || !actionId || !Array.isArray(cardIds) || cardIds.length !== 2 || new Set(cardIds).size !== 2)
        throw new https_1.HttpsError('invalid-argument', 'Cần chọn đúng 2 lá.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const state = await tx.get(room); const action = await tx.get(room.collection('pendingActions').doc(actionId)); const player = await tx.get(room.collection('players').doc(uid)); const own = await tx.get(room.collection('privateStates').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); const choices = [...(action.get('choices') ?? [])]; if (!state.exists || state.get('phase') !== 'character_skill_selection' || !action.exists || action.get('actorPlayerId') !== uid || !cardIds.every(id => choices.includes(id)))
        throw new https_1.HttpsError('failed-precondition', 'Lựa chọn Kit Carlson không hợp lệ.'); const remain = choices.filter(id => !cardIds.includes(id)); const pile = [...remain, ...(deck.get('drawPile') ?? [])]; const hand = [...(own.get('handCardIds') ?? []), ...cardIds]; tx.update(own.ref, { handCardIds: hand }); tx.update(player.ref, { cardCount: hand.length }); tx.update(deck.ref, { drawPile: pile }); tx.delete(action.ref); tx.update(room, { phase: 'play_phase', hasDrawnThisTurn: true, cardsDrawnThisTurn: 2, bangUsedThisTurn: 0, deckRemainingCount: pile.length, updatedAt: serverNow() }); });
    return {};
});
/** Lucky Duke draws two judgement cards and selects which one is used as the result. */
exports.openLuckyDukeJudgment = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId, judgmentContext } = request.data;
    if (!roomId || !actionId || !judgmentContext)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu dữ liệu phán xét.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const player = await tx.get(room.collection('players').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); const action = await tx.get(room.collection('pendingActions').doc(actionId)); const pile = [...(deck.get('drawPile') ?? [])]; if (!player.exists || player.get('characterId') !== 'lucky_duke' || action.exists || pile.length < 2)
        throw new https_1.HttpsError('failed-precondition', 'Không thể dùng Lucky Duke.'); const choices = [pile.shift(), pile.shift()]; tx.update(deck.ref, { drawPile: pile }); tx.set(action.ref, { actionId, actionType: 'lucky_duke_judgment', actorPlayerId: uid, judgmentContext, choices, status: 'waiting' }); });
    return {};
});
exports.chooseLuckyDukeJudgment = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, actionId, resultCardId } = request.data;
    if (!roomId || !actionId || !resultCardId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu kết quả phán xét.');
    const room = db.doc(`rooms/${roomId}`);
    let result = null;
    await db.runTransaction(async (tx) => { const action = await tx.get(room.collection('pendingActions').doc(actionId)); const deck = await tx.get(room.collection('serverState').doc('deck')); if (!action.exists || action.get('actionType') !== 'lucky_duke_judgment' || action.get('actorPlayerId') !== uid)
        throw new https_1.HttpsError('failed-precondition', 'Phán xét Lucky Duke không hợp lệ.'); const choices = [...(action.get('choices') ?? [])]; if (!choices.includes(resultCardId))
        throw new https_1.HttpsError('invalid-argument', 'Kết quả không thuộc hai lá đã rút.'); result = resultCardId; tx.update(deck.ref, { discardPile: [...(deck.get('discardPile') ?? []), ...choices] }); tx.delete(action.ref); });
    return { resultCardId: result };
});
/** Resolves the automatic heart judgement used by Jourdonnais against Bang. */
exports.resolveJourdonnais = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, pendingActionId } = request.data;
    if (!roomId || !pendingActionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu dữ liệu phản ứng.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const state = await tx.get(room); const pending = await tx.get(room.collection('pendingActions').doc(pendingActionId)); const player = await tx.get(room.collection('players').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); if (!state.exists || state.get('phase') !== 'waiting_response' || !pending.exists || pending.get('actionType') !== 'bang' || pending.get('targetPlayerId') !== uid || player.get('characterId') !== 'jourdonnais')
        throw new https_1.HttpsError('failed-precondition', 'Không thể phán xét Jourdonnais.'); const pile = [...(deck.get('drawPile') ?? [])]; if (!pile.length)
        throw new https_1.HttpsError('failed-precondition', 'Hết bài phán xét.'); const judgment = pile.shift(); const discard = [...(deck.get('discardPile') ?? []), judgment]; tx.update(deck.ref, { drawPile: pile, discardPile: discard }); if (suitOf(judgment) === 'heart') {
        tx.delete(pending.ref);
        tx.update(room, { phase: 'play_phase', deckRemainingCount: pile.length, discardCount: discard.length, discardTopCardId: judgment, updatedAt: serverNow() });
    }
    else
        tx.update(pending.ref, { jourdonnaisJudgmentCardId: judgment, judgmentFailed: true }); });
    return {};
});
/** Calamity Janet may spend Bang as a Dodge when a Bang reaction is pending. */
exports.useCalamityJanetDodge = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, pendingActionId, cardId } = request.data;
    if (!roomId || !pendingActionId || !cardId?.startsWith('bang_'))
        throw new https_1.HttpsError('invalid-argument', 'Cần một lá Bang.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const state = await tx.get(room); const pending = await tx.get(room.collection('pendingActions').doc(pendingActionId)); const player = await tx.get(room.collection('players').doc(uid)); const privateState = await tx.get(room.collection('privateStates').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); const hand = [...(privateState.get('handCardIds') ?? [])]; if (!state.exists || state.get('phase') !== 'waiting_response' || !pending.exists || pending.get('targetPlayerId') !== uid || player.get('characterId') !== 'calamity_janet' || !hand.includes(cardId))
        throw new https_1.HttpsError('failed-precondition', 'Không thể dùng kỹ năng Calamity Janet.'); const nextHand = hand.filter(card => card !== cardId); const discard = [...(deck.get('discardPile') ?? []), cardId]; tx.update(privateState.ref, { handCardIds: nextHand }); tx.update(player.ref, { cardCount: nextHand.length }); tx.update(deck.ref, { discardPile: discard }); tx.delete(pending.ref); tx.update(room, { phase: 'play_phase', discardCount: discard.length, discardTopCardId: cardId, updatedAt: serverNow() }); });
    return {};
});
/** Slab's target must discard two Dodge cards to stop one Bang. */
exports.resolveSlabDodge = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, pendingActionId, cardIds } = request.data;
    if (!roomId || !pendingActionId || !Array.isArray(cardIds) || cardIds.length !== 2 || new Set(cardIds).size !== 2)
        throw new https_1.HttpsError('invalid-argument', 'Cần đúng 2 lá Né.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const pending = await tx.get(room.collection('pendingActions').doc(pendingActionId)); const target = await tx.get(room.collection('players').doc(uid)); const own = await tx.get(room.collection('privateStates').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); const attacker = await tx.get(room.collection('players').doc(String(pending.get('actorPlayerId') ?? ''))); const hand = [...(own.get('handCardIds') ?? [])]; if (!pending.exists || pending.get('actionType') !== 'bang' || pending.get('targetPlayerId') !== uid || !attacker.exists || attacker.get('characterId') !== 'slab_the_killer' || !cardIds.every(card => hand.includes(card) && card.startsWith('dodge_')))
        throw new https_1.HttpsError('failed-precondition', 'Không thể né Bang của Slab.'); const nextHand = hand.filter(card => !cardIds.includes(card)); const discard = [...(deck.get('discardPile') ?? []), ...cardIds]; tx.update(own.ref, { handCardIds: nextHand }); tx.update(target.ref, { cardCount: nextHand.length }); tx.update(deck.ref, { discardPile: discard }); tx.delete(pending.ref); tx.update(room, { phase: 'play_phase', discardCount: discard.length, discardTopCardId: cardIds[1], updatedAt: serverNow() }); });
    return {};
});
/** Takes a pending Bang hit and applies El Gringo, Bart Cassidy and Suzy Lafayette. */
exports.acceptBangDamage = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const { roomId, pendingActionId } = request.data;
    if (!roomId || !pendingActionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu action sát thương.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const pending = await tx.get(room.collection('pendingActions').doc(pendingActionId)); const target = await tx.get(room.collection('players').doc(uid)); const own = await tx.get(room.collection('privateStates').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); if (!pending.exists || pending.get('actionType') !== 'bang' || pending.get('targetPlayerId') !== uid || pending.get('status') !== 'waiting')
        throw new https_1.HttpsError('failed-precondition', 'Không có Bang cần nhận sát thương.'); let hand = [...(own.get('handCardIds') ?? [])]; let pile = [...(deck.get('drawPile') ?? [])]; const actorId = String(pending.get('actorPlayerId') ?? ''); if (target.get('characterId') === 'bart_cassidy' && pile.length)
        hand.push(pile.shift()); if (target.get('characterId') === 'el_gringo' && actorId) {
        const actor = await tx.get(room.collection('players').doc(actorId));
        const actorState = await tx.get(room.collection('privateStates').doc(actorId));
        const actorHand = [...(actorState.get('handCardIds') ?? [])];
        if (actorHand.length) {
            const stolen = actorHand[Math.floor(Math.random() * actorHand.length)];
            hand.push(stolen);
            const rest = actorHand.filter(card => card !== stolen);
            tx.update(actorState.ref, { handCardIds: rest });
            tx.update(actor.ref, { cardCount: rest.length });
        }
    } if (target.get('characterId') === 'suzy_lafayette' && hand.length === 0 && pile.length)
        hand.push(pile.shift()); const health = Number(target.get('health')) - 1; tx.update(own.ref, { handCardIds: hand }); tx.update(target.ref, { health, cardCount: hand.length }); tx.update(deck.ref, { drawPile: pile }); tx.delete(pending.ref); tx.update(room, { phase: health <= 0 ? 'dying' : 'play_phase', dyingPlayerId: health <= 0 ? uid : admin.firestore.FieldValue.delete(), deckRemainingCount: pile.length, updatedAt: serverNow() }); });
    return {};
});
/** Safe post-action trigger for Suzy Lafayette whenever her hand becomes empty. */
exports.triggerSuzyLafayette = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const uid = request.auth.uid;
    const roomId = request.data?.roomId;
    if (!roomId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu roomId.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const player = await tx.get(room.collection('players').doc(uid)); const own = await tx.get(room.collection('privateStates').doc(uid)); const deck = await tx.get(room.collection('serverState').doc('deck')); const hand = [...(own.get('handCardIds') ?? [])]; const pile = [...(deck.get('drawPile') ?? [])]; if (!player.exists || player.get('characterId') !== 'suzy_lafayette' || player.get('isAlive') === false || hand.length !== 0 || !pile.length)
        return; const drawn = pile.shift(); tx.update(own.ref, { handCardIds: [drawn] }); tx.update(player.ref, { cardCount: 1 }); tx.update(deck.ref, { drawPile: pile }); tx.update(room, { deckRemainingCount: pile.length, updatedAt: serverNow() }); });
    return {};
});
/** Lets any connected client safely advance an expired server-owned response. */
exports.resolveExpiredResponse = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu đăng nhập.');
    const { roomId, pendingActionId } = request.data;
    if (!roomId || !pendingActionId)
        throw new https_1.HttpsError('invalid-argument', 'Thiếu action hết hạn.');
    const room = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => { const pending = await tx.get(room.collection('pendingActions').doc(pendingActionId)); const state = await tx.get(room); if (!pending.exists || pending.get('status') !== 'waiting')
        return; const deadline = pending.get('responseDeadlineAt'); if (!deadline || deadline.toMillis() > Date.now())
        throw new https_1.HttpsError('failed-precondition', 'Action chưa hết hạn.'); const targetId = String(pending.get('targetPlayerId') ?? pending.get('currentTargetId') ?? ''); const target = await tx.get(room.collection('players').doc(targetId)); if (!target.exists) {
        tx.delete(pending.ref);
        tx.update(room, { phase: 'play_phase', updatedAt: serverNow() });
        return;
    } const health = Number(target.get('health')) - 1; tx.update(target.ref, { health }); tx.delete(pending.ref); tx.update(room, { phase: health <= 0 ? 'dying' : 'play_phase', dyingPlayerId: health <= 0 ? targetId : admin.firestore.FieldValue.delete(), updatedAt: serverNow() }); });
    return {};
});
