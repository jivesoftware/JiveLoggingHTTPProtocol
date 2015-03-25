/*
     File: JLHPLoggingHTTPProtocol.m
 Abstract: An NSURLProtocol subclass that overrides the built-in HTTP/HTTPS protocol.
  Version: 1.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import "JLHPLoggingHTTPProtocol.h"

#import "JLHPCanonicalRequest.h"
#import "JLHPCacheStoragePolicy.h"
#import "JLHPQNSURLSessionDemux.h"

#import "JLHPLog.h"

@interface JLHPLoggingHTTPProtocol () <NSURLSessionDataDelegate>

@property (atomic, strong, readwrite) NSThread *                        clientThread;       ///< The thread on which we should call the client.

@property (atomic, strong, readwrite) NSString *                        UUIDString;         ///< String form of a UUID that uniquely identifies this request

/*! The log for the response.
 *  \details In order to print the response and the content atomically,
 *  we must store them both together until we're ready to print.
 *  We might need to print it after -stopLoading, so don't nil it there.
 */
@property (atomic, strong, readwrite) JLHPLog *                         responseLog;        ///< log to capture the complete response and data together.

/*! The run loop modes in which to call the client.
 *  \details The concurrency control here is complex.  It's set up on the client 
 *  thread in -startLoading and then never modified.  It is, however, read by code 
 *  running on other threads (specifically the main thread), so we deallocate it in 
 *  -dealloc rather than in -stopLoading.  We can be sure that it's not read before 
 *  it's set up because the main thread code that reads it can only be called after 
 *  -startLoading has started the connection running.
 */

@property (atomic, copy,   readwrite) NSArray *                         modes;
@property (atomic, strong, readwrite) NSURLSessionDataTask *            task;               ///< The NSURLSession task for that request; client thread only.

@end

@implementation JLHPLoggingHTTPProtocol

#pragma mark * Subclass specific additions

+ (void)start
{
    [NSURLProtocol registerClass:self];
}

/*! Returns the session demux object used by all the protocol instances.
 *  \details This object allows us to have a single NSURLSession, with a session delegate, 
 *  and have its delegate callbacks routed to the correct protocol instance on the correct 
 *  thread in the correct modes.  Can be called on any thread.
 */

+ (JLHPQNSURLSessionDemux *)sharedDemux
{
    static dispatch_once_t      sOnceToken;
    static JLHPQNSURLSessionDemux * sDemux;
    dispatch_once(&sOnceToken, ^{
        NSURLSessionConfiguration *     config;
        
        config = [NSURLSessionConfiguration defaultSessionConfiguration];
        // You have to explicitly configure the session to use your own protocol subclass here 
        // otherwise you don't see redirects <rdar://problem/17384498>.
        config.protocolClasses = @[ self ];
        sDemux = [[JLHPQNSURLSessionDemux alloc] initWithConfiguration:config];
    });
    return sDemux;
}

#pragma mark * NSURLProtocol overrides

/*! Used to mark our recursive requests so that we don't try to handle them (and thereby 
 *  suffer an infinite recursive death).
 */

static NSString * kJLHPRecursiveRequestFlagProperty = @"com.jivesoftware.mobile.JLHPLoggingHTTPProtocol";

static NSString * kJLHPUUIDStringRequestFlagProperty = @"com.jivesoftware.mobile.JLHPLoggingHTTPProtocol.UUIDString";

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    BOOL        shouldAccept;
    NSURL *     url;
    NSString *  scheme;
    
    // Check the basics.  This routine is extremely defensive because experience has shown that 
    // it can be called with some very odd requests <rdar://problem/15197355>.
    
    shouldAccept = (request != nil);
    if (shouldAccept) {
        url = [request URL];
        shouldAccept = (url != nil);
    }
    
    // Decline our recursive requests.
    
    if (shouldAccept) {
        shouldAccept = ([self propertyForKey:kJLHPRecursiveRequestFlagProperty inRequest:request] == nil);
    }
    
    // Get the scheme.
    
    if (shouldAccept) {
        scheme = [[url scheme] lowercaseString];
        shouldAccept = (scheme != nil);
    }
    
    // Look for "http" or "https".
    //
    // Flip either or both of the following to YESes to control which schemes go through this custom 
    // NSURLProtocol subclass.
    
    if (shouldAccept) {
// Trying to minimize the amount of Apple-code I change. Don't fix their warnings, just ignore them.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
        shouldAccept = NO && [scheme isEqual:@"http"];
#pragma clang diagnostic pop
        if ( ! shouldAccept ) {
            shouldAccept = YES && [scheme isEqual:@"https"];
        }
    }
    
    return shouldAccept;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    NSURLRequest *      result;
    
    assert(request != nil);
    // can be called on any thread
    
    // Canonicalising a request is quite complex, so all the heavy lifting has 
    // been shuffled off to a separate module.
    
    result = JLHPCanonicalRequestForRequest(request);
    
    return result;
}

- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id <NSURLProtocolClient>)client
{
    assert(request != nil);
    // cachedResponse may be nil
    assert(client != nil);
    // can be called on any thread

    return [super initWithRequest:request cachedResponse:cachedResponse client:client];
}

- (void)dealloc
{
    assert(self->_task == nil);                     // we should have cleared it by now
    
    assert(self->_responseLog == nil);              // we should have cleared it by now
    assert(self->_UUIDString == nil);               // we should have cleared it by now
}

- (void)startLoading
{
    NSMutableURLRequest *   recursiveRequest;
    NSMutableArray *        calculatedModes;
    NSString *              currentMode;

    // At this point we kick off the process of loading the URL via NSURLSession. 
    // The thread that calls this method becomes the client thread.
    
    assert(self.clientThread == nil);           // you can't call -startLoading twice
    assert(self.task == nil);

    // Calculate our effective run loop modes.  In some circumstances (yes I'm looking at 
    // you UIWebView!) we can be called from a non-standard thread which then runs a 
    // non-standard run loop mode waiting for the request to finish.  We detect this 
    // non-standard mode and add it to the list of run loop modes we use when scheduling 
    // our callbacks.  Exciting huh?
    //
    // For debugging purposes the non-standard mode is "WebCoreSynchronousLoaderRunLoopMode" 
    // but it's better not to hard-code that here.
    
    assert(self.modes == nil);
    calculatedModes = [NSMutableArray array];
    [calculatedModes addObject:NSDefaultRunLoopMode];
    currentMode = [[NSRunLoop currentRunLoop] currentMode];
    if ( (currentMode != nil) && ! [currentMode isEqual:NSDefaultRunLoopMode] ) {
        [calculatedModes addObject:currentMode];
    }
    self.modes = calculatedModes;
    assert([self.modes count] > 0);

    // Create new request that's a clone of the request we were initialised with, 
    // except that it has our 'recursive request flag' property set on it.
    
    recursiveRequest = [[self request] mutableCopy];
    assert(recursiveRequest != nil);
    
    [[self class] setProperty:@YES forKey:kJLHPRecursiveRequestFlagProperty inRequest:recursiveRequest];
    
    // Latch the thread we were called on, primarily for debugging purposes.
    
    self.clientThread = [NSThread currentThread];
    
    self.UUIDString = [[self class] propertyForKey:kJLHPUUIDStringRequestFlagProperty
                                         inRequest:recursiveRequest];
    if (!self.UUIDString) {
        self.UUIDString = [[NSUUID UUID] UUIDString];
        [[self class] setProperty:self.UUIDString
                           forKey:kJLHPUUIDStringRequestFlagProperty
                        inRequest:recursiveRequest];
    }
    
    // Once everything is ready to go, create a data task with the new request.

    self.task = [[[self class] sharedDemux] dataTaskWithRequest:recursiveRequest delegate:self modes:self.modes];
    assert(self.task != nil);
    
    [self logRequest:recursiveRequest];
    
    [self.task resume];
}

- (void)stopLoading
{
    // The implementation just cancels the current load (if it's still running).
    
    assert(self.clientThread != nil);           // someone must have called -startLoading

    // Check that we're being stopped on the same thread that we were started 
    // on.  Without this invariant things are going to go badly (for example, 
    // run loop sources that got attached during -startLoading may not get 
    // detached here).
    //
    // I originally had code here to bounce over to the client thread but that 
    // actually gets complex when you consider run loop modes, so I've nixed it. 
    // Rather, I rely on our client calling us on the right thread, which is what 
    // the following assert is about.
    
    assert([NSThread currentThread] == self.clientThread);
    
    if (self.task != nil) {
        [self.task cancel];
        self.task = nil;
        // The following ends up calling -URLSession:task:didCompleteWithError: with NSURLErrorDomain / NSURLErrorCancelled, 
        // which specificallys traps and ignores the error.
    }
    // Don't nil out self.modes; see property declaration comments for a a discussion of this.
    
    // Don't nil out self.responseLog; see property declaration comments for a discussion of this.
    self.UUIDString = nil;
}

