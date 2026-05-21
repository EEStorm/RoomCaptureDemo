# RoomCaptureDemo 项目 AI 指南 (Project Instructions)

本项目是一个复杂的 iOS 房间采集与 3D 重建应用，利用了 AVFoundation、ARKit 以及专门的采集流程（如 3D 高斯泼溅 - 3DGS）。

## 项目概览 (Project Overview)

- **核心目标**: 为 3D 重建（Room Tour、3DGS）采集高质量的视频和元数据。
- **核心技术**: Objective-C (为主), Swift (少量), ARKit, AVFoundation, Metal, SceneKit。
- **构建系统**: XcodeGen (需通过 `project.yml` 生成 `.xcodeproj`)。

## 架构与目录结构 (Architecture & Directory Structure)

### 1. 应用入口 (`/App`)
- `AppDelegate.h/m`: 应用生命周期管理。
- `main.m`: 标准入口。

### 2. 服务层 (`/Services`)
业务逻辑与硬件抽象。
- `CDCameraService.h/m`: 核心相机管理 (AVFoundation)。处理会话、输入输出及基础录制。
- `CD3DGSCameraService.h/m`: 3DGS 采集专用服务，管理 ARKit 集成与元数据采集。

### 3. 视图控制器 (`/ViewControllers`)
按功能/流程组织：
- `ThreeDGSCapture/`: 3D 高斯泼溅 (3DGS) 采集流程。
    - `CD3DGSCaptureViewController.m`: 核心采集逻辑 (**注意：此文件极大，约 7.8 万行**)。
    - `CD3DGSTrainingResultViewController.m`: 重建结果展示。
- `RoomShootFlow/`: 标准化房间拍摄流程。
    - `CDRoomVideoReviewViewController.m`: 房间视频回放。
    - `CDVideoConfirmViewController.m`: 确认与提交逻辑。
- `MeshCamera/`: 可能涉及 LiDAR 或基于网格的采集。
- `StereoCamera/`: 双目或立体采集逻辑。
- `MainTabs/`: 根导航与标签页管理。
- `Common/`: 通用 UI 组件与工具类。

### 4. 资源文件 (`/Resources`)
- `Assets.xcassets`: 图标、图片及颜色资源。

## 关键符号与逻辑 (Key Symbols & Logic)

- **相机管理**: 标准采集参考 `CDCameraService`，AR 增强采集参考 `CD3DGSCameraService`。
- **主采集界面**: `CD3DGSCaptureViewController` 是 3DGS 的核心入口。
- **数据持久化**: 视频保存在 `Documents/Videos` 目录下（在 `CDCameraService` 中配置）。

## AI 导航建议 (AI Navigation Tips)

- **超大文件处理**: `CD3DGSCaptureViewController.m` 非常巨大。分析时建议按类别搜索（如 `@implementation`、`@interface` 或特定的方法前缀 `cd_`）。
- **混编处理**: 项目以 Objective-C 为主。处理 `CD3DGSPitchCalibration.swift` 等 Swift 文件时，需查看 `CaptureDemo-Bridging-Header.h`。
- **构建规范**: **严禁直接修改 `.xcodeproj`**。如需添加文件或依赖，请更新 `project.yml` 后运行 `xcodegen generate`。

## 常用开发工作流 (Common Workflows)

1. **添加新服务**: 在 `/Services` 创建 `.h/m`，必要时更新 `project.yml` 并重新生成项目。
2. **修改采集参数**: 检查 `CDCameraService.m` 或 `CDCameraSettingsViewController.m`。
3. **更新 UI**: 大多数 UI 是代码编写的，位于 `ViewControllers` 相应的子目录中。

## 编码规范 (Coding Standards)

- **语言选择**: 优先使用 Objective-C 以保持一致性，除非必须使用现代 Swift API。
- **命名规范**: 类名使用 `CD` 前缀 (例如 `CDCameraService`)。
- **内存管理**: 使用 ARC (Automatic Reference Counting)。
