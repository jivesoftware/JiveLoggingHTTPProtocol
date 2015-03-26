Pod::Spec.new do |s|
  s.name = 'JiveLoggingHTTPProtocol'
  s.version = '0.2.2'
  s.license = { :type => 'BSD', :file => 'LICENSE' }
  s.summary = 'An NSURLProtocol to log HTTP Requests and Responses'
  s.homepage = 'https://github.com/jivesoftware/JiveLoggingHTTPProtocol'
  s.social_media_url = 'http://twitter.com/JiveSoftware'
  s.authors = { 'Jive Mobile' => 'jive-mobile@jivesoftware.com' }
  s.source = { :git => 'https://github.com/jivesoftware/JiveLoggingHTTPProtocol.git', :tag => s.version }

  s.ios.deployment_target = '7.0'

  s.requires_arc = true
  s.source_files = 'Source/JiveLoggingHTTPProtocol/*.{h,m}'

end
