# 删除 3DGS 相机码率设置

## 目标

删除 3DGS 相机从设置界面到视频输出配置的整条码率设置链路，让系统使用编码器默认码率。

## 范围

- 从公共 3DGS 相机设置页删除码率行、展示文本、选择弹窗、默认值、保存与重置逻辑。
- 删除 `CDSettingsVideoBitrateKbpsKey` 公共常量。
- 从 `CD3DGSCameraService` 删除码率属性、设置读取，以及 `AVVideoAverageBitRateKey` 输出配置。
- 删除仅用于验证码率设置的测试文件及其 Xcode 工程引用。

## 非目标

- 不修改 3DGS 相机现有 HEVC 编码选择。
- 不修改分辨率、帧率、ISO、白平衡等设置。
- 不修改双目相机与 Mesh 相机的视频码率配置。
- 不清理用户设备上已经写入的旧 `UserDefaults` 键；该键不再读取，不会影响行为。

## 验证

- 全仓搜索确认 3DGS 码率键、属性、UI 文案和 `AVVideoAverageBitRateKey` 引用已从相关链路消失。
- 确认 Mesh 相机的固定码率配置仍存在。
- 构建 `CaptureDemo`，确认源码和工程文件引用有效。
