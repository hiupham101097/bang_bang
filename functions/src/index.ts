import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/https";
export { beginGameSetup, chooseCharacter, resumeGameSetup } from "./game_setup";
export { runBotTurn } from "./bot_turns";
export { runBotResponse } from "./bot_responses";
export {
  drawTurnCards,
  playCard,
  respondToAction,
  requestEndTurn,
  discardCards,
  resolveDying,
  resolveTurnTimeout,
} from "./game_play";
export { resolveElimination } from "./game_resolution";
export {
  applyBartCassidyDamage,
  applySuzyLafayette,
  setBangResponseDeadline,
} from "./character_triggers";
export {
  acceptBangDamage,
  chooseGeneralStoreCard,
  chooseKitCarlson,
  chooseLuckyDukeJudgment,
  drawCharacterTurnCards,
  drawJesseJones,
  openGeneralStore,
  openKitCarlson,
  openLuckyDukeJudgment,
  playSpecialCard,
  resolveExpiredResponse,
  resolveJourdonnais,
  resolveSlabDodge,
  resolveTargetCard,
  resolveTurnJudgments,
  respondMultiAttack,
  startMultiAttack,
  respondDuel,
  startDuel,
  triggerSuzyLafayette,
  useCalamityJanetDodge,
  useSidKetchum,
} from "./game_phase4";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const rooms = db.collection("rooms");
const now = () => admin.firestore.FieldValue.serverTimestamp();
const code = () =>
  Array.from(
    { length: 6 },
    () => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[Math.floor(Math.random() * 32)],
  ).join("");
const uid = (request: { auth?: { uid: string } }) => {
  if (!request.auth)
    throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  return request.auth.uid;
};
const roomId = (data: { roomId?: unknown }) => {
  if (typeof data.roomId !== "string")
    throw new HttpsError("invalid-argument", "Thiếu roomId.");
  return data.roomId;
};
const member = (id: string, name: string, seat: number, host = false) => ({
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

export const createRoom = onCall(async (request) => {
  const owner = uid(request);
  const data = request.data as Record<string, unknown>;
  const maxPlayers = Number(data.maxPlayers ?? 8);
  if (!Number.isInteger(maxPlayers) || maxPlayers < 4 || maxPlayers > 8)
    throw new HttpsError("invalid-argument", "Cấu hình phòng không hợp lệ.");
  const ref = rooms.doc();
  const roomCode = code();
  const name = `Bàn ${roomCode}`;
  const profile = await db.doc(`users/${owner}`).get();
  const displayName =
    profile.get("displayName") ?? `Cao bồi ${owner.slice(0, 5)}`;
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
    tx.set(
      ref.collection("players").doc(owner),
      member(owner, displayName, 0, true),
    );
    tx.set(
      db.doc(`users/${owner}`),
      { currentRoomId: ref.id, updatedAt: now() },
      { merge: true },
    );
  });
  return { roomId: ref.id };
});

export const joinRoom = onCall(async (request) => {
  const player = uid(request);
  const data = request.data as Record<string, unknown>;
  let id = typeof data.roomId === "string" ? data.roomId : "";
  if (!id && typeof data.roomCode === "string") {
    const hit = await rooms
      .where("roomCode", "==", data.roomCode.toUpperCase())
      .limit(1)
      .get();
    id = hit.docs[0]?.id ?? "";
  }
  if (!id) throw new HttpsError("not-found", "Không tìm thấy phòng.");
  const ref = rooms.doc(id);
  const profile = await db.doc(`users/${player}`).get();
  const displayName =
    profile.get("displayName") ?? `Cao bồi ${player.slice(0, 5)}`;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (
      !snap.exists ||
      snap.get("status") !== "waiting" ||
      snap.get("totalPlayerCount") >= snap.get("maxPlayers")
    )
      throw new HttpsError("failed-precondition", "Phòng đã bắt đầu hoặc đầy.");
    const mine = await tx.get(ref.collection("players").doc(player));
    if (mine.exists) return;
    const players = await tx.get(ref.collection("players"));
    const occupied = new Set(players.docs.map((d) => d.get("seat")));
    const seat = Array.from(
      { length: snap.get("maxPlayers") },
      (_, i) => i,
    ).find((i) => !occupied.has(i));
    if (seat === undefined)
      throw new HttpsError("resource-exhausted", "Không còn ghế.");
    tx.set(
      ref.collection("players").doc(player),
      member(player, displayName, seat),
    );
    tx.update(ref, {
      humanPlayerCount: admin.firestore.FieldValue.increment(1),
      totalPlayerCount: admin.firestore.FieldValue.increment(1),
      updatedAt: now(),
    });
    tx.set(
      db.doc(`users/${player}`),
      { currentRoomId: id, updatedAt: now() },
      { merge: true },
    );
  });
  return { roomId: id };
});

