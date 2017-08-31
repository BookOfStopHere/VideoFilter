/*
 * Copyright (c) 2010 Nicolas George
 * Copyright (c) 2011 Stefano Sabatini
 * Copyright (c) 2014 Andrey Utkin
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

/**
 * @file
 * API example for demuxing, decoding, filtering, encoding and muxing
 * @example transcoding.c
 */

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavfilter/avfiltergraph.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>

static AVFormatContext *ifmt_ctx;
static AVFormatContext *ofmt_ctx;
typedef struct FilteringContext {
    AVFilterContext *buffersink_ctx;
    AVFilterContext *buffersrc_ctx;
    AVFilterGraph *filter_graph;
} FilteringContext;
static FilteringContext *filter_ctx;

static int open_input_file(const char *filename)
{
    int ret;
    unsigned int i;
    
    ifmt_ctx = NULL;
    if ((ret = avformat_open_input(&ifmt_ctx, filename, NULL, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open input file\n");
        return ret;
    }
    
    if ((ret = avformat_find_stream_info(ifmt_ctx, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find stream information\n");
        return ret;
    }
    
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *stream;
        AVCodecContext *codec_ctx;
        stream = ifmt_ctx->streams[i];
        codec_ctx = stream->codec;
        /* Reencode video & audio and remux subtitles etc. */
        if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO
            || codec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
            /* Open decoder */
            ret = avcodec_open2(codec_ctx,
                                avcodec_find_decoder(codec_ctx->codec_id), NULL);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Failed to open decoder for stream #%u\n", i);
                return ret;
            }
        }
    }
    
    av_dump_format(ifmt_ctx, 0, filename, 0);
    return 0;
}

#if 0
static int open_output_file(const char *filename)
{
    AVStream *out_stream;
    AVStream *in_stream;
    AVCodecContext *dec_ctx, *enc_ctx;
    AVCodec *encoder;
    int ret;
    unsigned int i;
    
    ofmt_ctx = NULL;
    avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, filename);
    if (!ofmt_ctx) {
        av_log(NULL, AV_LOG_ERROR, "Could not create output context\n");
        return AVERROR_UNKNOWN;
    }
    
    
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        out_stream = avformat_new_stream(ofmt_ctx, NULL);
        if (!out_stream) {
            av_log(NULL, AV_LOG_ERROR, "Failed allocating output stream\n");
            return AVERROR_UNKNOWN;
        }
        
        in_stream = ifmt_ctx->streams[i];
        dec_ctx = in_stream->codec;
        enc_ctx = out_stream->codec;
        
        if (dec_ctx->codec_type == AVMEDIA_TYPE_VIDEO
            || dec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
            /* in this example, we choose transcoding to same codec */
            
            encoder = avcodec_find_encoder(dec_ctx->codec_id);
            if (!encoder) {
                av_log(NULL, AV_LOG_FATAL, "Necessary encoder not found\n");
                return AVERROR_INVALIDDATA;
            }
            
            /* In this example, we transcode to same properties (picture size,
             * sample rate etc.). These properties can be changed for output
             * streams easily using filters */
            if (dec_ctx->codec_type == AVMEDIA_TYPE_VIDEO) {
                enc_ctx->height = dec_ctx->height;
                enc_ctx->width = dec_ctx->width;
                enc_ctx->sample_aspect_ratio = dec_ctx->sample_aspect_ratio;
                /* take first format from list of supported formats */
                if (encoder->pix_fmts)
                    enc_ctx->pix_fmt = encoder->pix_fmts[0];
                else
                    enc_ctx->pix_fmt = dec_ctx->pix_fmt;
                /* video time_base can be set to whatever is handy and supported by encoder */
                enc_ctx->time_base = dec_ctx->time_base;
                
                
            } else {
                enc_ctx->sample_rate = dec_ctx->sample_rate;
                enc_ctx->channel_layout = dec_ctx->channel_layout;
                enc_ctx->channels = av_get_channel_layout_nb_channels(enc_ctx->channel_layout);
                /* take first format from list of supported formats */
                enc_ctx->sample_fmt = encoder->sample_fmts[0];
                enc_ctx->time_base = (AVRational){1, enc_ctx->sample_rate};
            }
            
            /* Third parameter can be used to pass settings to encoder */
            ret = avcodec_open2(enc_ctx, encoder, NULL);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Cannot open video encoder for stream #%u\n", i);
                return ret;
            }
            
        } else if (dec_ctx->codec_type == AVMEDIA_TYPE_UNKNOWN) {
            av_log(NULL, AV_LOG_FATAL, "Elementary stream #%d is of unknown type, cannot proceed\n", i);
            return AVERROR_INVALIDDATA;
        } else {
            /* if this stream must be remuxed */
            ret = avcodec_copy_context(ofmt_ctx->streams[i]->codec,
                                       ifmt_ctx->streams[i]->codec);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Copying stream context failed\n");
                return ret;
            }
        }
        
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
            enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
        
    }
    av_dump_format(ofmt_ctx, 0, filename, 1);
    
    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Could not open output file '%s'", filename);
            return ret;
        }
    }
    
    /* init muxer, write output file header */
    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Error occurred when opening output file\n");
        return ret;
    }
    
    return 0;
}