#pragma mark * NSURLSession delegate callbacks

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)newRequest completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    NSMutableURLRequest *    redirectRequest;

    #pragma unused(session)
    #pragma unused(task)
    assert(task == self.task);
    assert(response != nil);
    assert(newRequest != nil);
    #pragma unused(completionHandler)
    assert(completionHandler != nil);
    assert([NSThread currentThread] == self.clientThread);

    // The new request was copied from our old request, so it has our magic property.  We actually 
    // have to remove that so that, when the client starts the new request, we see it.  If we 
    // don't do this then we never see the new request and thus don't get a chance to change 
    // its caching behaviour.
    //
    // We also cancel our current connection because the client is going to start a new request for 
    // us anyway.

    assert([[self class] propertyForKey:kJLHPRecursiveRequestFlagProperty inRequest:newRequest] != nil);
    
    redirectRequest = [newRequest mutableCopy];
    [[self class] removePropertyForKey:kJLHPRecursiveRequestFlagProperty inRequest:redirectRequest];
    
    JLHPLog *redirectResponseLog = [[JLHPLog alloc] initWithUUIDString:self.UUIDString
                                                              response:response];
    [redirectResponseLog logCancel];
    [redirectResponseLog print];
    
    // Tell the client about the redirect.
    
    [[self client] URLProtocol:self wasRedirectedToRequest:redirectRequest redirectResponse:response];
    
    // Stop our load.  The CFNetwork infrastructure will create a new NSURLProtocol instance to run 
    // the load of the redirect.
    
    // The following ends up calling -URLSession:task:didCompleteWithError: with NSURLErrorDomain / NSURLErrorCancelled, 
    // which specificallys traps and ignores the error.
    
    [self.task cancel];

    [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    NSURLCacheStoragePolicy cacheStoragePolicy;
    NSInteger               statusCode;
    
    #pragma unused(session)
    #pragma unused(dataTask)
    assert(dataTask == self.task);
    assert(response != nil);
    assert(completionHandler != nil);
    assert([NSThread currentThread] == self.clientThread);

    // Pass the call on to our client.  The only tricky thing is that we have to decide on a 
    // cache storage policy, which is based on the actual request we issued, not the request 
    // we were given.

    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        cacheStoragePolicy = JLHPCacheStoragePolicyForRequestAndResponse(self.task.originalRequest, (NSHTTPURLResponse *) response);
        statusCode = [((NSHTTPURLResponse *) response) statusCode];
        
        self.responseLog = [[JLHPLog alloc] initWithUUIDString:self.UUIDString
                                                      response:(NSHTTPURLResponse *)response];
    } else {
        assert(NO);
        cacheStoragePolicy = NSURLCacheStorageNotAllowed;
        statusCode = 42;
        
        self.responseLog = [[JLHPLog alloc] initWithUUIDString:self.UUIDString
                                                      response:nil];
    }
    
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:cacheStoragePolicy];
    
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    #pragma unused(session)
    #pragma unused(dataTask)
    assert(dataTask == self.task);
    assert(data != nil);
    assert([NSThread currentThread] == self.clientThread);

    // Just pass the call on to our client.
    
    [self.responseLog logData:data];

    [[self client] URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse *))completionHandler
{
    #pragma unused(session)
    #pragma unused(dataTask)
    assert(dataTask == self.task);
    assert(proposedResponse != nil);
    assert(completionHandler != nil);
    assert([NSThread currentThread] == self.clientThread);

    // We implement this delegate callback purely for the purposes of logging.

    completionHandler(proposedResponse);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
    // An NSURLSession delegate callback.  We pass this on to the client.
{
    #pragma unused(session)
    #pragma unused(task)
    assert( (self.task == nil) || (task == self.task) );        // can be nil in the 'cancel from -stopLoading' case
    assert([NSThread currentThread] == self.clientThread);

    // Just log and then, in most cases, pass the call on to our client.

    if (error == nil) {
        [self.responseLog print];
        
        [[self client] URLProtocolDidFinishLoading:self];
    } else if ( [[error domain] isEqual:NSURLErrorDomain] && ([error code] == NSURLErrorCancelled) ) {
        [self.responseLog logCancel];
        [self.responseLog print];
        
        // Do nothing.  This happens in two cases:
        //
        // o during a redirect, in which case the redirect code has already told the client about 
        //   the failure
        // 
        // o if the request is cancelled by a call to -stopLoading, in which case the client doesn't 
        //   want to know about the failure
    } else {
        [self.responseLog logError:error];
        [self.responseLog print];
        
        [[self client] URLProtocol:self didFailWithError:error];
    }

    // We don't need to clean up the connection here; the system will call, or has already called, 
    // -stopLoading to do that.
    
    // except for self.responseLog, which we now no longer need.
    self.responseLog = nil;
}

- (void)logRequest:(NSURLRequest *)request {
    JLHPLog *log = [[JLHPLog alloc] initWithUUIDString:self.UUIDString
                                               request:request];
    [log print];
}

@end
