Pod::Spec.new do |s|
  s.name         = "GTXiLib"
  s.version      = "5.1.3"
  s.summary      = "iOS Accessibility testing library."
  s.description  = <<-DESC
  iOS Accessibility testing library that works with XCTest based frameworks.
                   DESC
  s.homepage     = "https://github.com/google/GTXiLib"
  s.license      = "Apache License 2.0"
  s.author       = "j-sid"
  s.platform     = :ios
  s.source       = { :git => "https://github.com/google/GTXiLib.git", :tag => "5.1.3" }
  s.ios.deployment_target = "9.0"
  s.swift_version = "5.0"
  # Module map removed when building as framework (handled by post_install hook in Podfile)
  # For local dev: all files in one framework, no subspecs
  # Including new Swift extensions and protocols for snapshot testing
  s.source_files = "Classes/**/*.{h,m,mm,swift}",
                   "Classes/Swift/**/*.swift",
                   "OOPClasses/**/*.{h,cc}"
  s.public_header_files = "Classes/**/*.h"
  s.private_header_files = "Classes/ObjCPP/*.h", "Classes/XCTest/*.h", "OOPClasses/**/*.h"
  s.resources = ["ios_translations.bundle"]
  s.ios.frameworks = ["Vision"]
  # XCTest weak framework removed to prevent linking test frameworks in main app
  # s.ios.weak_frameworks = ["XCTest"]
  s.libraries = "c++"
  s.dependency "abseil"
  s.dependency "tinyxml"

end
