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
    case idle = 0
    case startingRecording
    case recording
    case stoppingRecording
    
    init() {
        self = .idle
    }
}

class IDCaptureSessionAssetWriterCoordinator: IDCaptureSessionCoordinator, IDAssetWriterCoordinatorDelegate,  AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    var videoDataOutputQueue: DispatchQueue = DispatchQueue(label: "com.example.capturesession.videodata", attributes: [])
    var audioDataOutputQueue: DispatchQueue = DispatchQueue(label: "com.example.capturesession.audiodata", attributes: [])
    var recordingStatus: RecordingStatus = RecordingStatus()
    
    var assetWriterCoordinator: IDAssetWriterCoordinator!
    var outputVideoFormatDescription: CMFormatDescription!
    var outputAudioFormatDescription: CMFormatDescription!
    var recordingURL: URL!
    
    fileprivate var videoDataOutput: AVCaptureVideoDataOutput!
    fileprivate var audioDataOutput: AVCaptureAudioDataOutput!
    fileprivate var audioConnection: AVCaptureConnection!
    fileprivate var videoConnection: AVCaptureConnection!
    fileprivate var videoCompressionSettings: [String : AnyObject]!
    fileprivate var audioCompressionSettings: [String : AnyObject]!
    
    fileprivate let lockQueue = DispatchQueue(label: "com.test.LockQueue", attributes: [])
    
    override init() {
        super.init()
        
//        videoDataOutputQueue.setTarget(queue: DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.high))
        self.addDataOutputsToCaptureSession(self.captureSession)
    }
    
    // MARK: - Recording
    override func startRecording() {
        print("startRecording")
        lockQueue.sync {
            if self.recordingStatus != RecordingStatus.idle {
                NSException(name: NSExceptionName.internalInconsistencyException, reason: "Already recording", userInfo: nil).raise()
                return
            }
            self.transitionToRecordingStatus(RecordingStatus.startingRecording, error: nil)
        }
        let fm: IDFileManager = IDFileManager()
        self.recordingURL = fm.tempFileURL() as URL!
        self.assetWriterCoordinator = IDAssetWriterCoordinator(URL: recordingURL as URL)
        if outputAudioFormatDescription != nil {
            assetWriterCoordinator.addAudioTrackWithSourceFormatDescription(self.outputAudioFormatDescription, settings: audioCompressionSettings)
        }
        assetWriterCoordinator.addVideoTrackWithSourceFormatDescription(self.outputVideoFormatDescription, settings: videoCompressionSettings)
        let callbackQueue: DispatchQueue = DispatchQueue(label: "com.example.capturesession.writercallback", attributes: [])

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
        lockQueue.sync {
            if self.recordingStatus != RecordingStatus.recording {
                return
            }
            self.transitionToRecordingStatus(RecordingStatus.stoppingRecording, error: nil)
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
    
    func addDataOutputsToCaptureSession(_ captureSession: AVCaptureSession) {
        self.videoDataOutput = AVCaptureVideoDataOutput()
        self.videoDataOutput.videoSettings = nil
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = false
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        self.audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
        self.addOutput(videoDataOutput, toCaptureSession: self.captureSession)
        self.videoConnection = videoDataOutput.connection(with: AVMediaType.video)
        self.addOutput(audioDataOutput, toCaptureSession: self.captureSession)
        self.audioConnection = audioDataOutput.connection(with: AVMediaType.audio)
        self.setCompressionSettings()
    }

    func setCompressionSettings() {
        self.videoCompressionSettings = videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: AVFileType.mov)! as [String: AnyObject]
        self.audioCompressionSettings = audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: AVFileType.mov) as! [String: AnyObject]
    }
    
    func setupVideoPipelineWithInputFormatDescription(_ inputFormatDescription: CMFormatDescription) {
        self.outputVideoFormatDescription = inputFormatDescription
    }
    
    // MARK: - SampleBufferDelegate methods
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let formatDescription: CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
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
                lockQueue.sync {
                    if self.recordingStatus == RecordingStatus.recording {
                        self.assetWriterCoordinator.appendVideoSampleBuffer(sampleBuffer)
                    }
                }
            }
        }
        else if connection == audioConnection {
            self.outputAudioFormatDescription = formatDescription
            lockQueue.sync {
                if self.recordingStatus == RecordingStatus.recording {
                    self.assetWriterCoordinator.appendAudioSampleBuffer(sampleBuffer)
                }
            }
        }
        
    }
    
    // MARK: - IDAssetWriterCoordinatorDelegate methods
    func writerCoordinatorDidFinishPreparing(_ coordinator: IDAssetWriterCoordinator) {
        
        lockQueue.sync {
            if self.recordingStatus != RecordingStatus.startingRecording {
                NSException(name: NSExceptionName.internalInconsistencyException, reason: "Expected to be in StartingRecording state", userInfo: nil).raise()
                return
            }
            self.transitionToRecordingStatus(RecordingStatus.recording, error: nil)
        }
    }
    
    func writerCoordinator(_ recorder: IDAssetWriterCoordinator, didFailWithError error: NSError?) {
        lockQueue.sync {
            self.assetWriterCoordinator = nil
            self.transitionToRecordingStatus(RecordingStatus.idle, error: error)
        }
    }
    
    func writerCoordinatorDidFinishRecording(_ coordinator: IDAssetWriterCoordinator) {
        lockQueue.sync {
            if self.recordingStatus != RecordingStatus.stoppingRecording {
                NSException(name: NSExceptionName.internalInconsistencyException, reason: "Expected to be in StoppingRecording state", userInfo: nil).raise()
                return
            }
            // No state transition, we are still in the process of stopping.
            // We will be stopped once we save to the assets library.
        }
        self.assetWriterCoordinator = nil
        lockQueue.sync {
            self.transitionToRecordingStatus(RecordingStatus.idle, error: nil)
        }
    }

    // MARK: - Recording State Machine
    
    func transitionToRecordingStatus(_ newStatus: RecordingStatus, error: NSError?) {
        print("transition status")
        let oldStatus: RecordingStatus = recordingStatus
        self.recordingStatus = newStatus
        if newStatus != oldStatus {
            if error != nil && (newStatus == RecordingStatus.idle) {
                self.delegateCallbackQueue!.async(execute: {() -> Void in
                    self.delegate!.coordinator(self, didFinishRecordingToOutputFileURL: self.recordingURL, error: nil)
                })
            }
            else {
                // only the above delegate method takes an error
                if oldStatus == RecordingStatus.startingRecording && newStatus == RecordingStatus.recording {
                    self.delegateCallbackQueue!.async(execute: {() -> Void in
                        self.delegate!.coordinatorDidBeginRecording(self)
                    })
                }
                else if oldStatus == RecordingStatus.stoppingRecording && newStatus == RecordingStatus.idle {
                    self.delegateCallbackQueue!.async(execute: {() -> Void in
                        self.delegate!.coordinator(self, didFinishRecordingToOutputFileURL: self.recordingURL, error: nil)
                    })
                }
            }
        }
    }
    
}
