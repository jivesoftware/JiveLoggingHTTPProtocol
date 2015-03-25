//
//  main.m
//  JiveLoggingHTTPProtocolDemo
//
//  Created by Heath Borders on 3/2/15.
//  Copyright (c) 2015 Jive Software. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import <JiveLoggingHTTPProtocol/JLHPLoggingHTTPProtocol.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        // NSUserDefaults grab any program arguments with the format `-name value`.
        // In the JiveLoggingHTTPProtocolDemo scheme, we have `-logHTTP YES` defined.
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"logHTTP"]) {
            [JLHPLoggingHTTPProtocol start];
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
