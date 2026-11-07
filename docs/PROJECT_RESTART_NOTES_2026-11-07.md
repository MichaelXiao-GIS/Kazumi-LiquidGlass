# Kazumi Liquid Glass：迁移复工记录

核验日期：2026-11-07。依据：迁移目录中的源码、Git 历史、适配说明、视觉检查记录、构建产物，以及当日读取的 GitHub 分支与 Releases。

本次工作是恢复项目上下文和检查迁移完整性。未修改应用代码，未重新构建、运行 Flutter/XCTest、安装应用或发布版本。下文的历史测试结果均明确标注来源。

## 1. 当前接续点

| 项目 | 已核验状态 |
| --- | --- |
| 项目定位 | 基于 Predidit/Kazumi 的非官方 iOS 适配分支，保留 Flutter 与既有业务能力 |
| 上游基线 | Kazumi 2.4.2，`7cb58d7d800c8de46b9a36ec4ae97cd6a3f9602b` |
| 个人仓库 | https://github.com/MichaelXiao-GIS/Kazumi-LiquidGlass |
| 本地分支 | `codex/ios27-liquid-glass`，跟踪 `personal/main` |
| 远端主分支 | `main` |
| 本地 HEAD / 远端 main | `657b680bc7bc8644497624e65ee7f4b0587081fd`，2026-11-01 |
| 最新发布 | `Kazumi Liquid Glass测试版0012`，2026-11-01 发布 |
| 最新发布标签 | `v2.4.2-ios27.1-test.r0012` |
| 应用版本 | `2.4.2+20403`；IPA 内部版本同为 2.4.2（20403） |
| 改造规模 | 相对基线 17 个提交；101 个文件，6,282 行增加、1,289 行删除（Git 文本统计） |
| 工作区源码内容 | 本次新增本文档之前，忽略执行权限后与 HEAD 无差异；HEAD 与远端 main 相同 |

重要远端约定：`origin` 指向 **Predidit/Kazumi**；`personal` 指向 **MichaelXiao-GIS/Kazumi-LiquidGlass**。后续推送必须明确目标，不能把 `origin` 当作个人仓库。

最新 Release：
https://github.com/MichaelXiao-GIS/Kazumi-LiquidGlass/releases/tag/v2.4.2-ios27.1-test.r0012

## 2. Purpose：之前要解决什么

在 Kazumi 原有的规则解析、番剧目录、搜索、追番、历史、弹幕、播放、下载和同步基础上，建立更符合 iOS 使用习惯的界面，并适配 iPhone Duo 的内外屏、动态窗口和折叠分区。

目标包括：

- 用原生 Liquid Glass 悬浮导航、SF Symbols、系统字体、圆角卡片和分组设置改善 iOS 外观。
- 根据当前窗口和系统保留区域重新排布导航与内容，处理相机、状态区、不对称安全区和折线。
- 内外屏、旋转和全屏切换时保留当前路由、列表位置、播放器实例及播放状态。
- 改进真实播放交互：左右分栏、全屏、选集、菜单、单击显示/隐藏、双击暂停/继续。
- 继续维护深浅色、大字号、降低透明度、增强对比度与减少动态效果的处理。

实现继续由 Flutter 管理路由、内容和播放状态，Swift/UIKit 提供原生导航材质及场景信息。没有把整个应用重写成 SwiftUI/UIKit。

## 3. Input：输入与依赖

| 输入 | 在项目中的用途与位置 |
| --- | --- |
| 上游 Kazumi 2.4.2 | 全部业务底座；`lib/`、各平台工程、现有测试和资源 |
| Flutter 3.47.7 | `pubspec.yaml` 指定的 Flutter 版本；Dart 约束 `>=3.10.0 <4.0.0` |
| 锁定依赖 | `pubspec.lock`；MobX、flutter_modular、media-kit、Hive 等继续沿用。迁移时先恢复锁定版本 |
| iOS 开发工具链 | 历史使用 Xcode/iOS SDK 27.1；构建脚本要求 iOS SDK >= 27.1，部署目标 iOS 15 |
| 原生场景信息 | `UIView.reservedRegions(kind:)` 的活动 occlusion/division 区域，以及辅助功能偏好 |
| Apple 适配资料 | 见 `ios27-liquid-glass.md` 的依据；强调窗口尺寸、动态变化和避免按设备型号决定布局 |
| 用户选定的播放器设计 | `design-qa.md` 记录“悬浮玻璃 · 调整版”与后续修正；原会话生成图未在此目录找到 |
| 用户提供的应用图标 | `assets/images/logo/logo_ios.png`；不透明构建源 `logo_ios_opaque.png`，背景色 `#554943` |
| 真实服务与规则源 | 番剧元数据、弹幕、搜索/解析、视频、同步仍依赖原有第三方服务与用户规则 |
| 历史反馈与验证材料 | `docs/ios27-liquid-glass.md`、`design-qa.md`、`test/`、`ios/RunnerTests/`、`dist/`、`static/screenshot/` |

