# Podfile for m{ai}geXR iOS App
# Created: 2026-02-08

platform :ios, '16.0'

# Use frameworks for Swift compatibility
use_frameworks!

# Disable input/output paths to speed up builds
install! 'cocoapods', :disable_input_output_paths => true

target 'XRAiAssistant' do
  # Google Mobile Ads SDK (AdMob)
  pod 'Google-Mobile-Ads-SDK', '~> 11.0'

  # Unity Ads SDK
  pod 'UnityAds', '~> 4.9'

  # Optional: Google User Messaging Platform for GDPR consent
  pod 'GoogleUserMessagingPlatform', '~> 2.1'

  target 'XRAiAssistantTests' do
    inherit! :search_paths
    # Pods for testing
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Set minimum deployment target
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'

      # Enable Swift whole module optimization for release builds
      if config.name == 'Release'
        config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
        config.build_settings['SWIFT_COMPILATION_MODE'] = 'wholemodule'
      end

      # Fix for Xcode 15+ compatibility
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
end
