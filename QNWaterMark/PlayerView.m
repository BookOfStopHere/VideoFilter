//
//  PlayerView.m
//  qn_localsever_demo
//
//  Created by yang on 2017/8/3.
//  Copyright © 2017年 yang. All rights reserved.
//

#import "PlayerView.h"

@implementation PlayerView

- (void)setPlayer:(AVPlayer *)player
{
    AVPlayerLayer *avLayer = (AVPlayerLayer *)self.layer;
    avLayer.player = player;
    [avLayer setBackgroundColor:[UIColor blackColor].CGColor];
    avLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    avLayer.needsDisplayOnBoundsChange = YES;
}

- (void)pause
{
    [self.player pause];
}

- (void)play
{
    [self.player play];
}

+ (Class)layerClass
{
    return AVPlayerLayer.class;
}

- (UILabel *)detailLabel
{
    if(!_detailLabel)
    {
        _detailLabel = [[UILabel alloc] init];
        _detailLabel.textColor = [UIColor orangeColor];
        _detailLabel.font = [UIFont boldSystemFontOfSize:15];
        _detailLabel.backgroundColor = [UIColor whiteColor];
        [self addSubview:_detailLabel];
    }
    _detailLabel.frame = CGRectMake(0 , self.bounds.size.height - 150, self.bounds.size.width , 40);
    [self bringSubviewToFront:_detailLabel];
    return _detailLabel;
}

- (UILabel *)curTimeLabel
{
    if(!_curTimeLabel)
    {
        _curTimeLabel = [[UILabel alloc] init];
        _curTimeLabel.textColor = [UIColor redColor];
        _curTimeLabel.font = [UIFont boldSystemFontOfSize:15];
        [self addSubview:_curTimeLabel];
    }
    _curTimeLabel.frame = CGRectMake(20, self.bounds.size.height - 50, 100, 40);
    return _curTimeLabel;
}

- (UILabel *)durationLabel
{
    if(!_durationLabel)
    {
        _durationLabel = [[UILabel alloc] init];
        _durationLabel.textColor = [UIColor redColor];
        _durationLabel.font = [UIFont boldSystemFontOfSize:15];
        [self addSubview:_durationLabel];
    }
    _durationLabel.frame = CGRectMake(self.bounds.size.width - 110 , self.bounds.size.height - 50, 100, 40);
    return _durationLabel;
}


- (UILabel *)startLabel
{
    if(!_startLabel)
    {
        _startLabel = [[UILabel alloc] init];
        _startLabel.textColor = [UIColor redColor];
        _startLabel.font = [UIFont boldSystemFontOfSize:15];
        [self addSubview:_startLabel];
    }
    _startLabel.frame = CGRectMake(self.bounds.size.width - 200 , self.bounds.size.height - 100, 200, 40);
    return _startLabel;
}

- (UISlider *)slider
{
    if(!_slider)
    {
        UISlider *slider = [[UISlider alloc] init];
        slider.minimumValue = 0;
        slider.maximumValue = 1;
        [slider addTarget:self action:@selector(sliderActon:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:slider];
        _slider = slider;
    }
    return _slider;
}


- (void)layoutSubviews
{
    [super layoutSubviews];
    self.slider.frame = CGRectMake(10, self.bounds.size.height - 30 -10, self.bounds.size.width - 20, 30);
}


- (AVPlayer *)player
{
    AVPlayerLayer *avLayer = (AVPlayerLayer *)self.layer;
    return avLayer.player;
}
- (void)sliderActon:( UISlider *)slider
{
    if(self.player.currentItem.duration.value > 0)
    {
//        Float64 cur =  CMTimeGetSeconds(self.player.currentTime);
        [self.player pause];
        [self.player seekToTime:CMTimeMake(slider.value *CMTimeGetSeconds(self.player.currentItem.duration) , 1) completionHandler:^(BOOL finish){
            [self.player play];
        }];
    }
    else
    {
        _slider.value = 0;
    }
}
@end

