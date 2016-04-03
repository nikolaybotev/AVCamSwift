//
//  PreviewView.swift
//  AVCamSwift
//
//  Created by Nikolay Botev on 4/2/16.
//  Copyright © 2016 Chuckmoji. All rights reserved.
//

import UIKit
import AVFoundation

class PreviewView: UIView {

    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var session: AVCaptureSession {
        get {
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            return previewLayer.session
        }
        set {
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            previewLayer.session = newValue
        }
    }

}
