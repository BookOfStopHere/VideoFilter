//
//  remuxing.h
//  QNWaterMark
//
//  Created by yang on 2017/8/29.
//  Copyright © 2017年 yang. All rights reserved.
//

#ifndef remuxing_h
#define remuxing_h

/**
 * 有的MP4文件有问题，pts／dts 读取的有问题
 * 比如截取的时候从B帧或者P帧开始的，所以前面解码出来的时间戳都是错的，到时Interlace的时候用dts进行流排序出错
 * 有的没有问题
 *
 */

int remuxing(const char *in_filename, const char *out_filename);

#endif /* remuxing_h */