#else
static int open_output_file(const char *filename)
{
    AVStream*out_stream;
    AVStream*in_stream;
    AVCodecContext*dec_ctx, *enc_ctx;
    AVCodec*encoder;
    int ret;
    unsigned int i;
    ofmt_ctx =NULL;
    avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, filename);
    if (!ofmt_ctx) {
        av_log(NULL, AV_LOG_ERROR, "Could notcreate output context\n");
        return AVERROR_UNKNOWN;
    }
    
    //
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVStream *out_stream = avformat_new_stream(ofmt_ctx, avcodec_find_encoder(in_stream->codec->codec_id));
        if (!out_stream) {
            fprintf(stderr, "Failed allocating output stream\n");
            ret = AVERROR_UNKNOWN;
            return ret;
        }
//        avcodec_get_context_defaults3(out_stream->codec, avcodec_find_encoder(in_stream->codec->codec_id));
        ret = avcodec_copy_context(out_stream->codec, in_stream->codec);
        ///http://ffmpeg.sourcearchive.com/documentation/0.6/libavcodec_2options_8c_3933b21b9dcb9173df3e56673b7a7d76.html
        //The resulting destination codec context will be unopened  i.e. you are required to call avcodec_open() before you can use this AVCodecContext to decode/encode video/audio data.
        if (ret < 0) {
            fprintf(stderr, "Failed to copy context from input to output stream codec context\n");
            return ret;
        }
        out_stream->codec->codec_tag = 0;
        
        
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
            out_stream->codec->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
        
        encoder = avcodec_find_encoder(in_stream->codec->codec_id);
        
        if(in_stream->codec->codec_type == AVMEDIA_TYPE_VIDEO)
        {
            //https://github.com/youtube/yt-watchme/blob/master/app/src/main/jni/ffmpeg-jni.c
            AVDictionary *opts = NULL;
            av_dict_set(&opts, "profile","main",0);
            av_dict_set(&opts, "rc-lookahead", 0, 0);
            av_dict_set(&opts, "tune", "film", 0);
            av_dict_set(&opts, "preset", "ultrafast", 0);
//            av_dict_set(&opts, "vprofile", "baseline", 0);//https://stackoverflow.com/questions/3553003/how-to-encode-h-264-with-libavcodec-x264
            
            
            
            //start
            //https://stackoverflow.com/questions/3553003/how-to-encode-h-264-with-libavcodec-x264
            out_stream->codec->bit_rate = 500*1000;
            out_stream->codec->bit_rate_tolerance = 0;
            out_stream->codec->rc_max_rate = 0;
            out_stream->codec->rc_buffer_size = 0;
            out_stream->codec->gop_size = 40;
            out_stream->codec->max_b_frames = 3;
            out_stream->codec->b_frame_strategy = 1;
            out_stream->codec->coder_type = 1;
            out_stream->codec->me_cmp = 1;
            out_stream->codec->me_range = 16;
            out_stream->codec->qmin = 10;
            out_stream->codec->qmax = 51;
            out_stream->codec->scenechange_threshold = 40;
            out_stream->codec->flags |= CODEC_FLAG_LOOP_FILTER;
            out_stream->codec->me_method = ME_HEX;
            out_stream->codec->me_subpel_quality = 5;
            out_stream->codec->i_quant_factor = 0.71;
            out_stream->codec->qcompress = 0.6;
            out_stream->codec->max_qdiff = 4;
//            out_stream->codec->width = 410 + 60;
//            out_stream->codec->height = 728 + 60;
            ////end
            
            ret = avcodec_open2(out_stream->codec, encoder,&opts);
            av_dict_free(&opts);
        }
        else
        {
            ret = avcodec_open2(out_stream->codec, encoder, NULL);
        }
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot open video encoder for stream #%u\n", i);
            return ret;
        }
