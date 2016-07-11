//
//  IDFileManager.h
//  VideoCaptureDemo
//
//  Created by Adriaan Stellingwerff on 9/04/2015.
//  Copyright (c) 2015 Infoding. All rights reserved.
//
import Foundation
class IDFileManager: NSObject {
    
    var error:NSError?
    
    func tempFileURL() -> NSURL {
        var path: String? = nil
        let fm: NSFileManager = NSFileManager.defaultManager()
        var i: Int = 0
        while path == nil || fm.fileExistsAtPath(path!) {
            path = "\(NSTemporaryDirectory())\(Int(i)).mov"
            i += 1
        }
        return NSURL.fileURLWithPath(path!)
    }

    func removeFile(fileURL: NSURL) {
        let filePath: String = fileURL.path!
        let fileManager: NSFileManager = NSFileManager.defaultManager()
        if fileManager.fileExistsAtPath(filePath) {
            do {
                try fileManager.removeItemAtPath(filePath)
            } catch _ {
                print("error removing file: \(error?.localizedDescription)")
            }
        }
    }

    func copyFileToDocuments(fileURL: NSURL) {
        let documentsDirectory: String = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
        let dateFormatter: NSDateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let destinationPath: String = documentsDirectory.stringByAppendingFormat("/output_%@.mov", dateFormatter.stringFromDate(NSDate()))
        do {
            try NSFileManager.defaultManager().copyItemAtURL(fileURL, toURL: NSURL.fileURLWithPath(destinationPath))
        } catch _ {
            print("error copying file: \(error?.localizedDescription)")
        }
    }

    func copyFileToCameraRoll(fileURL: NSURL) {
        let library: ALAssetsLibrary = ALAssetsLibrary()
        if !library.videoAtPathIsCompatibleWithSavedPhotosAlbum(fileURL) {
            print("video incompatible with camera roll")
        }
        library.writeVideoAtPathToSavedPhotosAlbum(fileURL, completionBlock: {(assetURL, error) in
            if error != nil {
                print("Error: Domain = \(error.domain), Code = \(error.localizedDescription)")
            }
            else if assetURL == nil {
                //It's possible for writing to camera roll to fail, without receiving an error message, but assetURL will be nil
                //Happens when disk is (almost) full
                print("Error saving to camera roll: no error message, but no url returned")
            }
            else {
                    //remove temp file
                do {
                    try NSFileManager.defaultManager().removeItemAtURL(fileURL)
                } catch _ {
                    print("error: \(error.localizedDescription)")
                }
            }
        })
    }
}
//
//  IDFileManager.m
//  VideoCaptureDemo
//
//  Created by Adriaan Stellingwerff on 9/04/2015.
//  Copyright (c) 2015 Infoding. All rights reserved.
//

import AssetsLibrary