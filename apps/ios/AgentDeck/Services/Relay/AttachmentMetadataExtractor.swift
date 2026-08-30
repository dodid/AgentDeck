import Foundation
import ImageIO
import AVFoundation
import CoreGraphics
import UniformTypeIdentifiers

struct AttachmentMediaMetadata: Sendable {
    let width: Int?
    let height: Int?
    let durationMS: Int?
}

struct AttachmentPreviewResult: Sendable {
    let jpegData: Data
    let width: Int
    let height: Int
}

enum AttachmentMetadataExtractor {

    static func extractMetadata(fileURL: URL, kind: AttachmentKind) async -> AttachmentMediaMetadata {
        switch kind {
        case .image:
            return extractImageMetadata(fileURL: fileURL)
        case .video:
            return await extractVideoMetadata(fileURL: fileURL)
        case .audio:
            return await extractAudioMetadata(fileURL: fileURL)
        case .file, .unknown:
            return AttachmentMediaMetadata(width: nil, height: nil, durationMS: nil)
        }
    }

    static func generatePreview(fileURL: URL, kind: AttachmentKind, maxDimension: CGFloat = 512) async -> AttachmentPreviewResult? {
        switch kind {
        case .image:
            return generateImagePreview(fileURL: fileURL, maxDimension: maxDimension)
        case .video:
            return await generateVideoPosterPreview(fileURL: fileURL, maxDimension: maxDimension)
        case .audio, .file, .unknown:
            return nil
        }
    }

    // MARK: - Image

    private static func extractImageMetadata(fileURL: URL) -> AttachmentMediaMetadata {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return AttachmentMediaMetadata(width: nil, height: nil, durationMS: nil)
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return AttachmentMediaMetadata(width: nil, height: nil, durationMS: nil)
        }
        let width = props[kCGImagePropertyPixelWidth] as? Int
        let height = props[kCGImagePropertyPixelHeight] as? Int
        return AttachmentMediaMetadata(width: width, height: height, durationMS: nil)
    }

    private static func generateImagePreview(fileURL: URL, maxDimension: CGFloat) -> AttachmentPreviewResult? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return compressToJPEG(cgImage: thumb)
    }

    // MARK: - Video

    private static func extractVideoMetadata(fileURL: URL) async -> AttachmentMediaMetadata {
        let asset = AVURLAsset(url: fileURL)
        let duration = try? await asset.load(.duration)
        let durationMS: Int?
        if let duration {
            let seconds = CMTimeGetSeconds(duration)
            durationMS = seconds.isFinite ? Int(seconds * 1000) : nil
        } else {
            durationMS = nil
        }
        var width: Int?
        var height: Int?
        let tracks = try? await asset.loadTracks(withMediaType: .video)
        if let track = tracks?.first,
           let naturalSize = try? await track.load(.naturalSize),
           let preferredTransform = try? await track.load(.preferredTransform) {
            let size = naturalSize.applying(preferredTransform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }
        let positiveDurationMS = durationMS.flatMap { $0 > 0 ? $0 : nil }
        return AttachmentMediaMetadata(width: width, height: height, durationMS: positiveDurationMS)
    }

    private static func generateVideoPosterPreview(fileURL: URL, maxDimension: CGFloat) async -> AttachmentPreviewResult? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        let duration = try? await asset.load(.duration)
        let seconds = duration.map(CMTimeGetSeconds) ?? 0
        let previewSeconds = min(1.0, max(seconds, 0) * 0.1)
        let time = CMTime(seconds: previewSeconds, preferredTimescale: 600)
        guard let cgImage = await generateCGImage(generator: generator, at: time) else { return nil }
        return compressToJPEG(cgImage: cgImage)
    }

    // MARK: - Audio

    private static func extractAudioMetadata(fileURL: URL) async -> AttachmentMediaMetadata {
        let asset = AVURLAsset(url: fileURL)
        let duration = try? await asset.load(.duration)
        let durationMS: Int?
        if let duration {
            let seconds = CMTimeGetSeconds(duration)
            durationMS = seconds.isFinite ? Int(seconds * 1000) : nil
        } else {
            durationMS = nil
        }
        let positiveDurationMS = durationMS.flatMap { $0 > 0 ? $0 : nil }
        return AttachmentMediaMetadata(width: nil, height: nil, durationMS: positiveDurationMS)
    }

    // MARK: - Helpers

    private static func generateCGImage(generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result == .succeeded ? image : nil)
            }
        }
    }

    private static func compressToJPEG(cgImage: CGImage, quality: CGFloat = 0.7) -> AttachmentPreviewResult? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return AttachmentPreviewResult(
            jpegData: data as Data,
            width: cgImage.width,
            height: cgImage.height
        )
    }
}
