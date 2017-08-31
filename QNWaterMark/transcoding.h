//
//  transcoding.h
//  QNWaterMark
//
//  Created by yang on 2017/8/15.
//  Copyright © 2017年 yang. All rights reserved.
//

#ifndef transcoding_h
#define transcoding_h

/**
 * 不显示的问题是由于视频的编码参数没设置好导致的
 */
int process_transcoding_main(char *inFile,const char *acv, char *outFile);

#endif /* transcoding_h */
