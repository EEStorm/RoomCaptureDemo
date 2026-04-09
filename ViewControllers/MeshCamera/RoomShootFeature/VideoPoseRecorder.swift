//
//  VideoPoseRecorder.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import ARKit
import AVFoundation
import Foundation
import UIKit

final class VideoPoseRecorder {
    struct ExportResult {
        let folderURL: URL
        let videoURL: URL
        let jsonURL: URL
        let zipURL: URL
    }

    enum RecorderError: Error {
        case writerNotReady
        case writerFailed(String)
        case missingFirstFrame
    }

    private let queue = DispatchQueue(label: "VideoPoseRecorder.queue")

    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var poses: [CameraPoseSample] = []
    private var firstFrameTime: CMTime?
    private var outputFolder: URL?
    private var outputVideoURL: URL?
    private var outputJSONURL: URL?
    private var recordingTransform: CGAffineTransform?

    func startNewRecording() {
        queue.sync {
            poses.removeAll(keepingCapacity: true)
            firstFrameTime = nil
            writer = nil
            writerInput = nil
            adaptor = nil
            recordingTransform = nil

            let folder = Self.makeNewOutputFolder()
            let videoURL = folder.appendingPathComponent("frames.mp4")
            let jsonURL = folder.appendingPathComponent("poses.json")
            outputFolder = folder
            outputVideoURL = videoURL
            outputJSONURL = jsonURL
        }
    }

    func append(frame: ARFrame) {
        queue.async {
            do {
                try self.ensureWriterConfiguredIfNeeded(firstFrame: frame)
                let didAppend = try self.appendVideoFrame(frame: frame)
                if didAppend {
                    self.appendPose(frame: frame)
                }
            } catch {
                print("Recorder append failed: \(error)")
            }
        }
    }

    func stop(completion: @escaping (Result<ExportResult, Error>) -> Void) {
        queue.async {
            guard let writer = self.writer,
                  let input = self.writerInput,
                  let folderURL = self.outputFolder,
                  let videoURL = self.outputVideoURL,
                  let jsonURL = self.outputJSONURL
            else {
                completion(.failure(RecorderError.writerNotReady))
                return
            }

            input.markAsFinished()
            writer.finishWriting {
                if writer.status == .failed {
                    completion(.failure(RecorderError.writerFailed(writer.error?.localizedDescription ?? "Unknown")))
                    return
                }

                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(self.poses)
                    try data.write(to: jsonURL, options: [.atomic])

                    // Package results into a zip for easy export/share.
                    let zipURL = folderURL.deletingLastPathComponent()
                        .appendingPathComponent(folderURL.lastPathComponent + ".zip")
                    let base = folderURL.deletingLastPathComponent()
                    let parent = folderURL.lastPathComponent
                    try SimpleZipWriter.createZip(
                        at: zipURL,
                        entries: [
                            .init(fileURL: videoURL, pathInZip: "\(parent)/\(videoURL.lastPathComponent)"),
                            .init(fileURL: jsonURL, pathInZip: "\(parent)/\(jsonURL.lastPathComponent)"),
                        ]
                    )

                    completion(.success(ExportResult(folderURL: folderURL, videoURL: videoURL, jsonURL: jsonURL, zipURL: zipURL)))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Private

    private func ensureWriterConfiguredIfNeeded(firstFrame frame: ARFrame) throws {
        if writer != nil { return }

        guard let folderURL = outputFolder, let videoURL = outputVideoURL else {
            throw RecorderError.writerNotReady
        }

        let pixelBuffer = frame.capturedImage
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Fix the movie orientation by applying a transform. The raw `capturedImage` buffer is in sensor
        // orientation (often looks like "home button right"). We lock a transform at the first frame based on
        // current interface orientation.
        if recordingTransform == nil {
            let orientation = Self.currentInterfaceOrientation()
            recordingTransform = Self.transformFor(interfaceOrientation: orientation, width: width, height: height)
            print("Recording interface orientation: \(orientation.rawValue), applying transform: \(String(describing: recordingTransform))")
        }

        let codec: AVVideoCodecType = .hevc
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 20_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ]

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)

        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)

        // Simulator/older devices may not support HEVC encode; fall back to H.264 if needed.
        let preferredInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        preferredInput.expectsMediaDataInRealTime = true

        let chosenInput: AVAssetWriterInput
        if writer.canAdd(preferredInput) {
            writer.add(preferredInput)
            chosenInput = preferredInput
        } else {
            let fallbackSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 16_000_000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                ],
            ]
            let fallbackInput = AVAssetWriterInput(mediaType: .video, outputSettings: fallbackSettings)
            fallbackInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(fallbackInput) else {
                throw RecorderError.writerFailed("Cannot add writer input (HEVC/H.264)")
            }
            writer.add(fallbackInput)
            chosenInput = fallbackInput
        }

        self.writer = writer
        self.writerInput = chosenInput
        if let t = recordingTransform {
            chosenInput.transform = t
        }

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        self.adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: chosenInput, sourcePixelBufferAttributes: attrs)
        self.firstFrameTime = nil

        print("Recording folder: \(folderURL.path)")
        print("Recording video: \(videoURL.path)")
    }

    private func appendVideoFrame(frame: ARFrame) throws -> Bool {
        guard let writer = writer, let input = writerInput, let adaptor = adaptor else {
            throw RecorderError.writerNotReady
        }

        let time = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        if firstFrameTime == nil {
            firstFrameTime = time
            writer.startWriting()
            writer.startSession(atSourceTime: time)
        }

        guard writer.status != .failed else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "Unknown")
        }

        guard input.isReadyForMoreMediaData else { return false }

        let buffer = frame.capturedImage
        return adaptor.append(buffer, withPresentationTime: time)
    }

    private func appendPose(frame: ARFrame) {
        let camera = frame.camera
        let sample = CameraPoseSample(
            timestamp: frame.timestamp,
            transformColumns: camera.transform.columnsArray,
            intrinsicsColumns: camera.intrinsics.columnsArray
        )
        poses.append(sample)
    }

    private static func makeNewOutputFolder() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let name = "RoomShoot_" + formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return docs.appendingPathComponent(name, isDirectory: true)
    }
}

private extension VideoPoseRecorder {
    static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        // Prefer the active foreground scene.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        return scenes.first?.interfaceOrientation ?? .portrait
    }

    static func transformFor(interfaceOrientation: UIInterfaceOrientation, width: Int, height: Int) -> CGAffineTransform {
        let w = CGFloat(width)
        let h = CGFloat(height)

        // Assume the raw buffer is in landscapeRight. Apply a transform so the exported movie displays
        // matching the UI orientation.
        switch interfaceOrientation {
        case .portrait:
            // 90° CCW + translate.
            return CGAffineTransform(rotationAngle: .pi / 2).translatedBy(x: 0, y: -w)
        case .portraitUpsideDown:
            // 90° CW + translate.
            return CGAffineTransform(rotationAngle: -.pi / 2).translatedBy(x: -h, y: 0)
        case .landscapeLeft:
            // 180° rotation.
            return CGAffineTransform(rotationAngle: .pi).translatedBy(x: -w, y: -h)
        case .landscapeRight:
            return .identity
        default:
            return .identity
        }
    }
}
