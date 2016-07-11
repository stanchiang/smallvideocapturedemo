//
//  IDCameraPermissionsManager.h
//  VideoCameraDemo
//
//  Created by Adriaan Stellingwerff on 10/03/2014.
//  Copyright (c) 2014 Infoding. All rights reserved.
//
import AVFoundation
import UIKit

class IDPermissionsManager: NSObject, UIAlertViewDelegate {
    func checkMicrophonePermissionsWithBlock(block: (granted: Bool) -> Void) {
        let mediaType: String = AVMediaTypeAudio
        AVCaptureDevice.requestAccessForMediaType(mediaType, completionHandler: {(granted: Bool) -> Void in
            if !granted {
                dispatch_async(dispatch_get_main_queue(), {() -> Void in
                    let alert: UIAlertView = UIAlertView(title: "Microphone Disabled", message: "To enable sound recording with your video please go to the Settings app > Privacy > Microphone and enable access.", delegate: self, cancelButtonTitle: "OK", otherButtonTitles: "Settings")
                    alert.delegate = self
                    alert.show()
                })
            }
            block(granted: granted)
        })
    }

    func checkCameraAuthorizationStatusWithBlock(block: (granted: Bool) -> Void) {
        let mediaType: String = AVMediaTypeVideo
        AVCaptureDevice.requestAccessForMediaType(mediaType, completionHandler: {(granted: Bool) -> Void in
            if !granted {
                //Not granted access to mediaType
                dispatch_async(dispatch_get_main_queue(), {() -> Void in
                    let alert: UIAlertView = UIAlertView(title: "Camera disabled", message: "This app doesn't have permission to use the camera, please go to the Settings app > Privacy > Camera and enable access.", delegate: self, cancelButtonTitle: "OK", otherButtonTitles: "Settings")
                    alert.delegate = self
                    alert.show()
                })
            }
            block(granted: granted)
        })
    }

// MARK: - UIAlertViewDelegate methods

    func alertView(alertView: UIAlertView, clickedButtonAtIndex buttonIndex: Int) {
        if buttonIndex == 1 {
            UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
        }
    }
}