构建 SDK 与最低系统版本不能混为一谈。源码中原生 `UIGlassEffect` 的分支条件是 iOS 26+，更早系统使用 `UIBlurEffect.systemMaterial`；Duo 的 reserved-regions 桥接分支条件是 iOS 27.1+。

## 4. Process：实现方式与代码入口

### 4.1 架构关系

Flutter 的应用入口/路由与 MobX 状态继续驱动界面。`AppDelegate` 注册 `KazumiGlassPlugin`，后者通过 Platform View 提供 UIKit 玻璃，通过 EventChannel 向 Flutter 发布当前场景数据。Flutter 再依据窗口、遮挡与分区计算导航、列表和播放器布局。

| 关注点 | 首先阅读的文件 | 已实现的关键行为 |
| --- | --- | --- |
| 原生桥接 | `ios/Runner/KazumiGlassPlugin.swift`、`ios/Runner/AppDelegate.swift` | UIKit 材质、场景探针、系统偏好、拖动水滴、原生导航事件 |
| Flutter 原生控件封装 | `lib/bean/widget/ios_glass.dart` | Platform View 创建、配置更新、路由切换时立即隐藏原生层 |
| 场景数据 | `lib/bean/widget/ios_scene_environment.dart` | occlusions/divisions、减少动态效果/透明度、高对比度；丢弃尺寸不匹配的旧场景几何 |
| 自适应规则 | `lib/utils/adaptive_layout.dart` | 底栏/侧栏、海报列数、播放双栏、水平/竖直折叠分区、状态区中轴 |
| 主页面导航 | `lib/pages/menu/adaptive_navigation_scaffold.dart`、`menu.dart` | 相机/状态区下方侧栏、独立搜索与回顶；保持主路由组件位置 |
| 返回转场 | `lib/pages/menu/route_visibility.dart` | 返回动画和交互式侧滑结束后才恢复原生导航；取消侧滑不会提前显示 |
| 主题 | `lib/utils/theme.dart`、`lib/app_widget.dart` | iOS 系统字体、Cupertino 转场、卡片、按钮、分组设置；安装场景环境 |
| 滚动边缘 | `lib/bean/widget/ios_bottom_scrim.dart`、`lib/bean/settings/settings_scroll_edge.dart` | 内容延伸至底边、渐变模糊与触控穿透、列表末尾避让、辅助功能回退 |
| 首页数据刷新 | `lib/pages/popular/popular_page.dart` | 在 Observer 内读取列表快照，处理初次加载、追加分页与标签异步返回 |
| 详情播放按钮 | `lib/pages/info/info_page.dart` | 向下滚动后收起为 56×56，回顶展开；实际背景连续变宽，右边缘固定 |
| 播放页布局 | `lib/pages/video/video_page_layout.dart`、`video_viewport_geometry.dart` | 窄屏上下、宽屏左右、折叠分区、全屏；黑色背景全幅、控件局部避让 |
| 播放控件 | `lib/pages/player/player_glass_controls.dart`、`player_item_panel.dart` | 左上返回/标题、右上选集/更多、底部浮动控制条；按宽度/字号调整按钮 |
| 手势与菜单 | `lib/pages/player/player_panel_hold.dart` | 仅控件区域接收悬停/指针，空白画面留给手势；菜单动画和滚动条修正 |
| 全屏与状态区 | `lib/pages/video/video_fullscreen_controller.dart`、`video_system_bars.dart`、`lib/services/platform/display_mode_service.dart` | 全屏请求按序处理、主动请求横屏、退出释放方向、进入播放隐藏状态区并在离开时恢复 |
| 构建 | `tool/check_ios_sdk.sh`、`tool/build_ios27.sh` | 检查 SDK，构建无签名 Release，封装 IPA |

### 4.2 后续修改必须保留的设计决定

