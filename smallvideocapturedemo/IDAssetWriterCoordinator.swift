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
    func writerCoordinatorDidFinishPreparing(_ coordinator: IDAssetWriterCoordinator)
    func writerCoordinator(_ coordinator: IDAssetWriterCoordinator, didFailWithError error: NSError?)
    func writerCoordinatorDidFinishRecording(_ coordinator: IDAssetWriterCoordinator)
}

// internal state machine
enum WriterStatus : Int {
    case idle = 0
    case preparingToRecord
    case recording
    case finishingRecordingPart1
    // waiting for inflight buffers to be appended
    case finishingRecordingPart2
    // calling finish writing on the asset writer
    case finished
    // terminal state
    case failed
    
    init() {
        self = .idle
    }
}

class IDAssetWriterCoordinator: NSObject {
    
    weak var delegate: IDAssetWriterCoordinatorDelegate?
    
    var URL: Foundation.URL!
    var writingQueue: DispatchQueue = DispatchQueue(label: "com.example.assetwriter.writing", attributes: [])
    var videoTrackTransform: CGAffineTransform! = CGAffineTransform(rotationAngle: CGFloat(M_PI_2)) //portrait orientation
    var status: WriterStatus = WriterStatus()
    var haveStartedSession: Bool = false
    
    var error: NSError?
    var delegateCallbackQueue: DispatchQueue!
    var assetWriter: AVAssetWriter!
    var audioTrackSourceFormatDescription: CMFormatDescription!
    var audioTrackSettings: [String: AnyObject]!
    var audioInput: AVAssetWriterInput!
    var videoTrackSourceFormatDescription: CMFormatDescription!
    var videoTrackSettings: [String : AnyObject]!
    var videoInput: AVAssetWriterInput!
    
    let lockQueue = DispatchQueue(label: "com.test.LockQueue", attributes: [])
    
    init(URL: Foundation.URL) {
        super.init()
        self.URL = URL
    }
    
    func addVideoTrackWithSourceFormatDescription(_ formatDescription: CMFormatDescription, settings videoSettings: [String : AnyObject]) {
        
        lockQueue.sync {
            if self.status != WriterStatus.idle {
                NSException(name: NSExceptionName.invalidArgumentException, reason: "Cannot add tracks while not idle", userInfo: nil).raise()
                return
            }

            self.videoTrackSourceFormatDescription = formatDescription
            self.videoTrackSettings = videoSettings
        }
    }
    
    func addAudioTrackWithSourceFormatDescription(_ formatDescription: CMFormatDescription, settings audioSettings: [String : AnyObject]) {
        
        lockQueue.sync {
            self.audioTrackSourceFormatDescription = formatDescription
            self.audioTrackSettings = audioSettings
        }
    }
    
    func setDelegate(_ delegate: IDAssetWriterCoordinatorDelegate, callbackQueue delegateCallbackQueue: DispatchQueue) {

        lockQueue.sync {
            self.delegate = delegate
            self.delegateCallbackQueue = delegateCallbackQueue
        }
    }
    
