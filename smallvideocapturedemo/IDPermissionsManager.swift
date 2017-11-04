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
    func checkMicrophonePermissionsWithBlock(_ block: @escaping (_ granted: Bool) -> Void) {
        let mediaType: String = AVMediaType.audio.rawValue
        AVCaptureDevice.requestAccess(for: AVMediaType(rawValue: mediaType), completionHandler: {(granted: Bool) -> Void in
            if !granted {
                DispatchQueue.main.async(execute: {() -> Void in
                    let alert: UIAlertView = UIAlertView(title: "Microphone Disabled", message: "To enable sound recording with your video please go to the Settings app > Privacy > Microphone and enable access.", delegate: self, cancelButtonTitle: "OK", otherButtonTitles: "Settings")
                    alert.delegate = self
                    alert.show()
                })
            }
            block(granted)
        })
    }

    func checkCameraAuthorizationStatusWithBlock(_ block: @escaping (_ granted: Bool) -> Void) {
        let mediaType: String = AVMediaType.video.rawValue
        AVCaptureDevice.requestAccess(for: AVMediaType(rawValue: mediaType), completionHandler: {(granted: Bool) -> Void in
            if !granted {
                //Not granted access to mediaType
                DispatchQueue.main.async(execute: {() -> Void in
                    let alert: UIAlertView = UIAlertView(title: "Camera disabled", message: "This app doesn't have permission to use the camera, please go to the Settings app > Privacy > Camera and enable access.", delegate: self, cancelButtonTitle: "OK", otherButtonTitles: "Settings")
                    alert.delegate = self
                    alert.show()
                })
            }
            block(granted)
        })
    }

// MARK: - UIAlertViewDelegate methods

    func alertView(_ alertView: UIAlertView, clickedButtonAt buttonIndex: Int) {
        if buttonIndex == 1 {
            UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
        }
    }
}
