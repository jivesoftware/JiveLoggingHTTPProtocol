//
//  main.m
//  JiveLoggingHTTPProtocolDemo
//
//  Created by Heath Borders on 3/2/15.
//  Copyright (c) 2015 Jive Software. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import <JiveLoggingHTTPProtocol/JiveLoggingHTTPProtocol.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        [JiveLoggingHTTPProtocol start];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
