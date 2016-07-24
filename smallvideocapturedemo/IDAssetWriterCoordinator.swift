//
//  IDAssetWriterCoordinator.swift
//  smallvideocapturedemo
//
//  Created by Stanley Chiang on 7/11/16.
//  Copyright © 2016 Stanley Chiang. All rights reserved.
//

import Foundation
import CoreMedia
import AVFoundation

protocol IDAssetWriterCoordinatorDelegate: class {
    func writerCoordinatorDidFinishPreparing(coordinator: IDAssetWriterCoordinator)
    func writerCoordinator(coordinator: IDAssetWriterCoordinator, didFailWithError error: NSError?)
    func writerCoordinatorDidFinishRecording(coordinator: IDAssetWriterCoordinator)
}

// internal state machine
enum WriterStatus : Int {
    case Idle = 0
    case PreparingToRecord
    case Recording
    case FinishingRecordingPart1
    // waiting for inflight buffers to be appended
    case FinishingRecordingPart2
    // calling finish writing on the asset writer
    case Finished
    // terminal state
    case Failed
    
    init() {
        self = .Idle
    }
}

class IDAssetWriterCoordinator: NSObject {
    
    weak var delegate: IDAssetWriterCoordinatorDelegate?
    
    var URL: NSURL!
    var writingQueue: dispatch_queue_t = dispatch_queue_create("com.example.assetwriter.writing", DISPATCH_QUEUE_SERIAL)
    var videoTrackTransform: CGAffineTransform! = CGAffineTransformMakeRotation(CGFloat(M_PI_2)) //portrait orientation
    var status: WriterStatus = WriterStatus()
    var haveStartedSession: Bool = false
    
    var error: NSError?
    var delegateCallbackQueue: dispatch_queue_t!
    var assetWriter: AVAssetWriter!
    var audioTrackSourceFormatDescription: CMFormatDescriptionRef!
    var audioTrackSettings: [String: AnyObject]!
    var audioInput: AVAssetWriterInput!
    var videoTrackSourceFormatDescription: CMFormatDescriptionRef!
    var videoTrackSettings: [String : AnyObject]!
    var videoInput: AVAssetWriterInput!
    
    let lockQueue = dispatch_queue_create("com.test.LockQueue", nil)
    
    init(URL: NSURL) {
        super.init()
        self.URL = URL
    }
    
    func addVideoTrackWithSourceFormatDescription(formatDescription: CMFormatDescriptionRef, settings videoSettings: [String : AnyObject]) {
        
        dispatch_sync(lockQueue) {
            if self.status != WriterStatus.Idle {
                NSException(name: NSInvalidArgumentException, reason: "Cannot add tracks while not idle", userInfo: nil).raise()
                return
            }

            self.videoTrackSourceFormatDescription = formatDescription
            self.videoTrackSettings = videoSettings
        }
    }
    
    func addAudioTrackWithSourceFormatDescription(formatDescription: CMFormatDescriptionRef, settings audioSettings: [String : AnyObject]) {
        
        dispatch_sync(lockQueue) {
            self.audioTrackSourceFormatDescription = formatDescription
            self.audioTrackSettings = audioSettings
        }
    }
    
    func setDelegate(delegate: IDAssetWriterCoordinatorDelegate, callbackQueue delegateCallbackQueue: dispatch_queue_t) {

        dispatch_sync(lockQueue) {
            self.delegate = delegate
            self.delegateCallbackQueue = delegateCallbackQueue
        }
    }
    
