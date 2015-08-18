//
//  ViewController.swift
//  camera
//
//  Created by Natalia Terlecka on 10/10/14.
//  Copyright (c) 2014 imaginaryCloud. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    // MARK: - Constants

    let cameraManager = CameraManager.sharedInstance
    
    // MARK: - @IBOutlets

    @IBOutlet weak var cameraView: UIView!
    
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var flashModeButton: UIButton!
    
    @IBOutlet weak var askForPermissionsButton: UIButton!
    @IBOutlet weak var askForPermissionsLabel: UILabel!
    
    
    // MARK: - UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.cameraManager.showAccessPermissionPopupAutomatically = false
        
        self.askForPermissionsButton.hidden = true
        self.askForPermissionsLabel.hidden = true

        let currentCameraState = self.cameraManager.currentCameraStatus()
        
        if currentCameraState == .NotDetermined {
            self.askForPermissionsButton.hidden = false
            self.askForPermissionsLabel.hidden = false
        } else if (currentCameraState == .Ready) {
            self.addCameraToView()
        }
        if !self.cameraManager.hasFlash {
            self.flashModeButton.enabled = false
            self.flashModeButton.setTitle("No flash", forState: UIControlState.Normal)
        }
        
    }
    
    override func viewWillAppear(animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.navigationController?.navigationBar.hidden = true
        self.cameraManager.resumeCaptureSession()
    }
    
    override func viewWillDisappear(animated: Bool)
    {
        super.viewWillDisappear(animated)
        self.cameraManager.stopCaptureSession()
    }
    
    
    // MARK: - ViewController
    
    private func addCameraToView()
    {
        self.cameraManager.addPreviewLayerToView(self.cameraView, newCameraOutputMode: CameraOutputMode.VideoWithMic)
		self.cameraView.backgroundColor = UIColor.blackColor()
        CameraManager.sharedInstance.showErrorBlock = { (erTitle: String, erMessage: String) -> Void in            
            
//            var alertController = UIAlertController(title: erTitle, message: erMessage, preferredStyle: .Alert)
//            alertController.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: { (alertAction) -> Void in
//                //
//            }))
//            
//            let topController = UIApplication.sharedApplication().keyWindow?.rootViewController
//            
//            if (topController != nil) {
//                topController?.presentViewController(alertController, animated: true, completion: { () -> Void in
//                    //
//                })
//            }
        }
    }

    // MARK: - @IBActions

    @IBAction func changeFlashMode(sender: UIButton)
    {
        
        
        switch (self.cameraManager.changeFlashMode()) {
        case .Off:
            sender.setTitle("Flash Off", forState: UIControlState.Normal)
        case .On:
            sender.setTitle("Flash On", forState: UIControlState.Normal)
        case .Auto:
            sender.setTitle("Flash Auto", forState: UIControlState.Normal)
        }
    }
    
    @IBAction func recordButtonTapped(sender: UIButton)
    {
        switch (self.cameraManager.cameraOutputMode) {
        case .StillImage:
            self.cameraManager.capturePictureWithCompletition({ (image, error) -> Void in
                let vc: ImageViewController? = self.storyboard?.instantiateViewControllerWithIdentifier("ImageVC") as? ImageViewController
                if let validVC: ImageViewController = vc {
                    if let capturedImage = image {
                        validVC.image = capturedImage
                        self.navigationController?.pushViewController(validVC, animated: true)
                    }
                }
            })
        case .VideoWithMic, .VideoOnly:
            sender.selected = !sender.selected
            sender.setTitle(" ", forState: UIControlState.Selected)
            sender.backgroundColor = sender.selected ? UIColor.redColor() : UIColor.greenColor()
            if sender.selected {
                self.cameraManager.startRecordingVideo()
            } else {
                self.cameraManager.stopRecordingVideo({ (videoURL, error) -> Void in
                    if let errorOccured = error {                        
                        self.cameraManager.showErrorBlock(erTitle: "Error occurred", erMessage: errorOccured.localizedDescription)
                    }
                })
            }
        }
    }
    
    @IBAction func outputModeButtonTapped(sender: UIButton)
    {
        self.cameraManager.cameraOutputMode = self.cameraManager.cameraOutputMode == CameraOutputMode.VideoWithMic ? CameraOutputMode.StillImage : CameraOutputMode.VideoWithMic
        switch (self.cameraManager.cameraOutputMode) {
        case .StillImage:
            self.cameraButton.selected = false
            self.cameraButton.backgroundColor = UIColor.greenColor()
            sender.setTitle("Image", forState: UIControlState.Normal)
        case .VideoWithMic, .VideoOnly:
            sender.setTitle("Video", forState: UIControlState.Normal)
        }
    }
    
    @IBAction func changeCameraDevice(sender: UIButton)
    {
		let newCameraDevice = self.cameraManager.cameraDevice == CameraDevice.Front ? CameraDevice.Back : CameraDevice.Front
		self.cameraManager.setCameraDeviceWithFlipAnimation(newCameraDevice)
//        self.cameraManager.cameraDevice = self.cameraManager.cameraDevice == CameraDevice.Front ? CameraDevice.Back : CameraDevice.Front
        switch (self.cameraManager.cameraDevice) {
        case .Front:
            sender.setTitle("Front", forState: UIControlState.Normal)
        case .Back:
            sender.setTitle("Back", forState: UIControlState.Normal)
        }
    }
    
    @IBAction func askForCameraPermissions(sender: UIButton)
    {
        self.cameraManager.askUserForCameraPermissions({ permissionGranted in
            self.askForPermissionsButton.hidden = true
            self.askForPermissionsLabel.hidden = true
            self.askForPermissionsButton.alpha = 0
            self.askForPermissionsLabel.alpha = 0
            if permissionGranted {
                self.addCameraToView()
            }
        })
    }
    
    @IBAction func changeCameraQuality(sender: UIButton)
    {
        switch (self.cameraManager.changeQualityMode()) {
        case .High:
            sender.setTitle("High", forState: UIControlState.Normal)
        case .Low:
            sender.setTitle("Low", forState: UIControlState.Normal)
        case .Medium:
            sender.setTitle("Medium", forState: UIControlState.Normal)
        }
    }
}


