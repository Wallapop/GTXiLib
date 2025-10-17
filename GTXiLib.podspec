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
  # Module map removed when building as framework (handled by post_install hook in Podfile)
  # For local dev: all files in one framework, no subspecs
  s.source_files = "Classes/**/*.{h,m,mm,swift}", "OOPClasses/**/*.{h,cc}"
  s.public_header_files = "Classes/**/*.h"
  s.private_header_files = "Classes/ObjCPP/*.h", "Classes/XCTest/*.h", "OOPClasses/**/*.h"
  s.resources = ["ios_translations.bundle"]
  s.ios.frameworks = ["Vision", "XCTest"]
  s.libraries = "c++"
  s.dependency "abseil"
  s.dependency "tinyxml"

  # Original subspec structure (for reference, not used in local builds)
  if false
  s.subspec "GTXiLib" do |sp|
    sp.source_files = "Classes/**/*.{h,m,mm}"
    sp.public_header_files = "Classes/**/*.h"
    sp.private_header_files = "Classes/ObjCPP/*.h"
    sp.exclude_files = ["Classes/XCTest/*.{h,m,mm}"]
    sp.resources = ["ios_translations.bundle"]
    sp.ios.deployment_target = "9.0"
    sp.ios.framework = "Vision"
    sp.dependency "GTXiLib/GTXOOPLib"
  end
  s.subspec "GTXOOPLib" do |sp|
    sp.source_files = "OOPClasses/**/*.{h,cc}"
    sp.public_header_files = "OOPClasses/**/*.h"
    sp.resources = ["ios_translations.bundle"]
    sp.ios.deployment_target = "9.0"
    sp.ios.framework = "Vision"
    sp.libraries = "c++"
    sp.dependency "abseil"
    sp.dependency "tinyxml"
  end
  s.subspec "XCTestLib" do |sp|
    sp.source_files = "Classes/XCTest/*.{h,m,swift,mm,cc}"
    sp.public_header_files = "Classes/XCTest/*.h"
    sp.ios.framework = "XCTest"
    sp.dependency "GTXiLib/GTXiLib"
  end
  s.default_subspec = "GTXiLib"
  end # if false
end
