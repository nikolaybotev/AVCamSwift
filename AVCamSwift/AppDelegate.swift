//
//  AppDelegate.swift
//  AVCamSwift
//
//  Created by Nikolay Botev on 4/2/16.
//  Copyright © 2016 Chuckmoji. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        UIDevice.currentDevice().beginGeneratingDeviceOrientationNotifications()
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        UIDevice.currentDevice().endGeneratingDeviceOrientationNotifications()
    }

    func applicationWillEnterForeground(application: UIApplication) {
        UIDevice.currentDevice().beginGeneratingDeviceOrientationNotifications()
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        UIDevice.currentDevice().endGeneratingDeviceOrientationNotifications()
    }

}

