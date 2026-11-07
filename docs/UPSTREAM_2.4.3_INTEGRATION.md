# Kazumi 2.4.3 整合记录

日期：2026-11-07。状态：源码整合、依赖恢复、Flutter 与原生回归、iOS 构建完成，对应测试版 0013。

## 目的、输入、过程和输出

- 目的：接入上游 2.4.3 的功能与修复，保留本分支已经实现的 Liquid Glass、iPhone Duo 布局与播放交互。
- 输入：原始上游 2.4.2 `7cb58d7d800c8de46b9a36ec4ae97cd6a3f9602b`；本分支 `657b680bc7bc8644497624e65ee7f4b0587081fd`；上游 2.4.3 `7265274fac136a0cfe6ee32ea37f32f06ea57672`。
- 过程：检查上游 17 个提交、30 个变更路径；获取并校验 28 个普通文件的 Git blob SHA，以原始上游为共同基线进行三方整合；手工协调播放器菜单、应用初始化和版本号冲突；比较 Duo 相关实现。
- 输出：版本 `2.4.3+20404`，新增规则仓库配置及回归测试，保留本分支原生导航和播放器布局。测试版编号为 0013，标签 `v2.4.3-ios27.1-test.r0013`。

上一版 `2.4.2+20403` / `v2.4.2-ios27.1-test.r0012` 的 Release 和附件保留不变；本次附件来自新的 2.4.3（20404）构建。

## iPhone Duo 方案评估

上游发布说明列有“适配 iPhone Duo 内屏”，但对应提交 `69ba855ef4554b79a18d8becc83165c0fd000443` 的改动是把两个 iOS CI 任务的运行器从 `macos-latest` 改为 `xcode-27`。整个 2.4.2 → 2.4.3 差异没有增加 Duo 专用页面布局或原生场景桥接。工具链升级与本分支布局工作相互补充。

| 方面 | 上游 2.4.3 | 本分支现有方案 | 本次决定 |
| --- | --- | --- | --- |
| 编译工具链 | Flutter 3.47.9，iOS 使用 `xcode-27` 运行器标签 | 原 Flutter 3.47.7，SDK 检查要求 iOS 27.1+ | 升到 3.47.9，保留 SDK 检查 |
| 导航 | `OrientationBuilder` 按布局约束宽高选择标准 NavigationBar/Rail | 按实际可用窗口及遮挡切换原生玻璃底栏/侧栏 | 保留本分支 |
| 系统遮挡与分区 | 本次差异没有新增相应桥接 | `reservedRegions`、场景尺寸校验、相机与系统区域避让 | 保留本分支 |
| 内屏播放布局 | 现有宽大于高路径使用填满窗口的播放器布局 | 视频/选集双栏、折叠分区、显式全屏和控件局部避让 | 保留本分支 |
| 折叠与旋转状态 | 本次没有引入本分支同等的稳定组件布局机制 | 路由出口和播放器在布局切换时保持挂载 | 保留本分支 |
| 维护成本 | 标准组件较简单 | 更多原生桥接、布局及交互测试需要维护 | 接受维护成本，继续回归验证 |

结论：对于本项目的 Liquid Glass 与 Duo 交互目标，保留现有布局覆盖面更完整；吸收上游工具链与业务更新。此结论来自源码比较，并非新版本真机/模拟器 A/B 测试或性能测量。`OrientationBuilder` 判断的是布局约束形状，不能误解为直接读取设备物理旋转传感器。

## 已接入的更新

- 自定义规则仓库：地址校验与规范化、仓库切换、目录缓存隔离；切换仓库不会删除已安装规则，排队中的规则下载保持原始仓库来源。自定义仓库不显示仅适用于官方仓库的镜像选择。入口沿用本分支设置页面与底部安全区方案。
- DLNA：依赖升级为 `dlna_dart 0.1.1`，过滤 AVTransport 设备、改善发现订阅和播放顺序、传入实际播放集数标题。本分支播放菜单在暂停前检查离线视频与 Referer 限制，保留菜单生命周期与恢复播放逻辑。
- 下载弹幕：在排队下载完成并获得最终目录后缓存弹幕，移除等待目录的旧轮询。
- 收藏分类切换：减少整体重建和逐帧字体样式变化。
- 桌面退出：引入 `TrayService` / `AppExit`，销毁托盘后退出。
- Linux DEB：同步 `libva-wayland2` 依赖；同步相关结构文档和 PR 模板。