//        stream_ctx[i].enc_ctx = out_stream->codec;
    }
    //
    
    av_dump_format(ofmt_ctx, 0, filename, 1);
    if (!(ofmt_ctx->oformat->flags &AVFMT_NOFILE)) {
        ret =avio_open(&ofmt_ctx->pb, filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Could notopen output file '%s'", filename);
            return ret;
        }
    }
    
    
    /* init muxer, write output file header */
    ret =avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        av_log(NULL,AV_LOG_ERROR, "Error occurred when openingoutput file\n");
        return ret;
    }
    return 0;
}

#endif

static int init_filter(FilteringContext* fctx, AVCodecContext *dec_ctx,
                       AVCodecContext *enc_ctx, const char *filter_spec)
{
    char args[512];
    int ret = 0;
    AVFilter *buffersrc = NULL;
    AVFilter *buffersink = NULL;
    AVFilterContext *buffersrc_ctx = NULL;
    AVFilterContext *buffersink_ctx = NULL;
    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *inputs  = avfilter_inout_alloc();
    AVFilterGraph *filter_graph = avfilter_graph_alloc();
    
    if (!outputs || !inputs || !filter_graph) {
        ret = AVERROR(ENOMEM);
        goto end;
    }
    
    if (dec_ctx->codec_type == AVMEDIA_TYPE_VIDEO) {
        buffersrc = avfilter_get_by_name("buffer");
        buffersink = avfilter_get_by_name("buffersink");
        if (!buffersrc || !buffersink) {
            av_log(NULL, AV_LOG_ERROR, "filtering source or sink element not found\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }
        
        snprintf(args, sizeof(args),
                 "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
                 dec_ctx->width, dec_ctx->height, dec_ctx->pix_fmt,
                 dec_ctx->time_base.num, dec_ctx->time_base.den,
                 dec_ctx->sample_aspect_ratio.num,
                 dec_ctx->sample_aspect_ratio.den);
        
        ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in",
                                           args, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot create buffer source\n");
            goto end;
        }
        
        ret = avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out",
                                           NULL, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot create buffer sink\n");
            goto end;
        }
        
        ret = av_opt_set_bin(buffersink_ctx, "pix_fmts",
                             (uint8_t*)&enc_ctx->pix_fmt, sizeof(enc_ctx->pix_fmt),
                             AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot set output pixel format\n");
            goto end;
        }
    } else if (dec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
        buffersrc = avfilter_get_by_name("abuffer");
        buffersink = avfilter_get_by_name("abuffersink");
        if (!buffersrc || !buffersink) {
            av_log(NULL, AV_LOG_ERROR, "filtering source or sink element not found\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }
        
        if (!dec_ctx->channel_layout)
            dec_ctx->channel_layout =
            av_get_default_channel_layout(dec_ctx->channels);
        snprintf(args, sizeof(args),
                 "time_base=%d/%d:sample_rate=%d:sample_fmt=%s:channel_layout=0x%"PRIx64,
                 dec_ctx->time_base.num, dec_ctx->time_base.den, dec_ctx->sample_rate,
                 av_get_sample_fmt_name(dec_ctx->sample_fmt),
                 dec_ctx->channel_layout);
        ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in",
                                           args, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot create audio buffer source\n");
            goto end;
        }
        
        ret = avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out",
                                           NULL, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot create audio buffer sink\n");
            goto end;
        }
        
        ret = av_opt_set_bin(buffersink_ctx, "sample_fmts",
                             (uint8_t*)&enc_ctx->sample_fmt, sizeof(enc_ctx->sample_fmt),
                             AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot set output sample format\n");
            goto end;
        }
        
        ret = av_opt_set_bin(buffersink_ctx, "channel_layouts",
                             (uint8_t*)&enc_ctx->channel_layout,
                             sizeof(enc_ctx->channel_layout), AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot set output channel layout\n");
            goto end;
        }
        
        ret = av_opt_set_bin(buffersink_ctx, "sample_rates",
                             (uint8_t*)&enc_ctx->sample_rate, sizeof(enc_ctx->sample_rate),
                             AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot set output sample rate\n");
            goto end;
        }
    } else {
        ret = AVERROR_UNKNOWN;
        goto end;
    }
    
    /* Endpoints for the filter graph. */
    outputs->name       = av_strdup("in");
    outputs->filter_ctx = buffersrc_ctx;
    outputs->pad_idx    = 0;
    outputs->next       = NULL;
    
    inputs->name       = av_strdup("out");
    inputs->filter_ctx = buffersink_ctx;
    inputs->pad_idx    = 0;
    inputs->next       = NULL;
    
    if (!outputs->name || !inputs->name) {
        ret = AVERROR(ENOMEM);
        goto end;
    }
    
    if ((ret = avfilter_graph_parse_ptr(filter_graph, filter_spec,
                                        &inputs, &outputs, NULL)) < 0)
        goto end;
    
    if ((ret = avfilter_graph_config(filter_graph, NULL)) < 0)
        goto end;
    
    /* Fill FilteringContext */
    fctx->buffersrc_ctx = buffersrc_ctx;
    fctx->buffersink_ctx = buffersink_ctx;
    fctx->filter_graph = filter_graph;
    
end:
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    
    return ret;
}

