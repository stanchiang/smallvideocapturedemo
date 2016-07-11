//
//  IDCaptureSessionCoordinator.swift
//  smallvideocapturedemo
//
//  Created by Stanley Chiang on 7/10/16.
//  Copyright © 2016 Stanley Chiang. All rights reserved.
//

import Foundation
import AVFoundation

protocol IDCaptureSessionCoordinatorDelegate: class {
    func coordinatorDidBeginRecording(coordinator: IDCaptureSessionCoordinator)
    func coordinator(coordinator: IDCaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: NSURL, error: NSError?)
}

class IDCaptureSessionCoordinator: NSObject {
    
    weak var delegate: IDCaptureSessionCoordinatorDelegate?
    var sessionQueue: dispatch_queue_t = dispatch_queue_create("com.example.capturepipeline.session", DISPATCH_QUEUE_SERIAL)
    
    var delegateCallbackQueue: dispatch_queue_t?
    var previewLayer: AVCaptureVideoPreviewLayer!
    var captureSession: AVCaptureSession!
    var cameraDevice: AVCaptureDevice!
    var error:NSError?
    
    override init() {
        super.init()
        self.captureSession = self.setupCaptureSession()
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    }
    
    func setDelegate(delegate: IDCaptureSessionCoordinatorDelegate, callbackQueue delegateCallbackQueue: dispatch_queue_t) {
        let lockQueue = dispatch_queue_create("com.test.LockQueue", nil)
        dispatch_sync(lockQueue) {
            self.delegate = delegate
            self.delegateCallbackQueue = delegateCallbackQueue
        }
    }
    
    func startRunning() {
        dispatch_sync(sessionQueue, {() -> Void in
            self.captureSession.startRunning()
        })
    }
    
    func stopRunning() {
        dispatch_sync(sessionQueue, {() -> Void in
            // the captureSessionDidStopRunning method will stop recording if necessary as well, but we do it here so that the last video and audio samples are better aligned
            self.stopRecording()
            // does nothing if we aren't currently recording
            self.captureSession.stopRunning()
        })
    }
    
    func startRecording() {
//        print("start Recording super class")
    }
    
    func stopRecording() {
//        print("stop Recording super class")
    }
    
    func addInput(input: AVCaptureDeviceInput, toCaptureSession captureSession: AVCaptureSession) -> Bool {
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            return true
        }
        else {
            print("can't add input: \(input.description)")
            return false
        }
    }
    
    func addOutput(output: AVCaptureOutput, toCaptureSession captureSession: AVCaptureSession) -> Bool {
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            return true
        }
        else {
            print("can't add output: \(output.description)")
            return false
        }
        
    }
    
    // MARK: - Capture Session Setup
    
    func setupCaptureSession() -> AVCaptureSession {
        let captureSession: AVCaptureSession = AVCaptureSession()
        if !self.addDefaultCameraInputToCaptureSession(captureSession) {
            print("failed to add camera input to capture session")
        }
        if !self.addDefaultMicInputToCaptureSession(captureSession) {
            print("failed to add mic input to capture session")
        }
        return captureSession
    }
    
    func addDefaultCameraInputToCaptureSession(captureSession: AVCaptureSession) -> Bool {
        let cameraDeviceInput: AVCaptureDeviceInput!
        do {
            cameraDeviceInput = try AVCaptureDeviceInput(device: AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo))
            let success: Bool = self.addInput(cameraDeviceInput, toCaptureSession: captureSession)
            self.cameraDevice = cameraDeviceInput.device
            return success
        } catch _ {
            print("error configuring camera input: \(error?.localizedDescription)")
            return false
        }
    }
    
    func addDefaultMicInputToCaptureSession(captureSession: AVCaptureSession) -> Bool {
        let micDeviceInput: AVCaptureDeviceInput
        
        do {
            micDeviceInput = try AVCaptureDeviceInput(device: AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio))
            let success: Bool = self.addInput(micDeviceInput, toCaptureSession: captureSession)
            return success
        } catch _ {
            print("error configuring mic input: \(error?.localizedDescription)")
            return false
        }
        
    }
    

}
