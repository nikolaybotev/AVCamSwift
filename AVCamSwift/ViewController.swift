//
//  ViewController.swift
//  AVCamSwift
//
//  Created by Nikolay Botev on 4/2/16.
//  Copyright © 2016 Chuckmoji. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {

    enum AVCamSetupResult {
        case Success
        case CameraNotAuthorized
        case SessionConfigurationFailed
    }

    // For use in the storyboards.
    @IBOutlet var previewView: PreviewView!
    @IBOutlet var cameraUnavailableLabel: UILabel!
    @IBOutlet var resumeButton: UIButton!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var cameraButton: UIButton!
    @IBOutlet var stillButton: UIButton!

    // Session management.
    var sessionQueue: dispatch_queue_t!
    var session: AVCaptureSession!
    var videoDeviceInput: AVCaptureDeviceInput!
    var movieFileOutput: AVCaptureMovieFileOutput!
    var stillImageOutput: AVCaptureStillImageOutput!

    // Utilities.
    var setupResult: AVCamSetupResult!
    var sessionRunning: Bool!
    var backgroundRecordingID: UIBackgroundTaskIdentifier!


    override func viewDidLoad() {
        super.viewDidLoad()

        // Dsiable UI
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.stillButton.enabled = false

        // Create the session
        self.session = AVCaptureSession()

        // Setup the preview view
        self.previewView.session = session

        // Communicate with the session and other session objects on this queue.
        self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)

        self.setupResult = .Success

        switch (AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)) {
        case .Authorized:
            break
        case .NotDetermined:
            dispatch_suspend(sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo) { (granted) in
                if (!granted) {
                    self.setupResult = .CameraNotAuthorized
                }
                dispatch_resume(self.sessionQueue)
            }
        default:
            setupResult = .CameraNotAuthorized
        }

        // Setup the capture session.
        dispatch_async(sessionQueue) {
            if (self.setupResult != .Success) {
                return
            }

            self.backgroundRecordingID = UIBackgroundTaskInvalid

            self.session.beginConfiguration()

            let videoDevice = ViewController.deviceWith(AVMediaTypeVideo, preferredPosition: .Back)
            do {
                let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

                if (self.session.canAddInput(videoDeviceInput)) {
                    self.session.addInput(videoDeviceInput)
                    self.videoDeviceInput = videoDeviceInput

                    dispatch_async(dispatch_get_main_queue()) {
                        // Why are we dispatching this to the main queue?
                        // Because AVCaptureVideoPreviewLayer is the backing layer of PreviewView and UIView
                        // can only be manipulated on the main thread.
                        // Note: As an exception to the above rule, it is not necessary to serialize video
                        // orientation changes on the AVCaptureVideoPreviewLayers connection with other
                        // session manipulation.

                        // Use the status bar orientation as the initial video orientation. Subsequent
                        // orientation changes are handled by viewWillTransitionToSize:withTransitionCoordinator:

                        let statusBarOrientation = UIApplication.sharedApplication().statusBarOrientation
                        let mapping: [UIInterfaceOrientation: AVCaptureVideoOrientation] =
                            [.Unknown: .Portrait,
                             .Portrait: .Portrait,
                             .PortraitUpsideDown: .PortraitUpsideDown,
                             .LandscapeLeft: .LandscapeLeft,
                             .LandscapeRight: .LandscapeRight]
                        let initialVideoOrientation = mapping[statusBarOrientation] ?? .Portrait

                        let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                        previewLayer.connection.videoOrientation = initialVideoOrientation
                    }
                } else {
                    NSLog("Could not add video device input to the session.")
                }
            } catch let error {
                NSLog("Could not create video device input: \(error)")
            }

            do {
                let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
                let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)

                if (self.session.canAddInput(audioDeviceInput)) {
                    self.session.addInput(audioDeviceInput)
                } else {
                    NSLog("Could not add audio device input to the session.")
                }
            } catch let error {
                NSLog("Could not create audio device input: \(error)")
            }

            let movieFileOutput = AVCaptureMovieFileOutput()
            if (self.session.canAddOutput(movieFileOutput)) {
                self.session.addOutput(movieFileOutput)
                let connection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                if (connection.supportsVideoStabilization) {
                    connection.preferredVideoStabilizationMode = .Auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                NSLog("Could not add movie file output to the session")
                self.setupResult = .SessionConfigurationFailed
            }

            let stillImageOutput = AVCaptureStillImageOutput()
            if (self.session.canAddOutput(stillImageOutput)) {
                stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            } else {
                NSLog("Could not add still image file output to the session")
                self.setupResult = .SessionConfigurationFailed
            }

            self.session.commitConfiguration()
        }
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        dispatch_async(self.sessionQueue) {
            switch (self.setupResult!) {
            case .Success:
                self.addObservers()
                self.session.startRunning()
                self.sessionRunning = self.session.running
            case .CameraNotAuthorized:
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("No permission to use camera", comment: "Alert when user-denied")
                    let alertController = UIAlertController(title: "AVCamSwift", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK"), style: .Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open settings"), style: .Default) { action in
                        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                    }
                    alertController.addAction(settingsAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            case .SessionConfigurationFailed:
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCamSwift", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK"), style: .Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    override func viewDidDisappear(animated: Bool) {
        dispatch_async(self.sessionQueue) {
            if (self.setupResult == .Success) {
                self.session.stopRunning()
                self.removeObservers()
            }
        }

        super.viewDidDisappear(animated)
    }

    // MARK: Orientation

    override func shouldAutorotate() -> Bool {
        // Disable autorotation of the interface when recording is in progress
        return !(self.movieFileOutput?.recording ?? true)
    }

    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return .All
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)

        // Note that the app delegate controls the device orintation notification required to use the device orientation.
        let deviceOrientation = UIDevice.currentDevice().orientation
        if (UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation)) {
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            let mapping: [UIDeviceOrientation: AVCaptureVideoOrientation] =
                [.Portrait: .Portrait,
                 .PortraitUpsideDown: .PortraitUpsideDown,
                 .LandscapeLeft: .LandscapeRight,
                 .LandscapeRight: .LandscapeLeft]

            previewLayer.connection.videoOrientation = mapping[deviceOrientation] ?? .Portrait
        }
    }

    // MARK: KVO and Notifications

    static let CapturingStillImageContext = UnsafeMutablePointer<Void>.alloc(1)
    static let SessionRunningContext = UnsafeMutablePointer<Void>.alloc(1)

    func addObservers() {
        self.session.addObserver(self, forKeyPath: "running", options: .New, context: ViewController.SessionRunningContext)
        self.stillImageOutput.addObserver(self, forKeyPath: "capturingStillImage", options: .New, context: ViewController.CapturingStillImageContext)

        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(ViewController.subjectAreaDidChange),
                                                         name: AVCaptureDeviceSubjectAreaDidChangeNotification,
                                                         object: self.videoDeviceInput.device)
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(ViewController.sessionRuntimeError),
                                                         name: AVCaptureSessionRuntimeErrorNotification,
                                                         object: self.session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.

        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(ViewController.sessionWasInterrupted),
                                                         name: AVCaptureSessionWasInterruptedNotification,
                                                         object: self.session)
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(ViewController.sessionInterruptionEnded),
                                                         name: AVCaptureSessionInterruptionEndedNotification,
                                                         object: self.session)
    }

    func removeObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self)

        self.session.removeObserver(self, forKeyPath: "running", context: ViewController.SessionRunningContext)
        self.stillImageOutput.removeObserver(self, forKeyPath: "capturingStillImage", context: ViewController.CapturingStillImageContext)
    }

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if (context == ViewController.CapturingStillImageContext) {
            let isCapturingStillImage = change![NSKeyValueChangeNewKey]?.boolValue ?? false

            if (isCapturingStillImage) {
                dispatch_async(dispatch_get_main_queue()) {
                    self.previewView.layer.opacity = 0.0
                    UIView.animateWithDuration(0.25) {
                        self.previewView.layer.opacity = 1.0
                    }
                }
            }
        } else if (context == ViewController.SessionRunningContext) {
            let isSessionRunning = change![NSKeyValueChangeNewKey]?.boolValue ?? false

            dispatch_async(dispatch_get_main_queue()) {
                // Only enable the ability to change camera if the device has more than one camera.
                self.cameraButton.enabled = isSessionRunning && AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1
                self.recordButton.enabled = isSessionRunning
                self.stillButton.enabled = isSessionRunning
            }
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }

    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPointMake(0.5, 0.5)

        self.focus(.ContinuousAutoFocus, exposureMode: .ContinuousAutoExposure, atPoint: devicePoint, monitorSubjectAreaChange: false)
    }

    func sessionRuntimeError(notification: NSNotification) {
        let error = notification.userInfo![AVCaptureSessionErrorKey] as! NSError
        NSLog("Capture session runtime error: \(error)")

        // Automatically try to restart thesession running if media services were reset and the last start running succeeded.
        // Otherwise, enable the user to try to resume the session running.
        if (error.code == AVError.MediaServicesWereReset.rawValue) {
            dispatch_async(self.sessionQueue) {
                if (self.sessionRunning!) {
                    self.session.startRunning()
                    self.sessionRunning = self.session.running
                } else {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.resumeButton.hidden = false
                    }
                }
            }
        } else {
            self.resumeButton.hidden = false
        }
    }

    func sessionWasInterrupted(notification: NSNotification) {
        // In some scenarios we wnat to enable the user to resume the session running.
        // For example, if music playback is initiated via control center while using AVCam,
        // then the user can let AVCam resume the session running, which will stop music playback.
        // Note that stopping music playback in control center will not automatically resume the session running.
        // Also note that it is not always possible to resume, see #resumeInterruptedSession.
        var showResumeButton = false

        // In iOS 9 and later, the suserInfo dictionary contains information on why the session was interrupted.
        if #available(iOS 9.0, *) {
            let reason = notification.userInfo![AVCaptureSessionInterruptionReasonKey]?.integerValue

            switch (AVCaptureSessionInterruptionReason(rawValue: reason!)!) {
            case .AudioDeviceInUseByAnotherClient,
                 .VideoDeviceInUseByAnotherClient:
                showResumeButton = true
            case .VideoDeviceNotAvailableWithMultipleForegroundApps:
                // Simply fade-in a label to inform the user that the camera is unavailable.
                self.cameraUnavailableLabel.hidden = false
                self.cameraUnavailableLabel.alpha = 0.0
                UIView.animateWithDuration(0.25) {
                    self.cameraUnavailableLabel.alpha = 1.0
                }
            case .VideoDeviceNotAvailableInBackground:
                showResumeButton = false
            }
        } else {
            showResumeButton = UIApplication.sharedApplication().applicationState == .Inactive
        }

        if (showResumeButton) {
            // Simply fade-in a button to enable the user to try to resume the session running.
            self.resumeButton.hidden = false
            self.resumeButton.alpha = 0.0
            UIView.animateWithDuration(0.25) {
                self.resumeButton.alpha = 1.0
            }
        }
    }

    func sessionInterruptionEnded(notification: NSNotification) {
        NSLog("Capture session interruption ended")

        if (!self.resumeButton.hidden) {
            UIView.animateWithDuration(0.25, animations: {
                self.resumeButton.alpha = 0.0
                }, completion: { finished in
                    self.resumeButton.hidden = true
            })
        }
        if (!self.cameraUnavailableLabel.hidden) {
            UIView.animateWithDuration(0.25, animations: {
                self.cameraUnavailableLabel.alpha = 0.0
                }, completion: { finished in
                    self.cameraUnavailableLabel.hidden = true
            })
        }
    }

    // MARK: Actions

    @IBAction func resumeInterruptedSession(sender: UIButton) {
        dispatch_async(self.sessionQueue) {
            // The session might fail to start running, e.g., if a phone or FacreTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            self.session.startRunning()
            self.sessionRunning = self.session.running
            if (!self.session.running) {
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCamSwift", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK"), style: .Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            } else {
                dispatch_async(dispatch_get_main_queue()) {
                    self.resumeButton.hidden = true
                }
            }
        }
    }

    @IBAction func toggleMovieRecording(sender: UIButton) {
        // Disable the Camera button until recording finishes, and disable the Record button until recording starts or finishes. See the
        // AVCaptureFielOutputRecordingDelegate methods.
        self.cameraButton.enabled = false
        self.recordButton.enabled = false

        dispatch_async(self.sessionQueue) {
            if (!self.movieFileOutput.recording) {
                if (UIDevice.currentDevice().multitaskingSupported) {
                    // Setup background task. This is needed because the captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:
                    // callback is not received until AVCam returns to the foreground unless you request background execution time.
                    // This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                    // To conclude this background execution, endBackgroundTask is called in
                    // captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error after the recorded file has been saved.
                    self.backgroundRecordingID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler(nil)
                }

                // Update the orientation on the movie file output video connection before starting recording.
                let connection = self.movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                connection.videoOrientation = previewLayer.connection.videoOrientation

                // Turn OFF flash for video recording.
                ViewController.setFlashMode(.Off, device: self.videoDeviceInput.device)

                // Start recording to a temporary file.
                let outputFileURL = NSURL.fileURLWithPath(NSTemporaryDirectory())
                    .URLByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString)
                    .URLByAppendingPathExtension("mov")
                self.movieFileOutput.startRecordingToOutputFileURL(outputFileURL, recordingDelegate: self)
            } else {
                self.movieFileOutput.stopRecording()
            }
        }
    }

    @IBAction func changeCamera(sender: UIButton) {
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.stillButton.enabled = false

        dispatch_async(self.sessionQueue) {
            let currentVideoDevice = self.videoDeviceInput.device
            var preferredPosition = AVCaptureDevicePosition.Unspecified
            let currentPosition = currentVideoDevice.position

            switch (currentPosition) {
            case .Unspecified, .Front:
                preferredPosition = .Back
            case .Back:
                preferredPosition = .Front
            }

            let videoDevice = ViewController.deviceWith(AVMediaTypeVideo, preferredPosition: preferredPosition)

            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice)

            self.session.beginConfiguration()

            self.session.removeInput(self.videoDeviceInput)

            if (self.session.canAddInput(videoDeviceInput)) {
                NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: currentVideoDevice)

                ViewController.setFlashMode(.Auto, device: videoDevice)
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.subjectAreaDidChange), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: videoDevice)

                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                self.session.addInput(self.videoDeviceInput)
            }

            let connection = self.movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
            if (connection.supportsVideoStabilization) {
                connection.preferredVideoStabilizationMode = .Auto
            }

            self.session.commitConfiguration()

            dispatch_async(dispatch_get_main_queue()) {
                self.cameraButton.enabled = true
                self.recordButton.enabled = true
                self.stillButton.enabled = true
            }
        }
    }

    @IBAction func snapStillImage(sender: UIButton) {
        dispatch_async(self.sessionQueue) {
            let connection = self.stillImageOutput.connectionWithMediaType(AVMediaTypeVideo)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer

            // Update the orientation on the still image output video connection before capturing.
            connection.videoOrientation = previewLayer.connection.videoOrientation

            // Flash set to Auto for Still Capture.
            ViewController.setFlashMode(.Auto, device: self.videoDeviceInput.device)

            // Capture a sitll image.
            self.stillImageOutput.captureStillImageAsynchronouslyFromConnection(connection) {
                imageDataSampleBuffer, error in
                if let buffer = imageDataSampleBuffer {
                    // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer)
                    PHPhotoLibrary.requestAuthorization() { status in
                        if (status == .Authorized) {
                            // To preserve the metadata, we create an asset from the JPEG NSData representation.
                            // Note that creating an asset from a UIImage discards the metadata.
                            // In iOS 9, we can use PHAssetCreationRequest.addResourceWithType:data:options.
                            // In iOS 8, we save the image to a temporary file and use PHAssetChangeRequest.creationRequestForAssetFromImageAtFileURL:.
                            if #available(iOS 9.0, *) {
                                PHPhotoLibrary.sharedPhotoLibrary().performChanges(
                                    {
                                        PHAssetCreationRequest.creationRequestForAsset().addResourceWithType(.Photo, data: imageData, options: nil)
                                    }, completionHandler: {
                                        success, error in
                                        if (!success) {
                                            NSLog("Error occurred while saving image to photo library: \(error)")
                                        }
                                    }
                                )
                            } else {
                                let temporaryFileURL = NSURL.fileURLWithPath(NSTemporaryDirectory())
                                    .URLByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString)
                                    .URLByAppendingPathExtension("jpg")

                                PHPhotoLibrary.sharedPhotoLibrary().performChanges(
                                    {
                                        do {
                                            try imageData.writeToURL(temporaryFileURL, options: .DataWritingAtomic)
                                            PHAssetChangeRequest.creationRequestForAssetFromImageAtFileURL(temporaryFileURL)
                                        } catch let error {
                                            NSLog("Error occurred while writing image data to a temporary file: \(error)")
                                        }
                                    }, completionHandler: {
                                        success, error in
                                        if (!success) {
                                            NSLog("Error occurred while saving image to photo library: \(error)")
                                        }

                                        // Delete the temporary file.
                                        do {
                                            try NSFileManager.defaultManager().removeItemAtURL(temporaryFileURL)
                                        } catch let error {
                                            NSLog("Error deleting temporary file: \(error)")
                                        }
                                    }
                                )
                            }
                        }
                    }
                } else {
                    NSLog("Could not capture still image: \(error)")
                }
            }
        }
    }

    @IBAction func focusAndExposeTap(gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer)
            .captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
        self.focus(.AutoFocus, exposureMode: .AutoExpose, atPoint: devicePoint, monitorSubjectAreaChange: true)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: File Output Recording Delegate

    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) {
        // Enable the Record button to let the user stop the recording.
        dispatch_async(dispatch_get_main_queue()) {
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), forState: .Normal)
        }
    }

    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
        // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
        // is back to false - which happens sometime after this method returns.
        // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
        let currentBackgroundRecordingID = self.backgroundRecordingID
        self.backgroundRecordingID = UIBackgroundTaskInvalid

        let cleanup = {
            if (try? NSFileManager.defaultManager().removeItemAtURL(outputFileURL)) == nil {
                NSLog("Error removing temporary file")
            }
            if (currentBackgroundRecordingID != UIBackgroundTaskInvalid) {
                UIApplication.sharedApplication().endBackgroundTask(currentBackgroundRecordingID)
            }
        }

        var success = true

        if (error != nil) {
            NSLog("Movie file finishing error: \(error)")
            success = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey]?.boolValue ?? false
        }
        if (success) {
            // Check authorization status.
            PHPhotoLibrary.requestAuthorization() { status in
                if (status == .Authorized) {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.sharedPhotoLibrary().performChanges(
                        {
                            // In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
                            // This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
                            if #available(iOS 9.0, *) {
                                let options = PHAssetResourceCreationOptions()
                                options.shouldMoveFile = true
                                let changeRequest = PHAssetCreationRequest.creationRequestForAsset()
                                changeRequest.addResourceWithType(.Video, fileURL: outputFileURL, options: options)
                            } else {
                                PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(outputFileURL)
                            }
                        }, completionHandler: { success, error in
                            if (!success) {
                                NSLog("Could not save movie to photo library: \(error)")
                            }
                            cleanup()
                        }
                    )
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }

        // Enable teh Camera and Record buttons to let the user switch camera and start another recording.
        dispatch_async(dispatch_get_main_queue()) {
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraButton.enabled = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), forState: .Normal)
        }
    }

    // MARK: Device Configuration

    func focus(focusMode: AVCaptureFocusMode, exposureMode: AVCaptureExposureMode, atPoint: CGPoint, monitorSubjectAreaChange: Bool) {
        dispatch_async(sessionQueue) {
            let device = self.videoDeviceInput.device

            do {
                try device.lockForConfiguration()

                // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure)
                // operation. Call set(Focus/Exposure)Mode to apply the new point of interest.
                if (device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode)) {
                    device.focusPointOfInterest = atPoint
                    device.focusMode = focusMode
                }

                if (device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode)) {
                    device.exposurePointOfInterest = atPoint
                    device.exposureMode = exposureMode
                }

                device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange

                device.unlockForConfiguration()
            } catch let error {
                NSLog("Could not lock device for configuration: \(error)")
            }
        }
    }

    class func deviceWith(mediaType: String, preferredPosition: AVCaptureDevicePosition) -> AVCaptureDevice {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType)

        for device in devices {
            if (device.position == preferredPosition) {
                return device as! AVCaptureDevice
            }
        }

        return devices.first as! AVCaptureDevice
    }

    class func setFlashMode(flashMode: AVCaptureFlashMode, device: AVCaptureDevice) {
        if (device.hasFlash && device.isFlashModeSupported(flashMode)) {
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } catch let error {
                NSLog("Could not lock device for configuration: \(error)")
            }
        }
    }

}

