# CaptureDemo - iOS 相机采集 Demo

一款基于 AVFoundation 封装的 iOS 相机采集 Demo，支持视频预览与录制。

## 功能特性

- **实时相机预览** - 使用 AVCaptureVideoPreviewLayer 显示相机画面
- **视频录制** - 支持录制 1080P 30fps 的 MP4 视频
- **超广角镜头** - 默认使用 0.5x 超广角摄像头
- **手动参数调节** - 支持手动设置白平衡（4500K）、快门（1/250）、ISO（320）
- **录制时长显示** - 实时显示当前录制时长
- **视频列表** - 录制完成后可查看已保存的视频列表

## 技术栈

- **框架**: AVFoundation
- **语言**: Objective-C
- **项目管理**: XcodeGen
- **最低 iOS 版本**: iOS 14.0

## 项目结构

```
CaptureDemo/
├── App/                      # 应用入口
│   ├── AppDelegate.h/m
│   └── main.m
├── Services/                 # 服务层
│   └── CDCameraService.h/m   # 相机服务封装
├── ViewControllers/          # 视图控制器
│   ├── CDCameraViewController.h/m   # 相机预览/录制界面
│   └── CDVideoListViewController.h/m # 视频列表界面
├── Resources/                # 资源文件
│   └── Assets.xcassets/
├── CaptureDemo.xcodeproj/    # Xcode 项目文件
└── project.yml               # XcodeGen 配置文件
```

## 快速开始

### 环境要求

- Xcode 14.0 或更高版本
- XcodeGen (未安装请先执行 `brew install xcodegen`)
- iOS 14.0 及以上设备或模拟器（相机功能需真机）

### 构建步骤

1. 克隆项目
   ```bash
   git clone https://github.com/EEStorm/RoomCaptureDemo.git
   cd RoomCaptureDemo
   ```

2. 生成 Xcode 项目
   ```bash
   xcodegen generate
   ```

3. 用 Xcode 打开 `CaptureDemo.xcodeproj`，选择目标设备，点击运行

## 使用说明

1. 打开应用后，相机会自动启动并显示实时预览
2. 点击中间的**圆形录制按钮**开始录制视频
3. 录制过程中，顶部会显示录制时长
4. 再次点击录制按钮可停止录制
5. 点击右下角的**文件夹图标**可查看已录制的视频列表

## 录制参数

| 参数 | 值 |
|------|-----|
| 分辨率 | 1920 x 1080 (1080P) |
| 帧率 | 30 fps |
| 摄像头 | 超广角 (0.5x) |
| 白平衡 | 4500K |
| 快门 | 1/250 秒 |
| ISO | 320 |
| 格式 | MP4 |

## 视频存储

录制完成的视频保存在应用的 Documents/Videos 目录下，可通过文件管理App或 iTunes 文件共享访问。

## License

MIT License
