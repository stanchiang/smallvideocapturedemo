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
    @IBOutlet var recordButton: UIBarButtonItem!
    var recording: Bool = false
    var dismissing: Bool = false
    
    override func viewDidLoad() {
        
        self.checkPermissions()
        captureSessionCoordinator.setDelegate(self, callbackQueue: dispatch_get_main_queue())
        self.configureInterface()
    }

    @IBAction func toggleRecording(sender: AnyObject) {
        if recording {
            captureSessionCoordinator.stopRecording()
        }
        else {
            // Disable the idle timer while recording
            UIApplication.sharedApplication().idleTimerDisabled = true
            self.recordButton.enabled = false
            // re-enabled once recording has finished starting
            self.recordButton.title = "Stop"
            self.captureSessionCoordinator.startRecording()
            self.recording = true
        }
    }
    
    @IBAction func closeCamera(sender: AnyObject) {
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
        self.view.layer.insertSublayer(previewLayer, atIndex: 0)
        captureSessionCoordinator.startRunning()
    }
    
    func stopPipelineAndDismiss() {
        captureSessionCoordinator.stopRunning()
        self.dismissViewControllerAnimated(true, completion: { _ in })
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
    
    func coordinatorDidBeginRecording(coordinator: IDCaptureSessionCoordinator) {
        self.recordButton.enabled = true
    }
    
    func coordinator(coordinator: IDCaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: NSURL, error: NSError?) {
        UIApplication.sharedApplication().idleTimerDisabled = false
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
