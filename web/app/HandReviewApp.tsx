"use client";

import {
  ChangeEvent,
  PointerEvent as ReactPointerEvent,
  TouchEvent as ReactTouchEvent,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { historicalProfits } from "./historicalProfits";

type AmountUnit = "bb" | "chips";
type StreetKey = "preflop" | "flop" | "turn" | "river";
type Screen = "overview" | "home" | "quick" | "route" | "detail" | "inbox" | "backup" | "ledger" | "settlement";

type PlayingCard = { rank: string; suit: "♠" | "♥" | "♦" | "♣" };
type Straddle = { id: string; position: string; amountBB: number };
type SessionResult = {
  profit: number;
  durationHours: number;
  stakes: string;
  location: string;
  note: string;
  source: "app" | "secondbrain";
  buyIn?: number;
  cashOut?: number;
};
type ReviewSession = {
  id: string;
  sb: number;
  bb: number;
  currency: string;
  unit: AmountUnit;
  playerCount: number;
  straddles: Straddle[];
  squidGame?: boolean;
  buyIns?: { id: string; amount: number; at: string }[];
  createdAt: string;
  endedAt?: string;
  result?: SessionResult;
};
type HandAction = {
  id: string;
  actor: string;
  action: string;
  amountBB?: number;
  amountScope?: "streetTotal";
  hero: boolean;
};
type StreetRecord = {
  board: PlayingCard[];
  potBB?: number;
  confidence: string;
  actions: HandAction[];
};
type PokerHand = {
  id: string;
  createdAt: string;
  status: "draft" | "complete";
  captureState?: "editing" | "saved";
  note?: string;
  tags: string[];
  heroPosition: string;
  effectiveStackBB: number;
  heroCards: PlayingCard[];
  playerCount: number;
  straddles: Straddle[];
  streets: Record<StreetKey, StreetRecord>;
  review: { decision: string; basis: string; correction: string };
};
type SessionArchive = { session: ReviewSession; hands: PokerHand[] };
type StoreSnapshot = { activeSessionID: string | null; archives: SessionArchive[] };

const DB_NAME = "key-hand-review";
const DB_VERSION = 1;
const STORE_NAME = "snapshots";
const SNAPSHOT_KEY = "main";
const streets: StreetKey[] = ["preflop", "flop", "turn", "river"];
const streetLabels: Record<StreetKey, string> = {
  preflop: "翻前",
  flop: "Flop",
  turn: "Turn",
  river: "River",
};
const tags = ["待复盘", "诈唬", "抓诈", "Hero Fold", "价值", "冤家", "自定义"];
const ranks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"];
const suits: PlayingCard["suit"][] = ["♠", "♥", "♦", "♣"];
const actionOptions = ["check", "call", "bet", "raise", "fold", "all-in"];
const actionLabels: Record<string, string> = { check: "过牌", call: "跟注", bet: "下注", raise: "加注", fold: "弃牌", "all-in": "全下", unknown: "动作待补" };

const emptySnapshot: StoreSnapshot = { activeSessionID: null, archives: [] };

function parseStakes(stakes: string) {
  const values = stakes.match(/\d+(?:\.\d+)?/g)?.map(Number) ?? [1, 2];
  return { sb: values[0] || 1, bb: values[1] || values[0] * 2 || 2 };
}

function mergeHistoricalProfits(snapshot: StoreSnapshot): StoreSnapshot {
  const existing = new Set(snapshot.archives.map((archive) => archive.session.id));
  const imported = historicalProfits.flatMap((record, index) => {
    const id = `secondbrain-profit-${index + 1}`;
    if (existing.has(id)) return [];
    const stakes = parseStakes(record.stakes);
    return [{
      session: {
        id,
        ...stakes,
        currency: "CNY",
        unit: "chips" as const,
        playerCount: 8,
        straddles: [],
        createdAt: `${record.date}T12:00:00`,
        endedAt: `${record.date}T12:00:00`,
        result: {
          profit: record.profit,
          durationHours: record.durationHours,
          stakes: record.stakes,
          location: record.location,
          note: "",
          source: "secondbrain" as const,
        },
      },
      hands: [],
    }];
  });
  if (!imported.length) return snapshot;
  return {
    ...snapshot,
    archives: [...snapshot.archives, ...imported].sort(
      (a, b) => new Date(b.session.createdAt).getTime() - new Date(a.session.createdAt).getTime(),
    ),
  };
}

function formatProfit(value: number) {
  return `${value > 0 ? "+" : ""}${value.toLocaleString("zh-CN")}`;
}

function sessionStakes(session: ReviewSession) {
  return session.result?.stakes || `${session.sb}/${session.bb}`;
}

function dateInputValue(value: Date) {
  const local = new Date(value.getTime() - value.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

function estimatedDurationHours(session?: ReviewSession) {
  if (!session) return 4;
  const elapsed = (Date.now() - new Date(session.createdAt).getTime()) / 3_600_000;
  if (!Number.isFinite(elapsed)) return 4;
  return Math.max(0.5, Math.round(elapsed * 2) / 2);
}

function uid() {
  return crypto.randomUUID();
}

function blankStreet(): StreetRecord {
  return { board: [], confidence: "unknown", actions: [] };
}

function newHand(session: ReviewSession): PokerHand {
  return {
    id: uid(),
    createdAt: new Date().toISOString(),
    status: "draft",
    captureState: "editing",
    tags: ["待复盘"],
    heroPosition: "CO",
    effectiveStackBB: 100,
    heroCards: [],
    playerCount: session.playerCount,
    straddles: session.straddles,
    streets: {
      preflop: blankStreet(),
      flop: blankStreet(),
      turn: blankStreet(),
      river: blankStreet(),
    },
    review: { decision: "", basis: "", correction: "" },
  };
}

function positions(count: number) {
  const map: Record<number, string[]> = {
    4: ["UTG", "BTN", "SB", "BB"],
    5: ["UTG", "CO", "BTN", "SB", "BB"],
    6: ["UTG", "HJ", "CO", "BTN", "SB", "BB"],
    7: ["UTG", "LJ", "HJ", "CO", "BTN", "SB", "BB"],
    8: ["UTG", "UTG+1", "LJ", "HJ", "CO", "BTN", "SB", "BB"],
    9: ["UTG", "UTG+1", "UTG+2", "LJ", "HJ", "CO", "BTN", "SB", "BB"],
    10: ["UTG", "UTG+1", "UTG+2", "MP", "LJ", "HJ", "CO", "BTN", "SB", "BB"],
  };
  return map[count] ?? map[8];
}

function handState(hand: PokerHand) {
  if (hand.captureState === "editing") return "草稿";
  return hand.review.decision.trim() ? "已复盘" : "待复盘";
}

function totalBuyIn(session: ReviewSession) {
  return session.buyIns?.reduce((sum, entry) => sum + entry.amount, 0) ?? session.result?.buyIn ?? 0;
}

function cardText(card: PlayingCard) {
  return `${card.rank}${card.suit}`;
}

function chipsFromBB(value: number, bigBlind: number) {
  return Math.round(value * bigBlind * 100) / 100;
}

function bbFromChips(value: number, bigBlind: number) {
  return bigBlind > 0 ? value / bigBlind : value;
}

function chipText(valueBB: number, bigBlind: number) {
  return `${chipsFromBB(valueBB, bigBlind).toLocaleString("zh-CN")} 筹码`;
}

function actionText(action: HandAction, bigBlind: number) {
  const needsAmount = ["call", "bet", "raise", "all-in"].includes(action.action);
  return `${action.actor} ${actionLabels[action.action] ?? action.action}${action.amountBB == null ? needsAmount ? " · 金额待补" : "" : `${action.amountScope === "streetTotal" ? "至" : " "}${chipText(action.amountBB, bigBlind)}`}`;
}

type ReplayStep = { street: StreetKey; kind: "start" | "action" | "end"; action?: HandAction };

function replaySteps(hand: PokerHand): ReplayStep[] {
  const steps: ReplayStep[] = [{ street: "preflop", kind: "start" }];
  for (const street of streets) {
    const record = hand.streets[street];
    if (street !== "preflop" && (record.board.length || record.actions.length || record.potBB != null)) steps.push({ street, kind: "start" });
    for (const action of record.actions) steps.push({ street, kind: "action", action });
    if (record.potBB != null) steps.push({ street, kind: "end" });
  }
  return steps;
}

function replayBoard(hand: PokerHand, street: StreetKey) {
  return streets.slice(1, streets.indexOf(street) + 1).flatMap((key) =>
    Array.from({ length: key === "flop" ? 3 : 1 }, (_, index): PlayingCard | null => hand.streets[key].board[index] ?? null),
  );
}

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(STORE_NAME)) {
        request.result.createObjectStore(STORE_NAME);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function loadSnapshot(): Promise<StoreSnapshot> {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const request = db.transaction(STORE_NAME, "readonly").objectStore(STORE_NAME).get(SNAPSHOT_KEY);
    request.onsuccess = () => resolve(mergeHistoricalProfits(request.result ?? emptySnapshot));
    request.onerror = () => reject(request.error);
  });
}

async function saveSnapshot(snapshot: StoreSnapshot) {
  const db = await openDatabase();
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, "readwrite");
    transaction.objectStore(STORE_NAME).put(snapshot, SNAPSHOT_KEY);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error ?? new Error("本机存储已中止"));
  });
}

function download(name: string, content: string, type: string) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  URL.revokeObjectURL(url);
}

