# 更新记录

记录用户可见的产品变化。每次迭代都要补这里，避免只靠 commit 回忆。

## 2026-07-11｜文档治理基线

- 新增产品原则文档：`docs/PRODUCT.md`。
- 新增关键决策记录：`docs/DECISIONS.md`。
- 新增更新记录：`docs/CHANGELOG.md`。
- README 增加项目文档入口。

## 2026-07-11｜本地 Session 历史与固定公共牌信息条

对应提交：`5194273 Add local session history and sticky board context`

- 路线页顶部新增固定信息条，常驻显示 Hero 手牌、公共牌、当前街和底池。
- 回放页复盘按钮改为 `保存并返回首页`。
- 首页新增 `结束本场`。
- 结束后的场次进入历史列表，可重新进入查看和补复盘。
- 存储从单个当前 session 升级为本机本地 JSON 快照，支持多场 Session 历史。
- README 记录本机本地存储边界：卸载 App 会按 iOS 默认逻辑清除数据。

## 2026-07-11｜修复行动闭合后循环 check

对应提交：`dccdb7d Stop closed streets from cycling actions`

- 一条街没有新的 bet / raise 时，所有应行动玩家完成动作后，本街闭合。
- 有 bet / raise 时，只推荐仍需回应的玩家。
- 已经不欠动作的位置置灰，避免重复 check / call。
- 漏记时仍可在本街路线中插入或编辑动作，并重新计算行动状态。

## 2026-07-11｜行动顺序成为路线记录主入口

对应提交：`884e62d Streamline action-order route entry`

- `行动顺序与记录` 成为本街动作录入主入口。
- `本街路线` 收敛为生成文本和修正入口。
- 支持插入、编辑、删除动作。
- 修正后重新计算底池、当前下注、待跟和下一位行动人。
- Call 默认使用系统计算的待跟金额。
- Open / bet / raise / 3bet / 4bet 使用“下注到 X”的语义。

## 2026-07-11｜行动顺序时间线编辑

对应提交：`b5df131 Add action order timeline editing`

- 增加行动顺序栏。
- 支持跳过未记录玩家。
- 支持临时切换当前行动人。
- 支持在路线中补插漏记动作。

## 2026-07-11｜iOS MVP

对应提交：`c3cf1a4 Initial iOS key hand recorder app`

- SwiftUI iOS 本地安装版。
- 支持新建复盘记录：盲注、筹码单位、人数、默认 straddle。
- 支持快速保存关键手牌：标签、Hero 位置、有效后手、Hero 手牌。
- 支持补行动路线、待复盘列表、回放与复盘三问。
- 支持 Markdown 复制和系统分享。

