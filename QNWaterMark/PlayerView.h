//
//  PlayerView.h
//  qn_localsever_demo
//
//  Created by yang on 2017/8/3.
//  Copyright © 2017年 yang. All rights reserved.
//

#import <UIKit/UIKit.h>
#include <AVFoundation/AVFoundation.h>

@interface PlayerView : UIView

@property (nonatomic, strong) UILabel *curTimeLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *startLabel;

@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *detailLabel;

- (void)setPlayer:(AVPlayer *)player;

- (void)pause;
- (void)play;
@end