1. **主导航与播放器材质实现不同。** 主导航使用 UIKit 原生玻璃；播放器使用 Flutter `BackdropFilter`，保持视频、控件与弹出菜单处于同一合成体系。历史记录指出，播放器使用原生玻璃曾采样/覆盖后出现的 Flutter 菜单，因此不能仅为“全原生玻璃”直接改回。
2. **布局依赖当前窗口。** 使用 LayoutBuilder/MediaQuery 和当前 scene 数据，不能用固定设备尺寸代替。`IosSceneData.matches` 防止旋转中使用上一姿态的遮挡坐标。
3. **改变位置时保持组件生命周期。** 主路由出口和播放器子树的父子关系保持稳定，避免折叠后重置滚动、集数或播放状态。
4. **视频背景与控件避让分开。** 背景覆盖播放区，视频保持原比例，只有与相机实际相交的控件局部移动。不要恢复“给整个视频裁出一列空白”的做法。
5. **玻璃层可见性必须覆盖路由动画全过程。** Flutter 移除 Platform View 并不意味着 UIKit 当帧立即消失；保留 `hide` 通道与转场门控。
6. **手势命中区域必须保持局部。** 当前 `MouseRegion` 使用 `HitTestBehavior.deferToChild`，防止透明的全屏控件容器吞掉画面单击、双击或持有控件显示状态。
7. **导航拖动只在松手时提交一次。** 拖动中预览，取消/栏外释放/旋转/隐藏时回退；图标文字保持在玻璃水滴上层。
8. **系统区域中轴有历史经验修正。** 无相机的侧边状态区使用 ±6pt 修正，这是针对 27.1 模拟器测得的结果。换到当前机器的 27.2 SDK/运行时后需要重测，不能视为所有版本恒定规则。
9. **图标与已有业务能力继续沿用。** 已提交 iOS 各尺寸图标，不必每次重建；其他平台图标不应被 iOS 图标生成操作顺带替换。

### 4.3 版本推进过程

以下编号均为现行四位测试版编号；0001–0011 在 2026-10-30 统一了 Release 名称与标签格式。

| 测试版 | 发布日期 | 主要完成事项 |
| --- | --- | --- |
| 0001 | 10-23 | 原生玻璃导航、Duo 自适应、安全区、顶栏缺口及分隔线 |
| 0002 | 10-23 | 侧滑返回时原生侧栏穿透、取消返回时提前恢复的问题 |
| 0003 | 10-23 | 内容延伸至底边、渐变模糊、最后一排内容与悬浮控件避让 |
| 0004 | 10-23 | “开始观看”“保存并测试”等带文字按钮的胶囊背景 |
| 0005 | 10-23 | 左右播放分栏、整列黑色播放背景、全屏及侧栏收起白屏 |
| 0006 | 10-27 | 推荐页冷启动刷新、水滴拖动导航、清晰图文、深棕色新图标 |
| 0007 | 10-27 | 详情页播放按钮随滚动收起、回顶展开 |
| 0008 | 10-27 | 修复按钮只有占位动画、实际背景瞬间缩小的问题 |
| 0009 | 10-30 | 三组悬浮播放器控件、主动横屏、状态区、局部相机避让、菜单动画与黑色滚动条 |
| 0010 | 10-30 | 设置页底边模糊、推荐页回顶按钮移入侧栏 |
| 0011 | 10-30 | 导航、搜索、回顶与相机/状态区的中轴对齐 |
| 0012 | 11-01 | 恢复反复单击显示/隐藏和双击暂停/继续，底栏改为 32pt 连续圆角；构建号升至 20403 |

## 5. Output：已经留下什么

### 源码与说明

- 可追溯至 2.4.2 基线的完整 Git 仓库；当前源码与个人仓库 main 对齐。
- `README.md`：项目定位、下载入口、当前功能与截图。
- `docs/ios27-liquid-glass.md`：实现、构建、发布命名和历史验证记录。
- `design-qa.md`：0009–0011 的视觉修正经过、检查边界和旧机器临时资料路径。
- `static/screenshot/`：首页内外屏、详情、设置、播放分栏与全屏截图。
- `dist/`：最新 IPA、构建信息、校验文件，以及多版预览图/录像。此目录中的预览不全属于 0012。

README 播放器截图明确来自 0009，首页图来自 0011。它们可用于理解既定设计，但不能当作 0012 连续圆角或手势表现的最新运行证明。

### 当前 IPA 完整性

| 字段 | 本次实测 |
| --- | --- |
| 文件 | `dist/Kazumi_iOS27_unsigned.ipa` |
| 大小 | 29,573,870 bytes |
| SHA-256 | `bf026ab9fc6be3139abf8bfb0d3d37d8c49b356526905de0948d47f567b2721d` |
| 与远端附件的关系 | 大小和 SHA-256 与 0012 Release 附件一致 |
| Bundle ID | `com.example.kazumi` |
| 版本/构建号 | `2.4.2` / `20403` |
| SDK / 最低系统 | IPA 内 Info.plist：`iphoneos27.1` / `15.0` |
| 安装方式 | 发布记录为 unsigned；需原有 Apple 签名或侧载工具重新签名 |

