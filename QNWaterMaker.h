//
//  QNWaterMaker.h
//  QNWaterMark
//
//  Created by yang on 2017/8/11.
//  Copyright © 2017年 yang. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface QNWaterMaker : NSObject

+ (void)processVideo:(NSString *)vpath withMark:(NSString *)mPath toPath:(NSString *)oPath;

@end
