//
//  ViewController.m
//  JiveLoggingURLProtocolDemo
//
//  Created by Heath Borders on 3/2/15.
//  Copyright (c) 2015 Jive Software. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic, weak) IBOutlet UIWebView *webView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // this will redirect to https://www.jivesoftware.com
    // so you'll see some redirects in the output.
    [self.webView loadRequest:[[NSURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://jivesoftware.com"]]];
}

@end