    func prepareToRecord(){
        print("prepareToRecord")
        dispatch_sync(lockQueue) {
            if self.status != WriterStatus.Idle {
                NSException(name: NSInternalInconsistencyException, reason: "Already prepared, cannot prepare again", userInfo: nil).raise()
                return
            }
            self.transitionToStatus(WriterStatus.PreparingToRecord, error: nil)
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), {
            // AVAssetWriter will not write over an existing file.
            do {
                try NSFileManager.defaultManager().removeItemAtURL(self.URL)
            } catch _ {
                print(self.error?.localizedDescription)
            }
            
            do {
                self.assetWriter = try AVAssetWriter(URL: self.URL, fileType: AVFileTypeQuickTimeMovie)
            } catch _ {
                print(self.error?.localizedDescription)
            }
            
            // Create and add inputs
            if (self.error == nil) && (self.videoTrackSourceFormatDescription != nil) {
                if self.assetWriter.canApplyOutputSettings(self.videoTrackSettings, forMediaType: AVMediaTypeVideo) {
                    self.videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: self.videoTrackSettings, sourceFormatHint: self.videoTrackSourceFormatDescription)
                    self.videoInput.transform = self.videoTrackTransform
                    self.videoInput.expectsMediaDataInRealTime = true
                    if self.assetWriter.canAddInput(self.videoInput) {
                        self.assetWriter.addInput(self.videoInput)
                    }
                }
            }
            if (self.error == nil) && (self.audioTrackSourceFormatDescription != nil) {
                if self.assetWriter.canApplyOutputSettings(self.audioTrackSettings, forMediaType: AVMediaTypeAudio) {
                    self.audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: self.audioTrackSettings, sourceFormatHint: self.audioTrackSourceFormatDescription)
                    self.audioInput.expectsMediaDataInRealTime = true
                    if self.assetWriter.canAddInput(self.audioInput) {
                        self.assetWriter.addInput(self.audioInput)
                    }
                }
            }
            if (self.error == nil) {
                let success: Bool = self.assetWriter.startWriting()
                if !success {
                    self.error = self.assetWriter.error
                }
            }
            dispatch_sync(self.lockQueue) {
                if self.error != nil {
                    self.transitionToStatus(WriterStatus.Failed, error: self.error!)
                }
                else {
                    self.transitionToStatus(WriterStatus.Recording, error: nil)
                }
            }
        })
    }
    
    func finishRecording() {
        dispatch_sync(lockQueue) {
            var shouldFinishRecording: Bool = false
            switch self.status {
                case WriterStatus.Idle, WriterStatus.PreparingToRecord, WriterStatus.FinishingRecordingPart1, WriterStatus.FinishingRecordingPart2, WriterStatus.Finished:
                    NSException(name: NSInternalInconsistencyException, reason: "Not recording", userInfo: nil).raise()
                case WriterStatus.Failed:
                    // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                    // Because of this we are lenient when finishRecording is called and we are in an error state.
                    print("Recording has failed, nothing to do")
                case WriterStatus.Recording:
                    shouldFinishRecording = true
            }
            
            if shouldFinishRecording {
                self.transitionToStatus(WriterStatus.FinishingRecordingPart1, error: nil)
            }
            else {
                return
            }
        }
        dispatch_async(writingQueue, {() -> Void in
            dispatch_sync(self.lockQueue) {
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                if self.status != WriterStatus.FinishingRecordingPart1 {
                    return
                }
                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                self.transitionToStatus(WriterStatus.FinishingRecordingPart2, error: nil)
            }
            self.assetWriter.finishWritingWithCompletionHandler({() -> Void in
                dispatch_sync(self.lockQueue) {
                    let error: NSError? = self.assetWriter.error
                    if error != nil {
                        self.transitionToStatus(WriterStatus.Failed, error: error)
                    }
                    else {
                        self.transitionToStatus(WriterStatus.Finished, error: nil)
                    }
                }
            })
            
        })
    }
    
    func appendVideoSampleBuffer(sampleBuffer: CMSampleBufferRef) {
        self.appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaTypeVideo)
    }
    
    func appendAudioSampleBuffer(sampleBuffer: CMSampleBufferRef) {
        self.appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaTypeAudio)
    }
    
    // MARK: - Private methods
    
    func appendSampleBuffer(sampleBuffer: CMSampleBufferRef, ofMediaType mediaType: String) {
        dispatch_sync(lockQueue) {
            if self.status.rawValue < WriterStatus.Recording.rawValue {
                NSException(name: NSInternalInconsistencyException, reason: "Not ready to record yet", userInfo: nil).raise()
                return
            }
        }
        dispatch_async(writingQueue, {() -> Void in
            if !self.haveStartedSession && mediaType == AVMediaTypeVideo {
                self.assetWriter.startSessionAtSourceTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.haveStartedSession = true
            }
            
            let input: AVAssetWriterInput = (mediaType == AVMediaTypeVideo) ? self.videoInput : self.audioInput
            if input.readyForMoreMediaData {
                
                //1. apply opencv processing to samplebuffer video frame
                let newBufferRef = self.applyOpenCV(sampleBuffer)
                
                
                //2. append processed video frame to receiver
                let successful: Bool = input.appendSampleBuffer(sampleBuffer)
                if !successful {
                    self.error = self.assetWriter.error
                    dispatch_sync(self.lockQueue) {
                        self.transitionToStatus(WriterStatus.Failed, error: self.error)
                    }
                }
                
                //encode videos to mp4 or ts in 5 second chunks to server
                if successful && CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds > 5.0 {
                    
                }
                
            }else {
                print("\(mediaType) input not ready for more media data, dropping buffer")
            }
        })
    }
    
    func transitionToStatus(newStatus: WriterStatus, error: NSError?) {
        var shouldNotifyDelegate: Bool = false
        if newStatus != status {
            // terminal states
            if (newStatus == WriterStatus.Finished) || (newStatus == WriterStatus.Failed) {
                shouldNotifyDelegate = true
                // make sure there are no more sample buffers in flight before we tear down the asset writer and inputs
                dispatch_async(writingQueue, {() -> Void in
                    self.assetWriter = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    if newStatus == WriterStatus.Failed {
                        do {
                            try NSFileManager.defaultManager().removeItemAtURL(self.URL)
                        } catch _ {
                            print("NSFileManager.defaultManager().removeItemAtURL error: \(error?.localizedDescription)")
                        }
                    }
                })
            } else if newStatus == WriterStatus.Recording {
                shouldNotifyDelegate = true
            }
            
            self.status = newStatus
        }
        
        if (shouldNotifyDelegate) {
            dispatch_async(delegateCallbackQueue, {() -> Void in
                switch newStatus {
                case WriterStatus.Recording:
                    print("writerCoordinatorDidFinishPreparing")
                    self.delegate!.writerCoordinatorDidFinishPreparing(self)
                case WriterStatus.Finished:
                    print("writerCoordinatorDidFinishRecording")
                    self.delegate!.writerCoordinatorDidFinishRecording(self)
                case WriterStatus.Failed:
                    print("writerCoordinator")
                    self.delegate!.writerCoordinator(self, didFailWithError: error)
                default:
                    break
                }
            })
        } else {
            print("skipping delegatecallbackqueue")
        }
    }

    func applyOpenCV(sampleBuffer: CMSampleBufferRef){
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
    }
}
