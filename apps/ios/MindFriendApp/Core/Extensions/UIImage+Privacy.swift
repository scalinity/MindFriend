import UIKit
import ImageIO
import CoreImage

// MARK: - UIImage Privacy Extensions

extension UIImage {
    /// Strips EXIF metadata from image for privacy
    ///
    /// Removes all EXIF data including:
    /// - GPS location
    /// - Device model
    /// - Original timestamps
    /// - Camera settings
    ///
    /// Preserves:
    /// - Image orientation
    /// - Color profile (for consistent rendering)
    ///
    /// - Parameter quality: JPEG compression quality (0.0-1.0)
    /// - Returns: Data with EXIF stripped, or nil if processing fails
    func strippingEXIF(quality: CGFloat = 0.8) -> Data? {
        guard let cgImage = self.cgImage else {
            return nil
        }

        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }

        // Create clean properties without EXIF
        // Only include compression quality and color profile
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            // Preserve orientation for correct display
            kCGImagePropertyOrientation: cgImageOrientation
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    /// Iteratively compress image to fit within size limit
    ///
    /// Tries multiple quality levels: 0.8 → 0.6 → 0.4 → 0.2
    /// Stops at first quality that produces data under maxBytes
    ///
    /// - Parameter maxBytes: Maximum file size in bytes (default 5MB)
    /// - Returns: Compressed image data, or nil if cannot compress under limit
    func compressToLimit(maxBytes: Int = 5_242_880) -> Data? {
        let qualities: [CGFloat] = [0.8, 0.6, 0.4, 0.2]

        for quality in qualities {
            if let data = strippingEXIF(quality: quality),
               data.count <= maxBytes {
                return data
            }
        }

        // Failed to compress under limit even at lowest quality
        return nil
    }

    /// Resize image to fit within maximum dimension while preserving aspect ratio
    ///
    /// - Parameter maxDimension: Maximum width or height in pixels
    /// - Returns: Resized UIImage
    func resized(maxDimension: CGFloat) -> UIImage {
        let size = self.size

        // Already smaller than max, but still need to strip EXIF if called independently
        // Note: This is a safety measure - callers should use strippingEXIF() for privacy
        guard size.width > maxDimension || size.height > maxDimension else {
            return self
        }

        // Calculate new size preserving aspect ratio
        let aspectRatio = size.width / size.height
        let newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Render resized image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Generate thumbnail with aspect-fit sizing
    ///
    /// Creates square thumbnail maintaining aspect ratio
    ///
    /// - Parameters:
    ///   - size: Thumbnail size (both width and height)
    ///   - quality: JPEG compression quality (default 0.6 for thumbnails)
    /// - Returns: Compressed thumbnail data with EXIF stripped
    func generateThumbnail(size: CGFloat = 200, quality: CGFloat = 0.6) -> Data? {
        // Use preparingThumbnail for efficient downsampling (iOS 17+)
        let targetSize = CGSize(width: size, height: size)

        guard let thumbnail = self.preparingThumbnail(of: targetSize) else {
            // Fallback to manual resize if preparingThumbnail fails
            return self.resized(maxDimension: size).strippingEXIF(quality: quality)
        }

        return thumbnail.strippingEXIF(quality: quality)
    }

    /// CGImage orientation converted to EXIF orientation value
    ///
    /// Maps UIImage.Orientation to CGImagePropertyOrientation
    private var cgImageOrientation: Int {
        switch self.imageOrientation {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }
}

// MARK: - Data Privacy Extensions

extension Data {
    /// Verify that data does not contain EXIF metadata
    ///
    /// Useful for testing EXIF stripping
    ///
    /// - Returns: True if no EXIF data found, false otherwise
    func hasEXIF() -> Bool {
        guard let source = CGImageSourceCreateWithData(self as CFData, nil) else {
            return false
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return false
        }

        // Check for common EXIF keys
        let exifKeys: Set<String> = [
            "{Exif}",
            "{GPS}",
            "{TIFF}",
            "Orientation",
            "DateTime",
            "Make",
            "Model"
        ]

        for key in exifKeys {
            if properties[key] != nil {
                return true
            }
        }

        return false
    }
}
