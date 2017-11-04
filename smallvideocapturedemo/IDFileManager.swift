//
//  IDFileManager.h
//  VideoCaptureDemo
//
//  Created by Adriaan Stellingwerff on 9/04/2015.
//  Copyright (c) 2015 Infoding. All rights reserved.
//
import Foundation
import AssetsLibrary

class IDFileManager: NSObject {
    
    var error:NSError?
    
    func tempFileURL() -> URL {
        var path: String? = nil
        let fm: FileManager = FileManager.default
        var i: Int = 0
        while path == nil || fm.fileExists(atPath: path!) {
            path = "\(NSTemporaryDirectory())\(Int(i)).mov"
            i += 1
        }
        return URL(fileURLWithPath: path!)
    }

    func removeFile(_ fileURL: URL) {
        let filePath: String = fileURL.path
        let fileManager: FileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath) {
            do {
                try fileManager.removeItem(atPath: filePath)
            } catch _ {
                print("error removing file: \(error?.localizedDescription)")
            }
        }
    }

    func copyFileToDocuments(_ fileURL: URL) {
        let documentsDirectory: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let dateFormatter: DateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let destinationPath: String = documentsDirectory.appendingFormat("/output_%@.mov", dateFormatter.string(from: Date()))
        do {
            try FileManager.default.copyItem(at: fileURL, to: URL(fileURLWithPath: destinationPath))
        } catch _ {
            print("error copying file: \(error?.localizedDescription)")
        }
    }

    func copyFileToCameraRoll(_ fileURL: URL) {
        let library: ALAssetsLibrary = ALAssetsLibrary()
        if !library.videoAtPathIs(compatibleWithSavedPhotosAlbum: fileURL) {
            print("video incompatible with camera roll")
        }
        library.writeVideoAtPath(toSavedPhotosAlbum: fileURL, completionBlock: {(assetURL, error) in
            if error != nil {
                print("Error: Code = \(error?.localizedDescription)")
            }
            else if assetURL == nil {
                //It's possible for writing to camera roll to fail, without receiving an error message, but assetURL will be nil
                //Happens when disk is (almost) full
                print("Error saving to camera roll: no error message, but no url returned")
            }
            else {
                    //remove temp file
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch _ {
                    print("error: \(error?.localizedDescription)")
                }
            }
        })
    }
}