function handMarkdown(hand: PokerHand, session: ReviewSession) {
  const sections = streets
    .filter((street) => hand.streets[street].actions.length || hand.streets[street].board.length)
    .map((street) => {
      const record = hand.streets[street];
      const board = record.board.length ? `：${record.board.map(cardText).join(" ")}` : "";
      const route = record.actions.length ? record.actions.map((action) => actionText(action, session.bb)).join("；") : "[待补]";
      const pot = record.potBB == null ? "" : `\n池量：${chipText(record.potBB, session.bb)}。`;
      return `## ${streetLabels[street]}${board}\n${route}${pot}`;
    })
    .join("\n\n");
  return `# ${hand.heroPosition} ${hand.heroCards.map(cardText).join(" ") || "[手牌待补]"}｜有效后手 ${chipText(hand.effectiveStackBB, session.bb)}

标签：${hand.tags.join(" / ")}
场次：${session.sb}/${session.bb} NLH · ${hand.playerCount} 人桌
鱿鱼游戏：${session.squidGame ? "有" : "无"}
现场笔记：${hand.note || "[未填写]"}

${sections}

## 复盘
- 关键决策：${hand.review.decision || "[待补]"}
- 当时依据：${hand.review.basis || "[待补]"}
- 下次默认修正：${hand.review.correction || "[待补]"}
`;
}

export default function HandReviewApp() {
  const [snapshot, setSnapshot] = useState<StoreSnapshot>(emptySnapshot);
  const [loaded, setLoaded] = useState(false);
  const [loadError, setLoadError] = useState(false);
  const [screen, setScreen] = useState<Screen>("home");
  const [selectedArchiveID, setSelectedArchiveID] = useState<string | null>(null);
  const [editingHand, setEditingHand] = useState<PokerHand | null>(null);
  const [settlementSessionID, setSettlementSessionID] = useState<string | null>(null);
  const [street, setStreet] = useState<StreetKey>("preflop");
  const [notice, setNotice] = useState("");
  const [saveState, setSaveState] = useState("输入会自动保存为草稿");
  const snapshotRef = useRef(snapshot);
  const saveQueue = useRef(Promise.resolve());
  const saveRevision = useRef(0);
  const importRef = useRef<HTMLInputElement>(null);

  const persist = (next: StoreSnapshot, rollbackOnError = false) => {
    const previous = snapshotRef.current;
    const revision = ++saveRevision.current;
    snapshotRef.current = next;
    setSnapshot(next);
    setSaveState("保存中…");
    const pending = saveQueue.current.catch(() => undefined).then(() => saveSnapshot(next));
    saveQueue.current = pending;
    return pending.then(() => {
      if (revision === saveRevision.current) setSaveState("已保存到本机");
      return true;
    }).catch(() => {
      if (rollbackOnError && revision === saveRevision.current) { snapshotRef.current = previous; setSnapshot(previous); }
      if (revision === saveRevision.current) setSaveState("保存失败，请重试");
      setNotice("本机保存失败，请勿关闭页面。请重试或导出备份。");
      return false;
    });
  };

  useEffect(() => {
    loadSnapshot()
      .then((next) => {
        setSnapshot(next);
        snapshotRef.current = next;
      })
      .catch(() => setLoadError(true))
      .finally(() => setLoaded(true));
    if ("serviceWorker" in navigator) {
      const appBase = new URL(".", document.baseURI).pathname;
      navigator.serviceWorker.register(`${appBase}sw.js`).catch(() => undefined);
    }
    navigator.storage?.persist?.().catch(() => undefined);
  }, []);

  const archive = useMemo(() => {
    const id = selectedArchiveID ?? snapshot.activeSessionID;
    return snapshot.archives.find((item) => item.session.id === id) ?? null;
  }, [selectedArchiveID, snapshot]);

  const updateSnapshot = (change: (draft: StoreSnapshot) => void, rollbackOnError = false) => {
    const next = structuredClone(snapshotRef.current);
    change(next);
    return persist(next, rollbackOnError);
  };

  const saveHand = (hand: PokerHand) => {
    if (!archive) return Promise.resolve(false);
    return updateSnapshot((draft) => {
      const target = draft.archives.find((item) => item.session.id === archive.session.id);
      if (!target) return;
      const index = target.hands.findIndex((item) => item.id === hand.id);
      if (index >= 0) target.hands[index] = hand;
      else target.hands.unshift(hand);
    });
  };

  const openHand = (hand: PokerHand, destination?: Screen) => {
    setEditingHand(structuredClone(hand));
    if (saveState !== "保存中…" && !saveState.includes("失败")) setSaveState("已保存到本机");
    setStreet("preflop");
    setScreen(destination ?? (
      hand.captureState === "editing" ? "quick" : hand.status === "draft" ? "route" : "detail"
    ));
  };

  if (loadError) return <main className="app-shell loading"><p role="alert">无法读取本机数据。请检查浏览器存储权限后重试，不要清除网站数据。</p><button className="primary" onClick={() => window.location.reload()}>重新读取</button></main>;

  if (!loaded) {
    return (
      <main className="app-shell loading">
        <div className="brand-mark">K</div>
        <p>正在读取本机手牌…</p>
      </main>
    );
  }

  const goHome = () => {
    setEditingHand(null);
    setSettlementSessionID(null);
    setScreen("home");
  };

  const goOverview = () => {
    setEditingHand(null);
    setSettlementSessionID(null);
    setSelectedArchiveID(null);
    setScreen("overview");
  };

  return (
    <main className="app-shell">
      <header className="topbar">
        <button className="brand" onClick={goOverview} aria-label="返回总首页">
          <span className="brand-mark">K</span>
          <span>
            <strong>手牌复盘速记</strong>
            <small>只存这台设备</small>
          </span>
        </button>
        {archive && screen !== "home" && screen !== "quick" && (
          <button className="text-button" onClick={goHome}>
            返回本场
          </button>
        )}
      </header>

      {notice && (
        <button className="notice" onClick={() => setNotice("")}>
          {notice}
        </button>
      )}

      {(screen === "overview" || (screen === "home" && !archive)) && (
        <StartScreen
          archives={snapshot.archives}
          activeSessionID={snapshot.activeSessionID}
          onStart={async (session) => {
            if (!await updateSnapshot((draft) => {
              draft.archives.unshift({ session, hands: [] });
              draft.activeSessionID = session.id;
            }, true)) return false;
            setSelectedArchiveID(null);
            setScreen("home");
            return true;
          }}
          onOpen={(id) => {
            setSelectedArchiveID(id);
            setScreen("home");
          }}
          onBackup={() => setScreen("backup")}
          onLedger={() => setScreen("ledger")}
          onAddResult={() => { setSettlementSessionID(null); setScreen("settlement"); }}
        />
      )}

      {(screen === "home" || screen === "quick") && archive && (
        <HomeScreen
          archive={archive}
          isActive={snapshot.activeSessionID === archive.session.id}
          onNew={() => {
            setEditingHand(newHand(archive.session));
            setSaveState("输入会自动保存为草稿");
            setScreen("quick");
          }}
          onOpenHand={openHand}
          onInbox={() => setScreen("inbox")}
          onBackup={() => setScreen("backup")}
          onLedger={() => setScreen("ledger")}
          onBuyIn={(amount, entryID) => updateSnapshot((draft) => {
            const target = draft.archives.find((item) => item.session.id === archive.session.id);
            if (target) {
              const entries = target.session.buyIns ??= [];
              const existing = entries.find((entry) => entry.id === entryID);
              if (existing) existing.amount = amount;
              else entries.push({ id: entryID, amount, at: new Date().toISOString() });
            }
          }, true)}
          onEnd={() => {
            setSettlementSessionID(archive.session.id);
            setScreen("settlement");
          }}
          onResume={() => {
            updateSnapshot((draft) => {
              const target = draft.archives.find((item) => item.session.id === archive.session.id);
              if (target) delete target.session.endedAt;
              draft.activeSessionID = archive.session.id;
            });
            setSelectedArchiveID(null);
          }}
          onClose={goOverview}
          onDelete={(id) => {
            if (!confirm("删除这手牌？删除后无法恢复。")) return;
            updateSnapshot((draft) => {
              const target = draft.archives.find((item) => item.session.id === archive.session.id);
              if (target) target.hands = target.hands.filter((hand) => hand.id !== id);
            });
          }}
        />
      )}

      {screen === "quick" && editingHand && archive && (
        <QuickScreen
          hand={editingHand}
          bigBlind={archive.session.bb}
          saveState={saveState}
          onRetry={() => void persist(snapshotRef.current)}
          onChange={(hand) => {
            setEditingHand(hand);
            saveHand(hand);
          }}
          onCancel={async () => {
            if (snapshotRef.current.archives.some((item) => item.hands.some((hand) => hand.id === editingHand.id))) {
              if (!await saveHand(editingHand)) return;
              setNotice("草稿已自动保存在本场。");
            }
            goHome();
          }}
          onSave={async () => {
            const savedHand = { ...editingHand, captureState: "saved" as const };
            setEditingHand(savedHand);
            if (!await saveHand(savedHand)) return;
            setNotice("已保存这手牌，可从手牌列表继续补路线。");
            goHome();
          }}
        />
      )}

      {screen === "route" && editingHand && archive && (
        <RouteScreen
          key={`${editingHand.id}-${street}`}
          hand={editingHand}
          bigBlind={archive.session.bb}
          street={street}
          saveState={saveState}
          onEditBasics={() => setScreen("quick")}
          onStreet={setStreet}
          onChange={(hand) => {
            setEditingHand(hand);
            saveHand(hand);
          }}
          onFinish={async () => {
            const hand = { ...editingHand, status: "complete" as const };
            setEditingHand(hand);
            if (!await saveHand(hand)) return;
            setScreen("detail");
          }}
        />
      )}

      {screen === "detail" && editingHand && archive && (
        <DetailScreen
          hand={editingHand}
          session={archive.session}
          onEditBasics={() => setScreen("quick")}
          onChange={(hand) => { setEditingHand(hand); void saveHand(hand); }}
          onEditRoute={() => setScreen("route")}
          onSave={async () => {
            if (!await saveHand(editingHand)) return;
            setNotice("复盘已保存到本机。");
            goHome();
          }}
        />
      )}

      {screen === "inbox" && archive && (
        <InboxScreen
          hands={archive.hands.filter((hand) => handState(hand) !== "已复盘")}
          onOpen={(hand) => openHand(hand)}
        />
      )}

      {screen === "backup" && (
        <BackupScreen
          snapshot={snapshot}
          hasArchive={snapshot.archives.length > 0}
          onImport={(next) => {
            void persist(next);
            setSelectedArchiveID(null);
            setScreen("home");
            setNotice("备份已恢复到本机。");
          }}
          onPickImport={() => importRef.current?.click()}
        />
      )}

      {screen === "ledger" && (
        <LedgerScreen
          archives={snapshot.archives}
          onClose={goOverview}
          onAdd={() => {
            setSettlementSessionID(null);
            setScreen("settlement");
          }}
          onEdit={(id) => {
            setSettlementSessionID(id);
            setScreen("settlement");
          }}
        />
      )}

      {screen === "settlement" && (
        <SettlementScreen
          archive={snapshot.archives.find((item) => item.session.id === settlementSessionID) ?? null}
          onCancel={() => {
            const cameFromHome = settlementSessionID != null && (
              snapshot.activeSessionID === settlementSessionID || selectedArchiveID === settlementSessionID
            );
            setScreen(cameFromHome ? "home" : "ledger");
          }}
          onSave={async (record) => {
            const saved = await updateSnapshot((draft) => {
              const target = settlementSessionID
                ? draft.archives.find((item) => item.session.id === settlementSessionID)
                : null;
              if (target) {
                if (dateInputValue(new Date(target.session.createdAt)) !== record.date) target.session.createdAt = `${record.date}T12:00:00`;
                target.session.endedAt = new Date().toISOString();
                // Existing hands retain the blind baseline used to store chip amounts.
                if (!target.hands.length) { target.session.sb = record.sb; target.session.bb = record.bb; }
                target.session.result = record.result;
                if (draft.activeSessionID === target.session.id) draft.activeSessionID = null;
              } else {
                const id = uid();
                draft.archives.unshift({
                  session: {
                    id,
                    sb: record.sb,
                    bb: record.bb,
                    currency: "CNY",
                    unit: "chips",
                    playerCount: 8,
                    straddles: [],
                    createdAt: `${record.date}T12:00:00`,
                    endedAt: new Date().toISOString(),
                    result: record.result,
                  },
                  hands: [],
                });
              }
              draft.archives.sort(
                (a, b) => new Date(b.session.createdAt).getTime() - new Date(a.session.createdAt).getTime(),
              );
            }, true);
            if (!saved) return false;
            setSelectedArchiveID(null);
            setSettlementSessionID(null);
            setScreen("ledger");
            setNotice("本场盈亏已保存。 ");
            return true;
          }}
        />
      )}

      <input
        ref={importRef}
        className="visually-hidden"
        type="file"
        accept="application/json,.json"
        onChange={(event) => void importBackup(event, (next) => {
          if (!confirm("恢复会覆盖当前全部数据，确定继续吗？")) return;
          void persist(next);
          setSelectedArchiveID(null);
          setScreen("home");
          setNotice("备份已恢复到本机。");
        })}
      />

      <footer className="privacy-footer">
        <span className="status-dot" /> 无账号 · 无云端数据库 · 自动保存在本机
      </footer>
    </main>
  );
}

