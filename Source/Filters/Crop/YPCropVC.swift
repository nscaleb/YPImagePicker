//
//  YPCropVC.swift
//  YPImagePicker
//
//  Created by Sacha DSO on 12/02/2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation

public enum YPCropType {
    case none
    case rectangle(ratio: Double)
}

class YPCropVC: UIViewController {
    
    public var didFinishCropping: ((UIImage, CGRect?) -> Void)?
    public var didFinishVideoCropping: ((YPMediaVideo, CGRect) -> Void)?
    override var prefersStatusBarHidden: Bool { return YPConfig.hidesStatusBar }
    var activityIndicator: UIActivityIndicatorView?
    private let originalImage: UIImage
    private let pinchGR = UIPinchGestureRecognizer()
    private let panGR = UIPanGestureRecognizer()
    var video: YPMediaVideo?
    var v: YPCropView
    var ratio = 1.0
    var maxZoom: CGFloat = 3.0
    override func loadView() { view = v }
    
    required init(image: UIImage, ratio: Double) {
        v = YPCropView(image: image, ratio: ratio)
        originalImage = image
        super.init(nibName: nil, bundle: nil)
        self.title = YPConfig.wordings.crop
    }
    
    init(video: YPMediaVideo, ratio: Double) {
        originalImage = video.thumbnail
        self.video = video
        self.ratio = ratio
        self.maxZoom = 1.0
        self.v = YPCropView.init(video: video, ratio: ratio)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
        setupGestureRecognizers()
    }
    
