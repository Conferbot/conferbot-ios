Pod::Spec.new do |s|
  s.name             = 'Conferbot'
  s.version          = '2.0.1'
  s.summary          = 'Native iOS SDK for Conferbot - AI-powered customer support chat'
  s.description      = <<-DESC
Conferbot iOS SDK enables seamless integration of AI-powered customer support chat
into your native iOS applications. Features include real-time messaging, live agent
handover, file uploads, push notifications, and full customization support.
                       DESC

  s.homepage         = 'https://conferbot.com'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'Conferbot' => 'support@conferbot.com' }
  s.source           = { :git => 'https://github.com/Conferbot/conferbot-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_versions = ['5.7', '5.8', '5.9']

  s.source_files = 'Sources/Conferbot/**/*.{swift,h,m}'
  # The widget's words in its five languages (scripts/sync-i18n.sh, Core/I18n)
  s.resource_bundles = { 'Conferbot' => ['Sources/Conferbot/Resources/i18n-strings.json'] }

  s.frameworks = 'UIKit', 'Foundation', 'Combine'
  s.dependency 'Socket.IO-Client-Swift', '~> 16.0'

  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '5.7' }
end
