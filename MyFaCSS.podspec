Pod::Spec.new do |s|
  s.name         = 'MyFaCSS'
  s.version      = '19.1.4'
  s.summary      = 'The CSS-inspired styling and layout framework for iOS'
  s.homepage     = 'https://github.com/MyFiziqApp/InterfaCSS'
  s.license      = 'MIT'
  s.authors      = { 'Tobias Löfstrand' => 'tobias@leafnode.se', 'MyFiziq Dev' => 'dev@myfiziq.com' }
  s.source       = { :git => 'https://github.com/MyFiziqApp/InterfaCSS.git', :tag => '19.1.4_trunk' }
  s.ios.deployment_target = '12.1'

  s.source_files = 'InterfaCSS/**/*.{h,m}'
  s.requires_arc = true
  s.frameworks   = 'Foundation', 'UIKit', 'CoreGraphics', 'QuartzCore'

end