static int init_filters(const char *acv)
{
    const char *filter_spec;
    unsigned int i;
    int ret;
    filter_ctx = av_malloc_array(ifmt_ctx->nb_streams, sizeof(*filter_ctx));
    if (!filter_ctx)
        return AVERROR(ENOMEM);
    
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        filter_ctx[i].buffersrc_ctx  = NULL;
        filter_ctx[i].buffersink_ctx = NULL;
        filter_ctx[i].filter_graph   = NULL;
        if (!(ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO
              || ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO))
            continue;
        char ll[1024];
        snprintf(ll, sizeof(ll), "curves=psfile='%s':green='0/0 0.45/0.53 1/1'",acv);
        
        if (ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO)
            filter_spec =
            "lenscorrection=k1=-0.001:k2=1";//曲线
//            "drawtext=text=this is a \\\\\\'string\\\\\\'\\\\: may contain one\\, or more\\, special characters";//--enable-libfreetype
//"split [main][tmp]; [tmp] crop=iw:ih/2:0:0, vflip [flip]; [main][flip] overlay=0:H/2";//视频一分为二 上下旋转  最后拼在一起
//            "lut2='ifnot(x-y,0,pow(2,bdx)-1):ifnot(x-y,pow(2,bdx-1),pow(2,bdx)-1):ifnot(x-y,pow(2,bdx-1),pow(2,bdx)-1)'";//
//            "kerndeint=map=1";//
//            "hue=h=90:s=1";//
//            "fftfilt=dc_Y=128:weight_Y='squish(1-(Y+X)/100)'";//频域变换
//            "edgedetect=mode=colormix:high=0";//保留色彩的边缘检测
//            "edgedetect=low=0.1:high=0.4";//边沿检测
// "curves=psfile='MyCurvesPresets/purple.acv':green='0/0 0.45/0.53 1/1'";//acv photoshop 曲线文件
//            "curves=r='0/0.11 .42/.51 1/0.95':g='0/0 0.50/0.48 1/1':b='0/0.22 .49/.44 1/0.8'";
//            " crop=150:150";
//            "hflip";//没什么效果
            
//            "crop=w=310:h=668:x=100:y=30";
//        "crop=350:668 pad=iw:ih:30:30:pink";//
//            "pad=470:818:30:10:pink";//填充视频(pad)在视频帧上增加一快额外额区域，经常用在播放的时候显示不同的横纵比 语法：pad=width[:height:[:x[:y:[:color]]]]
//"cropdetect";//去黑边
//"drawbox=x=100:y=100:w=100:h=100:color=pink@0.5:t=20";
//"lutyuv='y=maxval+minval-val:u=maxval+minval-val:v=maxval+minval-val'";// lueyuv /lue /luergb 滤镜
//"boxblur=2:1:cr=0:ar=0";//模糊处理
//"colorlevels=romin=0.5:gomin=0.5:bomin=0.5";//增加亮度
//"colorchannelmixer=.3:.4:.3:0:.3:.4:.3:0:.3:.4:.3";//灰颜色处理
//"crop=w=200:h=300:x=100:y=200";//裁剪视频
//"drawbox=x=0:y=0:w=410:h=728:color=pink@0.5:t=max";//添加视频遮罩
//            "drawgrid=width=100:height=100:thickness=8:color=red@0.9";//绘制网格
//        "delogo=x=300:y=20:w=100:h=100";//去除水印
        //"boxblur=2:1:cr=0:ar=0";
        //"curves=vintage";
        //"null"; /* passthrough (dummy) filter for video */
        else
            filter_spec = "anull"; /* passthrough (dummy) filter for audio */
        ret = init_filter(&filter_ctx[i], ifmt_ctx->streams[i]->codec,
                          ofmt_ctx->streams[i]->codec, filter_spec);
        if (ret)
            return ret;
    }
    return 0;
}

