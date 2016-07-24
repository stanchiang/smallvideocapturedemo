//
//  IDCaptureSessionAssetWriterCoordinator.swift
//  smallvideocapturedemo
//
//  Created by Stanley Chiang on 7/10/16.
//  Copyright © 2016 Stanley Chiang. All rights reserved.
//

import AVFoundation
import MobileCoreServices

// internal state machine
enum RecordingStatus : Int {
    case Idle = 0
    case StartingRecording
    case Recording
    case StoppingRecording
    
    init() {
        self = .Idle
    }
}

class IDCaptureSessionAssetWriterCoordinator: IDCaptureSessionCoordinator, IDAssetWriterCoordinatorDelegate,  AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    var videoDataOutputQueue: dispatch_queue_t = dispatch_queue_create("com.example.capturesession.videodata", DISPATCH_QUEUE_SERIAL)
    var audioDataOutputQueue: dispatch_queue_t = dispatch_queue_create("com.example.capturesession.audiodata", DISPATCH_QUEUE_SERIAL)
    var recordingStatus: RecordingStatus = RecordingStatus()
    
    var assetWriterCoordinator: IDAssetWriterCoordinator!
    var outputVideoFormatDescription: CMFormatDescriptionRef!
    var outputAudioFormatDescription: CMFormatDescriptionRef!
    var recordingURL: NSURL!
    
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var audioDataOutput: AVCaptureAudioDataOutput!
    private var audioConnection: AVCaptureConnection!
    private var videoConnection: AVCaptureConnection!
    private var videoCompressionSettings: [String : AnyObject]!
    private var audioCompressionSettings: [String : AnyObject]!
    
    private let lockQueue = dispatch_queue_create("com.test.LockQueue", nil)
    
    override init() {
        super.init()
        
        dispatch_set_target_queue(videoDataOutputQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))
        self.addDataOutputsToCaptureSession(self.captureSession)
    }
    
    // MARK: - Recording
    override func startRecording() {
        print("startRecording")
        dispatch_sync(lockQueue) {
            if self.recordingStatus != RecordingStatus.Idle {
                NSException(name: NSInternalInconsistencyException, reason: "Already recording", userInfo: nil).raise()
                return
            }
            self.transitionToRecordingStatus(RecordingStatus.StartingRecording, error: nil)
        }
        let fm: IDFileManager = IDFileManager()
        self.recordingURL = fm.tempFileURL()
        self.assetWriterCoordinator = IDAssetWriterCoordinator(URL: recordingURL)
        if outputAudioFormatDescription != nil {
            assetWriterCoordinator.addAudioTrackWithSourceFormatDescription(self.outputAudioFormatDescription, settings: audioCompressionSettings)
        }
        assetWriterCoordinator.addVideoTrackWithSourceFormatDescription(self.outputVideoFormatDescription, settings: videoCompressionSettings)
        let callbackQueue: dispatch_queue_t = dispatch_queue_create("com.example.capturesession.writercallback", DISPATCH_QUEUE_SERIAL)

        // guarantee ordering of callbacks with a serial queue
        assetWriterCoordinator.setDelegate(self, callbackQueue: callbackQueue)
        assetWriterCoordinator.prepareToRecord()
        // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done

        if let _ = self.assetWriterCoordinator {
            print("startRecording: i got my trusty assetWriterCoordinator")
        } else {
            print("startRecording: where are the assetWriterCoordinators of yesteryear?")
        }

    }
    
    override func stopRecording() {
        print("stoprecording")
        dispatch_sync(lockQueue) {
            if self.recordingStatus != RecordingStatus.Recording {
                return
            }
            self.transitionToRecordingStatus(RecordingStatus.StoppingRecording, error: nil)
        }

        if let _ = self.assetWriterCoordinator {
            print("stoprecording: i got my trusty assetWriterCoordinator")
            self.assetWriterCoordinator.finishRecording()
        } else {
            print("stoprecording: where are the assetWriterCoordinators of yesteryear?")
        }
        
        // asynchronous, will call us back with
    }
    
    // MARK: - Private methods
    
    func addDataOutputsToCaptureSession(captureSession: AVCaptureSession) {
        self.videoDataOutput = AVCaptureVideoDataOutput()
        self.videoDataOutput.videoSettings = nil
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = false
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        self.audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
        self.addOutput(videoDataOutput, toCaptureSession: self.captureSession)
        self.videoConnection = videoDataOutput.connectionWithMediaType(AVMediaTypeVideo)
        self.addOutput(audioDataOutput, toCaptureSession: self.captureSession)
        self.audioConnection = audioDataOutput.connectionWithMediaType(AVMediaTypeAudio)
        self.setCompressionSettings()
    }

    func setCompressionSettings() {
        self.videoCompressionSettings = videoDataOutput.recommendedVideoSettingsForAssetWriterWithOutputFileType(AVFileTypeQuickTimeMovie) as! [String: AnyObject]
        self.audioCompressionSettings = audioDataOutput.recommendedAudioSettingsForAssetWriterWithOutputFileType(AVFileTypeQuickTimeMovie) as! [String: AnyObject]
    }
    
    func setupVideoPipelineWithInputFormatDescription(inputFormatDescription: CMFormatDescriptionRef) {
        self.outputVideoFormatDescription = inputFormatDescription
    }
    
    // MARK: - SampleBufferDelegate methods
    func captureOutput(captureOutput: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, fromConnection connection: AVCaptureConnection) {
        
        let formatDescription: CMFormatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer)!
        if connection == videoConnection {
            if self.outputVideoFormatDescription == nil {
                // Don't render the first sample buffer.
                // This gives us one frame interval (33ms at 30fps) for setupVideoPipelineWithInputFormatDescription: to complete.
                // Ideally this would be done asynchronously to ensure frames don't back up on slower devices.
                //TODO: outputVideoFormatDescription should be updated whenever video configuration is changed (frame rate, etc.)
                //Currently we don't use the outputVideoFormatDescription in IDAssetWriterRecoredSession
                self.setupVideoPipelineWithInputFormatDescription(formatDescription)
            }
            else {
                self.outputVideoFormatDescription = formatDescription
                dispatch_sync(lockQueue) {
                    if self.recordingStatus == RecordingStatus.Recording {
                        self.assetWriterCoordinator.appendVideoSampleBuffer(sampleBuffer)
                    }
                }
            }
        }
        else if connection == audioConnection {
            self.outputAudioFormatDescription = formatDescription
            dispatch_sync(lockQueue) {
                if self.recordingStatus == RecordingStatus.Recording {
                    self.assetWriterCoordinator.appendAudioSampleBuffer(sampleBuffer)
                }
            }
        }
        
    }
    
    // MARK: - IDAssetWriterCoordinatorDelegate methods
    func writerCoordinatorDidFinishPreparing(coordinator: IDAssetWriterCoordinator) {
        
        dispatch_sync(lockQueue) {
            if self.recordingStatus != RecordingStatus.StartingRecording {
                NSException(name: NSInternalInconsistencyException, reason: "Expected to be in StartingRecording state", userInfo: nil).raise()
                return
            }
            self.transitionToRecordingStatus(RecordingStatus.Recording, error: nil)
        }
    }
    
    func writerCoordinator(recorder: IDAssetWriterCoordinator, didFailWithError error: NSError?) {
        dispatch_sync(lockQueue) {
            self.assetWriterCoordinator = nil
            self.transitionToRecordingStatus(RecordingStatus.Idle, error: error)
        }
    }
    
    func writerCoordinatorDidFinishRecording(coordinator: IDAssetWriterCoordinator) {
        dispatch_sync(lockQueue) {
            if self.recordingStatus != RecordingStatus.StoppingRecording {
                NSException(name: NSInternalInconsistencyException, reason: "Expected to be in StoppingRecording state", userInfo: nil).raise()
                return
            }
            // No state transition, we are still in the process of stopping.
            // We will be stopped once we save to the assets library.
        }
        self.assetWriterCoordinator = nil
        dispatch_sync(lockQueue) {
            self.transitionToRecordingStatus(RecordingStatus.Idle, error: nil)
        }
    }

    // MARK: - Recording State Machine
    
    func transitionToRecordingStatus(newStatus: RecordingStatus, error: NSError?) {
        print("transition status")
        let oldStatus: RecordingStatus = recordingStatus
        self.recordingStatus = newStatus
        if newStatus != oldStatus {
            if error != nil && (newStatus == RecordingStatus.Idle) {
                dispatch_async(self.delegateCallbackQueue!, {() -> Void in
                    self.delegate!.coordinator(self, didFinishRecordingToOutputFileURL: self.recordingURL, error: nil)
                })
            }
            else {
                // only the above delegate method takes an error
                if oldStatus == RecordingStatus.StartingRecording && newStatus == RecordingStatus.Recording {
                    dispatch_async(self.delegateCallbackQueue!, {() -> Void in
                        self.delegate!.coordinatorDidBeginRecording(self)
                    })
                }
                else if oldStatus == RecordingStatus.StoppingRecording && newStatus == RecordingStatus.Idle {
                    dispatch_async(self.delegateCallbackQueue!, {() -> Void in
                        self.delegate!.coordinator(self, didFinishRecordingToOutputFileURL: self.recordingURL, error: nil)
                    })
                }
            }
        }
    }
    
}
