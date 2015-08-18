//
//  CameraManager.swift
//  camera
//
//  Created by Natalia Terlecka on 10/10/14.
//  Copyright (c) 2014 imaginaryCloud. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary

private let _singletonSharedInstance = CameraManager()

public enum CameraState {
    case Ready, AccessDenied, NoDeviceFound, NotDetermined
}

public enum CameraDevice {
    case Front, Back
}

public enum CameraFlashMode: Int {
    case Off, On, Auto
}

public enum CameraOutputMode {
    case StillImage, VideoWithMic, VideoOnly
}

public enum CameraOutputQuality: Int {
    case Low, Medium, High
}

/// Class for handling iDevices custom camera usage
public class CameraManager: NSObject, AVCaptureFileOutputRecordingDelegate {

    // MARK: - Public properties

    /// CameraManager singleton instance to use the camera.
    public class var sharedInstance: CameraManager {
        return _singletonSharedInstance
    }
    
    /// Capture session to customize camera settings.
    public var captureSession: AVCaptureSession?
    
    /// Property to determine if the manager should show the error for the user. If you want to show the errors yourself set this to false. If you want to add custom error UI set showErrorBlock property. Default value is false.
    public var showErrorsToUsers = false
    
    /// Property to determine if the manager should show the camera permission popup immediatly when it's needed or you want to show it manually. Default value is true. Be carful cause using the camera requires permission, if you set this value to false and don't ask manually you won't be able to use the camera.
    public var showAccessPermissionPopupAutomatically = true
    
    /// A block creating UI to present error message to the user. This can be customised to be presented on the Window root view controller, or to pass in the viewController which will present the UIAlertController, for example.
    public var showErrorBlock:(erTitle: String, erMessage: String) -> Void = { (erTitle: String, erMessage: String) -> Void in
        
//        var alertController = UIAlertController(title: erTitle, message: erMessage, preferredStyle: .Alert)
//        alertController.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: { (alertAction) -> Void in
//            //
//        }))
//        
//        let topController = UIApplication.sharedApplication().keyWindow?.rootViewController
//        
//        if (topController != nil) {
//            topController?.presentViewController(alertController, animated: true, completion: { () -> Void in
//                //
//            })
//        }
    }

    /// Property to determine if manager should write the resources to the phone library. Default value is true.
    public var writeFilesToPhoneLibrary = true

