/*
 File: JLHPLog.m
 
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
 
 Copyright (C) 2014 Jive Software Inc. All Rights Reserved.
 
 */

#import "JLHPLog.h"

static NSUInteger const JIVE_LOG_TEXT_MUTABLE_DATA_MAX_LENGTH = 1024L * 1024L;

@interface JLHPLog ()

@property (nonatomic, strong) NSString *prefix;
@property (nonatomic, strong) NSString *UUIDString;

@property (nonatomic, strong) NSMutableString *mutableString;

@property (nonatomic, assign) BOOL responseMode;
@property (nonatomic, assign) BOOL dataIsText;
@property (nonatomic, strong) NSMutableData *textMutableData;
@property (nonatomic, assign) NSUInteger dataLength;
@property (nonatomic, strong) NSMutableArray *errors;

@end

@implementation JLHPLog

- (instancetype)initWithUUIDString:(NSString *)UUIDString
                           request:(NSURLRequest *)request {
    self = [super init];
    if (self) {
        self.prefix = @">";
        self.UUIDString = UUIDString;
        
        self.mutableString = [NSMutableString string];
        
        [self logRequest:request];
    }
    
    return self;
}

- (instancetype)initWithUUIDString:(NSString *)UUIDString
                          response:(NSHTTPURLResponse *)response {
    self = [super init];
    if (self) {
        self.prefix = @"<";
        self.UUIDString = UUIDString;
        
        self.mutableString = [NSMutableString string];
        
        [self logResponse:response];
    }
    
    return self;
}

- (void)print {
    NSUInteger unbodiedLength = [self.mutableString length];
    
    if (self.responseMode) {
        // append the current body so the entire log can be atomically printed
        if (self.dataIsText) {
            [self log:@"Body Text:"];
            NSString *text = [[NSString alloc] initWithData:self.textMutableData
                                                   encoding:NSUTF8StringEncoding];
            if (!text) {
                text = [[NSString alloc] initWithData:self.textMutableData
                                             encoding:NSISOLatin1StringEncoding];
            }
            if (!text) {
                text = [[NSString alloc] initWithData:self.textMutableData
                                             encoding:NSASCIIStringEncoding];
            }
            if (!text) {
                text = [NSString stringWithFormat:@"Could not decode %@ bytes of text!",
                        @(self.dataLength)];
            }
            
            assert(text);
            [self.mutableString appendString:text];
            if ([self.textMutableData length] <= self.dataLength) {
                [self.mutableString appendString:@"\n"];
            } else {
                [self.mutableString appendFormat:@"... truncated to %@ of %@ bytes\n",
                 @([self.textMutableData length]),
                 @(self.dataLength)];
            }
        } else {
            [self log:[NSString stringWithFormat:@"%@ bytes of Content",
                       @(self.dataLength)]];
        }
        
        for (NSError *error in self.errors) {
            [self log:[NSString stringWithFormat:@"terminated by error: %@ %@ %@",
                       error.domain,
                       @(error.code),
                       error.userInfo]];
        }
    }
    
    printf("%s", [self.mutableString cStringUsingEncoding:NSUTF8StringEncoding]);
    
    if (self.responseMode) {
        NSRange bodyRange = NSMakeRange(unbodiedLength, [self.mutableString length] - unbodiedLength);
        
        // remove the body in case someone adds more logs.
        [self.mutableString deleteCharactersInRange:bodyRange];
    }
}

- (void)logNewline {
    [self.mutableString appendFormat:@"%@\n",
     self.prefix];
}

- (void)log:(NSString *)message {
    [self.mutableString appendFormat:@"%@ %@\n",
     self.prefix,
     message];
}

- (void)logHTTPHeadersDictionary:(NSDictionary *)httpHeaders {
    for (id httpHeaderNameObject in httpHeaders.allKeys) {
        if ([httpHeaderNameObject isKindOfClass:[NSString class]]) {
            NSString *httpHeaderName = httpHeaderNameObject;
            NSString *httpHeaderValue = httpHeaders[httpHeaderName];
            
            [self log:[NSString stringWithFormat:@"%@: %@",
                       httpHeaderName,
                       httpHeaderValue]];
        }
    }
}

