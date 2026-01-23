import SwiftUI
import UIKit

// MARK: - Image Processing Constants
enum ImageProcessingConstants {
    static let avatarSize: CGFloat = 512
    static let maxFileSize: Int = 500_000 // 500KB
    static let minDimension: CGFloat = 100
    static let maxDimension: CGFloat = 4096
    static let compressionQuality: CGFloat = 0.85
    static let minCompressionQuality: CGFloat = 0.1
}

extension UIImage {
    /// Validate image is safe for use as avatar
    /// - Throws: ImageValidationError if validation fails
    func validateForAvatar() throws {
        guard let cgImage = self.cgImage else {
            throw ImageValidationError.invalidFormat
        }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        // Check minimum dimensions
        guard width >= ImageProcessingConstants.minDimension,
              height >= ImageProcessingConstants.minDimension else {
            throw ImageValidationError.dimensionsTooSmall
        }
        
        // Check maximum dimensions
        guard width <= ImageProcessingConstants.maxDimension,
              height <= ImageProcessingConstants.maxDimension else {
            throw ImageValidationError.dimensionsTooLarge
        }
        
        // Check aspect ratio (reject extreme aspect ratios)
        let aspectRatio = width / height
        guard aspectRatio > 0.1, aspectRatio < 10.0 else {
            throw ImageValidationError.invalidAspectRatio
        }
        
        // Verify image can be converted to JPEG (security check)
        guard self.jpegData(compressionQuality: 1.0) != nil else {
            throw ImageValidationError.cannotEncodeJPEG
        }
    }
    
    /// Resize image to target size (512×512 for avatars)
    func resized(to targetSize: CGSize) -> UIImage? {
        let size = self.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let scaleFactor = min(widthRatio, heightRatio)

        let scaledSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )

        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: scaledSize))
        }
    }

    /// Compress to JPEG with quality target (max 500KB)
    /// - Returns: Compressed JPEG data, or nil if cannot meet maxBytes requirement
    func compressedJPEG(maxBytes: Int = ImageProcessingConstants.maxFileSize) -> Data? {
        var compression: CGFloat = ImageProcessingConstants.compressionQuality
        guard var data = self.jpegData(compressionQuality: compression) else {
            return nil
        }

        // Iteratively reduce quality if still too large
        while data.count > maxBytes && compression > ImageProcessingConstants.minCompressionQuality {
            compression -= 0.1
            guard let newData = self.jpegData(compressionQuality: compression) else {
                break
            }
            data = newData
        }

        // Return nil if still exceeds maxBytes after compression
        guard data.count <= maxBytes else {
            return nil
        }
        
        return data
    }

    /// Crop image to square aspect ratio (center crop)
    func croppedToSquare() -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        
        // Use pixel dimensions from CGImage, not point dimensions from UIImage
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let minDimension = min(pixelWidth, pixelHeight)
        
        let originX = (pixelWidth - minDimension) / 2
        let originY = (pixelHeight - minDimension) / 2
        
        guard let croppedCGImage = cgImage.cropping(to: CGRect(
            x: originX,
            y: originY,
            width: minDimension,
            height: minDimension
        )) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: self.scale, orientation: self.imageOrientation)
    }
}

// MARK: - Validation Errors
enum ImageValidationError: LocalizedError {
    case invalidFormat
    case dimensionsTooSmall
    case dimensionsTooLarge
    case invalidAspectRatio
    case cannotEncodeJPEG
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid image format"
        case .dimensionsTooSmall:
            return "Image is too small (minimum 100×100 pixels)"
        case .dimensionsTooLarge:
            return "Image is too large (maximum 4096×4096 pixels)"
        case .invalidAspectRatio:
            return "Invalid image aspect ratio"
        case .cannotEncodeJPEG:
            return "Cannot convert image to JPEG format"
        }
    }
}