export const quickJoinRoom = onCall(async (request) => {
  uid(request);
  const hits = await rooms
    .where("status", "==", "waiting")
    .where("isPublic", "==", true)
    .orderBy("updatedAt", "desc")
    .limit(20)
    .get();
  const candidate = hits.docs
    .filter((d) => d.get("totalPlayerCount") < d.get("maxPlayers"))
    .sort(
      (a, b) =>
        b.get("humanPlayerCount") - a.get("humanPlayerCount") ||
        a.get("botPlayerCount") - b.get("botPlayerCount"),
    )[0];
  if (!candidate) return { roomId: null };
  return joinRoom.run({
    data: { roomId: candidate.id },
    auth: request.auth,
  } as never);
});

export const setReady = onCall(async (request) => {
  const player = uid(request);
  const id = roomId(request.data);
  const ref = rooms.doc(id);
  await db.runTransaction(async (tx) => {
    const room = await tx.get(ref);
    const mine = ref.collection("players").doc(player);
    if (
      !room.exists ||
      room.get("status") !== "waiting" ||
      !(await tx.get(mine)).exists
    )
      throw new HttpsError("failed-precondition", "Không thể sẵn sàng.");
    tx.update(mine, { isReady: request.data.isReady === true });
    tx.update(ref, { updatedAt: now() });
  });
  return {};
});
export const addBot = onCall(async (request) => {
  const owner = uid(request);
  const id = roomId(request.data);
  const ref = rooms.doc(id);
  await db.runTransaction(async (tx) => {
    const room = await tx.get(ref);
    if (
      !room.exists ||
      room.get("hostUid") !== owner ||
      room.get("status") !== "waiting" ||
      !room.get("allowBots") ||
      room.get("totalPlayerCount") >= room.get("maxPlayers")
    )
      throw new HttpsError("permission-denied", "Không thể thêm bot.");
    const players = await tx.get(ref.collection("players"));
    const occupied = new Set(players.docs.map((d) => d.get("seat")));
    const seat = Array.from(
      { length: room.get("maxPlayers") },
      (_, i) => i,
    ).find((i) => !occupied.has(i));
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
export const removeBot = onCall(async (request) => {
  const owner = uid(request);
  const id = roomId(request.data);
  const botId = String(request.data.botId ?? "");
  const ref = rooms.doc(id);
  await db.runTransaction(async (tx) => {
    const room = await tx.get(ref);
    const bot = await tx.get(ref.collection("players").doc(botId));
    if (
      !room.exists ||
      room.get("hostUid") !== owner ||
      !bot.exists ||
      bot.get("playerType") !== "bot"
    )
      throw new HttpsError("permission-denied", "Không thể xóa bot.");
    tx.delete(bot.ref);
    tx.update(ref, {
      botPlayerCount: admin.firestore.FieldValue.increment(-1),
      totalPlayerCount: admin.firestore.FieldValue.increment(-1),
      updatedAt: now(),
    });
  });
  return {};
});
export const leaveRoom = onCall(async (request) => {
  const player = uid(request);
  const id = roomId(request.data);
  const ref = rooms.doc(id);
  await db.runTransaction(async (tx) => {
    const room = await tx.get(ref);
    const mine = await tx.get(ref.collection("players").doc(player));
    if (!room.exists || !mine.exists) return;
    tx.delete(mine.ref);
    tx.update(ref, {
      humanPlayerCount: admin.firestore.FieldValue.increment(-1),
      totalPlayerCount: admin.firestore.FieldValue.increment(-1),
      updatedAt: now(),
    });
    tx.set(
      db.doc(`users/${player}`),
      { currentRoomId: admin.firestore.FieldValue.delete(), updatedAt: now() },
      { merge: true },
    );
  });
  return {};
});
export const startGame = onCall(async (request) => {
  const owner = uid(request);
  const id = roomId(request.data);
  const ref = rooms.doc(id);
  await db.runTransaction(async (tx) => {
    const room = await tx.get(ref);
    const players = await tx.get(ref.collection("players"));
    const humans = players.docs.filter((d) => d.get("playerType") === "human");
    const guests = humans.filter((d) => d.id !== owner);
    if (
      !room.exists ||
      room.get("hostUid") !== owner ||
      room.get("status") !== "waiting" ||
      players.size < 4 ||
      humans.length < 1 ||
      guests.some(
        (d) => !d.get("isReady") || d.get("connectionState") !== "online",
      )
    )
      throw new HttpsError(
        "failed-precondition",
        "Cần đủ 4 người chơi và mọi khách phải sẵn sàng.",
      );
    tx.update(ref, {
      status: "starting",
      phase: "assigning_roles",
      startedAt: now(),
      updatedAt: now(),
    });
  });
  return { roomId: id };
});
