//
// Copyright 2018 Google Inc.
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

/**
 *  Umbrella header for public GTX APIs.
 */
#import <UIKit/UIKit.h>

//! Project version number for GTXiLib.
FOUNDATION_EXPORT double gGTXiLibVersionNumber;

//! Project version string for GTXiLib.
FOUNDATION_EXPORT const unsigned char GTXiLibVersionString[];

#import "GTXAccessibilityTree.h"
#import "GTXAnalytics.h"
#import "GTXAnalyticsUtils.h"
#import "GTXAssertions.h"
#import "GTXCheckBlock.h"
#import "GTXCheckResult.h"
#import "GTXChecking.h"
#import "GTXChecksCollection.h"
#import "GTXCommon.h"
#import "GTXElementReference.h"
#import "GTXElementResultCollection.h"
#import "GTXError.h"
#import "GTXErrorReporter.h"
#import "GTXExcludeListBlock.h"
#import "GTXExcludeListFactory.h"
#import "GTXExcludeListing.h"
#import "GTXHierarchyResultCollection.h"
#import "GTXImageAndColorUtils.h"
#import "GTXImageRGBAData.h"
#import "GTXLogProperty.h"
#import "GTXLogger.h"
#import "GTXOCRContrastCheck.h"
#import "GTXPluginXCTestCase.h"
#import "GTXReport.h"
#import "GTXResult.h"
#import "GTXSwizzler.h"
#import "GTXTestCase.h"
#import "GTXTestEnvironment.h"
#import "GTXTestSuite.h"
#import "GTXToolKit.h"
#import "GTXTreeIteratorContext.h"
#import "GTXTreeIteratorElement.h"
#import "GTXXCUIApplicationProxy.h"
#import "GTXXCUIElementProxy.h"
#import "GTXXCUIElementQueryProxy.h"
#import "GTXiLibCore.h"
#import "NSError+GTXAdditions.h"
#import "NSObject+GTXLogging.h"
#import "UIColor+GTXAdditions.h"
