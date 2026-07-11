# 手牌复盘速记 · iOS 本地安装版

这是一个 SwiftUI 原生 iOS MVP，用来先在自己的 iPhone 上测试核心体验，不需要 App Store 上架，也不需要苹果审核。

## 当前包含

- 新建复盘记录：盲注、筹码单位、4–10 人、默认 straddle
- 快速保存：大池量 / 纠结 / 对手读牌、Hero 位置、有效后手、Hero 手牌点选
- 补行动路线：Preflop 模板、自定义逐条记录、Flop / Turn / River 点选公共牌
- 路线页固定信息条：记录过程中常驻展示 Hero 手牌、公共牌、当前街与底池，减少回看和记错
- 待复盘列表：纠结优先、继续补路线、查看回放
- 回放与复盘三问：保存复盘后返回首页，避免保存无反馈
- 本场 Session 管理：可结束本场，结束后回到历史场次；历史场次可重新进入查看和补复盘
- Markdown 复制与系统分享
- 本机本地存储：无登录、无后端、无网络依赖；数据保存在 iPhone App 本地，卸载 App 会随系统默认逻辑一并清除

## 如何安装到自己的 iPhone

1. 安装完整 Xcode（不是 Command Line Tools）。
2. 打开项目根目录里的 `KeyHandReview.xcodeproj`。

3. 在 Xcode 左侧选中项目 `KeyHandReview`，进入 target 的 `Signing & Capabilities`。
4. Team 选择你的 Apple ID / Personal Team。
5. 如果 Bundle Identifier 冲突，把 `com.lizhe.keyhandreview` 改成你自己的唯一值，例如：

   `com.yourname.keyhandreview`

6. 用数据线连接 iPhone，顶部设备选择你的 iPhone。
7. 点击 Run。
8. 如果手机提示“不受信任的开发者”，到 iPhone：

   `设置 → 通用 → VPN与设备管理`

   信任你的 Apple ID 开发者证书。

免费 Apple ID 安装的开发签名通常 7 天后过期，过期后用 Xcode 再 Run 一次即可。等你确认好用，再考虑 Apple Developer Program、TestFlight 或 App Store。

## 注意

这个版本定位是“个人手牌学习复盘记录工具”。不要加入登录、支付、约局、线上对局、结算、实时策略建议等功能；这些都会显著增加审核和合规风险。
