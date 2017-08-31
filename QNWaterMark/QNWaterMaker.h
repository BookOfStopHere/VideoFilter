//
//  QNWaterMaker.h
//  QNWaterMark
//
//  Created by yang on 2017/8/11.
//  Copyright © 2017年 yang. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface QNWaterMaker : NSObject

//支持后处理的播放器
//后处理 一定的后处理
//视频推流
//直播链路调优
// 工程业务
/**
 *
 * 需要支持视频纠错功能，主要纠错对象是定位I-frame
 * 有些视频截断的时候不是从I-Frame开始的 所以就出现DTS 报错的问题
 * 能提供纠错功能便是极好的
 * 视频编码相关的知识
 *
 */


+ (void)processVideo:(NSString *)vpath withMark:(NSString *)mPath toPath:(NSString *)oPath;


@end