    func setupToolbar() {
        let cancelButton = UIBarButtonItem(title: YPConfig.wordings.cancel,
                                           style: .plain,
                                           target: self,
                                           action: #selector(cancel))
        cancelButton.tintColor = .ypLabel
        cancelButton.setFont(font: YPConfig.fonts.leftBarButtonFont, forState: .normal)
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let saveButton = UIBarButtonItem(title: YPConfig.wordings.save,
                                           style: .plain,
                                           target: self,
                                           action: #selector(done))
        saveButton.setFont(font: YPConfig.fonts.rightBarButtonFont, forState: .normal)
        saveButton.tintColor = .ypLabel
        let rotateButton = UIBarButtonItem(title: "Rotate",
                                           style: .plain,
                                           target: self,
                                           action: #selector(rotate))
        rotateButton.setFont(font: YPConfig.fonts.rightBarButtonFont, forState: .normal)
        rotateButton.tintColor = .ypLabel
        
        v.toolbar.items = [cancelButton, flexibleSpace, rotateButton, flexibleSpace,  saveButton]
    }
    
    @objc func rotate() {
        if self.ratio > 1.0 {
            self.ratio = 0.6666//0.7142857
            
        } else {
            self.ratio = 1.5//1.4
        }
        if self.video != nil {
            self.v = YPCropView.init(video: self.video!, ratio: self.ratio)
        } else {
            self.v = YPCropView.init(image: self.originalImage, ratio: self.ratio)
        }
        
        self.view = v
        self.view.setNeedsLayout()
        setupToolbar()
        setupGestureRecognizers()
        
    }
    
    func setupGestureRecognizers() {
        // Pinch Gesture
        pinchGR.addTarget(self, action: #selector(pinch(_:)))
        pinchGR.delegate = self
        v.imageView.addGestureRecognizer(pinchGR)
        
        // Pan Gesture
        panGR.addTarget(self, action: #selector(pan(_:)))
        panGR.delegate = self
        v.imageView.addGestureRecognizer(panGR)
    }
    
    @objc
    func cancel() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc
    func done() {
        guard let image = v.imageView.image else {
            return
        }
        self.activityIndicator = UIActivityIndicatorView.init(style: .whiteLarge)
        self.activityIndicator?.frame = CGRect.init(x: (self.view.frame.width / 2.0) - 25.0, y: (self.view.frame.height / 2.0) - 25.0, width: 50.0, height: 50.0)
        self.view.addSubview(self.activityIndicator!)
        self.activityIndicator?.startAnimating()
        let xCrop = v.cropArea.frame.minX - v.imageView.frame.minX
        let yCrop = v.cropArea.frame.minY - v.imageView.frame.minY
        let widthCrop = v.cropArea.frame.width
        let heightCrop = v.cropArea.frame.height
        let scaleRatio = image.size.width / v.imageView.frame.width
        let scaledCropRect = CGRect(x: xCrop * scaleRatio,
                                    y: yCrop * scaleRatio,
                                    width: widthCrop * scaleRatio,
                                    height: heightCrop * scaleRatio)
        
        if let video = self.video {
            print(video.url)
            let videoAsset = AVAsset.init(url: video.url)
            if let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: false, attributes: nil)
                let url = supportDir.appendingPathComponent("croppedVideo.mp4")
                try? FileManager.default.removeItem(at: url)
                videoAsset.cropVideoTrack(at: 0, cropRect: scaledCropRect, outputURL: url) { (result) in

                    self.activityIndicator?.stopAnimating()
                    self.activityIndicator?.removeFromSuperview()
                    let croppedVideo = YPMediaVideo.init(thumbnail: image, videoURL: url)
                    croppedVideo.url = url
                    print(result)
                    self.didFinishVideoCropping?(croppedVideo, scaledCropRect)
                }
            }
        } else {
            if let cgImage = image.toCIImage()?.toCGImage(),
                let imageRef = cgImage.cropping(to: scaledCropRect) {
                let croppedImage = UIImage(cgImage: imageRef)
                didFinishCropping?(croppedImage, scaledCropRect)
            }
        }
    }
    
}

extension YPCropVC: UIGestureRecognizerDelegate {
    
    // MARK: - Pinch Gesture
    
    @objc
    func pinch(_ sender: UIPinchGestureRecognizer) {
        // TODO: Zoom where the fingers are (more user friendly)
        switch sender.state {
        case .began, .changed:
            var transform = v.imageView.transform
            // Apply zoom level.
            transform = transform.scaledBy(x: sender.scale,
                                            y: sender.scale)
            v.imageView.transform = transform
        case .ended:
            pinchGestureEnded()
        case .cancelled, .failed, .possible:
            ()
        @unknown default:
            fatalError()
        }
        // Reset the pinch scale.
        sender.scale = 1.0
    }
    
    private func pinchGestureEnded() {
        var transform = v.imageView.transform
        let kMinZoomLevel: CGFloat = 1.0
        let kMaxZoomLevel: CGFloat = maxZoom
        var wentOutOfAllowedBounds = false
        
        // Prevent zooming out too much
        if transform.a < kMinZoomLevel {
            transform = .identity
            wentOutOfAllowedBounds = true
        }
        
        // Prevent zooming in too much
        if transform.a > kMaxZoomLevel {
            transform.a = kMaxZoomLevel
            transform.d = kMaxZoomLevel
            wentOutOfAllowedBounds = true
        }
        
        // Animate coming back to the allowed bounds with a haptic feedback.
        if wentOutOfAllowedBounds {
            generateHapticFeedback()
            UIView.animate(withDuration: 0.3, animations: {
                self.v.imageView.transform = transform
            })
        }
    }
    
    func generateHapticFeedback() {
        if #available(iOS 10.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    // MARK: - Pan Gesture
    
    @objc
    func pan(_ sender: UIPanGestureRecognizer) {
        let translation = sender.translation(in: view)
        let imageView = v.imageView
        
        // Apply the pan translation to the image.
        imageView.center = CGPoint(x: imageView.center.x + translation.x, y: imageView.center.y + translation.y)
        
        // Reset the pan translation.
        sender.setTranslation(CGPoint.zero, in: view)
        
        if sender.state == .ended {
            keepImageIntoCropArea()
        }
    }
    
    private func keepImageIntoCropArea() {
        let imageRect = v.imageView.frame
        let cropRect = v.cropArea.frame
        var correctedFrame = imageRect
        
        // Cap Top.
        if imageRect.minY > cropRect.minY {
            correctedFrame.origin.y = cropRect.minY
        }
        
        // Cap Bottom.
        if imageRect.maxY < cropRect.maxY {
            correctedFrame.origin.y = cropRect.maxY - imageRect.height
        }
        
        // Cap Left.
        if imageRect.minX > cropRect.minX {
            correctedFrame.origin.x = cropRect.minX
        }
        
        // Cap Right.
        if imageRect.maxX < cropRect.maxX {
            correctedFrame.origin.x = cropRect.maxX - imageRect.width
        }
        
        // Animate back to allowed bounds
        if imageRect != correctedFrame {
            UIView.animate(withDuration: 0.3, animations: {
                self.v.imageView.frame = correctedFrame
            })
        }
    }
    
    /// Allow both Pinching and Panning at the same time.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension AVAsset {
    
    func cropVideoTrack(at index: Int, cropRect: CGRect, outputURL: URL, completion: @escaping (Result<Void, Swift.Error>) -> Void) {
        
        enum Orientation {
            case up, down, right, left
        }
        
        func orientation(for track: AVAssetTrack) -> Orientation {
            let t = track.preferredTransform
            
            if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0) {             // Portrait
                return .up
            } else if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0) {      // PortraitUpsideDown
                return .down
            } else if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0) {       // LandscapeRight
                return .right
            } else if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0) {     // LandscapeLeft
                return .left
            } else {
                return .up
            }
        }
        
        let videoTrack = tracks(withMediaType: .video)[index]
        let originalSize = videoTrack.naturalSize
        let trackOrientation = orientation(for: videoTrack)
        let cropRectIsPortrait = cropRect.width <= cropRect.height
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = cropRect.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 60, preferredTimescale: 30))
        
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        var finalTransform: CGAffineTransform = CGAffineTransform.identity // setup a transform that grows the video, effectively causing a crop
        finalTransform = finalTransform
            .translatedBy(x: cropRect.origin.x * -1.0, y: cropRect.origin.y * -1.0)
        
        
