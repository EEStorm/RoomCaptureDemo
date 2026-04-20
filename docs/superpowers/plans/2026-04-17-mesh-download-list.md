# Mesh Download List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a mesh capture history list that stores each capture as a folder containing `frames.mp4`, `poses.json`, and `mesh.obj`, with video album save and file sharing actions.

**Architecture:** Keep the existing per-capture folder layout in Documents, remove zip packaging from the mesh pipeline, and introduce a small mesh-record browsing layer that scans capture folders into list/detail models. Wire the new list entry point into the mesh camera tab without affecting the parameter camera flow.

**Tech Stack:** Objective-C UIKit, SwiftUI host embedding, Swift model/storage helpers, Photos, AVKit, XcodeGen

---

### Task 1: Add test coverage for mesh record discovery

**Files:**
- Create: `CaptureDemoTests/MeshCamera/MeshCaptureRecordStoreTests.swift`
- Modify: `project.yml`
- Modify: `CaptureDemo.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

```swift
func test_loadRecords_discoversVideoJsonAndOBJInCaptureFolder() throws
func test_loadRecords_sortsNewestCaptureFirst() throws
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: FAIL because the test target and record store do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
struct MeshCaptureRecordStore {
    func loadRecords() throws -> [MeshCaptureRecord] { ... }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS for the new record discovery tests

- [ ] **Step 5: Commit**

```bash
git add project.yml CaptureDemo.xcodeproj/project.pbxproj CaptureDemoTests/MeshCamera/MeshCaptureRecordStoreTests.swift
git commit -m "test: cover mesh capture record discovery"
```

### Task 2: Remove zip packaging from mesh export flow

**Files:**
- Modify: `ViewControllers/MeshCamera/RoomShootFeature/VideoPoseRecorder.swift`
- Modify: `ViewControllers/MeshCamera/RoomShootFeature/CaptureReviewModels.swift`
- Modify: `ViewControllers/MeshCamera/RoomShootFeature/CaptureSessionModel.swift`

- [ ] **Step 1: Write the failing test**

```swift
func test_exportResult_containsFolderVideoAndJSONWithoutZIP() throws
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: FAIL because the export result still requires `zipURL`

- [ ] **Step 3: Write minimal implementation**

```swift
struct ExportResult {
    let folderURL: URL
    let videoURL: URL
    let jsonURL: URL
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS with zip references removed from the mesh flow

- [ ] **Step 5: Commit**

```bash
git add ViewControllers/MeshCamera/RoomShootFeature/VideoPoseRecorder.swift ViewControllers/MeshCamera/RoomShootFeature/CaptureReviewModels.swift ViewControllers/MeshCamera/RoomShootFeature/CaptureSessionModel.swift
git commit -m "refactor: remove mesh zip packaging"
```

### Task 3: Build mesh list and detail UI

**Files:**
- Create: `ViewControllers/MeshCamera/CDMeshCaptureListViewController.h`
- Create: `ViewControllers/MeshCamera/CDMeshCaptureListViewController.m`
- Create: `ViewControllers/MeshCamera/CDMeshCaptureDetailViewController.h`
- Create: `ViewControllers/MeshCamera/CDMeshCaptureDetailViewController.m`
- Create: `ViewControllers/MeshCamera/RoomShootFeature/MeshCaptureRecordStore.swift`
- Modify: `ViewControllers/MeshCamera/CDMeshCameraViewController.m`
- Modify: `CaptureDemo.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

```swift
func test_deleteRecord_removesCaptureFolder() throws
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: FAIL because the store cannot delete capture folders yet

- [ ] **Step 3: Write minimal implementation**

```objc
self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"列表" style:UIBarButtonItemStylePlain target:self action:@selector(showCaptureList)];
```

```swift
func deleteRecord(_ record: MeshCaptureRecord) throws { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS with list/delete behavior covered and the new mesh list UI building cleanly

- [ ] **Step 5: Commit**

```bash
git add ViewControllers/MeshCamera/CDMeshCameraViewController.m ViewControllers/MeshCamera/CDMeshCaptureListViewController.h ViewControllers/MeshCamera/CDMeshCaptureListViewController.m ViewControllers/MeshCamera/CDMeshCaptureDetailViewController.h ViewControllers/MeshCamera/CDMeshCaptureDetailViewController.m ViewControllers/MeshCamera/RoomShootFeature/MeshCaptureRecordStore.swift CaptureDemo.xcodeproj/project.pbxproj
git commit -m "feat: add mesh capture download list"
```

### Task 4: Add share and album-save actions

**Files:**
- Modify: `ViewControllers/MeshCamera/CDMeshCaptureDetailViewController.m`
- Modify: `CaptureDemo/Info.plist`
- Modify: `project.yml`

- [ ] **Step 1: Write the failing test**

```swift
func test_recordFiles_marksVideoAsAlbumSavableAndOtherFilesAsShareOnly() throws
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: FAIL because file action metadata does not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
enum MeshCaptureFileKind {
    case video
    case json
    case obj
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme CaptureDemoTests -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS with detail actions wired for album save and sharing

- [ ] **Step 5: Commit**

```bash
git add ViewControllers/MeshCamera/CDMeshCaptureDetailViewController.m project.yml CaptureDemo/Info.plist
git commit -m "feat: add mesh record share actions"
```
