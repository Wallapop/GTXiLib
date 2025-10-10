//
// Copyright 2021 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "GTXLocalizedStringsManagerUtils.h"

#include <string>
#include <vector>

#import "NSString+GTXAdditions.h"
#include "localized_strings_manager.h"

static NSString *const kGTXTranslationsBundleResourceName = @"ios_translations.bundle";

@implementation GTXLocalizedStringsManagerUtils

+ (std::unique_ptr<gtx::LocalizedStringsManager>)defaultLocalizedStringsManager {
  // Try to find the bundle in multiple locations to support both app and test contexts
  NSString *subbundlePath =
      [[NSBundle bundleForClass:self] pathForResource:kGTXTranslationsBundleResourceName
                                               ofType:nil];

  // If not found in the class bundle, try the main bundle (for test contexts)
  if (subbundlePath == nil) {
    subbundlePath = [[NSBundle mainBundle] pathForResource:kGTXTranslationsBundleResourceName
                                                    ofType:nil];
  }

  // Also try looking for bundle name without .bundle extension
  if (subbundlePath == nil) {
    subbundlePath = [[NSBundle mainBundle] pathForResource:@"ios_translations"
                                                     ofType:@"bundle"];
  }

  // Determine the strings directory path
  NSString *strings_directory_path;
  if (subbundlePath != nil) {
    // Bundle found - check if Bazel nested the bundle
    // (i.e., ios_translations.bundle/ios_translations.bundle/Strings-*)
    NSString *nestedBundlePath = [subbundlePath stringByAppendingPathComponent:@"ios_translations.bundle"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:nestedBundlePath isDirectory:nil]) {
      strings_directory_path = nestedBundlePath;
    } else {
      // Not nested, use the bundle path directly
      strings_directory_path = subbundlePath;
    }
  } else {
    // Bundle not found - check if Strings-en directory exists directly in main bundle
    // (Bazel might flatten the bundle contents into the test bundle)
    NSString *enStringsPath = [[NSBundle mainBundle] pathForResource:@"Strings-en/strings"
                                                              ofType:@"xml"];
    if (enStringsPath != nil) {
      // Found Strings-en, use parent directory (main bundle resource path)
      strings_directory_path = [[NSBundle mainBundle] resourcePath];
    } else {
      // Last resort: check in bundleForClass
      enStringsPath = [[NSBundle bundleForClass:self] pathForResource:@"Strings-en/strings"
                                                               ofType:@"xml"];
      if (enStringsPath != nil) {
        strings_directory_path = [[NSBundle bundleForClass:self] resourcePath];
      } else {
        // Nothing found, fall back to main bundle (will likely fail but provides debug info)
        strings_directory_path = [[NSBundle mainBundle] resourcePath];
      }
    }
  }

  std::string strings_directory = [strings_directory_path gtx_stdString];
  std::vector<gtx::Locale> locales(gtx::kDefaultLocales.begin(), gtx::kDefaultLocales.end());
  return gtx::LocalizedStringsManager::LocalizedStringsManagerWithLocalesInDirectory(
      locales, strings_directory);
}

@end
