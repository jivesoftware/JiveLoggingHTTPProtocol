Pod::Spec.new do |s|
  s.name = 'JiveLoggingHTTPProtocol'
  s.version = '0.1.0'
  s.license = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.summary = 'An NSURLProtocol to log HTTP Requests and Responses'
  s.homepage = 'https://github.com/jivesoftware/JiveLoggingHTTPProtocol'
  s.authors = { 'Jive Mobile' => 'jive-mobile@jivesoftware.com' }
  s.source = { :git => 'git@git.jiveland.com:jive-kit', :tag => s.version }

  s.ios.deployment_target = '7.0'

  s.requires_arc = true
  s.source_files = 'Source/JiveLoggingHTTPProtocol/*.{h,m}'

end
