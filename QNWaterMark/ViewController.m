//
//  ViewController.m
//  QNWaterMark
//
//  Created by yang on 2017/8/11.
//  Copyright © 2017年 yang. All rights reserved.
//

#import "ViewController.h"
#include <AVFoundation/AVFoundation.h>
#import "PlayerView.h"
#import "QNWaterMaker.h"
#include "transcoding.h"
#include "remuxing.h"

@interface ViewController ()
{
    AVPlayer *avPlayer;
    AVPlayerItem *playerItem;
    PlayerView *playerView;
    CFAbsoluteTime curT;
    QNWaterMaker *marker;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    playerView = [[PlayerView alloc] initWithFrame:CGRectMake(0, 20, self.view.bounds.size.width, self.view.bounds.size.width*9/16.0)];
    [self.view addSubview:playerView];
    
    
    //sleep wakeup
    UIButton *sleepBtn = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.size.width - 100 -10, self.view.frame.size.height - 25 - 50 - 100, 100, 50)];
    [sleepBtn  setTitle:@"play" forState:0];
    [sleepBtn addTarget:self action:@selector(sleepAction:) forControlEvents:UIControlEventTouchUpInside];
    sleepBtn.backgroundColor = [UIColor orangeColor];
    sleepBtn.selected = 0;
    
    [self.view addSubview:sleepBtn];
    
    
    
    UIButton *clrBtn = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.size.width - 100 -10, self.view.frame.size.height - 25 - 50 - 100 - 100, 100, 50)];
    [clrBtn  setTitle:@"watermark" forState:0];
    [clrBtn addTarget:self action:@selector(watermark) forControlEvents:UIControlEventTouchUpInside];
    clrBtn.backgroundColor = [UIColor orangeColor];
    clrBtn.selected = 0;
    
    [self.view addSubview:clrBtn];
    
    
//    marker = WaterMarkMaker.new;
}

- (void)watermark
{
    
    //俯卧撑的视频 audio frame_size 与 samples 相等
    //110126.mp4 frame_size 与  samples 不相等
    //佟大为也是这样 frame_size 与  samples 不相等
    //
    
//    [marker makeVideo:@"" mark:@""];
    NSString *vPath = [[NSBundle mainBundle] pathForResource:@"s" ofType:@"mp4"];
    NSString *mPath = [[NSBundle mainBundle] pathForResource:@"mark" ofType:@"jpg"];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *oPath =   [paths[0] stringByAppendingPathComponent:@"water.mp4"];
    if([[NSFileManager defaultManager] fileExistsAtPath:oPath isDirectory:NULL])
    {
        [[NSFileManager defaultManager] removeItemAtPath:oPath error:nil];
    }
    
    
    
    NSString *acv = [[NSBundle mainBundle] pathForResource:@"FA_Curves3" ofType:@"acv"];
    ///remuxing
    
//    remuxing(vPath.UTF8String, oPath.UTF8String);
//    return;
    
 (void)process_transcoding_main(vPath.UTF8String, acv.UTF8String,oPath.UTF8String);
    [self playVideo:oPath];
    return;
    
//   [self playVideo:vPath];
//    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        curT = CFAbsoluteTimeGetCurrent();
        [QNWaterMaker processVideo:vPath withMark:mPath toPath:oPath];
        
        curT = CFAbsoluteTimeGetCurrent() - curT;
        dispatch_async(dispatch_get_main_queue(), ^{
            playerView.startLabel.text = [NSString stringWithFormat:@"时间(秒):%f",curT];
        });
        
//    });

    
//    [self playVideo:oPath];

}

- (void)sleepAction:(UIButton *)sleepBtn
{
    sleepBtn.selected = !sleepBtn.isSelected;
}

- (void)playVideo:(NSString *)url
{
    
    NSURL* contentURL = [NSURL fileURLWithPath:url];
    
//    [NSURL URLWithString: [NSString stringWithFormat:@"%@",url]];
//            contentURL = [[NSBundle mainBundle] URLForResource:@"110126" withExtension:@"mp4"];
    if(playerItem)
    {
//        [playerItem removeObserver:self forKeyPath:@"status"];
    }
    playerItem = [AVPlayerItem playerItemWithURL:contentURL];
    if (avPlayer != NULL) {
        [avPlayer pause];
        avPlayer = nil;
    }
    avPlayer = [AVPlayer playerWithPlayerItem:playerItem];
//    [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    avPlayer.muted = NO;
    [avPlayer play];
    [playerView setPlayer:avPlayer];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