    func prepareToRecord(){
        print("prepareToRecord")
        lockQueue.sync {
            if self.status != WriterStatus.idle {
                NSException(name: NSExceptionName.internalInconsistencyException, reason: "Already prepared, cannot prepare again", userInfo: nil).raise()
                return
            }
            self.transitionToStatus(WriterStatus.preparingToRecord, error: nil)
        }
        
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.low).async(execute: {
            // AVAssetWriter will not write over an existing file.
            do {
                try FileManager.default.removeItem(at: self.URL)
            } catch _ {
                print(self.error?.localizedDescription)
            }
            
            do {
                self.assetWriter = try AVAssetWriter(outputURL: self.URL, fileType: AVFileType.mov)
            } catch _ {
                print(self.error?.localizedDescription)
            }
            
            // Create and add inputs
            if (self.error == nil) && (self.videoTrackSourceFormatDescription != nil) {
                if self.assetWriter.canApply(outputSettings: self.videoTrackSettings, forMediaType: AVMediaType.video) {
                    self.videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: self.videoTrackSettings, sourceFormatHint: self.videoTrackSourceFormatDescription)
                    self.videoInput.transform = self.videoTrackTransform
                    self.videoInput.expectsMediaDataInRealTime = true
                    if self.assetWriter.canAdd(self.videoInput) {
                        self.assetWriter.add(self.videoInput)
                    }
                }
            }
            if (self.error == nil) && (self.audioTrackSourceFormatDescription != nil) {
                if self.assetWriter.canApply(outputSettings: self.audioTrackSettings, forMediaType: AVMediaType.audio) {
                    self.audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: self.audioTrackSettings, sourceFormatHint: self.audioTrackSourceFormatDescription)
                    self.audioInput.expectsMediaDataInRealTime = true
                    if self.assetWriter.canAdd(self.audioInput) {
                        self.assetWriter.add(self.audioInput)
                    }
                }
            }
            if (self.error == nil) {
                let success: Bool = self.assetWriter.startWriting()
                if !success {
                    self.error = self.assetWriter.error as! NSError
                }
            }
            let lockQueue = DispatchQueue(label: "com.test.LockQueue", attributes: [])
            lockQueue.sync {
                if self.error != nil {
                    self.transitionToStatus(WriterStatus.failed, error: self.error!)
                }
                else {
                    self.transitionToStatus(WriterStatus.recording, error: nil)
                }
            }
        })
    }
    
    func finishRecording() {
        lockQueue.sync {
            var shouldFinishRecording: Bool = false
            switch self.status {
                case WriterStatus.idle, WriterStatus.preparingToRecord, WriterStatus.finishingRecordingPart1, WriterStatus.finishingRecordingPart2, WriterStatus.finished:
                    NSException(name: NSExceptionName.internalInconsistencyException, reason: "Not recording", userInfo: nil).raise()
                case WriterStatus.failed:
                    // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                    // Because of this we are lenient when finishRecording is called and we are in an error state.
                    print("Recording has failed, nothing to do")
                case WriterStatus.recording:
                    shouldFinishRecording = true
            }
            
            if shouldFinishRecording {
                self.transitionToStatus(WriterStatus.finishingRecordingPart1, error: nil)
            }
            else {
                return
            }
        }
        writingQueue.async(execute: {() -> Void in
            self.lockQueue.sync {
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                if self.status != WriterStatus.finishingRecordingPart1 {
                    return
                }
                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                self.transitionToStatus(WriterStatus.finishingRecordingPart2, error: nil)
            }
            self.assetWriter.finishWriting(completionHandler: {() -> Void in
                self.lockQueue.sync {
                    if let error =  self.assetWriter.error {
                        self.transitionToStatus(WriterStatus.failed, error: error as NSError)
                    }
                    else {
                        self.transitionToStatus(WriterStatus.finished, error: nil)
                    }
                }
            })
            
        })
    }
    
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        self.appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaType.video.rawValue)
    }
    
    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        self.appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaType.audio.rawValue)
    }
    
    // MARK: - Private methods
    
    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, ofMediaType mediaType: String) {
        lockQueue.sync {
            if self.status.rawValue < WriterStatus.recording.rawValue {
                NSException(name: NSExceptionName.internalInconsistencyException, reason: "Not ready to record yet", userInfo: nil).raise()
                return
            }
        }
        writingQueue.async(execute: {() -> Void in
            self.lockQueue.sync {
//                    // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
//                    // Because of this we are lenient when samples are appended and we are no longer recording.
//                    // Instead of throwing an exception we just release the sample buffers and return.
//                    if status > WriterStatus.FinishingRecordingPart1 {
//                        CFRelease(sampleBuffer)
//                        return
//                    }
            }
            if !self.haveStartedSession && mediaType == AVMediaType.video.rawValue {
                self.assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.haveStartedSession = true
            }
            let input: AVAssetWriterInput = (mediaType == AVMediaType.video.rawValue) ? self.videoInput : self.audioInput
            if input.isReadyForMoreMediaData {
                let success: Bool = input.append(sampleBuffer)
                if !success {
                    self.error = self.assetWriter.error as! NSError
                    let lockQueue = DispatchQueue(label: "com.test.LockQueue", attributes: [])
                    lockQueue.sync {
                        self.transitionToStatus(WriterStatus.failed, error: self.error)
                    }
                }
            }
            else {
                print("\(mediaType) input not ready for more media data, dropping buffer")
            }
        })
    }
    
    func transitionToStatus(_ newStatus: WriterStatus, error: NSError?) {
        var shouldNotifyDelegate: Bool = false
        if newStatus != status {
            // terminal states
            if (newStatus == WriterStatus.finished) || (newStatus == WriterStatus.failed) {
                shouldNotifyDelegate = true
                // make sure there are no more sample buffers in flight before we tear down the asset writer and inputs
                writingQueue.async(execute: {() -> Void in
                    self.assetWriter = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    if newStatus == WriterStatus.failed {
                        do {
                            try FileManager.default.removeItem(at: self.URL)
                        } catch _ {
                            print("NSFileManager.defaultManager().removeItemAtURL error: \(error?.localizedDescription)")
                        }
                    }
                })
            } else if newStatus == WriterStatus.recording {
                shouldNotifyDelegate = true
            }
            
            self.status = newStatus
        }
        
        if (shouldNotifyDelegate) {
            delegateCallbackQueue.async(execute: {() -> Void in
                switch newStatus {
                case WriterStatus.recording:
                    print("writerCoordinatorDidFinishPreparing")
                    self.delegate!.writerCoordinatorDidFinishPreparing(self)
                case WriterStatus.finished:
                    print("writerCoordinatorDidFinishRecording")
                    self.delegate!.writerCoordinatorDidFinishRecording(self)
                case WriterStatus.failed:
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

}