- (void)logHTTPBodyData:(NSData *)HTTPBodyData
        withContentType:(NSString *)contentType {
    BOOL HTTPBodyDataIsText = [self contentTypeIsText:contentType];
    
    if (HTTPBodyDataIsText) {
        NSString *HTTPBodyText = [[NSString alloc] initWithData:HTTPBodyData
                                                       encoding:NSUTF8StringEncoding];
        
        [self log:HTTPBodyText];
    } else {
        [self log:[NSString stringWithFormat:@"<%@ bytes of non-text data>",
                   @([HTTPBodyData length])]];
    }
    
    [self logNewline];
}

- (void)logRequest:(NSURLRequest *)request {
    [self log:[NSString stringWithFormat:@"Request: %@ %@",
               self.UUIDString,
               request.URL.absoluteString]];
    
    [self log:[NSString stringWithFormat:@"%@ %@ HTTP/1.1",
               request.HTTPMethod,
               request.URL.path]];
    [self logHTTPHeadersDictionary:request.allHTTPHeaderFields];
    
    if (request.HTTPShouldHandleCookies) {
        NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:request.URL];
        NSDictionary *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        [self logHTTPHeadersDictionary:cookieHeaders];
    }
    
    [self logNewline];
    
    if (request.HTTPBody) {
        NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"];
        [self logHTTPBodyData:request.HTTPBody
              withContentType:contentType];
    } else if (request.HTTPBodyStream) {
        NSString *contentLength = [request valueForHTTPHeaderField:@"Content-Lenth"];
        if (contentLength) {
            [self log:[NSString stringWithFormat:@"<%@ bytes of streaming data>",
                       contentLength]];
        } else {
            [self log:@"<streaming data of unknown length>"];
        }
        [self logNewline];
    }
}

- (void)logResponse:(NSHTTPURLResponse *)response {
    self.responseMode = YES;
    
    [self log:[NSString stringWithFormat:@"Response: %@",
               self.UUIDString]];
    
    if (response) {
        [self log:[NSString stringWithFormat:@"HTTP/1.1 %@ %@",
                   @(response.statusCode),
                   [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode]]];
        
        [self logHTTPHeadersDictionary:response.allHeaderFields];
        
        NSString *contentType = response.allHeaderFields[@"Content-Type"];
        self.dataIsText = [self contentTypeIsText:contentType];
        if (self.dataIsText) {
            self.textMutableData = [NSMutableData data];
        }
    }
    
    self.errors = [NSMutableArray arrayWithCapacity:1];
}

- (void)logCancel {
    [self log:[NSString stringWithFormat:@"Cancelled: %@",
               self.UUIDString]];
}

- (void)logData:(NSData *)data {
    if (self.dataIsText) {
        NSUInteger newLength = [self.textMutableData length] + [data length];
        if (newLength < JIVE_LOG_TEXT_MUTABLE_DATA_MAX_LENGTH) {
            [self.textMutableData appendData:data];
        } else {
            NSUInteger appendableLength = newLength - JIVE_LOG_TEXT_MUTABLE_DATA_MAX_LENGTH;
            [self.textMutableData appendData:[data subdataWithRange:NSMakeRange(0, appendableLength)]];
        }
    }
    
    self.dataLength += [data length];
}

- (void)logError:(NSError *)error {
    if (error) {
        [self.errors addObject:error];
    }
}

- (BOOL)contentTypeIsText:(NSString *)contentType {
    static NSArray *textContentTypePrefixes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        textContentTypePrefixes = @[
                                    @"application/",
                                    @"text/",
                                    ];
    });
    
    BOOL contentTypeIsText = NO;
    if (contentType) {
        for (NSString *textContentTypePrefix in textContentTypePrefixes) {
            if ([contentType rangeOfString:textContentTypePrefix].location == 0) {
                contentTypeIsText = YES;
                break;
            }
        }
    }
    
    return contentTypeIsText;
}

@end