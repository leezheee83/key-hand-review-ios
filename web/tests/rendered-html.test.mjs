import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the hand review app shell and install metadata", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html lang="zh-CN">/);
  assert.match(html, /<title>手牌复盘速记<\/title>/);
  assert.match(html, /数据只保存在本机/);
  assert.match(html, /rel="manifest" href="\/manifest\.webmanifest"/);
  assert.match(html, /apple-mobile-web-app-title/);
  assert.match(html, /theme-color/);
  assert.match(html, /正在读取本机手牌/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/);
});

test("ships device-local persistence, migration, and offline assets", async () => {
  const [client, history, manifest, serviceWorker, packageJson] = await Promise.all([
    readFile(new URL("../app/HandReviewApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/historicalProfits.ts", import.meta.url), "utf8"),
    readFile(new URL("../public/manifest.webmanifest", import.meta.url), "utf8"),
    readFile(new URL("../public/sw.js", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(client, /indexedDB\.open/);
  assert.match(client, /navigator\.serviceWorker\.register/);
  assert.match(client, /KeyHandReview-Backup/);
  assert.match(client, /activeSessionID/);
  assert.match(client, /恢复会覆盖当前全部数据/);
  assert.match(client, /记录一场盈亏/);
  assert.match(client, /secondbrain-profit-/);
  assert.match(client, /返回总首页/);
  assert.match(client, /请填写本场最终盈亏/);
  assert.match(client, /estimatedDurationHours/);
  assert.match(client, /累计盈利曲线/);
  assert.match(client, /ProfitCurve sessions=\{settled\}/);
  assert.match(client, /ResizeObserver/);
  assert.match(client, /getContext\("2d"\)/);
  assert.match(client, /onPointerMove=\{selectNearestPoint\}/);
  assert.match(client, /onTouchStart=\{selectNearestTouch\}/);
  assert.match(client, /onTouchMove=\{selectNearestTouch\}/);
  assert.match(client, /setPointerCapture\?\./);
  assert.match(client, /本场盈亏/);
  assert.match(client, /轻点或按住曲线左右滑动/);
  assert.match(client, /function CompactHandPicker/);
  assert.match(client, /选择第\{activeSlot \+ 1\}张牌/);
  assert.match(client, /保存这手，回到本场/);
  assert.match(client, /可从手牌列表继续补路线/);
  assert.match(client, /草稿已自动保存在本场/);
  assert.match(client, /输入会自动保存为草稿/);
  assert.match(client, /captureState\?: "editing" \| "saved"/);
  assert.match(client, /hand\.captureState === "editing" \? "quick"/);
  assert.match(client, /captureState: "saved" as const/);
  assert.match(client, /function handState/);
  assert.match(client, /一句话笔记/);
  assert.match(client, /沿用上次设置/);
  assert.match(client, /已打完？补记结果/);
  assert.match(client, /查看买入明细/);
  assert.match(client, /transaction\.onabort/);
  assert.match(client, /if \(!await saveHand\(savedHand\)\) return/);
  assert.doesNotMatch(client, /completeness\(/);
  assert.match(client, /有效后手（筹码）/);
  assert.match(client, /金额（筹码，可留空）/);
  assert.match(client, /本街结束底池（筹码）/);
  assert.match(client, /UTG 2×大盲/);
  assert.match(client, /鱿鱼游戏/);
  assert.match(client, /有鱿鱼/);
  assert.match(client, /squidGame\?: boolean/);
  assert.match(client, /unit: "chips"/);
  assert.doesNotMatch(client, /显示 bb/);
  assert.doesNotMatch(client, /显示筹码/);
  assert.match(client, /当前场次正在进行/);
  assert.match(client, /最近手牌记录/);
  assert.match(client, /已全部复盘/);
  assert.match(client, /recentHandArchives/);
  assert.doesNotMatch(client, /<h2>最近场次<\/h2>/);
  assert.match(client, /className="session-dock"/);
  assert.match(client, /className="quick-sheet"/);
  assert.doesNotMatch(client, /保存并补路线/);
  assert.doesNotMatch(client, /手牌要复盘，场次也要结算/);
  assert.doesNotMatch(client, /场来自 Second Brain/);
  assert.match(serviceWorker, /caches\.open/);
  assert.match(serviceWorker, /event\.request\.mode === "navigate"/);

  const parsedManifest = JSON.parse(manifest);
  assert.equal(parsedManifest.display, "standalone");
  assert.equal(parsedManifest.start_url, ".");
  assert.equal(parsedManifest.icons.length, 2);
  assert.equal(JSON.parse(packageJson).name, "key-hand-review-web");

  const historyRows = history.match(/const raw = `([\s\S]*?)`;/)?.[1].split("\n") ?? [];
  assert.equal(historyRows.length, 74);
  assert.equal(historyRows.reduce((sum, row) => sum + Number(row.split("|")[1]), 0), 304);
  assert.equal(historyRows.reduce((sum, row) => sum + Number(row.split("|")[3]), 0), 6207);

  await access(new URL("../public/icon-192.png", import.meta.url));
  await access(new URL("../public/icon-512.png", import.meta.url));
});
