# 组间

「组间」是一款以 Apple Watch 为核心的力量训练辅助 App。它通过手腕运动判断一组训练的开始和结束，在动作停止后自动启动组间休息倒计时，并通过触觉提醒下一组。

## 环境

- Xcode 26.3 或兼容版本
- watchOS 10.0 及以上
- 支持 Core Motion 和 HealthKit 的 Apple Watch
- Apple Developer 签名团队（真机安装需要）

## 在真实 Apple Watch 上运行

1. 用 Xcode 打开 `Zujian.xcodeproj`。
2. 选择 `Zujian` Target，在 Signing & Capabilities 中选择你的 Apple Developer Team。
3. 确认 `Zujian` 与 `ZujianWidgets` 使用同一开发团队，并保留 HealthKit、Workout Processing 与 App Groups 能力。
4. 选择已配对且启用开发者模式的 Apple Watch。
5. 点击 Run。首次开始训练时，允许“训练”写入权限；心率读取权限可以拒绝，核心自动计时仍可使用。

训练结束后，App 会丢弃系统 Workout Builder 的完整训练，不在“健身”中生成一条训练记录。组数及每组平均/最高心率仅保存在本地。系统在 Workout Session 期间产生的底层健康样本仍可能保留在 HealthKit。

## 表盘与智能叠放

安装新版本后，在表盘的“复杂功能”选择器或智能叠放的添加界面中选择“组间”。圆形版用于表盘，矩形版用于智能叠放；休息时会直接显示实时倒计时，点按任一组件即可返回 App。

## App 自录制（仅 Debug 开发版）

这是 App 内部的演示记录功能，不是系统录屏。Apple Watch 只记录页面、操作、手势、滚动、计时、文本和训练状态的时间轴。「组间素材台」负责接收和管理 JSON；最终宣传视频由 Mac 端的 watchOS 模拟器直接运行项目里现有的 `ReadyView` / `WorkoutView` / `FinishedView` 后录制纯 App 显示。视频不含 Watch 外壳、Simulator 窗口、红色录制按钮或训练诊断控件。

1. 使用 `ZujianStudio` Scheme 将配套 iPhone App 安装到与 Watch 配对的 iPhone（它会同时嵌入 Watch App）。录制功能只会出现在 `Debug` 构建中。
2. 在 Watch 的 App 内打开“设置”→“休息时长”，开启“App 自录制”中的“显示录制按钮”。返回要演示的页面，点按右上角 44pt 的红色圆点开始；完成演示后点按红色方块停止。每次成功点击都会有轻触反馈。
3. 录制 JSON 会通过 WatchConnectivity 后台传到 iPhone 的「组间素材台」。详情页里的画面和“生成近似预览 MP4”只用于快速检查时间轴，不是原生 Watch UI。
4. 在详情页点“导出 JSON 给 Mac 原生渲染”，通过 AirDrop 或“文件”传到 Mac。在 Xcode 中启动一台与录制真表尺寸一致的 Watch 模拟器，然后在项目根目录运行：

   ```sh
   ./Tools/render-native-watch.sh "/path/to/Zujian-Recording.json"
   ```

   脚本会自动校验像素尺寸、编译 Debug Watch App、注入时间轴、等原生 UI 就绪后开始录制，并在 JSON 旁生成带 `-native-时间` 后缀的 H.264 MP4。可选参数是 `输出.mp4`、`30|60`、`h264|hevc` 和 Watch 模拟器 UDID。

正常的 Release/生产构建不显示录制入口，也不会启动状态采集、原生回放或传输。这条链路不读取真实 Apple Watch framebuffer，不能录制其他 App、表盘、系统权限弹窗、通知、Siri/听写或声音。最终导出使用 watchOS Simulator 的显示输出；它能保持同一套 SwiftUI View、系统字体、原生 Button 和导航布局，但仍不等于对真表进行像素级录屏，需用同版本 watchOS 与同尺寸表款减少系统差异。时间轴会保存滚动位置，但 watchOS 10 没有可靠恢复任意连续像素偏移的公开 API，因此长列表滚动只能尽量对齐到已记录内容，不能承诺逐像素一致。

## 自动检测范围

首版优先支持具有持续、重复手腕运动的力量训练。清晰动作通常在第二次结束附近确认，变化较大的动作继续观察到第三次。固定手腕、静态训练、极慢或极小幅度动作不保证自动识别。检测参数集中在 `SetDetectionConfiguration`，UI 不暴露灵敏度选项。

## 项目结构

- `WorkoutCoordinator`：集中管理训练状态切换
- `WorkoutSessionManager`：管理 HealthKit Workout Session
- `MotionManager`：读取 Core Motion 数据
- `SetDetectionEngine`：以运动为硬前提的训练语义检测
- `HeartRateTrendScorer`：仅用新的心率上升趋势提供小幅可选加分
- `RestTimerManager`：基于结束日期的准确倒计时
- `HapticManager`：触觉反馈
- `HistoryStore`：本地训练历史
- `ZujianWidgets`：表盘复杂功能与智能叠放组件

## 重要说明

模拟器不能提供真实手腕运动与触觉效果。自动识别阈值和震动感受必须在真实 Apple Watch 上验证。