安装包、`BUILD_INFO.txt`、SHA 文件及远端发布信息形成一致的版本记录。覆盖升级时应沿用原签名身份与 Bundle ID，以延续原应用数据。

## 6. 验证边界

### 旧机器的记录

- 0012：全套 Flutter 测试 **266 项通过**；静态分析无 error/warning，保留 17 条既有 info。
- 0006：原生导航 XCTest **4 项通过**；测试源码仍在 `ios/RunnerTests/RunnerTests.swift`。
- 多次完成模拟器 Debug 与无签名设备目标 Release 构建。
- Duo/iOS 27.1 模拟器中做过真实联网播放、内外屏、折叠、旋转、全屏、菜单、回顶、按钮动画和手势检查。
- 当前目录共有 35 个 Dart 测试文件；相对上游新增 12 个，重点覆盖布局、生命周期、导航转场、底部像素、按钮中间帧、手势和系统方向等。

这些是文档、代码和产物支持的**历史记录**；本次没有在新机器重跑，不应写成“新机器 266 项测试通过”。

### 仍待验证的范围

- Duo 物理设备、真实系统旋转锁、多视频源长期播放。
- 播放中折叠的音频/弹幕连续性、画中画、后台播放及返回路径。
- 普通比例 iPhone 的完整联网播放验证。
- VoiceOver 与其他辅助功能在真实设备上的完整回归。
- 新机器 Xcode/SDK 27.2 与旧 27.1 视觉和原生 API 行为的差异。

布局测试使用播放器替身验证挂载关系，不能据此推断真实解码器、网络源或后台音频全部正常。

## 7. 本次发现的迁移问题

| 问题 | 本次证据 | 复工处理 |
| --- | --- | --- |
| 大量权限差异 | 679 个已跟踪文件从 Git 的 100644 变为可执行；忽略执行位后无源码差异 | 按 Git 记录逐项恢复原执行位，保留原本可执行的脚本；不要把权限噪声一起提交 |
| Xcode 尚未初始化完成 | 调用系统 `git` 被 Xcode 许可检查拦下 | 在 Xcode 完成许可与首次组件设置后检查工具链；本次未代为接受许可 |
| 新旧 SDK 不同 | 安装的 Xcode 版本元数据为 27.2，目录有 iPhoneOS27.2.sdk；旧包是 27.1 | 满足脚本的版本下限，但还需实际编译/运行验证 |
| 构建命令不在 PATH | 未发现 `flutter`、`dart`、`pod`、`cmake`、`ninja` | 安装或定位后设置路径，先匹配项目 Flutter 3.47.7 |
| 缓存仍指向旧临时目录 | package_config 指向 `/private/tmp/kazumi-flutter-3.47.7`、`/private/tmp/kazumi-pub-cache`，均不存在 | 重新获取依赖并生成工程配置，不直接沿用复制来的缓存 |
| iOS 插件链接失效 | `ios/` 内发现 34 个符号链接，34 个均断开，指向旧临时 pub cache | 在依赖恢复后重新生成插件链接并执行 pod install |
| Generated.xcconfig 过期 | 仍包含旧用户名 `michaelhsiao` 的项目路径和构建号 20402 | 由 Flutter 重新生成；当前版本以 pubspec 和已核验 IPA 的 20403 为准 |
| 部分视觉资料未迁移 | `/private/tmp/kazumi-test9-qa`、`test10-qa`、`test11-qa` 不存在 | 使用已有仓库截图/录像作为历史参考；新回归重新保存证据 |
| 本地缺少最新发布标签 | `git tag --points-at HEAD` 无输出；GitHub 上 r0012 Release 存在 | 恢复 Git 环境后从 `personal` 获取标签，避免凭本地标签列表重复创建 |

本次仅对权限和缓存做检查，没有修改它们。为读取历史使用了 Xcode 内的 Git 二进制；没有调用编译器绕过许可，也没有运行构建。

## 8. 下次更新值得优先处理的代码事项

### 应用内更新还没有接入本分支

源码中的 `ApiEndpoints.sourceUrl`、`latestApp` 仍指向上游，`AutoUpdater._latestRelease()` 实际读取 `ApiEndpoints.latestAppMirror`，即 `api.kazumi.fyi/kazumi/v1/app/latest`。因此仓库首页已经换成个人 Release，并不等于应用内更新来源也已切换。

此外，`lib/utils/version.dart` 的 `needUpdate()` 将点分隔片段直接 `int.parse`，不能直接比较本分支的 `v2.4.2-ios27.1-test.r0012`。仅更换 URL 无法完成适配；同一基础版本的 r0012/r0013 也需要独立的修订比较规则。

