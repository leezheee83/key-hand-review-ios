import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import vm from "node:vm";
import test from "node:test";
import ts from "typescript";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

const require = createRequire(import.meta.url);
const source = await readFile(new URL("../app/HandReviewApp.tsx", import.meta.url), "utf8");
const compiled = ts.transpileModule(source + "\nexport { StartScreen, QuickScreen, SettlementScreen, RouteScreen, HandReplay, actionText, replaySteps, replayBoard, handState, totalBuyIn, saveSnapshot };", {
  compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022 },
}).outputText;
function load(indexedDB) {
  const exports = {};
  vm.runInNewContext(compiled, { exports, indexedDB, require: (name) => name === "./historicalProfits" ? { historicalProfits: [] } : require(name) });
  return exports;
}
const app = load();
const noop = () => {};
const session = { id: "test-session", sb: 5, bb: 10, playerCount: 9, straddles: [], squidGame: true, createdAt: "2026-10-23T12:00:00", buyIns: [{ id: "a", amount: 1000, at: "2026-10-23T12:00:00" }, { id: "b", amount: 500, at: "2026-10-23T13:00:00" }], result: { profit: 300, durationHours: 4, stakes: "5/10", location: "", note: "", source: "app" } };
const hand = { id: "h", createdAt: session.createdAt, captureState: "editing", status: "draft", note: "转牌面对加注", heroCards: [], heroPosition: "CO", playerCount: 9, effectiveStackBB: 100, tags: ["待复盘"], review: { decision: "", basis: "", correction: "" } };

test("home prioritizes starting a session and reuses last table settings without copying buy-in", () => {
  const html = renderToStaticMarkup(React.createElement(app.StartScreen, { archives: [{ session, hands: [hand] }], activeSessionID: null, onStart: noop, onOpen: noop, onBackup: noop, onLedger: noop, onAddResult: noop }));
  assert.ok(html.indexOf("开始一场") < html.indexOf("累计盈亏"));
  assert.match(html, /5\/10 · 9 人 · 无 Straddle · 有鱿鱼/);
  assert.match(html, /沿用上次设置/);
  assert.match(html, /首次买入.*?value=""/s);
  assert.match(html, /<details class="optional-section">/);
  assert.match(html, /累计盈利曲线/);
});

test("note-only hand can be saved; optional controls remain collapsed", () => {
  const html = renderToStaticMarkup(React.createElement(app.QuickScreen, { hand, bigBlind: 10, saveState: "已保存到本机", onRetry: noop, onChange: noop, onCancel: noop, onSave: noop }));
  assert.match(html, /转牌面对加注/);
  assert.match(html, /<button class="primary">保存这手，回到本场<\/button>/);
  assert.match(html, /<details class="optional-section">/);
  assert.match(html, /role="status"/);
});

test("hand state does not require later streets for a preflop review", () => {
  assert.equal(app.handState(hand), "草稿");
  assert.equal(app.handState({ ...hand, captureState: "saved" }), "待复盘");
  assert.equal(app.handState({ ...hand, captureState: "saved", review: { ...hand.review, decision: "翻前应弃牌" } }), "已复盘");
  assert.equal(app.totalBuyIn(session), 1500);
  assert.equal(app.totalBuyIn({ result: { buyIn: 800 } }), 800);
});

test("settlement carries forward all buy-ins and keeps money before optional fields", () => {
  const html = renderToStaticMarkup(React.createElement(app.SettlementScreen, { archive: { session: { ...session, result: undefined }, hands: [hand] }, onCancel: noop, onSave: noop }));
  assert.match(html, /value="1500"/);
  assert.match(html, /查看买入明细 · 2 笔/);
  assert.ok(html.indexOf("累计买入") < html.indexOf("游戏时间"));
  assert.match(html, /可结算后继续/);
});

test("storage resolves only after transaction completion and rejects transaction abort", async () => {
  for (const outcome of ["complete", "abort"]) {
    let transaction;
    const indexedDB = { open() { const request = {}; queueMicrotask(() => { request.result = { transaction() { transaction = { objectStore: () => ({ put() {} }) }; return transaction; } }; request.onsuccess(); }); return request; } };
    const storage = load(indexedDB);
    let resolved = false;
    const pending = storage.saveSnapshot({ activeSessionID: null, archives: [] }).then(() => { resolved = true; });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(resolved, false);
    if (outcome === "complete") { transaction.oncomplete(); await pending; assert.equal(resolved, true); }
    else { const rejected = assert.rejects(pending, /本机存储已中止/); transaction.onabort(); await rejected; }
  }
});

const recordedHand = { ...hand, streets: {
  preflop: { board: [], actions: [{ id: "a1", actor: "CO", action: "raise", amountBB: 10, amountScope: "streetTotal", hero: true }], potBB: 25 },
  flop: { board: [{ rank: "A", suit: "♠" }, { rank: "K", suit: "♥" }, { rank: "2", suit: "♣" }], actions: [{ id: "a2", actor: "BB", action: "check", hero: false }] },
  turn: { board: [], actions: [{ id: "a3", actor: "CO", action: "unknown", hero: true }] },
  river: { board: [{ rank: "Q", suit: "♦" }], actions: [] },
} };

test("recording presents direct actions, actor selection, undo and explicit unknown action", () => {
  const html = renderToStaticMarkup(React.createElement(app.RouteScreen, { hand: recordedHand, bigBlind: 10, street: "preflop", saveState: "已保存到本机", onStreet: noop, onChange: noop, onFinish: noop, onEditBasics: noop }));
  assert.doesNotMatch(html, /<select/);
  for (const label of ["过牌", "跟注", "下注", "加注", "弃牌", "全下", "撤销上一步", "当前行动者", "这一步记不清"]) assert.ok(html.includes(label));
  assert.match(html, /CO 加注至100 筹码/);
});

test("replay orders street transitions and only exposes cards through the current street", () => {
  const steps = app.replaySteps(recordedHand);
  assert.equal(steps[0].kind, "start");
  assert.equal(steps[1].action.id, "a1");
  assert.equal(steps[2].kind, "end");
  assert.equal(steps[3].street, "flop");
  assert.equal(app.replayBoard(recordedHand, "preflop").length, 0);
  assert.equal(app.replayBoard(recordedHand, "flop").length, 3);
  const turn = app.replayBoard(recordedHand, "turn");
  assert.equal(turn.length, 4);
  assert.equal(turn[3], null);
  const river = app.replayBoard(recordedHand, "river");
  assert.equal(river[3], null);
  assert.equal(river[4].rank, "Q");
  const html = renderToStaticMarkup(React.createElement(app.HandReplay, { hand: recordedHand, bigBlind: 10 }));
  assert.match(html, /翻前 · 尚无公共牌/);
  assert.doesNotMatch(html, /Q♦/);
  assert.match(html, /回放进度/);
});

test("new totals are labeled explicitly without reinterpreting legacy amounts", () => {
  const action = { actor: "CO", action: "raise", amountBB: 10 };
  assert.equal(app.actionText(action, 10), "CO 加注 100 筹码");
  assert.equal(app.actionText({ ...action, amountScope: "streetTotal" }, 10), "CO 加注至100 筹码");
  assert.equal(app.actionText({ actor: "BB", action: "call" }, 10), "BB 跟注 · 金额待补");
});
