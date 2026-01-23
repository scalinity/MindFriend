import SwiftUI
import UIKit

struct ImageCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let imageSize = calculateImageSize(in: geometry.size)

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                        .offset(offset)
                        .gesture(
                            // Use simultaneous gestures for smooth interaction
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Update immediately without animation for real-time feedback
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                                .simultaneously(with:
                                    MagnificationGesture(minimumScaleDelta: 0)
                                        .onChanged { value in
                                            // value is CGFloat, not a struct with .magnification
                                            scale = lastScale * value
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                        }
                                )
                        )
                        .animation(nil, value: offset) // Disable animation for immediate response
                        .animation(nil, value: scale)

                    // Crop overlay (circular)
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: min(geometry.size.width, geometry.size.height) - 40,
                               height: min(geometry.size.width, geometry.size.height) - 40)
                        .allowsHitTesting(false)

                    // Dimming overlay
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.black.opacity(0.5))
                        .mask(
                            GeometryReader { geo in
                                Rectangle()
                                    .overlay(
                                        Circle()
                                            .frame(width: min(geo.size.width, geo.size.height) - 40,
                                                   height: min(geo.size.width, geo.size.height) - 40)
                                            .blendMode(.destinationOut)
                                    )
                            }
                        )
                        .compositingGroup()
                        .allowsHitTesting(false)
                }
                .onAppear {
                    containerSize = geometry.size
                }
                .onChange(of: geometry.size) { _, newSize in
                    containerSize = newSize
                }
            }
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        cropImage()
                    }
                }
            }
        }
    }

    private func calculateImageSize(in containerSize: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    private func cropImage() {
        guard let cgImage = image.cgImage else {
            onCancel()
            return
        }
        
        // Calculate displayed image size in view coordinates
        let displayedImageSize = calculateImageSize(in: containerSize)
        
        // Calculate crop circle parameters in view coordinates
        let cropDiameter = min(containerSize.width, containerSize.height) - 40
        let cropRadius = cropDiameter / 2
        let viewCenterX = containerSize.width / 2
        let viewCenterY = containerSize.height / 2
        
        // Calculate the image's position in view coordinates (accounting for scale and offset)
        let scaledImageWidth = displayedImageSize.width * scale
        let scaledImageHeight = displayedImageSize.height * scale
        let imageOriginX = viewCenterX - (scaledImageWidth / 2) + offset.width
        let imageOriginY = viewCenterY - (scaledImageHeight / 2) + offset.height
        
        // Convert crop circle center to image coordinates (relative to image origin)
        let cropCenterInImageX = viewCenterX - imageOriginX
        let cropCenterInImageY = viewCenterY - imageOriginY
        
        // Convert from view coordinates to original image pixel coordinates
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let scaleFactorX = pixelWidth / scaledImageWidth
        let scaleFactorY = pixelHeight / scaledImageHeight
        
        let cropCenterInPixelsX = cropCenterInImageX * scaleFactorX
        let cropCenterInPixelsY = cropCenterInImageY * scaleFactorY
        let cropRadiusInPixels = cropRadius * min(scaleFactorX, scaleFactorY)
        
        // Create crop rect (square inscribed in circle)
        let cropRectX = cropCenterInPixelsX - cropRadiusInPixels
        let cropRectY = cropCenterInPixelsY - cropRadiusInPixels
        let cropRectSize = cropRadiusInPixels * 2
        
        let cropRect = CGRect(
            x: max(0, cropRectX),
            y: max(0, cropRectY),
            width: min(cropRectSize, pixelWidth - max(0, cropRectX)),
            height: min(cropRectSize, pixelHeight - max(0, cropRectY))
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            onCancel()
            return
        }
        
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        onCrop(croppedImage)
    }
}

#Preview {
    ImageCropView(
        image: UIImage(systemName: "photo")!,
        onCrop: { _ in },
        onCancel: {}
    )
}
