/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <UIKit/UIKit.h>

#import <ReactABI26_0_0/ABI26_0_0RCTShadowView.h>

/**
 * Converts float values between Yoga and CoreGraphics representations,
 * especially in terms of edge cases.
 */
ABI26_0_0RCT_EXTERN float ABI26_0_0RCTYogaFloatFromCoreGraphicsFloat(CGFloat value);
ABI26_0_0RCT_EXTERN CGFloat ABI26_0_0RCTCoreGraphicsFloatFromYogaFloat(float value);

@interface ABI26_0_0RCTShadowView (Layout)

#pragma mark - Computed Layout-Inferred Metrics

@property (nonatomic, readonly) UIEdgeInsets paddingAsInsets;
@property (nonatomic, readonly) UIEdgeInsets borderAsInsets;
@property (nonatomic, readonly) UIEdgeInsets compoundInsets;
@property (nonatomic, readonly) CGSize availableSize;

#pragma mark - Measuring

/**
 * Measures shadow view without side-effects.
 */
- (CGSize)sizeThatFitsMinimumSize:(CGSize)minimumSize maximumSize:(CGSize)maximumSize;

#pragma mark - Dirty Propagation Control

/**
 * Designated method to control dirty propagation mechanism.
 * Dirties the shadow view (and all affected shadow views, usually a superview)
 * in terms of layout.
 * The default implementaion does nothing.
 */
- (void)dirtyLayout;

/**
 * Designated method to control dirty propagation mechanism.
 * Clears (makes not dirty) the shadow view.
 * The default implementaion does nothing.
 */
- (void)clearLayout;

@end