function StartScreen({
  archives,
  activeSessionID,
  onStart,
  onOpen,
  onBackup,
  onLedger,
  onAddResult,
}: {
  archives: SessionArchive[];
  activeSessionID: string | null;
  onStart: (session: ReviewSession) => Promise<boolean>;
  onOpen: (id: string) => void;
  onBackup: () => void;
  onLedger: () => void;
  onAddResult: () => void;
}) {
  const last = [...archives].filter((item) => !item.session.id.startsWith("secondbrain-") && (item.session.buyIns !== undefined || item.hands.length > 0 || !item.session.result)).sort((a, b) => b.session.createdAt.localeCompare(a.session.createdAt))[0]?.session;
  const previousStraddle = last?.straddles[0];
  const [sb, setSB] = useState(last?.sb ?? 1);
  const [bb, setBB] = useState(last?.bb ?? 2);
  const [playerCount, setPlayerCount] = useState(last?.playerCount ?? 8);
  const [straddleMode, setStraddleMode] = useState<"none" | "utg" | "custom">(previousStraddle ? previousStraddle.position === "UTG" && previousStraddle.amountBB === 2 ? "utg" : "custom" : "none");
  const [straddlePosition, setStraddlePosition] = useState(previousStraddle?.position ?? "UTG");
  const [straddleAmount, setStraddleAmount] = useState(previousStraddle ? previousStraddle.amountBB * (last?.bb ?? 2) : 4);
  const [squidGame, setSquidGame] = useState(last?.squidGame ?? false);
  const [buyIn, setBuyIn] = useState("");
  const [setupError, setSetupError] = useState("");
  const [starting, setStarting] = useState(false);
  const settled = archives.filter((item) => item.session.result);
  const activeArchive = archives.find((item) => item.session.id === activeSessionID);
  const recentHandArchives = archives.filter(
    (item) => item.hands.length > 0 && item.session.id !== activeSessionID,
  );
  const totalProfit = settled.reduce((sum, item) => sum + (item.session.result?.profit ?? 0), 0);
  const totalHours = settled.reduce((sum, item) => sum + (item.session.result?.durationHours ?? 0), 0);

  return (
    <section className="screen">
      {activeArchive && (
        <button className="active-session-return" onClick={() => onOpen(activeArchive.session.id)}>
          <span><small>当前场次正在进行</small><strong>{sessionStakes(activeArchive.session)} NLH</strong></span>
          <span><b>{activeArchive.hands.length}</b><small>已记手牌</small></span>
          <i>回到牌桌 →</i>
        </button>
      )}

      {!activeArchive && <article className="panel setup-panel">
        <div className="section-heading">
          <div>
            <h2>开始一场</h2>
          </div>
          <span className="local-chip">本机保存</span>
        </div>
        <label>首次买入<input inputMode="decimal" type="number" min="0" value={buyIn} onChange={(event) => setBuyIn(event.target.value)} placeholder="可稍后补记" /></label>
        <details className="optional-section">
          <summary><span>{sb}/{bb} · {playerCount} 人 · {straddleMode === "none" ? "无 Straddle" : "有 Straddle"} · {squidGame ? "有鱿鱼" : "无鱿鱼"}<small>{last ? "沿用上次设置" : "本场设置"}</small></span><b>修改</b></summary>
        <div className="field-grid two">
          <label>小盲<input inputMode="decimal" type="number" value={sb} onChange={(e) => setSB(Number(e.target.value))} /></label>
          <label>大盲<input inputMode="decimal" type="number" value={bb} onChange={(e) => setBB(Number(e.target.value))} /></label>
        </div>
        <FieldTitle title="默认人数" />
        <div className="choice-row wrap">
          {[4, 5, 6, 7, 8, 9, 10].map((count) => (
            <button key={count} className={playerCount === count ? "choice selected" : "choice"} onClick={() => setPlayerCount(count)}>
              {count} 人
            </button>
          ))}
        </div>
        <FieldTitle title="Straddle" note="可选" />
        <div className="choice-row">
          <button className={straddleMode === "none" ? "choice selected" : "choice"} onClick={() => setStraddleMode("none")}>无</button>
          <button className={straddleMode === "utg" ? "choice selected" : "choice"} onClick={() => setStraddleMode("utg")}>UTG 2×大盲</button>
          <button className={straddleMode === "custom" ? "choice selected" : "choice"} onClick={() => { setStraddleMode("custom"); setStraddleAmount(bb * 2); }}>自定义</button>
        </div>
        {straddleMode === "custom" && (
          <div className="field-grid two optional-fields">
            <label>位置<select value={straddlePosition} onChange={(e) => setStraddlePosition(e.target.value)}>{positions(playerCount).map((position) => <option key={position}>{position}</option>)}</select></label>
            <label>Straddle 筹码<input inputMode="decimal" type="number" value={straddleAmount} onChange={(e) => setStraddleAmount(Number(e.target.value))} /></label>
          </div>
        )}
        <FieldTitle title="鱿鱼游戏" note="本场是否开启" />
        <div className="choice-row">
          <button className={!squidGame ? "choice selected" : "choice"} onClick={() => setSquidGame(false)}>无</button>
          <button className={squidGame ? "choice selected" : "choice"} onClick={() => setSquidGame(true)}>有鱿鱼</button>
        </div>
        </details>
        {setupError && <p className="form-error" role="alert">{setupError}</p>}
        <button
          className="primary wide"
          disabled={starting}
          onClick={async () => {
            if (!(sb > 0 && bb >= sb && Number.isFinite(bb))) { setSetupError("请检查盲注，大盲应不小于小盲。"); return; }
            if (buyIn !== "" && (!Number.isFinite(Number(buyIn)) || Number(buyIn) < 0)) { setSetupError("买入金额不能为负数。"); return; }
            if (straddleMode === "custom" && (!(straddleAmount > 0) || !positions(playerCount).includes(straddlePosition))) { setSetupError("请检查 Straddle 的位置和金额。"); return; }
            setStarting(true);
            const saved = await onStart({
              id: uid(),
              sb,
              bb,
              currency: "U",
              unit: "chips",
              playerCount,
              squidGame,
              buyIns: buyIn === "" ? [] : [{ id: uid(), amount: Number(buyIn), at: new Date().toISOString() }],
              straddles: straddleMode === "none" ? [] : [{
                id: uid(),
                position: straddleMode === "utg" ? "UTG" : straddlePosition,
                amountBB: straddleMode === "utg" ? 2 : bbFromChips(straddleAmount, bb),
              }],
              createdAt: new Date().toISOString(),
            });
            setStarting(false);
            if (!saved) setSetupError("本机保存失败，请重试。");
          }}
        >
          {starting ? "保存中…" : "开始一场"}
        </button>
        <button className="text-button wide" onClick={onAddResult}>已打完？补记结果</button>
      </article>}

      {settled.length > 0 && (
        <button className="profit-overview" onClick={onLedger}>
          <span><small>累计盈亏</small><strong className={totalProfit >= 0 ? "profit-positive" : "profit-negative"}>{formatProfit(totalProfit)}</strong></span>
          <span><small>场次</small><b>{settled.length}</b></span>
          <span><small>时薪</small><b>{totalHours ? formatProfit(Math.round(totalProfit / totalHours)) : "—"}</b></span>
          <i>查看曲线与账本 →</i>
        </button>
      )}
      {settled.length > 0 && <ProfitCurve sessions={settled} />}

      {recentHandArchives.length > 0 && (
        <article className="panel">
          <div className="section-heading">
            <div><span className="step">REVIEW</span><h2>最近手牌记录</h2></div>
            <button className="text-button" onClick={onLedger}>盈利账本</button>
          </div>
          <div className="stack">
            {recentHandArchives.slice(0, 6).map((archive) => {
              const incomplete = archive.hands.filter((hand) => handState(hand) !== "已复盘").length;
              return (
                <button className="archive-row" key={archive.session.id} onClick={() => onOpen(archive.session.id)}>
                  <span><strong>{sessionStakes(archive.session)} NLH</strong><small>{new Date(archive.session.createdAt).toLocaleDateString("zh-CN")}{archive.session.result?.location ? ` · ${archive.session.result.location}` : ""}</small></span>
                  <span><b>{archive.hands.length} 手</b><small>{incomplete ? `${incomplete} 手待复盘` : "已全部复盘"}</small></span>
                </button>
              );
            })}
          </div>
          <button className="secondary wide history-backup" onClick={onBackup}>数据备份</button>
        </article>
      )}
    </section>
  );
}