//        if trackOrientation == .up {
//            if !cropRectIsPortrait { // center video rect vertically
//                finalTransform = finalTransform
//                    .translatedBy(x: originalSize.height, y: -(originalSize.width - cropRect.size.height) / 2)
//                    .rotated(by: CGFloat(90.0.degreesToRadians))
//            } else {
//                finalTransform = finalTransform
//                    .rotated(by: CGFloat(90.0.degreesToRadians))
//                    .translatedBy(x: 0, y: -originalSize.height)
//            }
//
//        } else if trackOrientation == .down {
//            if !cropRectIsPortrait { // center video rect vertically (NOTE: did not test this case, since camera doesn't support .portraitUpsideDown in this app)
//                finalTransform = finalTransform
//                    .translatedBy(x: -originalSize.height, y: (originalSize.width - cropRect.size.height) / 2)
//                    .rotated(by: CGFloat(-90.0.degreesToRadians))
//            } else {
//                finalTransform = finalTransform
//                    .rotated(by: CGFloat(-90.0.degreesToRadians))
//                    .translatedBy(x: -originalSize.width, y: -(originalSize.height - cropRect.size.height) / 2)
//            }
//
//        } else if trackOrientation == .right {
//            finalTransform = CGAffineTransform.identity
//            if cropRectIsPortrait {
//                finalTransform = finalTransform.translatedBy(x: -(originalSize.width - cropRect.size.width) / 2, y: 0)
//
//            } else {
//                finalTransform = CGAffineTransform.identity
//            }
//
//        } else if trackOrientation == .left {
//            if cropRectIsPortrait { // center video rect horizontally
//                finalTransform = finalTransform
//                    .rotated(by: CGFloat(-180.0.degreesToRadians))
//                    .translatedBy(x: -originalSize.width + (originalSize.width - cropRect.size.width) / 2, y: -originalSize.height)
//            } else {
//                finalTransform = finalTransform
//                    .rotated(by: CGFloat(-180.0.degreesToRadians))
//                    .translatedBy(x: -originalSize.width, y: -originalSize.height)
//            }
//        }
        
        transformer.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
        let exporter = AVAssetExportSession(asset: self, presetName: AVAssetExportPresetHighestQuality)
        exporter?.videoComposition = videoComposition
        exporter?.outputURL = outputURL
        exporter?.outputFileType=AVFileType.mp4
        
        exporter?.exportAsynchronously(completionHandler: { [weak exporter] in
            DispatchQueue.main.async {
                if let error = exporter?.error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        })
    }
}
extension FloatingPoint {
    var degreesToRadians: Self { self * .pi / 180 }
    var radiansToDegrees: Self { self * 180 / .pi }
}