    /// The Bool property to determine if current device has front camera.
    public var hasFrontCamera: Bool = {
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for  device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == .Front) {
                return true
            }
        }
        return false
        }()
    
    /// The Bool property to determine if current device has flash.
    public var hasFlash: Bool = {
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for  device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == .Back) {
                return captureDevice.hasFlash
            }
        }
        return false
        }()
    
    /// Property to change camera device between front and back.
    public var cameraDevice: CameraDevice {
        get {
            return _cameraDevice
        }
        set(newCameraDevice) {
            if let validCaptureSession = self.captureSession {
                validCaptureSession.beginConfiguration()
                let inputs = validCaptureSession.inputs as! [AVCaptureInput]

                switch newCameraDevice {
                case .Front:
                    if self.hasFrontCamera {
                        if let validBackDevice = self.rearCamera {
                            if inputs.contains(validBackDevice) {
                                validCaptureSession.removeInput(validBackDevice)
                            }
                        }
                        if let validFrontDevice = self.frontCamera {
                            if !inputs.contains(validFrontDevice) {
                                validCaptureSession.addInput(validFrontDevice)
                            }
                        }
                    }
                case .Back:
                    if let validFrontDevice = self.frontCamera {
                        if inputs.contains(validFrontDevice) {
                            validCaptureSession.removeInput(validFrontDevice)
                        }
                    }
                    if let validBackDevice = self.rearCamera {
                        if !inputs.contains(validBackDevice) {
                            validCaptureSession.addInput(validBackDevice)
                        }
                    }
                }
				
                validCaptureSession.commitConfiguration()
            }
            _cameraDevice = newCameraDevice
        }
    }

    /// Property to change camera flash mode.
    public var flashMode: CameraFlashMode {
        get {
            return _flashMode
        }
        set(newflashMode) {
            if newflashMode != _flashMode {
                _flashMode = newflashMode
                self._updateFlasMode(newflashMode)
            }
        }
    }

    /// Property to change camera output quality.
    public var cameraOutputQuality: CameraOutputQuality {
        get {
            return _cameraOutputQuality
        }
        set(newCameraOutputQuality) {
            if newCameraOutputQuality != _cameraOutputQuality {
                _cameraOutputQuality = newCameraOutputQuality
                self._updateCameraQualityMode(newCameraOutputQuality)
            }
        }
    }

    /// Property to change camera output.
    public var cameraOutputMode: CameraOutputMode {
        get {
            return _cameraOutputMode
        }
        set(newCameraOutputMode) {
            if newCameraOutputMode != _cameraOutputMode {
                self._setupOutputMode(newCameraOutputMode)
            }
        }
    }
	
    // MARK: - Private properties

    private weak var embeddingView: UIView?
    private var videoCompletition: ((videoURL: NSURL, error: NSError?) -> Void)?

    private var sessionQueue: dispatch_queue_t = dispatch_queue_create("CameraSessionQueue", DISPATCH_QUEUE_SERIAL)

    private var frontCamera: AVCaptureInput?
    private var rearCamera: AVCaptureInput?
    private var mic: AVCaptureDeviceInput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var library: ALAssetsLibrary?

    private var cameraIsSetup = false
    private var cameraIsObservingDeviceOrientation = false

    private var _cameraDevice = CameraDevice.Back
    private var _flashMode = CameraFlashMode.Off
    private var _cameraOutputMode = CameraOutputMode.StillImage
    private var _cameraOutputQuality = CameraOutputQuality.High
	
    private var tempFilePath: NSURL = {
		let tempPath = "\(NSTemporaryDirectory())/tempMovie.mp4"
        if NSFileManager.defaultManager().fileExistsAtPath(tempPath) {
            do {
                try NSFileManager.defaultManager().removeItemAtPath(tempPath)
            } catch {
                
            }
        }
        return NSURL(fileURLWithPath: tempPath)
        }()
	

    // MARK: - CameraManager

    /**
	Inits a capture session and adds a preview layer to the given view. Preview layer bounds will automaticaly be set to match given view. Default session is initialized with still image output.
	
	:param: view The view you want to add the preview layer to
	:param: cameraOutputMode The mode you want capturesession to run image / video / video and microphone
	
	:returns: Current state of the camera: Ready / AccessDenied / NoDeviceFound / NotDetermined.
    */
	public func addPreviewLayerToView(view: UIView) -> CameraState
    {
		return self.addPreviewLayerToView(view, atZIndex: nil, newCameraOutputMode: _cameraOutputMode)
    }
	
	public func addPreviewLayerToView(view: UIView, atZIndex index: UInt32) -> CameraState
	{
		return self.addPreviewLayerToView(view, atZIndex: index, newCameraOutputMode: _cameraOutputMode)
	}
	
    public func addPreviewLayerToView(view: UIView, newCameraOutputMode: CameraOutputMode) -> CameraState
    {
		return self.addPreviewLayerToView(view, atZIndex: nil, newCameraOutputMode: newCameraOutputMode)
	}
	
	public func addPreviewLayerToView(view: UIView, atZIndex index: UInt32?, newCameraOutputMode: CameraOutputMode) -> CameraState
	{
		if self._canLoadCamera() {
			if let _ = self.embeddingView {
				if let validPreviewLayer = self.previewLayer {
					validPreviewLayer.removeFromSuperlayer()
				}
			}
			if self.cameraIsSetup {
				self.previewLayerZIndex = index
				self._addPreviewLayerToView(view, atZIndex: index)
				self.cameraOutputMode = newCameraOutputMode
			} else {
				self._setupCamera({ Void -> Void in
					self.previewLayerZIndex = index
					self._addPreviewLayerToView(view, atZIndex: index)
					self.cameraOutputMode = newCameraOutputMode
				})
			}
		}
		return self._checkIfCameraIsAvailable()
	}

    /**
    Asks the user for camera permissions. Only works if the permissions are not yet determined. Note that it'll also automaticaly ask about the microphone permissions if you selected VideoWithMic output.
    
    :param: completition Completition block with the result of permission request
    */
    public func askUserForCameraPermissions(completition: Bool -> Void)
    {
        AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (alowedAccess) -> Void in
            if self.cameraOutputMode == .VideoWithMic {
                AVCaptureDevice.requestAccessForMediaType(AVMediaTypeAudio, completionHandler: { (alowedAccess) -> Void in
                    dispatch_sync(dispatch_get_main_queue(), { () -> Void in
                        completition(alowedAccess)
                    })
                })
            } else {
                dispatch_sync(dispatch_get_main_queue(), { () -> Void in
                    completition(alowedAccess)
                })

            }
        })

    }

    /**
    Stops running capture session but all setup devices, inputs and outputs stay for further reuse.
    */
    public func stopCaptureSession()
    {
        self.captureSession?.stopRunning()
        self._stopFollowingDeviceOrientation()
    }

    /**
    Resumes capture session.
    */
    public func resumeCaptureSession()
    {
        if let validCaptureSession = self.captureSession {
            if !validCaptureSession.running && self.cameraIsSetup {
                validCaptureSession.startRunning()
                self._startFollowingDeviceOrientation()
            }
        } else {
            if self._canLoadCamera() {
                if self.cameraIsSetup {
                    self.stopAndRemoveCaptureSession()
                }
                self._setupCamera({Void -> Void in
                    if let validembeddingView = self.embeddingView {
						self._addPreviewLayerToView(validembeddingView, atZIndex: self.previewLayerZIndex)
                    }
                    self._startFollowingDeviceOrientation()
                })
            }
        }
    }

    /**
    Stops running capture session and removes all setup devices, inputs and outputs.
    */
    public func stopAndRemoveCaptureSession()
    {
        self.stopCaptureSession()
        self.cameraDevice = .Back
        self.cameraIsSetup = false
        self.previewLayer = nil
        self.captureSession = nil
        self.frontCamera = nil
        self.rearCamera = nil
        self.mic = nil
        self.stillImageOutput = nil
        self.movieOutput = nil
    }

    /**
    Captures still image from currently running capture session.

    :param: imageCompletition Completition block containing the captured UIImage
    */
    public func capturePictureWithCompletition(imageCompletition: (UIImage?, NSError?) -> Void)
    {
        if self.cameraIsSetup {
            if self.cameraOutputMode == .StillImage {
                dispatch_async(self.sessionQueue, {
                    self._getStillImageOutput().captureStillImageAsynchronouslyFromConnection(self._getStillImageOutput().connectionWithMediaType(AVMediaTypeVideo), completionHandler: { [weak self] (sample: CMSampleBuffer!, error: NSError!) -> Void in
                        if (error != nil) {
                            dispatch_async(dispatch_get_main_queue(), {
                                if let weakSelf = self {
                                    weakSelf._show(NSLocalizedString("Error", comment:""), message: error.localizedDescription)
                                }
                            })
                            imageCompletition(nil, error)
                        } else {
                            let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sample)
                            if let weakSelf = self {
                                if weakSelf.writeFilesToPhoneLibrary {
                                    if let validLibrary = weakSelf.library {
                                        validLibrary.writeImageDataToSavedPhotosAlbum(imageData, metadata:nil, completionBlock: {
                                            (picUrl, error) -> Void in
                                            if (error != nil) {
                                                dispatch_async(dispatch_get_main_queue(), {
                                                    weakSelf._show(NSLocalizedString("Error", comment:""), message: error.localizedDescription)
                                                })
                                            }
                                        })
                                    }
                                }
                            }
                            imageCompletition(UIImage(data: imageData), nil)
                        }
                    })
                })
            } else {
                self._show(NSLocalizedString("Capture session output mode video", comment:""), message: NSLocalizedString("I can't take any picture", comment:""))
            }
        } else {
            self._show(NSLocalizedString("No capture session setup", comment:""), message: NSLocalizedString("I can't take any picture", comment:""))
        }
    }

    /**
    Starts recording a video with or without voice as in the session preset.
    */
    public func startRecordingVideo()
    {
        if self.cameraOutputMode != .StillImage {
            self._getMovieOutput().startRecordingToOutputFileURL(self.tempFilePath, recordingDelegate: self)
        } else {
            self._show(NSLocalizedString("Capture session output still image", comment:""), message: NSLocalizedString("I can only take pictures", comment:""))
        }
    }

    /**
    Stop recording a video. Save it to the cameraRoll and give back the url.
    */
    public func stopRecordingVideo(completition:(videoURL: NSURL, error: NSError?) -> Void)
    {
        if let runningMovieOutput = self.movieOutput {
            if runningMovieOutput.recording {
                self.videoCompletition = completition
                runningMovieOutput.stopRecording()
            }
        }
    }

    /**
    Current camera status.
    
    :returns: Current state of the camera: Ready / AccessDenied / NoDeviceFound / NotDetermined
    */
    public func currentCameraStatus() -> CameraState
    {
        return self._checkIfCameraIsAvailable()
    }
    
    /**
    Change current flash mode to next value from available ones.
    
    :returns: Current flash mode: Off / On / Auto
    */
    public func changeFlashMode() -> CameraFlashMode
    {
        self.flashMode = CameraFlashMode(rawValue: (self.flashMode.rawValue+1)%3)!
        return self.flashMode
    }
    
    /**
    Change current output quality mode to next value from available ones.
    
    :returns: Current quality mode: Low / Medium / High
    */
    public func changeQualityMode() -> CameraOutputQuality
    {
        self.cameraOutputQuality = CameraOutputQuality(rawValue: (self.cameraOutputQuality.rawValue+1)%3)!
        return self.cameraOutputQuality
    }
	
    // MARK: - AVCaptureFileOutputRecordingDelegate

    public func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!)
    {
        self.captureSession?.beginConfiguration()
        if self.flashMode != .Off {
            self._updateTorch(self.flashMode)
        }
        self.captureSession?.commitConfiguration()
    }

    public func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!)
    {
        self._updateTorch(.Off)
        if (error != nil) {
            self._show(NSLocalizedString("Unable to save video to the iPhone", comment:""), message: error.localizedDescription)
        } else {
            if let validLibrary = self.library {
                if self.writeFilesToPhoneLibrary {
                    validLibrary.writeVideoAtPathToSavedPhotosAlbum(outputFileURL, completionBlock: { (assetURL: NSURL?, error: NSError?) -> Void in
                        if (error != nil) {
                            self._show(NSLocalizedString("Unable to save video to the iPhone.", comment:""), message: error!.localizedDescription)
                        } else {
                            if let validAssetURL = assetURL {
                                self._executeVideoCompletitionWithURL(validAssetURL, error: error)
                            }
                        }
                    })
                } else {
                    self._executeVideoCompletitionWithURL(outputFileURL, error: error)
                }
            }
        }
    }

    // MARK: - CameraManager()

    private func _updateTorch(flashMode: CameraFlashMode)
    {
        self.captureSession?.beginConfiguration()
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for  device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == AVCaptureDevicePosition.Back) {
                let avTorchMode = AVCaptureTorchMode(rawValue: flashMode.rawValue)
                if (captureDevice.isTorchModeSupported(avTorchMode!)) {
                    do {
                        try captureDevice.lockForConfiguration()
                    } catch {
                        return;
                    }
                    captureDevice.torchMode = avTorchMode!
                    captureDevice.unlockForConfiguration()
                }
            }
        }
        self.captureSession?.commitConfiguration()
    }
    
    private func _executeVideoCompletitionWithURL(url: NSURL, error: NSError?)
    {
        if let validCompletition = self.videoCompletition {
            validCompletition(videoURL: url, error: error)
            self.videoCompletition = nil
        }
    }

    private func _getMovieOutput() -> AVCaptureMovieFileOutput
    {
        var shouldReinitializeMovieOutput = self.movieOutput == nil
        if !shouldReinitializeMovieOutput {
            if let connection = self.movieOutput!.connectionWithMediaType(AVMediaTypeVideo) {
                shouldReinitializeMovieOutput = shouldReinitializeMovieOutput || !connection.active
            }
        }
        
        if shouldReinitializeMovieOutput {
            self.movieOutput = AVCaptureMovieFileOutput()
            
            self.captureSession?.beginConfiguration()
            self.captureSession?.addOutput(self.movieOutput)
            self.captureSession?.commitConfiguration()
        }
        return self.movieOutput!
    }
    
    private func _getStillImageOutput() -> AVCaptureStillImageOutput
    {
        var shouldReinitializeStillImageOutput = self.stillImageOutput == nil
        if !shouldReinitializeStillImageOutput {
            if let connection = self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo) {
                shouldReinitializeStillImageOutput = shouldReinitializeStillImageOutput || !connection.active
            }
        }
        if shouldReinitializeStillImageOutput {
            self.stillImageOutput = AVCaptureStillImageOutput()
            
            self.captureSession?.beginConfiguration()
            self.captureSession?.addOutput(self.stillImageOutput)
            self.captureSession?.commitConfiguration()
        }
        return self.stillImageOutput!
    }
    
    @objc private func _orientationChanged()
    {
        var currentConnection: AVCaptureConnection?;
        switch self.cameraOutputMode {
        case .StillImage:
            currentConnection = self.stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo)
        case .VideoOnly, .VideoWithMic:
            currentConnection = self._getMovieOutput().connectionWithMediaType(AVMediaTypeVideo)
        }
        if let validPreviewLayer = self.previewLayer {
			if let validOutputLayerConnection = currentConnection {
				if validOutputLayerConnection.supportsVideoOrientation {
					validOutputLayerConnection.videoOrientation = self._currentVideoOrientation()
				}
			}
			if self.autoAdjustPreviewOrientation {
				if let validPreviewLayerConnection = validPreviewLayer.connection {
					if validPreviewLayerConnection.supportsVideoOrientation {
						validPreviewLayerConnection.videoOrientation = self._currentVideoOrientation()
					}
				}
			}
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				if let validembeddingView = self.embeddingView {
					validPreviewLayer.frame = validembeddingView.bounds
				}
			})
        }
    }

    private func _currentVideoOrientation() -> AVCaptureVideoOrientation
    {
        switch UIDevice.currentDevice().orientation {
        case .LandscapeLeft:
            return .LandscapeRight
        case .LandscapeRight:
            return .LandscapeLeft
		case .PortraitUpsideDown:
			return .PortraitUpsideDown
        default:
            return .Portrait
        }
    }

    private func _canLoadCamera() -> Bool
    {
        let currentCameraState = _checkIfCameraIsAvailable()
        return currentCameraState == .Ready || (currentCameraState == .NotDetermined && self.showAccessPermissionPopupAutomatically)
    }

    private func _setupCamera(completition: Void -> Void)
    {
        self.captureSession = AVCaptureSession()
        
        dispatch_async(sessionQueue, {
            if let validCaptureSession = self.captureSession {
                validCaptureSession.beginConfiguration()
                validCaptureSession.sessionPreset = AVCaptureSessionPresetHigh
                self._addVideoInput()
                self._setupOutputs()
                self._setupOutputMode(self._cameraOutputMode)
                self.cameraOutputQuality = self._cameraOutputQuality
                self._setupPreviewLayer()
                validCaptureSession.commitConfiguration()
                self._updateFlasMode(self.flashMode)
                self._updateCameraQualityMode(self.cameraOutputQuality)
                validCaptureSession.startRunning()
                self._startFollowingDeviceOrientation()
				self._startFollowingConfigurationChanges()
                self.cameraIsSetup = true
                self._orientationChanged()
                
                completition()
            }
        })
    }

    private func _startFollowingDeviceOrientation()
    {
        if !self.cameraIsObservingDeviceOrientation {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "_orientationChanged", name: UIDeviceOrientationDidChangeNotification, object: nil)
            self.cameraIsObservingDeviceOrientation = true
        }
    }

    private func _stopFollowingDeviceOrientation()
    {
        if self.cameraIsObservingDeviceOrientation {
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIDeviceOrientationDidChangeNotification, object: nil)
            self.cameraIsObservingDeviceOrientation = false
        }
    }
	
	private func _addPreviewLayerToView(view: UIView, atZIndex index: UInt32?)
    {
        self.embeddingView = view
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            guard let _ = self.previewLayer else {
                return
            }
            self.previewLayer!.frame = view.layer.bounds
            view.clipsToBounds = true
			
			if let index = index {
				
				view.layer.insertSublayer(self.previewLayer!, atIndex: index)
			}
			else {
				
				view.layer.addSublayer(self.previewLayer!)
			}
        })
    }

    private func _checkIfCameraIsAvailable() -> CameraState
    {
        let deviceHasCamera = UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.Rear) || UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.Front)
        if deviceHasCamera {
            let authorizationStatus = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
            let userAgreedToUseIt = authorizationStatus == .Authorized
            if userAgreedToUseIt {
                return .Ready
            } else if authorizationStatus == AVAuthorizationStatus.NotDetermined {
                return .NotDetermined
            } else {
                self._show(NSLocalizedString("Camera access denied", comment:""), message:NSLocalizedString("You need to go to settings app and grant acces to the camera device to use it.", comment:""))
                return .AccessDenied
            }
        } else {
            self._show(NSLocalizedString("Camera unavailable", comment:""), message:NSLocalizedString("The device does not have a camera.", comment:""))
            return .NoDeviceFound
        }
    }
    
    private func _addVideoInput()
    {
        if (self.frontCamera == nil) || (self.rearCamera == nil) {
            var videoFrontDevice: AVCaptureDevice?
            var videoBackDevice: AVCaptureDevice?
            for device: AnyObject in AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) {
                if device.position == AVCaptureDevicePosition.Back {
                    videoBackDevice = device as? AVCaptureDevice
                } else if device.position == AVCaptureDevicePosition.Front {
                    videoFrontDevice = device as? AVCaptureDevice
                }
            }
            do {
                if (self.frontCamera == nil) {
                    if let validVideoFrontDevice = videoFrontDevice {
                        try self.frontCamera = AVCaptureDeviceInput(device: validVideoFrontDevice)
                    }
                }
                if (self.rearCamera == nil) {
                    if let validVideoBackDevice = videoBackDevice {
                        try self.rearCamera = AVCaptureDeviceInput(device: validVideoBackDevice)
                    }
                }
            } catch let outError {
                self._show(NSLocalizedString("Device setup error occured", comment:""), message: "\(outError)")
                return
            }
        }
        self.cameraDevice = _cameraDevice
    }

    private func _setupMic()
    {
        if (self.mic == nil) {
            let micDevice:AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            do {
                try self.mic = AVCaptureDeviceInput(device: micDevice)
            } catch let outError {
                self.mic = nil
                self._show(NSLocalizedString("Mic error", comment:""), message: "\(outError)")
            }
        }
    }
    
    private func _setupOutputMode(newCameraOutputMode: CameraOutputMode)
    {
        self.captureSession?.beginConfiguration()
        
        if (_cameraOutputMode != newCameraOutputMode) {
            // remove current setting
            switch _cameraOutputMode {
            case .StillImage:
                if let validStillImageOutput = self.stillImageOutput {
                    self.captureSession?.removeOutput(validStillImageOutput)
                }
            case .VideoOnly, .VideoWithMic:
                if let validMovieOutput = self.movieOutput {
                    self.captureSession?.removeOutput(validMovieOutput)
                }
                if _cameraOutputMode == .VideoWithMic {
                    if let validMic = self.mic {
                        self.captureSession?.removeInput(validMic)
                    }
                }
            }
        }
        
        // configure new devices
        switch newCameraOutputMode {
        case .StillImage:
            if (self.stillImageOutput == nil) {
                self._setupOutputs()
            }
            if let validStillImageOutput = self.stillImageOutput {
                self.captureSession?.addOutput(validStillImageOutput)
            }
        case .VideoOnly, .VideoWithMic:
            self.captureSession?.addOutput(self._getMovieOutput())
            
            if newCameraOutputMode == .VideoWithMic {
                if (self.mic == nil) {
                    self._setupMic()
                }
                if let validMic = self.mic {
                    self.captureSession?.addInput(validMic)
                }
            }
        }
        self.captureSession?.commitConfiguration()
        _cameraOutputMode = newCameraOutputMode;
        self._updateCameraQualityMode(self.cameraOutputQuality)
        self._orientationChanged()
    }
    
    private func _setupOutputs()
    {
        if (self.stillImageOutput == nil) {
            self.stillImageOutput = AVCaptureStillImageOutput()
        }
        if (self.movieOutput == nil) {
            self.movieOutput = AVCaptureMovieFileOutput()
        }
        if self.library == nil {
            self.library = ALAssetsLibrary()
        }
    }

    private func _setupPreviewLayer()
    {
        if let validCaptureSession = self.captureSession {
            self.previewLayer = AVCaptureVideoPreviewLayer(session: validCaptureSession)
            self.previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        }
    }
    
    private func _updateFlasMode(flashMode: CameraFlashMode)
    {
        self.captureSession?.beginConfiguration()
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
        for  device in devices  {
            let captureDevice = device as! AVCaptureDevice
            if (captureDevice.position == AVCaptureDevicePosition.Back) {
                let avFlashMode = AVCaptureFlashMode(rawValue: flashMode.rawValue)
                if (captureDevice.isFlashModeSupported(avFlashMode!)) {
                    do {
                        try captureDevice.lockForConfiguration()
                    } catch {
                        return
                    }
                    captureDevice.flashMode = avFlashMode!
                    captureDevice.unlockForConfiguration()
                }
            }
        }
        self.captureSession?.commitConfiguration()
    }
    
    private func _updateCameraQualityMode(newCameraOutputQuality: CameraOutputQuality)
    {
        if let validCaptureSession = self.captureSession {
            var sessionPreset = AVCaptureSessionPresetLow
            switch (newCameraOutputQuality) {
            case CameraOutputQuality.Low:
                sessionPreset = AVCaptureSessionPresetLow
            case CameraOutputQuality.Medium:
                sessionPreset = AVCaptureSessionPresetMedium
            case CameraOutputQuality.High:
                if self.cameraOutputMode == .StillImage {
                    sessionPreset = AVCaptureSessionPresetPhoto
                } else {
                    sessionPreset = AVCaptureSessionPresetHigh
                }
            }
            if validCaptureSession.canSetSessionPreset(sessionPreset) {
                validCaptureSession.beginConfiguration()
                validCaptureSession.sessionPreset = sessionPreset
                validCaptureSession.commitConfiguration()
            } else {
                self._show(NSLocalizedString("Preset not supported", comment:""), message: NSLocalizedString("Camera preset not supported. Please try another one.", comment:""))
            }
        } else {
            self._show(NSLocalizedString("Camera error", comment:""), message: NSLocalizedString("No valid capture session found, I can't take any pictures or videos.", comment:""))
        }
    }

    private func _show(title: String, message: String)
    {
        if self.showErrorsToUsers {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.showErrorBlock(erTitle: title, erMessage: message)
            })
        }
    }
    
    deinit {
        self.stopAndRemoveCaptureSession()
        self._stopFollowingDeviceOrientation()
		self._stopFollowingConfigurationChanges()
    }
	
	
	// MARK: - Suggested additions
	
	/// Property that defines whether the camera manager should take care of adjusting the preview layer's orientation when the device orientation changes
	public var autoAdjustPreviewOrientation: Bool = true
	
	/**
	Switches between the current and specified camera using a flip animation similar to the one used in the iOS stock camera app
	*/
	public func setCameraDeviceWithFlipAnimation(newCameraDevice: CameraDevice) {
		
		if transitionAnimating {
			
			return
		}
		
		if let validCaptureSession = self.captureSession {
			
			var inputToRemove: AVCaptureInput?
			var inputToAdd: AVCaptureInput?
			
			let inputs = validCaptureSession.inputs as! [AVCaptureInput]
			
			switch newCameraDevice {
			case .Front:
				if self.hasFrontCamera {
					if let validBackDevice = self.rearCamera {
						if inputs.contains(validBackDevice) {
							inputToRemove = validBackDevice
						}
					}
					if let validFrontDevice = self.frontCamera {
						if !inputs.contains(validFrontDevice) {
							inputToAdd = validFrontDevice
						}
					}
				}
			case .Back:
				if let validFrontDevice = self.frontCamera {
					if inputs.contains(validFrontDevice) {
						inputToRemove = validFrontDevice
					}
				}
				if let validBackDevice = self.rearCamera {
					if !inputs.contains(validBackDevice) {
						inputToAdd = validBackDevice
					}
				}
			}
			
			if let inputToRemove = inputToRemove, let inputToAdd = inputToAdd {
				
				newConfigurationIsLive = false
				
				if let validEmbeddingView = self.embeddingView {
					if let validPreviewLayer = self.previewLayer {
						
						var tempView: UIView!
						
						if _blurSupported() {
							
							let blurEffect = UIBlurEffect(style: .Light)
							tempView = UIVisualEffectView(effect: blurEffect)
							tempView.frame = validEmbeddingView.bounds
						}
						else {
							
							tempView = UIView(frame: validEmbeddingView.bounds)
							tempView.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
						}
						
						validEmbeddingView.insertSubview(tempView, atIndex: Int(validPreviewLayer.zPosition + 1))
						
						cameraTransitionView = validEmbeddingView.snapshotViewAfterScreenUpdates(true)
						
						validEmbeddingView.insertSubview(cameraTransitionView!, atIndex: Int(validEmbeddingView.layer.zPosition + 1))
						tempView.removeFromSuperview()
						
						transitionAnimating = true
						
						validPreviewLayer.opacity = 0.0
						
						performSelector("_flipCameraTransitionView", withObject: nil, afterDelay: 0.00001)
					}
					
					dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
						
						validCaptureSession.beginConfiguration()
						validCaptureSession.removeInput(inputToRemove)
						validCaptureSession.addInput(inputToAdd)
						validCaptureSession.commitConfiguration()
					}
				}
			}
			_cameraDevice = newCameraDevice
		}
	}
	
	private var previewLayerZIndex: UInt32?
	private var cameraTransitionView: UIView?
	private var transitionAnimating = false
	private var newConfigurationIsLive = false
	
	private func _startFollowingConfigurationChanges()
	{
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "_newConfigurationDidBecomeLive", name: "ConfigurationDidBecomeLive", object: nil)
	}
	
	private func _stopFollowingConfigurationChanges()
	{
		
		NSNotificationCenter.defaultCenter().removeObserver(self, name: "ConfigurationDidBecomeLive", object: nil)
	}
	
	@objc private func _flipCameraTransitionView() {
		
		if let cameraTransitionView = cameraTransitionView {
			
			UIView.transitionWithView(cameraTransitionView,
				duration: 0.5,
				options: UIViewAnimationOptions.TransitionFlipFromLeft,
				animations: nil,
				completion: { (finished) -> Void in
					
					if (self.newConfigurationIsLive) {
						
						self._removeCameraTransistionView()
					}
			})
		}
	}
	
	private func _removeCameraTransistionView() {
		
		if let cameraTransitionView = cameraTransitionView {
			if let validPreviewLayer = self.previewLayer {
				
				validPreviewLayer.opacity = 1.0
			}
			
			UIView.animateWithDuration(0.5,
				animations: { () -> Void in
					
					cameraTransitionView.alpha = 0.0
					
				}, completion: { (finished) -> Void in
					
					self.transitionAnimating = false
					
					cameraTransitionView.removeFromSuperview()
					self.cameraTransitionView = nil
			})
		}
	}
	
	@objc private func _newConfigurationDidBecomeLive() {
		
		if !self.transitionAnimating {
			
			dispatch_async(dispatch_get_main_queue()) { () -> Void in
				
				self._removeCameraTransistionView()
			}
		}
		
		self.newConfigurationIsLive = true
	}
	
	// Determining whether the current device actually supports blurring
	// As seen on: http://stackoverflow.com/a/29997626/2269387
	private func _blurSupported() -> Bool {
		var supported = Set<String>()
		supported.insert("iPad")
		supported.insert("iPad1,1")
		supported.insert("iPhone1,1")
		supported.insert("iPhone1,2")
		supported.insert("iPhone2,1")
		supported.insert("iPhone3,1")
		supported.insert("iPhone3,2")
		supported.insert("iPhone3,3")
		supported.insert("iPod1,1")
		supported.insert("iPod2,1")
		supported.insert("iPod2,2")
		supported.insert("iPod3,1")
		supported.insert("iPod4,1")
		supported.insert("iPad2,1")
		supported.insert("iPad2,2")
		supported.insert("iPad2,3")
		supported.insert("iPad2,4")
		supported.insert("iPad3,1")
		supported.insert("iPad3,2")
		supported.insert("iPad3,3")
		
		return !supported.contains(_hardwareString())
	}
	
	private func _hardwareString() -> String {
		var name: [Int32] = [CTL_HW, HW_MACHINE]
		var size: Int = 2
		sysctl(&name, 2, nil, &size, &name, 0)
		var hw_machine = [CChar](count: Int(size), repeatedValue: 0)
		sysctl(&name, 2, &hw_machine, &size, &name, 0)
		
		let hardware: String = String.fromCString(hw_machine)!
		return hardware
	}
}
