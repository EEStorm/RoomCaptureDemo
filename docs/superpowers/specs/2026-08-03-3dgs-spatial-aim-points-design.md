# 3DGS SceneKit 空间引导点设计

## 目标

在 `CD3DGSCaptureViewController` 的相机预览上叠加一个不依赖 ARKit 的 SceneKit 引导层。引导层在启动方向生成 8 个水平空间点，一次只显示一个；用户将当前点保持在屏幕中心约 800ms 后，当前点消失并显示下一个点。该功能仅验证空间方向固定效果，不拍照、不控制现有视频录制。

## 范围

- 使用 `AVFoundation` 提供的现有相机预览。
- 使用 `CoreMotion` 获取设备旋转姿态，仅提供 3DoF 方向跟踪。
- 使用 `SceneKit` 绘制透明覆盖层。
- 8 个点均匀分布在半径 2.5 的水平圆周上，相邻点间隔 45°。
- 首点固定为场景 `(0, 0, -2.5)`，并在首次有效姿态到达时将当前水平航向校准为正前方。
- 不使用 `ARSession`、AR Anchor、世界追踪或位置追踪。
- 不改变现有录制、引导视频、步骤切换和拍摄文件逻辑。

## 架构

### CDMotionTrackingService

新增 Objective-C 服务，作为页面内 CoreMotion 的唯一入口。

职责：

- 持有唯一的 `CMMotionManager` 和串行运动队列。
- 使用 `CMAttitudeReferenceFrameXArbitraryZVertical` 启动 `deviceMotion`。
- 以 60Hz 为目标更新频率。
- 保存最新 `CMDeviceMotion`，并向订阅者发送姿态样本。
- 使用引用计数式 `start`/`stop` 生命周期，避免覆盖层和 IMU 指引互相停止传感器。
- 页面离开后停止更新并清理订阅。

该服务不解释业务姿态：坐标转换、首帧航向校准属于空间引导层；俯仰、翻滚、角速度和移动速度仍由 3DGS 页面计算。

### CDSpatialAimOverlayView

新增透明、不可交互的 `UIView` 组件，内部持有 `SCNView`、`SCNScene`、相机节点和点位队列。

职责：

- 创建 8 个 `SCNPlane` 圆形视觉节点。
- 维护 `pending -> visible -> completed` 的顺序状态。
- 将 CoreMotion 四元数转换为 SceneKit 相机方向。
- 首次收到有效姿态时只校准水平航向，使首点位于屏幕正前方，同时保留重力定义的俯仰和翻滚。
- 每个 SceneKit 渲染帧读取最新姿态并更新相机。
- 将当前点投影到屏幕，判断其中心是否进入准星半径。
- 连续命中 800ms 后播放缩放/淡出动画，然后显示下一点。
- 第 8 点完成后停止点位推进，但保持覆盖层可用。
- 暴露 `reset`，用于重新进入页面或后续手动重试。

覆盖层不持有 `CMMotionManager`，避免创建第二套传感器更新链路。

### CD3DGSCaptureViewController 集成

页面职责：

- 在相机预览容器之上、现有业务 UI 之下添加 `CDSpatialAimOverlayView`。
- 在 `viewWillAppear` 启动 `CDMotionTrackingService` 并注册订阅。
- 将每个 `CMDeviceMotion` 同时传给空间引导层和现有 IMU 计算逻辑。
- 现有 IMU UI 仍只在准备录制或录制期间显示；停止 IMU UI 时不再停止共享传感器服务。
- 在 `viewWillDisappear` 取消订阅并停止服务。

## 数据流

```text
CMMotionManager (60Hz)
        |
        v
CDMotionTrackingService
        |------------------------------|
        v                              v
CDSpatialAimOverlayView       CD3DGSCaptureViewController
SceneKit camera               pitch/roll/speed warnings
        |
        v
center hold 800ms -> next point
```

## 点位与视觉

点位坐标采用：

```text
x = radius * sin(yaw)
y = 0
z = -radius * cos(yaw)
```

其中 `radius = 2.5`，`yaw = index * 45°`。每个平面朝向圆心，使用高对比度的程序化材质，不新增图片资源。SceneKit View 透明且 `userInteractionEnabled = NO`，因此不会遮挡返回、设置、录制和步骤按钮。

首版使用当前相机设备的 `activeFormat.videoFieldOfView` 配置 SceneKit 水平视场；若真机发现边缘滑动，再在后续迭代使用视频帧内参构建自定义投影矩阵。

## 对准判定

每帧将当前点的世界中心通过 `projectPoint:` 投影到 SceneKit View：

- 点必须位于相机前方。
- 投影点到屏幕中心的距离必须小于固定像素半径。
- 连续满足 800ms 才完成当前点。
- 任一帧不满足即清空本次停留计时。
- 完成动画期间禁止重复触发。

首版不依赖 SceneKit 三角形 hit-test，避免平面尺寸、透明区域和双面材质影响触发结果。

## 生命周期与异常处理

- CoreMotion 不可用：覆盖层保持隐藏，现有相机和录制功能继续工作。
- SceneKit 初始化失败：不阻断相机页面。
- 应用进入后台或页面消失：停止渲染和运动更新。
- 页面重新出现：重启运动更新；点位队列默认从第一个点重新开始。
- 引导视频全屏覆盖时，空间点留在下层，不参与对准计时，避免用户看不到点时队列自动推进。

## 测试与验证

### 单元测试

- 8 个坐标均位于半径 2.5 的水平圆周。
- 首点为 `(0, 0, -2.5)`。
- 点间航向差为 45°。
- 命中不足 800ms 不推进。
- 命中中断后重新计时。
- 第 8 点完成后不会越界或重复显示。

### 构建验证

- 通过 XcodeGen 生成工程，不直接编辑 `.xcodeproj`。
- 运行 iOS Simulator 构建，验证 Objective-C、SceneKit 和 CoreMotion 接口编译。
- CoreMotion 空间效果必须使用真机验证。

### 真机验收

- 进入 3DGS 页面后首点出现在启动方向。
- 原地左右转动时点保持在同一物理方向，无明显跳动。
- 对准 800ms 后只切换点，不拍照、不改变录像状态。
- 转完 8 点约为完整一圈。
- 页面原有按钮和 IMU 指引正常工作。
- 快速旋转后回到起始方向，记录首尾闭合误差和边缘滑动情况。

## 非目标与已知限制

- 不跟踪设备平移，用户移动位置后点不会锚定在真实墙面。
- `XArbitraryZVertical` 的水平航向可能随时间漂移。
- 首版不做相机帧与姿态时间戳插值或预测。
- 首版不做镜头畸变校正和逐帧防抖裁切补偿。
- 不自动拍照、不自动开始录制、不写入点位完成记录。