下一次若完善更新功能，应明确：个人仓库预发布的发现方式、修订编号比较、更新提示中的仓库归属、iOS 跳转下载而非直接安装的行为，以及上游镜像与其他平台的保留策略。该事项来自本次源码审阅，尚未修改或做联网运行测试。

### 发布元数据目前不是构建脚本自动生成

`tool/build_ios27.sh` 负责检查 SDK、构建并封装 IPA，**不会自动更新** `dist/BUILD_INFO.txt` 或 `.sha256` 文件，也不会上传。下次构建后必须重新生成校验和与构建信息，避免新 IPA 配上旧版本记录。

### 新 SDK 下复查系统区域与布局

重点复查 ±6pt 侧栏中轴经验修正、reserved-regions 的活动区域、原生导航转场、播放器菜单合成和单/双击命中。这些已有明确修复历史，修改时应复用相应回归测试。

以上是接续建议，不代表用户已决定下一版新增功能或同意升级上游基线。

## 9. 建议的复工顺序

1. 完成 Xcode 首次设置，确认选用的 SDK/模拟器；恢复 Flutter 3.47.7、CocoaPods、CMake >=3.22、Ninja。
2. 恢复原 Git 文件执行位，核对内容差异与 `personal/main`，获取个人仓库标签；保留原基线。
3. 保留已核验的 `dist/` 发布产物，再清理/重新生成失效的本地构建缓存、插件链接与生成配置；恢复锁定依赖，不先做大范围依赖升级。
4. 先复现 0012：静态分析、全套 Flutter 测试、原生 XCTest、模拟器 Debug、无签名设备 Release。
5. 在 Duo 内外屏、半折叠、两种横屏及普通 iPhone 上检查导航与真实播放；补充当前 SDK 的视觉记录。
6. 在上述基线稳定后实施选定的下一版任务；新增逻辑对应已有回归项或必要的新测试。
7. 发布前核对版本、图标、Bundle ID、签名延续、IPA 内容、SHA、BUILD_INFO、说明与截图；只有实际完成的验证才写入发布记录。

环境恢复后可用的基础命令（本次未执行）：

```sh
flutter --version
flutter doctor -v
bash tool/check_ios_sdk.sh
flutter pub get
(cd ios && pod install)
flutter analyze --no-fatal-infos --fatal-warnings
flutter test
flutter build ios --simulator --debug
bash tool/build_ios27.sh
```

原生 XCTest 通过 Xcode 的 `ios/Runner.xcworkspace` / Runner 测试配置，选择实际可用的 Duo 模拟器运行；不沿用旧机器的模拟器 ID。

## 10. 下一版命名约定

- 若继续当前 2.4.2 适配线，下一个候选为 **Kazumi Liquid Glass测试版0013**。
- 对应标签 `v2.4.2-ios27.1-test.r0013`，不要恢复为 `test.13`。
- 当前应用构建号为 20403；下一次产生新的可分发包应递增，并以实际构建参数/IPA 为准。
- README 下载链接保持指向个人仓库 Releases 列表。
- `.github/workflows/release.yaml` 排除了 `!*-ios27.1-test.*`，该系列目前采用已验证的本地 IPA 发布，不会因这类标签触发全平台重建。
- 若因新 SDK 决定更改标签中的 `ios27.1`，需要同时审查上述排除模式；不能只改标签而意外触发其他平台发布流程。
- 历史记录说明旧 `test.1`–`test.11` 标签用于追溯；既有 Release/附件不应为统一命名再次打包或覆盖。

## 11. 证据入口

- 本地：`README.md`、`docs/ios27-liquid-glass.md`、`design-qa.md`、`dist/BUILD_INFO.txt`、`dist/Kazumi_iOS27_unsigned.ipa.sha256`。
- 当前提交：https://github.com/MichaelXiao-GIS/Kazumi-LiquidGlass/commit/657b680bc7bc8644497624e65ee7f4b0587081fd
- 发布列表：https://github.com/MichaelXiao-GIS/Kazumi-LiquidGlass/releases
- 上游基线：https://github.com/Predidit/Kazumi/commit/7cb58d7d800c8de46b9a36ec4ae97cd6a3f9602b
- Apple Duo 适配指南（本次已读取）：https://developer.apple.com/iphone-duo/prepare/
- Apple UIGlassEffect API（仓库引用）：https://developer.apple.com/documentation/uikit/uiglasseffect

这份记录可作为下一次工作起点。新功能修改、测试结果和发布状态发生变化后，应据新的实际证据更新对应条目。
