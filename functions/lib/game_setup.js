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
exports.resumeGameSetup = exports.chooseCharacter = exports.beginGameSetup = void 0;
const crypto_1 = require("crypto");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/firestore");
const https_1 = require("firebase-functions/https");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const roles = (count) => {
    if (count === 4)
        return ["sheriff", "deputy", "outlaw", "outlaw"];
    if (count < 4 || count > 8)
        throw new https_1.HttpsError("failed-precondition", "Phòng chỉ hỗ trợ 4–8 người.");
    const police = Math.floor((count - 1) / 2);
    return [
        "sheriff",
        ...Array(police - 1).fill("deputy"),
        ...Array(count - 1 - police).fill("outlaw"),
        "renegade",
    ];
};
const shuffled = (values) => {
    const copy = [...values];
    for (let i = copy.length - 1; i > 0; i--) {
        const j = (0, crypto_1.randomInt)(i + 1);
        [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
};
const characters = [
    ["paul_regret", 3],
    ["el_gringo", 3],
    ["vulture_sam", 4],
    ["calamity_janet", 4],
    ["black_jack", 4],
    ["willy_the_kid", 4],
    ["lucky_duke", 4],
    ["kit_carlson", 4],
    ["rose_doolan", 4],
    ["suzy_lafayette", 4],
    ["bart_cassidy", 4],
    ["jesse_jones", 4],
    ["slab_the_killer", 4],
    ["sid_ketchum", 4],
    ["jourdonnais", 4],
    ["pedro_ramirez", 4],
];
const cardTypes = [
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
    "appaloosa",
];
const ranks = [
    "ace",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "ten",
    "jack",
    "queen",
    "king",
];
const suits = ["spade", "club", "diamond", "heart"];
const now = () => admin.firestore.FieldValue.serverTimestamp();
function deck() {
    if (cardTypes.length !== 52)
        throw new Error("Deck config must have exactly 52 cards.");
    let i = 0;
    return suits.flatMap((suit) => ranks.map((rank) => ({
        id: `${cardTypes[i]}_${rank}_${suit}`,
        type: cardTypes[i++],
        rank,
        suit,
    })));
}
async function initialize(roomId) {
    const roomRef = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(roomRef);
        if (!room.exists ||
            room.get("status") !== "starting" ||
            room.get("phase") !== "assigning_roles")
            return;
        const players = (await tx.get(roomRef.collection("players"))).docs.sort((a, b) => a.get("seat") - b.get("seat"));
        const humans = players.filter((p) => p.get("playerType") === "human");
        const guests = humans.filter((p) => p.id !== room.get("hostUid"));
        if (players.length < 4 ||
            players.length > 8 ||
            humans.length < 1 ||
            players.length > room.get("maxPlayers") ||
            new Set(players.map((p) => p.id)).size !== players.length ||
            new Set(players.map((p) => p.get("seat"))).size !== players.length ||
            guests.some((p) => !p.get("isReady") || p.get("connectionState") !== "online"))
            throw new https_1.HttpsError("failed-precondition", "Danh sách phòng không hợp lệ.");
        const assigned = shuffled(roles(players.length));
        const sheriffIndex = assigned.indexOf("sheriff");
        const offered = shuffled(characters);
        if (offered.length < players.length * 2)
            throw new https_1.HttpsError("failed-precondition", "Không đủ thẻ nhân vật.");
        const deadline = admin.firestore.Timestamp.fromMillis(Date.now() + 20000);
        players.forEach((player, index) => {
            const role = assigned[index];
            const options = [offered[index * 2][0], offered[index * 2 + 1][0]];
            const isBot = player.get("playerType") === "bot";
            tx.set(roomRef.collection("privateStates").doc(player.id), {
                role,
                roleAssigned: true,
                characterOptions: options,
                selectedCharacterId: isBot ? options[(0, crypto_1.randomInt)(2)] : null,
                characterSelectionSubmitted: isBot,
                handCardIds: [],
            });
        });
        tx.update(roomRef, {
            sheriffPlayerId: players[sheriffIndex].id,
            phase: "choosing_character",
            characterDeadlineAt: deadline,
            updatedAt: now(),
        });
    });
    await finalizeIfReady(roomId, false);
}
async function finalizeIfReady(roomId, force) {
    const roomRef = db.doc(`rooms/${roomId}`);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(roomRef);
        if (!room.exists ||
            room.get("status") !== "starting" ||
            room.get("phase") !== "choosing_character")
            return;
        const players = (await tx.get(roomRef.collection("players"))).docs.sort((a, b) => a.get("seat") - b.get("seat"));
        const states = await Promise.all(players.map((player) => tx.get(roomRef.collection("privateStates").doc(player.id))));
        const deadline = room.get("characterDeadlineAt");
        if (!force &&
            states.some((state) => !state.get("characterSelectionSubmitted")) &&
            deadline.toMillis() > Date.now())
            return;
        const shuffledDeck = shuffled(deck());
        let cursor = 0;
        players.forEach((player, index) => {
            const state = states[index];
            const options = state.get("characterOptions");
            const selected = state.get("selectedCharacterId") ?? options[(0, crypto_1.randomInt)(options.length)];
            const baseHealth = characters.find((character) => character[0] === selected)?.[1] ?? 4;
            const health = baseHealth + (player.id === room.get("sheriffPlayerId") ? 1 : 0);
            const hand = shuffledDeck
                .slice(cursor, (cursor += health))
                .map((card) => card.id);
            tx.update(player.ref, {
                characterId: selected,
                maxHealth: health,
                health,
                cardCount: hand.length,
            });
            tx.set(state.ref, {
                selectedCharacterId: selected,
                characterSelectionSubmitted: true,
                handCardIds: hand,
            }, { merge: true });
        });
        tx.set(roomRef.collection("serverState").doc("deck"), {
            deckVersion: "mvp_1",
            drawPile: shuffledDeck.slice(cursor).map((card) => card.id),
            discardPile: [],
            initialized: true,
        });
        tx.update(roomRef, {
            status: "playing",
            phase: "turn_start",
            deckRemainingCount: 52 - cursor,
            discardCount: 0,
            discardTopCardId: null,
            currentTurnPlayerId: room.get("sheriffPlayerId"),
            turnNumber: 1,
            roundNumber: 1,
            cardsPlayedThisTurn: 0,
            turnStartedAt: now(),
            turnDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + Number(room.get("turnDurationSeconds")) * 1000),
            updatedAt: now(),
        });
    });
}
exports.beginGameSetup = (0, firestore_1.onDocumentUpdated)("rooms/{roomId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status !== "starting" &&
        after?.status === "starting" &&
        after?.phase === "assigning_roles")
        await initialize(event.params.roomId);
});
exports.chooseCharacter = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
    const playerId = request.auth.uid;
    const { roomId, characterId, actionId } = request.data;
    if (!roomId || !characterId || !actionId)
        throw new https_1.HttpsError("invalid-argument", "Thiếu dữ liệu chọn nhân vật.");
    const roomRef = db.doc(`rooms/${roomId}`);
    const stateRef = roomRef.collection("privateStates").doc(playerId);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(roomRef);
        const state = await tx.get(stateRef);
        if (!room.exists ||
            room.get("phase") !== "choosing_character" ||
            !state.exists ||
            state.get("characterSelectionSubmitted") ||
            room.get("characterDeadlineAt").toMillis() < Date.now())
            throw new https_1.HttpsError("failed-precondition", "Không thể chọn nhân vật.");
        const options = state.get("characterOptions");
        if (!options.includes(characterId))
            throw new https_1.HttpsError("permission-denied", "Nhân vật không thuộc lựa chọn của bạn.");
        const action = await tx.get(roomRef.collection("actions").doc(actionId));
        if (action.exists)
            return;
        tx.set(action.ref, {
            uid: playerId,
            type: "choose_character",
            createdAt: now(),
        });
        tx.update(stateRef, {
            selectedCharacterId: characterId,
            characterSelectionSubmitted: true,
        });
    });
    await finalizeIfReady(roomId, false);
    return { roomId };
});
exports.resumeGameSetup = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
    const roomId = String(request.data.roomId ?? "");
    const room = await db.doc(`rooms/${roomId}`).get();
    if (!room.exists)
        throw new https_1.HttpsError("not-found", "Không tìm thấy phòng.");
    if (room.get("phase") === "choosing_character" &&
        room.get("characterDeadlineAt").toMillis() <= Date.now())
        await finalizeIfReady(roomId, true);
    return {
        status: room.get("status"),
        phase: room.get("phase"),
        sheriffPlayerId: room.get("sheriffPlayerId"),
    };
});