static int encode_write_frame(AVFrame *filt_frame, unsigned int stream_index, int *got_frame) {
    int ret;
    int got_frame_local;
    AVPacket enc_pkt;
    int (*enc_func)(AVCodecContext *, AVPacket *, const AVFrame *, int *) =
    (ifmt_ctx->streams[stream_index]->codec->codec_type ==
     AVMEDIA_TYPE_VIDEO) ? avcodec_encode_video2 : avcodec_encode_audio2;
    
    if (!got_frame)
        got_frame = &got_frame_local;
    
    av_log(NULL, AV_LOG_INFO, "Encoding frame\n");
    /* encode filtered frame */
    enc_pkt.data = NULL;
    enc_pkt.size = 0;
    av_init_packet(&enc_pkt);
    
    AVCodecContext *codec = ofmt_ctx->streams[stream_index]->codec;
    ret = enc_func(codec, &enc_pkt,
                   filt_frame, got_frame);
    av_frame_free(&filt_frame);
    if (ret < 0)
        return ret;
    if (!(*got_frame))
        return 0;
    
    /* prepare packet for muxing */
    enc_pkt.stream_index = stream_index;
    av_packet_rescale_ts(&enc_pkt,
                         ofmt_ctx->streams[stream_index]->codec->time_base,
                         ofmt_ctx->streams[stream_index]->time_base);
    
    av_log(NULL, AV_LOG_DEBUG, "Muxing frame\n");
    /* mux encoded frame */
    ret = av_interleaved_write_frame(ofmt_ctx, &enc_pkt);
    return ret;
}

static int filter_encode_write_frame(AVFrame *frame, unsigned int stream_index)
{
    int ret;
    AVFrame *filt_frame;
    
    
    av_log(NULL, AV_LOG_INFO, "Pushing decoded frame to filters\n");
    /* push the decoded frame into the filtergraph */
    ret = av_buffersrc_add_frame_flags(filter_ctx[stream_index].buffersrc_ctx,
                                       frame, 0);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Error while feeding the filtergraph\n");
        return ret;
    }
    
    /* pull filtered frames from the filtergraph */
    while (1) {
        filt_frame = av_frame_alloc();
        if (!filt_frame) {
            ret = AVERROR(ENOMEM);
            break;
        }
        av_log(NULL, AV_LOG_INFO, "Pulling filtered frame from filters\n");
        ret = av_buffersink_get_frame(filter_ctx[stream_index].buffersink_ctx,
                                      filt_frame);
        if (ret < 0) {
            /* if no more frames for output - returns AVERROR(EAGAIN)
             * if flushed and no more frames for output - returns AVERROR_EOF
             * rewrite retcode to 0 to show it as normal procedure completion
             */
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                ret = 0;
            av_frame_free(&filt_frame);
            break;
        }
        
        filt_frame->pict_type = AV_PICTURE_TYPE_NONE;
        ret = encode_write_frame(filt_frame, stream_index, NULL);
        if (ret < 0)
            break;
    }
    
    return ret;
}

static int flush_encoder(unsigned int stream_index)
{
    int ret;
    int got_frame;
    
    if (!(ofmt_ctx->streams[stream_index]->codec->codec->capabilities &
          AV_CODEC_CAP_DELAY))
        return 0;
    
    while (1) {
        av_log(NULL, AV_LOG_INFO, "Flushing stream #%u encoder\n", stream_index);
        ret = encode_write_frame(NULL, stream_index, &got_frame);
        if (ret < 0)
            break;
        if (!got_frame)
            return 0;
    }
    return ret;
}