function HomeScreen({
  archive,
  isActive,
  onNew,
  onOpenHand,
  onInbox,
  onBackup,
  onLedger,
  onEnd,
  onResume,
  onClose,
  onDelete,
  onBuyIn,
}: {
  archive: SessionArchive;
  isActive: boolean;
  onNew: () => void;
  onOpenHand: (hand: PokerHand) => void;
  onInbox: () => void;
  onBackup: () => void;
  onLedger: () => void;
  onEnd: () => void;
  onResume: () => void;
  onClose: () => void;
  onDelete: (id: string) => void;
  onBuyIn: (amount: number, id: string) => Promise<boolean>;
}) {
  const incomplete = archive.hands.filter((hand) => handState(hand) !== "已复盘").length;
  const [addingBuyIn, setAddingBuyIn] = useState(false);
  const [amount, setAmount] = useState("");
  const [buyInError, setBuyInError] = useState("");
  const [adding, setAdding] = useState(false);
  const buyInID = useRef("");
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!isActive) return;
    const timer = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, [isActive]);
  const elapsedHours = Math.max(0, (now - new Date(archive.session.createdAt).getTime()) / 3_600_000);
  const elapsedLabel = elapsedHours < 1 ? `${Math.max(1, Math.round(elapsedHours * 60))} 分钟` : `${elapsedHours.toFixed(1)} 小时`;
  return (
    <section className={isActive ? "screen session-workbench" : "screen"}>
      <article className="session-card">
        <div>
          <p className="eyebrow">{isActive ? `已进行 ${elapsedLabel} · ` : ""}{archive.session.playerCount} 人桌 · {archive.session.straddles.length ? "有 straddle" : "无 straddle"} · {archive.session.squidGame ? "有鱿鱼" : "无鱿鱼"}</p>
          <h1>{sessionStakes(archive.session)} <span>NLH</span></h1>
        </div>
        <span className={isActive ? "live-badge" : "ended-badge"}>{isActive ? "记录中" : "已结束"}</span>
        <div className="metrics">
          <span><b>{archive.hands.length}</b><small>已保存</small></span>
          <span><b>{incomplete}</b><small>待复盘</small></span>
          <span><b>{archive.hands.filter((hand) => hand.review.decision).length}</b><small>已复盘</small></span>
        </div>
      </article>

      {isActive && <article className="panel live-actions">
        <div className="section-heading"><span>累计买入 <strong>{totalBuyIn(archive.session).toLocaleString("zh-CN")}</strong></span><button className="text-button" onClick={() => setAddingBuyIn(!addingBuyIn)}>补码 / 买入</button></div>
        {addingBuyIn && <div>
          <label>本次买入金额<input type="number" inputMode="decimal" min="0" value={amount} onChange={(event) => setAmount(event.target.value)} /></label>
          {buyInError && <p className="form-error" role="alert">{buyInError}</p>}
          <div className="button-pair"><button className="secondary" onClick={() => setAddingBuyIn(false)}>取消</button><button className="primary" disabled={adding} onClick={async () => {
            if (!(Number(amount) > 0) || !Number.isFinite(Number(amount))) { setBuyInError("请输入大于 0 的买入金额。"); return; }
            setAdding(true);
            buyInID.current ||= uid();
            if (await onBuyIn(Number(amount), buyInID.current)) { setAddingBuyIn(false); setAmount(""); setBuyInError(""); buyInID.current = ""; }
            setAdding(false);
          }}>确认买入</button></div>
        </div>}
        <button className="primary wide" onClick={onNew}>＋ 记一手</button>
      </article>}

      {archive.session.result && (
        <article className="settled-strip">
          <span><small>本场盈亏</small><strong className={archive.session.result.profit >= 0 ? "profit-positive" : "profit-negative"}>{formatProfit(archive.session.result.profit)}</strong></span>
          <span><small>游戏时间</small><b>{archive.session.result.durationHours} 小时</b></span>
          <span><small>地点</small><b>{archive.session.result.location || "未填写"}</b></span>
        </article>
      )}

      {!isActive && (archive.session.result ? (
        <div className="button-pair">
          <button className="primary" onClick={onEnd}>修改本场结果</button>
          <button className="secondary" onClick={onClose}>返回场次列表</button>
        </div>
      ) : (
        <div className="button-pair">
          <button className="primary" onClick={onResume}>继续记录本场</button>
          <button className="secondary" onClick={onClose}>返回场次列表</button>
        </div>
      ))}

      <div className="section-heading list-heading">
        <div><span className="step">HAND LOG</span><h2>手牌记录</h2></div>
        <button className="text-button" onClick={onInbox}>待复盘 {incomplete}</button>
      </div>

      {archive.hands.length === 0 ? (
        <div className="empty-state"><b>暂无手牌记录</b><span>一手结束后，只记值得回看的关键牌。</span></div>
      ) : (
        <div className="stack">
          {archive.hands.map((hand, index) => (
            <article className="hand-card" key={hand.id}>
              <button className="hand-main" onClick={() => onOpenHand(hand)}>
                <span className="hand-number">{String(index + 1).padStart(2, "0")}</span>
                <span className="hand-copy">
                  <small>{hand.tags.filter((tag) => tag !== "待复盘").join(" · ") || "关键手牌"}</small>
                  <strong>{hand.heroPosition} · {hand.heroCards.map(cardText).join(" ") || "手牌待补"}</strong>
                  <span>{chipText(hand.effectiveStackBB, archive.session.bb)} · {new Date(hand.createdAt).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })}</span>
                  {hand.note && <span className="hand-note">{hand.note}</span>}
                </span>
                <span className={handState(hand) === "已复盘" ? "score complete" : "score"}>{handState(hand)}</span>
              </button>
              <button className="delete-button" onClick={() => onDelete(hand.id)} aria-label="删除手牌">删除</button>
            </article>
          ))}
        </div>
      )}

      <div className="utility-row">
        <button onClick={onLedger}>场次账本</button>
        <button onClick={onBackup}>数据备份</button>
      </div>

      {isActive && (
        <div className="session-dock" aria-label="本场快捷操作">
          <button className="secondary" onClick={onEnd}>结束并结算</button>
          <button className="primary" onClick={onNew}><span>＋</span> 记一手</button>
        </div>
      )}
    </section>
  );
}

