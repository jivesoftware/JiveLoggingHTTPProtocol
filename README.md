JiveLoggingHTTPProtocol
=======================

Based on [Apple's CustomHTTPProtocol](https://developer.apple.com/library/prerelease/ios/samplecode/CustomHTTPProtocol/Introduction/Intro.html),
`JLHPLoggingHTTPProtocol` logs to the console all requests and responses visibile to the `NSURLProtocol` system.
This should only be used for debugging. It won't show all HTTP interactions because authentication interactions aren't
visible to the `NSURLProtocol` system. For example, `NTLM` uses multiple HTTP requests and responses for authentication before
the request that the `NSURLProtocol` system sees is accepted. Additionally, some iOS frameworks' HTTP calls aren't visible
to the `NSURLProtocol` system at all (AV Foundation streaming).

Usage
-----
Call `+[JLHPLoggingHTTPProtocol start]` as early as possible in your Application's lifecycle because `NSURLProtocol`
registrations are called in reverse-registration-order (the first `NSURLProtocol` registered is the last one called).
If other `NSURLProtocol`s modify a request, those modifications should happen before `JLHPLoggingHTTPProtocol` is called.

A good safe place to call `+[JLHPLoggingHTTPProtocol start]` early is in `main.m`.
Since this should only be used for debugging `+[JLHPLoggingHTTPProtocol start]` should be guarded somehow to ensure
it is only called in debug mode. In the example below, the Xcode scheme inserts arguments that will populate
`NSUserDefaults` to trigger the call.

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

License
-------

BSD per the LICENSE file.