#define ONLY_VIDEO 1
int process_transcoding_main(char *inFile,const char *acv, char *outFile)
{
    int ret;
    AVPacket packet = { .data = NULL, .size = 0 };
    AVFrame *frame = NULL;
    enum AVMediaType type;
    unsigned int stream_index;
    unsigned int i;
    int got_frame;
    int (*dec_func)(AVCodecContext *, AVFrame *, int *, const AVPacket *);

    int a_pts = 8088;
    

    av_register_all();
    avfilter_register_all();

    if ((ret = open_input_file(inFile)) < 0)
        goto end;
    if ((ret = open_output_file(outFile)) < 0)
        goto end;
    if ((ret = init_filters(acv)) < 0)
        goto end;

    /* read all packets */
    while (1) {
        if ((ret = av_read_frame(ifmt_ctx, &packet)) < 0)
            break;
        stream_index = packet.stream_index;
        type = ifmt_ctx->streams[packet.stream_index]->codec->codec_type;
        av_log(NULL, AV_LOG_DEBUG, "Demuxer gave frame of stream_index %u\n",
               stream_index);
        
        if (filter_ctx[stream_index].filter_graph) {
            av_log(NULL, AV_LOG_DEBUG, "Going to reencode&filter the frame\n");
            frame = av_frame_alloc();
            if (!frame) {
                ret = AVERROR(ENOMEM);
                break;
            }
            av_packet_rescale_ts(&packet,
                                 ifmt_ctx->streams[stream_index]->time_base,
                                 ifmt_ctx->streams[stream_index]->codec->time_base);
#if ONLY_VIDEO
            if(type == AVMEDIA_TYPE_VIDEO)
            {
#endif
                    dec_func = (type == AVMEDIA_TYPE_VIDEO) ? avcodec_decode_video2 :
                    avcodec_decode_audio4;
                    ret = dec_func(ifmt_ctx->streams[stream_index]->codec, frame,
                                   &got_frame, &packet);
                    if (ret < 0) {
                        av_frame_free(&frame);
                        av_log(NULL, AV_LOG_ERROR, "Decoding failed\n");
                        break;
                    }
                    
                    if (got_frame) {
                        frame->pts = av_frame_get_best_effort_timestamp(frame);
                        ret = filter_encode_write_frame(frame, stream_index);
                        av_frame_free(&frame);
                        if (ret < 0)
                            goto end;
                    } else {
                        av_frame_free(&frame);
                    }
#if ONLY_VIDEO
            }
            else
                av_frame_free(&frame);
#endif
        } else {
            /* remux this frame without reencoding */
            av_packet_rescale_ts(&packet,
                                 ifmt_ctx->streams[stream_index]->time_base,
                                 ofmt_ctx->streams[stream_index]->time_base);
            
            ret = av_interleaved_write_frame(ofmt_ctx, &packet);
            if (ret < 0)
                goto end;
        }
        av_packet_unref(&packet);
    }
    
    /* flush filters and encoders */
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        /* flush filter */
#if ONLY_VIDEO
        if(ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO)
#endif
        {
            if (!filter_ctx[i].filter_graph)
                continue;
            ret = filter_encode_write_frame(NULL, i);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Flushing filter failed\n");
                goto end;
            }
            
        
            /* flush encoder */
            ret = flush_encoder(i);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Flushing encoder failed\n");
                goto end;
            }
        }
    }
    
    av_write_trailer(ofmt_ctx);
end:
    av_packet_unref(&packet);
    av_frame_free(&frame);
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        avcodec_close(ifmt_ctx->streams[i]->codec);
        if (ofmt_ctx && ofmt_ctx->nb_streams > i && ofmt_ctx->streams[i] && ofmt_ctx->streams[i]->codec)
            avcodec_close(ofmt_ctx->streams[i]->codec);
        if (filter_ctx && filter_ctx[i].filter_graph)
            avfilter_graph_free(&filter_ctx[i].filter_graph);
    }
    av_free(filter_ctx);
    avformat_close_input(&ifmt_ctx);
    if (ofmt_ctx && !(ofmt_ctx->oformat->flags & AVFMT_NOFILE))
        avio_closep(&ofmt_ctx->pb);
    avformat_free_context(ofmt_ctx);
    
    if (ret < 0)
        av_log(NULL, AV_LOG_ERROR, "Error occurred: %s\n", av_err2str(ret));
    
    return ret ? 1 : 0;
}