## 有意保留的分支差异

- 原生 `KazumiGlassPlugin`、`IosSceneEnvironment`、导航和路由可见性管理、播放器玻璃组件、双栏/全屏布局及 iOS 图标没有被上游替换。
- 播放控件继续采用 Flutter 模糊绘制；原生导航使用 UIKit 玻璃。先前播放器 UIKit 玻璃的层叠问题不重新引入。
- README 保留分支说明与发布列表入口；上游赞助名单不当作对本分支的赞助。
- iOS CI 运行器使用 `${{ vars.IOS_RUNNER || 'macos-latest' }}`，可配置专用标签；不能假定个人仓库存在上游的 `xcode-27` 运行器。继续保留最低 SDK 检查与测试版标签排除条件。
- 没有修改非 iOS Fastlane 子模块指针：上游 `fastlane/.flutter` 目标为 `c197ca5199e9ee5661e865596c9c07294dfab51c`，`fastlane/.libmpv-android-video-build` 目标为 `0443048272a511d7a990a2a3d5ca6bbaf55a869a`。本次采用源码三方整合，没有创建上游 merge commit。完整同步跨平台发布链时需另外处理这两个 gitlink。
- 自动更新服务仍保留原有上游更新源与整数版本比较；本次仅同步其桌面退出清理，不宣称已支持分支测试版自动更新。

## 本机工具链与检查结果

共享 Flutter 3.47.9（revision `c197ca5199`）/ Dart 3.13.7 位于 `~/Developer/flutter`。Xcode 27.2 / iOS SDK 27.2 已通过许可和 SDK 检查。CocoaPods 1.16.2、Ruby 3.4.8、CMake 4.4.4 与 Ninja 1.13.2 安装在忽略提交的 `.local-tools/`；`tool/flutterw` 可使用这些本地工具，并优先使用共享 Flutter SDK。

- 依赖恢复成功；`pubspec.lock` 仅包含预期的 Flutter 和 `dlna_dart` 版本变化。
- 静态分析通过：无 error / warning，17 条既有 info。
- 全套 Flutter 测试 **283 项通过**（本机 2026-11-07 实测）。
- 新增规则配置与集成测试覆盖：仓库地址规范化、仓库切换与请求竞态、保留已安装规则、无效/相同地址、排队下载来源，以及编辑对话框在 Duo 内外屏尺寸和两档文字缩放之间的状态与安全区。
- 构建入口已改用 `tool/flutterw`，避免依赖当前终端恰好已设置所有工具路径；自动生成 `BUILD_INFO.txt` 和 SHA-256，标明源码提交及工作区是否干净。
- 新增 Swift Package 解析锁文件，固定本次 iOS 构建使用的原生依赖。
- iOS 27.2 模拟器 Debug 构建成功，Duo 外屏和展开内屏首次启动均进入引导页面，未见布局溢出；本次视觉检查限于首次启动。
- iOS 27.2 Duo 模拟器原生 XCTest **4 项通过**，覆盖玻璃导航拖动、取消、旋转/隐藏取消和独立搜索。
- 无签名设备 Release 构建与 IPA 封装成功：Bundle ID `com.example.kazumi`，版本 `2.4.3` / `20404`，SDK `iphoneos27.2`，最低 iOS 15。

复验命令：

```sh
bash tool/flutterw pub get
bash tool/flutterw analyze --no-fatal-infos --fatal-warnings
bash tool/flutterw test
bash tool/flutterw build ios --simulator --debug
bash tool/build_ios27.sh
```

## 验证边界

自动化布局与状态测试不等于真实解码器、视频源、后台音频及 DLNA 接收器验证。实机 DLNA 投屏、排队下载完成后的实际弹幕文件、真实视频播放中折叠/旋转/画中画，以及 VoiceOver 完整回归仍需设备验证。应用内更新仍指向上游，分支测试版通过 GitHub Release 获取。

## 来源

- [上游 2.4.3 发布](https://github.com/Predidit/Kazumi/releases/tag/2.4.3)
- [2.4.2 到 2.4.3 对比](https://github.com/Predidit/Kazumi/compare/2.4.2...2.4.3)
- [上游 iOS 构建环境提交](https://github.com/Predidit/Kazumi/commit/69ba855ef4554b79a18d8becc83165c0fd000443)
- [Flutter 官方 SDK 归档](https://docs.flutter.dev/install/archive)
- [Apple：准备适配 iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
