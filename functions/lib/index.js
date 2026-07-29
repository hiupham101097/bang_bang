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
exports.startGame = exports.leaveRoom = exports.removeBot = exports.addBot = exports.setReady = exports.quickJoinRoom = exports.joinRoom = exports.createRoom = exports.useSidKetchum = exports.useCalamityJanetDodge = exports.triggerSuzyLafayette = exports.startDuel = exports.respondDuel = exports.startMultiAttack = exports.respondMultiAttack = exports.resolveTurnJudgments = exports.resolveTargetCard = exports.resolveSlabDodge = exports.resolveJourdonnais = exports.resolveExpiredResponse = exports.playSpecialCard = exports.openLuckyDukeJudgment = exports.openKitCarlson = exports.openGeneralStore = exports.drawJesseJones = exports.drawCharacterTurnCards = exports.chooseLuckyDukeJudgment = exports.chooseKitCarlson = exports.chooseGeneralStoreCard = exports.acceptBangDamage = exports.expireTurn = exports.expireSequentialResponse = exports.expireBangResponse = exports.setBangResponseDeadline = exports.applySuzyLafayette = exports.applyBartCassidyDamage = exports.resolveElimination = exports.resolveTurnTimeout = exports.saveDyingPlayer = exports.resolveDying = exports.discardCards = exports.requestEndTurn = exports.respondToAction = exports.playCard = exports.drawTurnCards = exports.runBotResponse = exports.runBotTurn = exports.resumeGameSetup = exports.chooseCharacter = exports.beginGameSetup = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/https");
var game_setup_1 = require("./game_setup");
Object.defineProperty(exports, "beginGameSetup", { enumerable: true, get: function () { return game_setup_1.beginGameSetup; } });
Object.defineProperty(exports, "chooseCharacter", { enumerable: true, get: function () { return game_setup_1.chooseCharacter; } });
Object.defineProperty(exports, "resumeGameSetup", { enumerable: true, get: function () { return game_setup_1.resumeGameSetup; } });
var bot_turns_1 = require("./bot_turns");
Object.defineProperty(exports, "runBotTurn", { enumerable: true, get: function () { return bot_turns_1.runBotTurn; } });
var bot_responses_1 = require("./bot_responses");
Object.defineProperty(exports, "runBotResponse", { enumerable: true, get: function () { return bot_responses_1.runBotResponse; } });
var game_play_1 = require("./game_play");
Object.defineProperty(exports, "drawTurnCards", { enumerable: true, get: function () { return game_play_1.drawTurnCards; } });
Object.defineProperty(exports, "playCard", { enumerable: true, get: function () { return game_play_1.playCard; } });
Object.defineProperty(exports, "respondToAction", { enumerable: true, get: function () { return game_play_1.respondToAction; } });
Object.defineProperty(exports, "requestEndTurn", { enumerable: true, get: function () { return game_play_1.requestEndTurn; } });
Object.defineProperty(exports, "discardCards", { enumerable: true, get: function () { return game_play_1.discardCards; } });
Object.defineProperty(exports, "resolveDying", { enumerable: true, get: function () { return game_play_1.resolveDying; } });
Object.defineProperty(exports, "saveDyingPlayer", { enumerable: true, get: function () { return game_play_1.saveDyingPlayer; } });
Object.defineProperty(exports, "resolveTurnTimeout", { enumerable: true, get: function () { return game_play_1.resolveTurnTimeout; } });
var game_resolution_1 = require("./game_resolution");
Object.defineProperty(exports, "resolveElimination", { enumerable: true, get: function () { return game_resolution_1.resolveElimination; } });
var character_triggers_1 = require("./character_triggers");
Object.defineProperty(exports, "applyBartCassidyDamage", { enumerable: true, get: function () { return character_triggers_1.applyBartCassidyDamage; } });
Object.defineProperty(exports, "applySuzyLafayette", { enumerable: true, get: function () { return character_triggers_1.applySuzyLafayette; } });
Object.defineProperty(exports, "setBangResponseDeadline", { enumerable: true, get: function () { return character_triggers_1.setBangResponseDeadline; } });
var auto_timeouts_1 = require("./auto_timeouts");
Object.defineProperty(exports, "expireBangResponse", { enumerable: true, get: function () { return auto_timeouts_1.expireBangResponse; } });
Object.defineProperty(exports, "expireSequentialResponse", { enumerable: true, get: function () { return auto_timeouts_1.expireSequentialResponse; } });
Object.defineProperty(exports, "expireTurn", { enumerable: true, get: function () { return auto_timeouts_1.expireTurn; } });
var game_phase4_1 = require("./game_phase4");
Object.defineProperty(exports, "acceptBangDamage", { enumerable: true, get: function () { return game_phase4_1.acceptBangDamage; } });
Object.defineProperty(exports, "chooseGeneralStoreCard", { enumerable: true, get: function () { return game_phase4_1.chooseGeneralStoreCard; } });
Object.defineProperty(exports, "chooseKitCarlson", { enumerable: true, get: function () { return game_phase4_1.chooseKitCarlson; } });
Object.defineProperty(exports, "chooseLuckyDukeJudgment", { enumerable: true, get: function () { return game_phase4_1.chooseLuckyDukeJudgment; } });
Object.defineProperty(exports, "drawCharacterTurnCards", { enumerable: true, get: function () { return game_phase4_1.drawCharacterTurnCards; } });
Object.defineProperty(exports, "drawJesseJones", { enumerable: true, get: function () { return game_phase4_1.drawJesseJones; } });
Object.defineProperty(exports, "openGeneralStore", { enumerable: true, get: function () { return game_phase4_1.openGeneralStore; } });
Object.defineProperty(exports, "openKitCarlson", { enumerable: true, get: function () { return game_phase4_1.openKitCarlson; } });
Object.defineProperty(exports, "openLuckyDukeJudgment", { enumerable: true, get: function () { return game_phase4_1.openLuckyDukeJudgment; } });
Object.defineProperty(exports, "playSpecialCard", { enumerable: true, get: function () { return game_phase4_1.playSpecialCard; } });
Object.defineProperty(exports, "resolveExpiredResponse", { enumerable: true, get: function () { return game_phase4_1.resolveExpiredResponse; } });
Object.defineProperty(exports, "resolveJourdonnais", { enumerable: true, get: function () { return game_phase4_1.resolveJourdonnais; } });
Object.defineProperty(exports, "resolveSlabDodge", { enumerable: true, get: function () { return game_phase4_1.resolveSlabDodge; } });
Object.defineProperty(exports, "resolveTargetCard", { enumerable: true, get: function () { return game_phase4_1.resolveTargetCard; } });
Object.defineProperty(exports, "resolveTurnJudgments", { enumerable: true, get: function () { return game_phase4_1.resolveTurnJudgments; } });
Object.defineProperty(exports, "respondMultiAttack", { enumerable: true, get: function () { return game_phase4_1.respondMultiAttack; } });
Object.defineProperty(exports, "startMultiAttack", { enumerable: true, get: function () { return game_phase4_1.startMultiAttack; } });
Object.defineProperty(exports, "respondDuel", { enumerable: true, get: function () { return game_phase4_1.respondDuel; } });
Object.defineProperty(exports, "startDuel", { enumerable: true, get: function () { return game_phase4_1.startDuel; } });
Object.defineProperty(exports, "triggerSuzyLafayette", { enumerable: true, get: function () { return game_phase4_1.triggerSuzyLafayette; } });
Object.defineProperty(exports, "useCalamityJanetDodge", { enumerable: true, get: function () { return game_phase4_1.useCalamityJanetDodge; } });
Object.defineProperty(exports, "useSidKetchum", { enumerable: true, get: function () { return game_phase4_1.useSidKetchum; } });
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const rooms = db.collection("rooms");
const now = () => admin.firestore.FieldValue.serverTimestamp();
const code = () => Array.from({ length: 6 }, () => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[Math.floor(Math.random() * 32)]).join("");
const uid = (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
    return request.auth.uid;
};
const roomId = (data) => {
    if (typeof data.roomId !== "string")
        throw new https_1.HttpsError("invalid-argument", "Thiếu roomId.");
    return data.roomId;
};
const member = (id, name, seat, host = false) => ({
    playerType: "human",
    uid: id,
    displayName: name,
    avatarId: "avatar_01",
    seat,
    isHost: host,
    isReady: false,
    connectionState: "online",
    joinedAt: now(),
});
exports.createRoom = (0, https_1.onCall)(async (request) => {
    const owner = uid(request);
    const data = request.data;
    const maxPlayers = Number(data.maxPlayers ?? 8);
    if (!Number.isInteger(maxPlayers) || maxPlayers < 4 || maxPlayers > 8)
        throw new https_1.HttpsError("invalid-argument", "Cấu hình phòng không hợp lệ.");
    const ref = rooms.doc();
    const roomCode = code();
    const name = `Bàn ${roomCode}`;
    const profile = await db.doc(`users/${owner}`).get();
    const displayName = profile.get("displayName") ?? `Cao bồi ${owner.slice(0, 5)}`;
    await db.runTransaction(async (tx) => {
        tx.set(ref, {
            roomCode,
            roomName: name,
            hostUid: owner,
            status: "waiting",
            phase: "lobby",
            isPublic: data.isPublic !== false,
            minPlayers: 4,
            maxPlayers,
            humanPlayerCount: 1,
            botPlayerCount: 0,
            totalPlayerCount: 1,
            allowBots: data.allowBots !== false,
            turnDurationSeconds: Number(data.turnDurationSeconds ?? 45),
            responseDurationSeconds: 8,
            voiceEnabled: data.voiceEnabled !== false,
            chatEnabled: data.chatEnabled !== false,
            createdAt: now(),
            updatedAt: now(),
        });
        tx.set(ref.collection("players").doc(owner), member(owner, displayName, 0, true));
        tx.set(db.doc(`users/${owner}`), { currentRoomId: ref.id, updatedAt: now() }, { merge: true });
    });
    return { roomId: ref.id };
});
exports.joinRoom = (0, https_1.onCall)(async (request) => {
    const player = uid(request);
    const data = request.data;
    let id = typeof data.roomId === "string" ? data.roomId : "";
    if (!id && typeof data.roomCode === "string") {
        const hit = await rooms
            .where("roomCode", "==", data.roomCode.toUpperCase())
            .limit(1)
            .get();
        id = hit.docs[0]?.id ?? "";
    }
    if (!id)
        throw new https_1.HttpsError("not-found", "Không tìm thấy phòng.");
    const ref = rooms.doc(id);
    const profile = await db.doc(`users/${player}`).get();
    const displayName = profile.get("displayName") ?? `Cao bồi ${player.slice(0, 5)}`;
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists ||
            snap.get("status") !== "waiting" ||
            snap.get("totalPlayerCount") >= snap.get("maxPlayers"))
            throw new https_1.HttpsError("failed-precondition", "Phòng đã bắt đầu hoặc đầy.");
        const mine = await tx.get(ref.collection("players").doc(player));
        if (mine.exists)
            return;
        const players = await tx.get(ref.collection("players"));
        const occupied = new Set(players.docs.map((d) => d.get("seat")));
        const seat = Array.from({ length: snap.get("maxPlayers") }, (_, i) => i).find((i) => !occupied.has(i));
        if (seat === undefined)
            throw new https_1.HttpsError("resource-exhausted", "Không còn ghế.");
        tx.set(ref.collection("players").doc(player), member(player, displayName, seat));
        tx.update(ref, {
            humanPlayerCount: admin.firestore.FieldValue.increment(1),
            totalPlayerCount: admin.firestore.FieldValue.increment(1),
            updatedAt: now(),
        });
        tx.set(db.doc(`users/${player}`), { currentRoomId: id, updatedAt: now() }, { merge: true });
    });
    return { roomId: id };
});
exports.quickJoinRoom = (0, https_1.onCall)(async (request) => {
    uid(request);
    const hits = await rooms
        .where("status", "==", "waiting")
        .where("isPublic", "==", true)
        .orderBy("updatedAt", "desc")
        .limit(20)
        .get();
    const candidate = hits.docs
        .filter((d) => d.get("totalPlayerCount") < d.get("maxPlayers"))
        .sort((a, b) => b.get("humanPlayerCount") - a.get("humanPlayerCount") ||
        a.get("botPlayerCount") - b.get("botPlayerCount"))[0];
    if (!candidate)
        return { roomId: null };
    return exports.joinRoom.run({
        data: { roomId: candidate.id },
        auth: request.auth,
    });
});
exports.setReady = (0, https_1.onCall)(async (request) => {
    const player = uid(request);
    const id = roomId(request.data);
    const ref = rooms.doc(id);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(ref);
        const mine = ref.collection("players").doc(player);
        if (!room.exists ||
            room.get("status") !== "waiting" ||
            !(await tx.get(mine)).exists)
            throw new https_1.HttpsError("failed-precondition", "Không thể sẵn sàng.");
        tx.update(mine, { isReady: request.data.isReady === true });
        tx.update(ref, { updatedAt: now() });
    });
    return {};
});
exports.addBot = (0, https_1.onCall)(async (request) => {
    const owner = uid(request);
    const id = roomId(request.data);
    const ref = rooms.doc(id);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(ref);
        if (!room.exists ||
            room.get("hostUid") !== owner ||
            room.get("status") !== "waiting" ||
            !room.get("allowBots") ||
            room.get("totalPlayerCount") >= room.get("maxPlayers"))
            throw new https_1.HttpsError("permission-denied", "Không thể thêm bot.");
        const players = await tx.get(ref.collection("players"));
        const occupied = new Set(players.docs.map((d) => d.get("seat")));
        const seat = Array.from({ length: room.get("maxPlayers") }, (_, i) => i).find((i) => !occupied.has(i));
        const bot = `bot_${db.collection("_").doc().id}`;
        tx.set(ref.collection("players").doc(bot), {
            playerType: "bot",
            botId: bot,
            displayName: "Billy Bot",
            avatarId: "avatar_bot_01",
            difficulty: request.data.difficulty ?? "normal",
            seat,
            isHost: false,
            isReady: true,
            connectionState: "online",
            createdAt: now(),
        });
        tx.update(ref, {
            botPlayerCount: admin.firestore.FieldValue.increment(1),
            totalPlayerCount: admin.firestore.FieldValue.increment(1),
            updatedAt: now(),
        });
    });
    return {};
});
exports.removeBot = (0, https_1.onCall)(async (request) => {
    const owner = uid(request);
    const id = roomId(request.data);
    const botId = String(request.data.botId ?? "");
    const ref = rooms.doc(id);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(ref);
        const bot = await tx.get(ref.collection("players").doc(botId));
        if (!room.exists ||
            room.get("hostUid") !== owner ||
            !bot.exists ||
            bot.get("playerType") !== "bot")
            throw new https_1.HttpsError("permission-denied", "Không thể xóa bot.");
        tx.delete(bot.ref);
        tx.update(ref, {
            botPlayerCount: admin.firestore.FieldValue.increment(-1),
            totalPlayerCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: now(),
        });
    });
    return {};
});
exports.leaveRoom = (0, https_1.onCall)(async (request) => {
    const player = uid(request);
    const id = roomId(request.data);
    const ref = rooms.doc(id);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(ref);
        const mine = await tx.get(ref.collection("players").doc(player));
        if (!room.exists || !mine.exists)
            return;
        tx.delete(mine.ref);
        tx.update(ref, {
            humanPlayerCount: admin.firestore.FieldValue.increment(-1),
            totalPlayerCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: now(),
        });
        tx.set(db.doc(`users/${player}`), { currentRoomId: admin.firestore.FieldValue.delete(), updatedAt: now() }, { merge: true });
    });
    return {};
});
exports.startGame = (0, https_1.onCall)(async (request) => {
    const owner = uid(request);
    const id = roomId(request.data);
    const ref = rooms.doc(id);
    await db.runTransaction(async (tx) => {
        const room = await tx.get(ref);
        const players = await tx.get(ref.collection("players"));
        const caller = players.docs.find((player) => player.id === owner);
        const humans = players.docs.filter((d) => d.get("playerType") === "human");
        const guests = humans.filter((d) => d.id !== owner);
        if (!room.exists ||
            (room.get("hostUid") !== owner && caller?.get("isHost") !== true) ||
            room.get("status") !== "waiting" ||
            players.size < 4 ||
            humans.length < 1 ||
            guests.some((d) => !d.get("isReady") || d.get("connectionState") !== "online"))
            throw new https_1.HttpsError("failed-precondition", "Cần đủ 4 người chơi và mọi khách phải sẵn sàng.");
        tx.update(ref, {
            hostUid: owner,
            status: "starting",
            phase: "assigning_roles",
            startedAt: now(),
            updatedAt: now(),
        });
    });
    return { roomId: id };
});
