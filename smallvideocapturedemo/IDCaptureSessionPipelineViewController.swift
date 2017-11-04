//
//  IDCaptureSessionPipelineViewController.swift
//  smallvideocapturedemo
//
//  Created by Stanley Chiang on 7/10/16.
//  Copyright © 2016 Stanley Chiang. All rights reserved.
//

import UIKit
import AVFoundation

class IDCaptureSessionPipelineViewController: UIViewController, IDCaptureSessionCoordinatorDelegate {
    
    var captureSessionCoordinator: IDCaptureSessionCoordinator = IDCaptureSessionAssetWriterCoordinator()
    var recordButton: UIBarButtonItem!
    var closeButton: UIBarButtonItem!
    var recording: Bool = false
    var dismissing: Bool = false
    let toolbar = UIToolbar()
    
    override func viewDidLoad() {
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        recordButton = UIBarButtonItem(title: "Record", style: UIBarButtonItemStyle.plain, target: self, action: #selector(toggleRecording(_:)))
        closeButton = UIBarButtonItem(title: "Close", style: UIBarButtonItemStyle.plain, target: self, action: #selector(closeCamera(_:)))
        
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.items = [spacer, spacer, spacer, recordButton, spacer]
        view.addSubview(toolbar)
        
        self.checkPermissions()
        captureSessionCoordinator.setDelegate(self, callbackQueue: DispatchQueue.main)
        self.configureInterface()
    }
    
    override func viewDidLayoutSubviews() {
        toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        toolbar.bottomAnchor.constraint(equalTo: bottomLayoutGuide.topAnchor).isActive = true
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    @objc func toggleRecording(_ sender: AnyObject) {
        if recording {
            captureSessionCoordinator.stopRecording()
        }
        else {
            // Disable the idle timer while recording
            UIApplication.shared.isIdleTimerDisabled = true
            self.recordButton.isEnabled = false
            // re-enabled once recording has finished starting
            self.recordButton.title = "Stop"
            self.captureSessionCoordinator.startRecording()
            self.recording = true
        }
    }
    
    @objc func closeCamera(_ sender: AnyObject) {
        //TODO: tear down pipeline
        if recording {
            self.dismissing = true
            captureSessionCoordinator.stopRecording()
        }
        else {
            self.stopPipelineAndDismiss()
        }
    }
    
    func configureInterface() {
        let previewLayer: AVCaptureVideoPreviewLayer = captureSessionCoordinator.previewLayer
        previewLayer.frame = self.view.bounds
        self.view.layer.insertSublayer(previewLayer, at: 0)
        captureSessionCoordinator.startRunning()
    }
    
    func stopPipelineAndDismiss() {
        captureSessionCoordinator.stopRunning()
//        self.dismiss(animated: true, completion: { _ in })
        self.dismiss(animated: true) {
            
        }
        self.dismissing = false
    }
    
    func checkPermissions() {
        let pm: IDPermissionsManager = IDPermissionsManager()
        pm.checkCameraAuthorizationStatusWithBlock({(granted: Bool) -> Void in
            if !granted {
                print("we don't have permission to use the camera")
            }
        })
        pm.checkMicrophonePermissionsWithBlock({(granted: Bool) -> Void in
            if !granted {
                print("we don't have permission to use the microphone")
            }
        })
    }

    // MARK: = IDCaptureSessionCoordinatorDelegate methods
    
    func coordinatorDidBeginRecording(_ coordinator: IDCaptureSessionCoordinator) {
        self.recordButton.isEnabled = true
    }
    
    func coordinator(_ coordinator: IDCaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: URL, error: NSError?) {
        UIApplication.shared.isIdleTimerDisabled = false
        self.recordButton.title = "Record"
        self.recording = false
        //Do something useful with the video file available at the outputFileURL
        let fm: IDFileManager = IDFileManager()
        fm.copyFileToCameraRoll(outputFileURL)
        //Dismiss camera (when user taps cancel while camera is recording)
        if dismissing {
            self.stopPipelineAndDismiss()
        }
    }
}