function LedgerScreen({
  archives,
  onClose,
  onAdd,
  onEdit,
}: {
  archives: SessionArchive[];
  onClose: () => void;
  onAdd: () => void;
  onEdit: (id: string) => void;
}) {
  const sessions = [...archives]
    .filter((item) => item.session.result)
    .sort((a, b) => new Date(b.session.createdAt).getTime() - new Date(a.session.createdAt).getTime());
  const totalProfit = sessions.reduce((sum, item) => sum + (item.session.result?.profit ?? 0), 0);
  const totalHours = sessions.reduce((sum, item) => sum + (item.session.result?.durationHours ?? 0), 0);
  const wins = sessions.filter((item) => (item.session.result?.profit ?? 0) > 0).length;

  return (
    <section className="screen">
      <PageHeading kicker="SESSION LEDGER" title="每次上桌，都算清楚。" subtitle="历史盈利记录已经合并进来；以后散场后直接在这里补一条。" />
      <article className="ledger-summary">
        <div className="ledger-total">
          <small>累计盈亏</small>
          <strong className={totalProfit >= 0 ? "profit-positive" : "profit-negative"}>{formatProfit(totalProfit)}</strong>
        </div>
        <div className="ledger-metrics">
          <span><b>{sessions.length}</b><small>场次</small></span>
          <span><b>{totalHours}</b><small>小时</small></span>
          <span><b>{totalHours ? formatProfit(Math.round(totalProfit / totalHours)) : "—"}</b><small>时薪</small></span>
          <span><b>{sessions.length ? Math.round((wins / sessions.length) * 100) + "%" : "—"}</b><small>胜率</small></span>
        </div>
      </article>

      <ProfitCurve sessions={sessions} />

      <button className="primary record-button" onClick={onAdd}><span>＋</span> 记录一场盈亏</button>

      <div className="section-heading list-heading">
        <div><span className="step">ALL SESSIONS</span><h2>场次明细</h2></div>
        <button className="text-button" onClick={onClose}>返回</button>
      </div>
      <div className="stack">
        {sessions.map((archive) => {
          const result = archive.session.result!;
          return (
            <button className="ledger-row" key={archive.session.id} onClick={() => onEdit(archive.session.id)}>
              <span className="ledger-date">
                <strong>{new Date(archive.session.createdAt).toLocaleDateString("zh-CN", { month: "short", day: "numeric" })}</strong>
                <small>{new Date(archive.session.createdAt).getFullYear()}</small>
              </span>
              <span className="ledger-copy">
                <strong>{result.stakes} NLH</strong>
                <small>{result.durationHours} 小时{result.location ? " · " + result.location : ""}{archive.hands.length ? " · " + archive.hands.length + " 手牌" : ""}</small>
              </span>
              <span className={result.profit >= 0 ? "ledger-profit profit-positive" : "ledger-profit profit-negative"}>
                {formatProfit(result.profit)}
              </span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

function ProfitCurve({ sessions }: { sessions: SessionArchive[] }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const points = useMemo(() => {
    const chronological = [...sessions].sort(
      (a, b) => new Date(a.session.createdAt).getTime() - new Date(b.session.createdAt).getTime(),
    );
    return chronological.reduce<Array<{
      date: Date;
      value: number;
      profit: number;
      stakes: string;
      durationHours: number;
      location: string;
    }>>((result, archive) => {
      const previous = result[result.length - 1]?.value ?? 0;
      const sessionResult = archive.session.result!;
      return [
        ...result,
        {
          date: new Date(archive.session.createdAt),
          value: previous + sessionResult.profit,
          profit: sessionResult.profit,
          stakes: sessionResult.stakes,
          durationHours: sessionResult.durationHours,
          location: sessionResult.location,
        },
      ];
    }, []);
  }, [sessions]);
  const values = [0, ...points.map((point) => point.value)];
  const highest = Math.max(...values);
  const lowest = Math.min(...values);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || points.length === 0) return;
    const draw = () => {
      const width = Math.max(280, Math.round(canvas.getBoundingClientRect().width));
      const height = 220;
      const ratio = window.devicePixelRatio || 1;
      canvas.width = width * ratio;
      canvas.height = height * ratio;
      const context = canvas.getContext("2d");
      if (!context) return;
      context.scale(ratio, ratio);
      context.clearRect(0, 0, width, height);

      const padding = { top: 18, right: 12, bottom: 18, left: 12 };
      const chartWidth = width - padding.left - padding.right;
      const chartHeight = height - padding.top - padding.bottom;
      const min = Math.min(0, ...points.map((point) => point.value));
      const max = Math.max(0, ...points.map((point) => point.value));
      const spread = Math.max(1, max - min);
      const allPoints = [{ value: 0 }, ...points];
      const x = (index: number) => padding.left + (index / Math.max(1, allPoints.length - 1)) * chartWidth;
      const y = (value: number) => padding.top + ((max - value) / spread) * chartHeight;

      context.lineWidth = 1;
      context.strokeStyle = "rgba(111, 121, 118, 0.18)";
      for (let index = 0; index <= 4; index += 1) {
        const gridY = padding.top + (index / 4) * chartHeight;
        context.beginPath();
        context.moveTo(padding.left, gridY);
        context.lineTo(width - padding.right, gridY);
        context.stroke();
      }

      context.save();
      context.setLineDash([5, 5]);
      context.strokeStyle = "rgba(111, 121, 118, 0.55)";
      context.beginPath();
      context.moveTo(padding.left, y(0));
      context.lineTo(width - padding.right, y(0));
      context.stroke();
      context.restore();

      const finalPositive = allPoints[allPoints.length - 1].value >= 0;
      const gradient = context.createLinearGradient(0, padding.top, 0, height - padding.bottom);
      gradient.addColorStop(0, finalPositive ? "rgba(42, 139, 97, 0.22)" : "rgba(195, 76, 59, 0.2)");
      gradient.addColorStop(1, finalPositive ? "rgba(42, 139, 97, 0)" : "rgba(195, 76, 59, 0)");
      context.beginPath();
      allPoints.forEach((point, index) => {
        if (index === 0) context.moveTo(x(index), y(point.value));
        else context.lineTo(x(index), y(point.value));
      });
      context.lineTo(x(allPoints.length - 1), height - padding.bottom);
      context.lineTo(x(0), height - padding.bottom);
      context.closePath();
      context.fillStyle = gradient;
      context.fill();

      context.lineWidth = 3;
      context.lineJoin = "round";
      context.lineCap = "round";
      for (let index = 1; index < allPoints.length; index += 1) {
        context.beginPath();
        context.moveTo(x(index - 1), y(allPoints[index - 1].value));
        context.lineTo(x(index), y(allPoints[index].value));
        context.strokeStyle = allPoints[index].value >= 0 ? "#2a8b61" : "#c34c3b";
        context.stroke();
      }

      const last = allPoints.length - 1;
      context.beginPath();
      context.arc(x(last), y(allPoints[last].value), 5, 0, Math.PI * 2);
      context.fillStyle = allPoints[last].value >= 0 ? "#2a8b61" : "#c34c3b";
      context.fill();
      context.lineWidth = 3;
      context.strokeStyle = "#fffdf8";
      context.stroke();

      if (activeIndex != null) {
        const selected = Math.min(points.length - 1, Math.max(0, activeIndex)) + 1;
        const selectedPoint = allPoints[selected];
        context.save();
        context.setLineDash([4, 4]);
        context.strokeStyle = "rgba(21, 37, 35, 0.5)";
        context.lineWidth = 1;
        context.beginPath();
        context.moveTo(x(selected), padding.top);
        context.lineTo(x(selected), height - padding.bottom);
        context.stroke();
        context.restore();

        context.beginPath();
        context.arc(x(selected), y(selectedPoint.value), 6, 0, Math.PI * 2);
        context.fillStyle = selectedPoint.value >= 0 ? "#2a8b61" : "#c34c3b";
        context.fill();
        context.lineWidth = 3;
        context.strokeStyle = "#fffdf8";
        context.stroke();
      }
    };

    draw();
    if (typeof ResizeObserver !== "undefined") {
      const observer = new ResizeObserver(draw);
      observer.observe(canvas);
      return () => observer.disconnect();
    }
    window.addEventListener("resize", draw);
    return () => window.removeEventListener("resize", draw);
  }, [activeIndex, points]);

  if (!points.length) return null;
  const firstDate = points[0].date.toLocaleDateString("zh-CN", { year: "numeric", month: "short" });
  const lastDate = points[points.length - 1].date.toLocaleDateString("zh-CN", { year: "numeric", month: "short" });
  const activePoint = activeIndex == null ? null : points[activeIndex];
  const tooltipPosition = activeIndex == null
    ? 50
    : Math.min(92, Math.max(8, ((activeIndex + 1) / points.length) * 100));

  const selectNearestClientX = (clientX: number) => {
    const canvas = canvasRef.current;
    if (!canvas || !points.length) return;
    const bounds = canvas.getBoundingClientRect();
    const padding = 12;
    const chartWidth = Math.max(1, bounds.width - padding * 2);
    const relative = Math.min(1, Math.max(0, (clientX - bounds.left - padding) / chartWidth));
    const allPointIndex = Math.round(relative * points.length);
    setActiveIndex(Math.min(points.length - 1, Math.max(0, allPointIndex - 1)));
  };
  const selectNearestPoint = (event: ReactPointerEvent<HTMLCanvasElement>) => {
    selectNearestClientX(event.clientX);
  };
  const selectNearestTouch = (event: ReactTouchEvent<HTMLCanvasElement>) => {
    const touch = event.touches[0] ?? event.changedTouches[0];
    if (touch) selectNearestClientX(touch.clientX);
  };

  return (
    <article className="profit-chart-card">
      <div className="profit-chart-heading">
        <div><span className="step">PROFIT CURVE</span><h2>累计盈利曲线</h2></div>
        <small>{firstDate} — {lastDate}</small>
      </div>
      <p className="curve-hint">轻点或按住曲线左右滑动，查看每一场</p>
      <div className="profit-canvas-wrap">
        {activePoint && (
          <div
            className="curve-tooltip"
            style={{
              left: tooltipPosition + "%",
              transform: activeIndex === 0
                ? "translateX(0)"
                : activeIndex === points.length - 1
                  ? "translateX(-100%)"
                  : "translateX(-50%)",
            }}
          >
            <div>
              <strong>{activePoint.date.toLocaleDateString("zh-CN")}</strong>
              <span>{activePoint.stakes} · {activePoint.durationHours} 小时{activePoint.location ? " · " + activePoint.location : ""}</span>
            </div>
            <div className="tooltip-values">
              <span><small>本场盈亏</small><b className={activePoint.profit >= 0 ? "profit-positive" : "profit-negative"}>{formatProfit(activePoint.profit)}</b></span>
              <span><small>累计盈亏</small><b className={activePoint.value >= 0 ? "profit-positive" : "profit-negative"}>{formatProfit(activePoint.value)}</b></span>
            </div>
          </div>
        )}
        <canvas
          ref={canvasRef}
          className="profit-canvas"
          role="img"
          aria-label={"从 " + firstDate + " 到 " + lastDate + " 的累计盈利曲线，当前累计 " + formatProfit(points[points.length - 1].value)}
          onPointerDown={(event) => {
            selectNearestPoint(event);
            try {
              event.currentTarget.setPointerCapture?.(event.pointerId);
            } catch {
              // Older Safari continues through the native touch handlers below.
            }
          }}
          onPointerMove={selectNearestPoint}
          onTouchStart={selectNearestTouch}
          onTouchMove={selectNearestTouch}
          onClick={(event) => selectNearestClientX(event.clientX)}
          onPointerLeave={(event) => {
            if (event.pointerType === "mouse") setActiveIndex(null);
          }}
        />
      </div>
      <div className="curve-metrics">
        <span><small>历史高点</small><b className="profit-positive">{formatProfit(highest)}</b></span>
        <span><small>历史低点</small><b className={lowest < 0 ? "profit-negative" : "profit-positive"}>{formatProfit(lowest)}</b></span>
        <span><small>当前累计</small><b className={points[points.length - 1].value >= 0 ? "profit-positive" : "profit-negative"}>{formatProfit(points[points.length - 1].value)}</b></span>
      </div>
    </article>
  );
}

function SettlementScreen({
  archive,
  onCancel,
  onSave,
}: {
  archive: SessionArchive | null;
  onCancel: () => void;
  onSave: (record: { date: string; sb: number; bb: number; result: SessionResult }) => Promise<boolean>;
}) {
  const current = archive?.session.result;
  const initialDate = archive
    ? dateInputValue(new Date(archive.session.createdAt))
    : dateInputValue(new Date());
  const [date, setDate] = useState(initialDate);
  const [stakes, setStakes] = useState(current?.stakes ?? (archive ? archive.session.sb + "/" + archive.session.bb : "1/2"));
  const [duration, setDuration] = useState(String(current?.durationHours ?? estimatedDurationHours(archive?.session)));
  const [buyIn, setBuyIn] = useState(current?.buyIn != null ? String(current.buyIn) : archive?.session.buyIns?.length ? String(totalBuyIn(archive.session)) : "");
  const [cashOut, setCashOut] = useState(current?.cashOut == null ? "" : String(current.cashOut));
  const [profit, setProfit] = useState(current ? String(current.profit) : "");
  const [location, setLocation] = useState(current?.location ?? "");
  const [note, setNote] = useState(current?.note ?? "");
  const [formError, setFormError] = useState("");
  const [saving, setSaving] = useState(false);
  const calculated = buyIn !== "" && cashOut !== "";

  const updateCalculatedProfit = (nextBuyIn: string, nextCashOut: string) => {
    if (nextBuyIn !== "" && nextCashOut !== "") {
      setProfit(String(Number(nextCashOut) - Number(nextBuyIn)));
    }
  };

  return (
    <section className="screen">
      <div className="section-heading"><h1>{archive ? "结束并结算" : "补记结果"}</h1></div>
      <article className="panel settlement-panel">
        <div className="field-grid two">
          <label>累计买入<input inputMode="decimal" type="number" value={buyIn} onChange={(event) => { setBuyIn(event.target.value); updateCalculatedProfit(event.target.value, cashOut); }} placeholder="可不填" /></label>
          <label>离场带走<input inputMode="decimal" type="number" value={cashOut} onChange={(event) => { setCashOut(event.target.value); updateCalculatedProfit(buyIn, event.target.value); }} placeholder="可不填" /></label>
        </div>
        {!!archive?.session.buyIns?.length && <details className="optional-section"><summary>查看买入明细 · {archive.session.buyIns.length} 笔</summary>{archive.session.buyIns.map((entry, index) => <p key={entry.id}>{index === 0 ? "首次买入" : "补码"} · {new Date(entry.at).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })} · {entry.amount.toLocaleString("zh-CN")}</p>)}</details>}
        <label>
          本场盈亏
          <input className={Number(profit) >= 0 ? "profit-input positive" : "profit-input negative"} inputMode="decimal" type="number" readOnly={calculated} value={profit} onChange={(event) => setProfit(event.target.value)} placeholder="也可只填最终盈亏" />
          <small className="field-hint">{calculated ? "带出 − 累计买入，自动计算" : "盈利填正数，亏损填负数"}</small>
        </label>
        <div className="field-grid two">
          <label>日期<input type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label>
          <label>游戏时间（小时）<input inputMode="decimal" type="number" min="0" step="0.5" value={duration} onChange={(event) => setDuration(event.target.value)} placeholder="例如 4.5" /></label>
        </div>
        <details className="optional-section"><summary>更多信息 · {stakes}{location ? ` · ${location}` : ""}</summary>
        <label>盲注级别<input value={stakes} placeholder="例如 1/2/10" onChange={(event) => setStakes(event.target.value)} /></label>
        <label>地点<input value={location} onChange={(event) => setLocation(event.target.value)} placeholder="可选，例如诺德" /></label>
        <label>备注<textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="可选：桌况、状态或本场训练主题" /></label>
        </details>
        {!!archive?.hands.length && <p className="field-hint">本场 {archive.hands.filter((hand) => handState(hand) !== "已复盘").length} 手待复盘，可结算后继续。</p>}
        {formError && <p className="form-error" role="alert">{formError}</p>}
        <div className="button-pair">
          <button className="secondary" disabled={saving} onClick={onCancel}>返回</button>
          <button
            className="primary"
            disabled={saving}
            onClick={async () => {
              if ([buyIn, cashOut].some((value) => value !== "" && (!Number.isFinite(Number(value)) || Number(value) < 0))) { setFormError("买入和带出必须是非负金额。"); return; }
              if (!date) {
                setFormError("请选择本场日期。");
                return;
              }
              if (!stakes.trim()) {
                setFormError("请填写盲注级别。");
                return;
              }
              if (!(Number(duration) > 0) || !Number.isFinite(Number(duration))) {
                setFormError("请填写大于 0 的游戏时间。");
                return;
              }
              if (profit === "" || !Number.isFinite(Number(profit))) {
                setFormError("请填写本场最终盈亏；盈利填正数，亏损填负数。");
                return;
              }
              setFormError("");
              setSaving(true);
              const parsed = parseStakes(stakes);
              const saved = await onSave({
                date,
                ...parsed,
                result: {
                  profit: Number(profit),
                  durationHours: Number(duration),
                  stakes: stakes.trim(),
                  location: location.trim(),
                  note: note.trim(),
                  source: current?.source ?? "app",
                  ...(buyIn === "" ? {} : { buyIn: Number(buyIn) }),
                  ...(cashOut === "" ? {} : { cashOut: Number(cashOut) }),
                },
              });
              setSaving(false);
              if (!saved) setFormError("未能保存到本机，请重试。当前填写内容仍在。");
            }}
          >
            {saving ? "保存中…" : "保存本场结果"}
          </button>
        </div>
      </article>
    </section>
  );
}

function QuickScreen({ hand, bigBlind, saveState, onRetry, onChange, onCancel, onSave }: {
  hand: PokerHand;
  bigBlind: number;
  saveState: string;
  onRetry: () => void;
  onChange: (hand: PokerHand) => void;
  onCancel: () => void;
  onSave: () => void;
}) {
  return (
    <div className="quick-sheet-backdrop" onClick={onCancel}>
      <section className="quick-sheet" role="dialog" aria-modal="true" aria-label="快速记录手牌" onClick={(event) => event.stopPropagation()}>
        <div className="quick-sheet-handle" />
        <div className="quick-sheet-heading">
          <div><h2>记一手</h2></div>
          <button className="text-button" onClick={onCancel}>收起</button>
        </div>
        <p className="draft-status" role="status"><span className="status-dot" /> {saveState}{saveState.includes("失败") && <button className="text-button" onClick={onRetry}>重试</button>}</p>
        <article className="quick-panel">
        <FieldTitle title="我的底牌" note={`${hand.heroCards.length}/2`} />
        <CompactHandPicker selected={hand.heroCards} onChange={(heroCards) => onChange({ ...hand, heroCards })} />
        <FieldTitle title="我的位置" />
        <div className="choice-row wrap">
          {positions(hand.playerCount).map((position) => (
            <button key={position} className={hand.heroPosition === position ? "choice selected" : "choice"} onClick={() => onChange({ ...hand, heroPosition: position })}>{position}</button>
          ))}
        </div>
        <label>一句话笔记<textarea rows={2} value={hand.note ?? ""} onChange={(event) => onChange({ ...hand, note: event.target.value })} placeholder="例如：转牌被超池加注，纠结要不要跟" /></label>
        <details className="optional-section"><summary>更多信息：后手和标签</summary>
        <FieldTitle title="标记这手" note="可选" />
        <div className="choice-row wrap">
          {tags.map((tag) => (
            <button
              key={tag}
              className={hand.tags.includes(tag) ? "choice selected" : "choice"}
              onClick={() => onChange({ ...hand, tags: hand.tags.includes(tag) ? hand.tags.filter((item) => item !== tag) : [...hand.tags, tag] })}
            >
              {tag}
            </button>
          ))}
        </div>
        <label>有效后手（筹码）<input inputMode="decimal" type="number" value={chipsFromBB(hand.effectiveStackBB, bigBlind)} onChange={(e) => onChange({ ...hand, effectiveStackBB: bbFromChips(Number(e.target.value), bigBlind) })} /></label>
        </details>
        </article>
        <div className="quick-sheet-save">
        <button className="primary" disabled={hand.heroCards.length === 0 && !hand.note?.trim()} onClick={onSave}>
          保存这手，回到本场
        </button>
        </div>
      </section>
    </div>
  );
}

function CompactHandPicker({ selected, onChange }: {
  selected: PlayingCard[];
  onChange: (cards: PlayingCard[]) => void;
}) {
  const [activeSlot, setActiveSlot] = useState<0 | 1 | null>(null);
  const [pendingRank, setPendingRank] = useState<string | null>(null);

  const openSlot = (slot: 0 | 1) => {
    if (slot === 1 && !selected[0]) return;
    setActiveSlot(slot);
    setPendingRank(selected[slot]?.rank ?? null);
  };
  const closePicker = () => {
    setActiveSlot(null);
    setPendingRank(null);
  };
  const selectSuit = (suit: PlayingCard["suit"]) => {
    if (activeSlot == null || !pendingRank) return;
    const card = { rank: pendingRank, suit };
    const next = [...selected];
    next[activeSlot] = card;
    onChange(next);
    if (activeSlot === 0 && !selected[1]) {
      setActiveSlot(1);
      setPendingRank(null);
    } else {
      closePicker();
    }
  };

  return (
    <>
      <div className="quick-hand-slots">
        {([0, 1] as const).map((slot) => {
          const card = selected[slot];
          const red = card && (card.suit === "♥" || card.suit === "♦");
          return (
            <button
              key={slot}
              className={card ? "quick-card-slot selected" : "quick-card-slot"}
              disabled={slot === 1 && !selected[0]}
              onClick={() => openSlot(slot)}
              aria-label={`${slot === 0 ? "第一张" : "第二张"}手牌${card ? `，当前 ${cardText(card)}` : "，尚未选择"}`}
            >
              <small>{slot === 0 ? "第一张" : "第二张"}</small>
              <strong className={red ? "red-card-text" : ""}>{card ? cardText(card) : "＋"}</strong>
              <span>{card ? "点按更换" : slot === 1 && !selected[0] ? "先选第一张" : "点按选择"}</span>
            </button>
          );
        })}
      </div>

      {activeSlot != null && (
        <div className="compact-picker-backdrop" onClick={closePicker}>
          <section className="compact-picker-sheet" role="dialog" aria-modal="true" aria-label={`选择第${activeSlot + 1}张手牌`} onClick={(event) => event.stopPropagation()}>
            <div className="compact-picker-heading">
              <div><small>HERO 手牌</small><h2>选择第{activeSlot + 1}张牌</h2></div>
              <button onClick={closePicker} aria-label="关闭选牌器">关闭</button>
            </div>
            <div className="compact-rank-grid">
              {ranks.map((rank) => (
                <button
                  key={rank}
                  className={pendingRank === rank ? "selected" : ""}
                  onClick={() => setPendingRank(rank)}
                  aria-pressed={pendingRank === rank}
                >
                  {rank}
                </button>
              ))}
            </div>
            <div className="compact-suit-grid">
              {suits.map((suit) => {
                const duplicate = selected.some((card, index) => index !== activeSlot && card.rank === pendingRank && card.suit === suit);
                return (
                  <button
                    key={suit}
                    className={suit === "♥" || suit === "♦" ? "red-card-text" : ""}
                    disabled={!pendingRank || duplicate}
                    onClick={() => selectSuit(suit)}
                    aria-label={`${suit}${duplicate ? "，已选择" : ""}`}
                  >
                    {suit}
                  </button>
                );
              })}
            </div>
            <p>{pendingRank ? "再选择花色" : "先选择点数"}</p>
          </section>
        </div>
      )}
    </>
  );
}

function RouteScreen({ hand, bigBlind, street, saveState, onStreet, onChange, onFinish, onEditBasics }: {
  hand: PokerHand;
  bigBlind: number;
  street: StreetKey;
  saveState: string;
  onStreet: (street: StreetKey) => void;
  onChange: (hand: PokerHand) => void;
  onFinish: () => void;
  onEditBasics: () => void;
}) {
  const [actor, setActor] = useState(hand.heroPosition);
  const [action, setAction] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [error, setError] = useState("");
  const record = hand.streets[street];
  const blocked = [
    ...hand.heroCards,
    ...streets.flatMap((key) => hand.streets[key].board),
  ].filter((card, index, list) => list.findIndex((item) => cardText(item) === cardText(card)) === index);
  const boardLimit = street === "flop" ? 3 : street === "preflop" ? 0 : 1;

  const setRecord = (next: StreetRecord) => {
    onChange({ ...hand, streets: { ...hand.streets, [street]: next } });
  };

  const appendAction = (kind: string, amountValue = "") => {
    if (amountValue !== "" && (!(Number(amountValue) > 0) || !Number.isFinite(Number(amountValue)))) {
      setError("请输入大于 0 的筹码金额，或选择金额待补。");
      return;
    }
    const next: HandAction = { id: uid(), actor, action: kind, hero: actor === hand.heroPosition };
    if (amountValue !== "") { next.amountBB = bbFromChips(Number(amountValue), bigBlind); next.amountScope = "streetTotal"; }
    setRecord({ ...record, actions: [...record.actions, next] });
    setAction(null); setAmount(""); setError("");
  };

  return (
    <section className="screen">
      <div className="route-context">
        <div><small>我的底牌</small><strong>{hand.heroCards.map(cardText).join(" ") || "待补"}</strong></div>
        <div><small>当前街</small><strong>{streetLabels[street]}</strong></div>
        <div><small>底池</small><strong>{record.potBB == null ? "待补" : chipText(record.potBB, bigBlind)}</strong></div>
      </div>
      {hand.note && <p className="hand-note">{hand.note}</p>}
      <div className="utility-row"><button onClick={onEditBasics}>修改底牌 / 笔记</button><button onClick={onFinish}>直接进入复盘</button></div>
      <p className="draft-status" role="status">{saveState}</p>
      <div className="street-tabs">
        {streets.map((key) => <button key={key} className={street === key ? "active" : ""} onClick={() => onStreet(key)}>{streetLabels[key]}</button>)}
      </div>

      {boardLimit > 0 && (
        <details className="panel board-disclosure">
          <summary>{streetLabels[street]} 公共牌 · {record.board.map(cardText).join(" ") || "待补"}<span>选择 / 修改</span></summary>
          <FieldTitle title={`${streetLabels[street]} 公共牌`} note={`${record.board.length}/${boardLimit}`} />
          <CardPicker
            selected={record.board}
            max={boardLimit}
            blocked={blocked.filter((card) => !record.board.some((item) => cardText(item) === cardText(card)))}
            onChange={(board) => setRecord({ ...record, board })}
          />
        </details>
      )}

      <article className="panel action-panel">
        <div className="section-heading"><h2>记录行动</h2><button className="text-button" disabled={!record.actions.length} onClick={() => {
          const last = record.actions[record.actions.length - 1];
          setRecord({ ...record, actions: record.actions.slice(0, -1) });
          if (last) setActor(last.actor);
          setAction(null); setAmount(""); setError("");
        }}>撤销上一步</button></div>
        <div className="actor-focus"><span>当前行动者</span><strong>{actor}{actor === hand.heroPosition ? " · 我" : ""}</strong><small>手动选择位置，可跳记关键动作</small></div>
        {record.actions.length > 0 && <p className="last-action" role="status">已记：{actionText(record.actions[record.actions.length - 1], bigBlind)}。下一步可切换位置。</p>}
        <div className="choice-row wrap actor-choices" aria-label="选择行动者">
          {positions(hand.playerCount).map((position) => <button key={position} aria-pressed={actor === position} className={actor === position ? "choice selected" : "choice"} onClick={() => { setActor(position); setAction(null); setAmount(""); setError(""); }}>{position}{position === hand.heroPosition ? " · 我" : ""}</button>)}
        </div>
        <div className="action-buttons" aria-label="选择动作">
          {actionOptions.map((kind) => <button key={kind} aria-pressed={action === kind} className={action === kind ? "action-button selected" : "action-button"} onClick={() => {
            if (kind === "check" || kind === "fold") appendAction(kind);
            else { setAction(kind); setAmount(""); setError(""); }
          }}>{actionLabels[kind]}</button>)}
        </div>
        {action && <div className="action-amount-panel">
          <label>{actor} {actionLabels[action]}至（筹码）<input autoFocus inputMode="decimal" type="number" min="0" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="本街累计投入，不是本次追加金额" onKeyDown={(event) => { if (event.key === "Enter" && amount !== "") appendAction(action, amount); }} /></label>
          <p className="field-hint">例如先投入 20，再加注到 100，填写 100。</p>
          {error && <p className="form-error" role="alert">{error}</p>}
          <div className="button-pair"><button className="secondary" onClick={() => appendAction(action)}>金额待补</button><button className="primary" disabled={amount === ""} onClick={() => appendAction(action, amount)}>确认{actionLabels[action]}</button></div>
        </div>}
        <button className="text-button wide" onClick={() => appendAction("unknown")}>这一步记不清，标为待补</button>

        {record.actions.length > 0 && (
          <ol className="timeline">
            {record.actions.map((item, index) => (
              <li key={item.id}>
                <span>{index + 1}</span><b>{actionText(item, bigBlind)}{item.hero ? " · 我" : ""}</b>
                <button onClick={() => setRecord({ ...record, actions: record.actions.filter((actionItem) => actionItem.id !== item.id) })}>删除</button>
              </li>
            ))}
          </ol>
        )}

        <details className="optional-section"><summary>本街结束底池 · {record.potBB == null ? "可选" : chipText(record.potBB, bigBlind)}</summary><label>本街结束底池（筹码）<input inputMode="decimal" type="number" min="0" value={record.potBB == null ? "" : chipsFromBB(record.potBB, bigBlind)} onChange={(e) => {
          if (e.target.value !== "" && (!Number.isFinite(Number(e.target.value)) || Number(e.target.value) < 0)) return;
          setRecord({ ...record, potBB: e.target.value === "" ? undefined : bbFromChips(Number(e.target.value), bigBlind), confidence: "exact" });
        }} /></label></details>
      </article>

      <button
        className="primary wide bottom-action"
        onClick={() => {
          const index = streets.indexOf(street);
          if (index === streets.length - 1) onFinish();
          else onStreet(streets[index + 1]);
        }}
      >
        {street === "river" ? "完成路线，进入复盘" : `保存并继续 ${streetLabels[streets[streets.indexOf(street) + 1]]}`}
      </button>
    </section>
  );
}

function HandReplay({ hand, bigBlind }: { hand: PokerHand; bigBlind: number }) {
  const steps = replaySteps(hand);
  const [cursor, setCursor] = useState(0);
  const index = Math.min(cursor, steps.length - 1);
  const step = steps[index];
  const board = replayBoard(hand, step.street);
  const record = hand.streets[step.street];
  const summary = step.action ? actionText(step.action, bigBlind) : step.kind === "end" ? `${streetLabels[step.street]}结束 · 底池 ${chipText(record.potBB!, bigBlind)}` : `${streetLabels[step.street]}开始`;
  return <article className="panel hand-replayer" aria-label="手牌逐步回放">
    <div className="section-heading"><h2>手牌回放</h2><span className="local-chip">{index + 1} / {steps.length}</span></div>
    <div className="street-tabs" aria-label="跳转到街">
      {streets.map((street) => <button key={street} className={step.street === street ? "active" : ""} disabled={!steps.some((item) => item.street === street)} onClick={() => setCursor(steps.findIndex((item) => item.street === street))}>{streetLabels[street]}</button>)}
    </div>
    <div className="replay-frame">
      <div className="replay-hero"><small>我的底牌 · {hand.heroPosition}</small><strong>{hand.heroCards.map(cardText).join(" ") || "底牌待补"}</strong></div>
      <div className="replay-board" aria-label="当前公共牌">
        {board.length ? board.map((card, i) => <span key={i} aria-label={card ? cardText(card) : "公共牌待补"} className={card?.suit === "♥" || card?.suit === "♦" ? "replay-card red-card-text" : "replay-card"}>{card ? cardText(card) : "?"}</span>) : <span className="board-placeholder">翻前 · 尚无公共牌</span>}
      </div>
      <div className="replay-current" aria-live="polite"><small>{step.action ? `${step.action.actor}${step.action.hero ? " · 我" : ""}` : streetLabels[step.street]}</small><strong>{summary}</strong></div>
    </div>
    <label className="replay-progress">回放进度<input aria-label="回放进度" type="range" min="0" max={steps.length - 1} value={index} disabled={steps.length === 1} onChange={(event) => setCursor(Number(event.target.value))} /></label>
    <div className="button-pair"><button className="secondary" disabled={index === 0} onClick={() => setCursor(index - 1)}>← 上一步</button><button className="primary" disabled={index === steps.length - 1} onClick={() => setCursor(index + 1)}>下一步 →</button></div>
    <p className="field-hint">只回放已记录的步骤；未记录的动作和底池不作推算。</p>
    <details className="optional-section"><summary>步骤目录 · 点选跳转</summary><ol className="replay-step-list">{steps.map((item, i) => <li key={i}><button className={i === index ? "selected" : ""} aria-current={i === index ? "step" : undefined} onClick={() => setCursor(i)}>{i + 1}. {streetLabels[item.street]} · {item.action ? actionText(item.action, bigBlind) : item.kind === "end" ? "结束底池" : "开始"}</button></li>)}</ol></details>
  </article>;
}

function DetailScreen({ hand, session, onChange, onEditRoute, onSave, onEditBasics }: {
  hand: PokerHand;
  session: ReviewSession;
  onChange: (hand: PokerHand) => void;
  onEditRoute: () => void;
  onSave: () => void;
  onEditBasics: () => void;
}) {
  return (
    <section className="screen">
      <PageHeading kicker={hand.tags.join(" · ") || "HAND REVIEW"} title={`${hand.heroPosition} · ${hand.heroCards.map(cardText).join(" ") || "底牌待补"}`} subtitle={`${session.sb}/${session.bb} NLH · 有效后手 ${chipText(hand.effectiveStackBB, session.bb)}`} />
      <HandReplay key={hand.id} hand={hand} bigBlind={session.bb} />
      <article className="panel replay">
        {hand.note && <p className="hand-note">现场笔记：{hand.note}</p>}
        <button className="text-button" onClick={onEditBasics}>修改底牌 / 笔记</button>
        <details className="optional-section"><summary>查看完整行动记录</summary>
        {streets.map((street) => {
          const record = hand.streets[street];
          if (!record.actions.length && !record.board.length) return null;
          return (
            <div className="street-replay" key={street}>
              <h3>{streetLabels[street]} <span>{record.board.map(cardText).join(" ")}</span></h3>
              <p>{record.actions.map((action) => actionText(action, session.bb)).join(" → ") || "行动待补"}</p>
              {record.potBB != null && <small>底池 {chipText(record.potBB, session.bb)}</small>}
            </div>
          );
        })}
        </details>
        <button className="secondary wide" onClick={onEditRoute}>修改行动路线</button>
      </article>
      <article className="panel">
        <FieldTitle title="复盘三问" />
        <label>关键决策<textarea value={hand.review.decision} onChange={(e) => onChange({ ...hand, review: { ...hand.review, decision: e.target.value } })} /></label>
        <label>当时依据<textarea value={hand.review.basis} onChange={(e) => onChange({ ...hand, review: { ...hand.review, basis: e.target.value } })} /></label>
        <label>下次默认修正<textarea value={hand.review.correction} onChange={(e) => onChange({ ...hand, review: { ...hand.review, correction: e.target.value } })} /></label>
        <div className="button-pair">
          <button className="secondary" onClick={() => download(`hand-${hand.id}.md`, handMarkdown(hand, session), "text/markdown")}>导出 Markdown</button>
          <button className="primary" onClick={onSave}>保存并返回</button>
        </div>
      </article>
    </section>
  );
}

function InboxScreen({ hands, onOpen }: { hands: PokerHand[]; onOpen: (hand: PokerHand) => void }) {
  return (
    <section className="screen">
      <PageHeading kicker="REVIEW QUEUE" title="待补全优先。" subtitle="先处理记忆最鲜明的手牌。" />
      {hands.length === 0 ? <div className="empty-state"><b>全部补完了</b><span>这一场没有待处理手牌。</span></div> : (
        <div className="stack">
          {hands.map((hand) => (
            <button className="archive-row" key={hand.id} onClick={() => onOpen(hand)}>
              <span><strong>{hand.heroPosition} · {hand.heroCards.map(cardText).join(" ") || "手牌待补"}</strong><small>{hand.tags.join(" · ")}</small></span>
              <span><b>{handState(hand)}</b></span>
            </button>
          ))}
        </div>
      )}
    </section>
  );
}

function BackupScreen({ snapshot, hasArchive, onPickImport }: {
  snapshot: StoreSnapshot;
  hasArchive: boolean;
  onImport: (snapshot: StoreSnapshot) => void;
  onPickImport: () => void;
}) {
  return (
    <section className="screen">
      <PageHeading kicker="LOCAL FIRST" title="数据属于你。" subtitle="程序不上传手牌；请定期把完整备份保存到“文件”或自己的云盘。" />
      <article className="panel backup-card">
        <div className="backup-symbol">↓</div>
        <h2>导出完整 JSON</h2>
        <p>{snapshot.archives.length} 个场次 · {snapshot.archives.reduce((sum, archive) => sum + archive.hands.length, 0)} 手牌</p>
        <button
          className="primary wide"
          disabled={!hasArchive}
          onClick={() => download(`KeyHandReview-Backup-${new Date().toISOString().slice(0, 10)}.json`, JSON.stringify(snapshot, null, 2), "application/json")}
        >
          下载备份
        </button>
      </article>
      <article className="panel backup-card">
        <div className="backup-symbol upload">↑</div>
        <h2>恢复或迁移备份</h2>
        <p>兼容原生 iOS App 导出的完整 JSON。导入会覆盖当前全部数据。</p>
        <button className="secondary wide" onClick={onPickImport}>选择 JSON 文件</button>
      </article>
      <article className="install-tip">
        <b>添加到 iPhone 主屏幕</b>
        <span>Safari 分享按钮 → 添加到主屏幕。之后可像普通 App 一样打开并离线使用。</span>
      </article>
    </section>
  );
}

function CardPicker({ selected, max, blocked, onChange }: {
  selected: PlayingCard[];
  max: number;
  blocked: PlayingCard[];
  onChange: (cards: PlayingCard[]) => void;
}) {
  const blockedSet = new Set(blocked.map(cardText));
  const selectedSet = new Set(selected.map(cardText));
  return (
    <div className="card-picker">
      {ranks.flatMap((rank) => suits.map((suit) => {
        const card = { rank, suit };
        const key = cardText(card);
        const isSelected = selectedSet.has(key);
        return (
          <button
            key={key}
            disabled={blockedSet.has(key)}
            className={`${suit === "♥" || suit === "♦" ? "red-card" : ""} ${isSelected ? "picked" : ""}`}
            onClick={() => {
              if (isSelected) onChange(selected.filter((item) => cardText(item) !== key));
              else if (selected.length < max) onChange([...selected, card]);
            }}
          >
            {key}
          </button>
        );
      }))}
    </div>
  );
}

function PageHeading({ kicker, title, subtitle }: { kicker: string; title: string; subtitle: string }) {
  return <div className="page-heading"><p className="eyebrow">{kicker}</p><h1>{title}</h1><p>{subtitle}</p></div>;
}

function FieldTitle({ title, note }: { title: string; note?: string }) {
  return <div className="field-title"><b>{title}</b>{note && <span>{note}</span>}</div>;
}

async function importBackup(event: ChangeEvent<HTMLInputElement>, onImport: (snapshot: StoreSnapshot) => void) {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file) return;
  try {
    const parsed = JSON.parse(await file.text()) as StoreSnapshot;
    if (!Array.isArray(parsed.archives) || !("activeSessionID" in parsed)) throw new Error("invalid");
    onImport(parsed);
  } catch {
    alert("无法读取这个备份文件。请选择由手牌复盘速记导出的 JSON。");
  }
}
