//
//  QNWaterMaker.m
//  QNWaterMark
//
//  Created by yang on 2017/8/11.
//  Copyright © 2017年 yang. All rights reserved.
//

#import "QNWaterMaker.h"
#define USEFILTER 1

#define YANG 1
#if YANG

#ifdef __cplusplus
extern "C"
{
#endif
    
#include <libavutil/time.h>
#include <libavutil/opt.h>
#include <libavutil/pixfmt.h>
#include <libavutil/mathematics.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/audio_fifo.h>
#if USEFILTER
#include <libavfilter/avfiltergraph.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#endif
    
#ifdef __cplusplus
};
#endif


#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static int add_samples_to_fifo(AVAudioFifo *fifo,
                               uint8_t **converted_input_samples,
                               const int frame_size);
#if USEFILTER
int filter_change = 1;
char filter_descr[1024] = "null";

const char *filter_mirror = "crop=iw/2:ih:0:0,split[left][tmp];[tmp]hflip[right]; \
[left]pad=iw*2[a];[a][right]overlay=w";
const char *filter_watermark = "movie=test.jpg[wm];[in][wm]overlay=5:5[out]";
const char *filter_negate = "negate[out]";
const char *filter_edge = "edgedetect[out]";
const char *filter_split4 = "scale=iw/2:ih/2[in_tmp];[in_tmp]split=4[in_1][in_2][in_3][in_4];[in_1]pad=iw*2:ih*2[a];[a][in_2]overlay=w[b];[b][in_3]overlay=0:h[d];[d][in_4]overlay=w:h[out]";
const char *filter_vintage = "curves=vintage";
typedef enum{
    FILTER_NULL = 48,
    FILTER_MIRROR,
    FILTER_WATERMATK,
    FILTER_NEGATE,
    FILTER_EDGE,
    FILTER_SPLIT4,
    FILTER_VINTAGE
}FILTERS;

//AVFilterContext *buffersink_ctx;
//AVFilterContext *buffersrc_ctx;
//AVFilterGraph *filter_graph;
//AVFilter *buffersrc;
//AVFilter *buffersink;
//AVFrame* picref;
#endif
/**
 * Convert an error code into a text message.
 * @param error Error code to be converted
 * @return Corresponding error text (not thread-safe)
 */
static const char *get_error_text(const int error)
{
    static char error_buffer[255];
    av_strerror(error, error_buffer, sizeof(error_buffer));
    return error_buffer;
}
/**
 * global parameters
 */
AVFormatContext *ifmt_ctx = NULL;
AVFormatContext *ofmt_ctx = NULL;
AVAudioFifo *fifo = NULL;
typedef struct FilteringContext{
    AVFilterContext*buffersink_ctx;
    AVFilterContext*buffersrc_ctx;
    AVFilterGraph*filter_graph;
} FilteringContext;
static FilteringContext *filter_ctx;


typedef struct StreamContext {
    AVCodecContext *dec_ctx;
    AVCodecContext *enc_ctx;
} StreamContext;
static StreamContext *stream_ctx;

/**
 * Decode 封装
 */
static int decode(AVCodecContext *avctx, AVFrame *frame, int *got_frame, AVPacket *pkt)
{
    int ret;
    
    *got_frame = 0;
    
    if (pkt) {
        ret = avcodec_send_packet(avctx, pkt);
        // In particular, we don't expect AVERROR(EAGAIN), because we read all
        // decoded frames with avcodec_receive_frame() until done.
        if (ret < 0 && ret != AVERROR_EOF)
            return ret;
    }
    
    ret = avcodec_receive_frame(avctx, frame);
    if (ret < 0 && ret != AVERROR(EAGAIN))
        return ret;
    if (ret >= 0)
        *got_frame = 1;
    
    return 0;
}


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
    
    stream_ctx = av_mallocz_array(ifmt_ctx->nb_streams, sizeof(*stream_ctx));
    if (!stream_ctx)
        return AVERROR(ENOMEM);
    
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *stream = ifmt_ctx->streams[i];
        AVCodec *dec = avcodec_find_decoder(stream->codecpar->codec_id);
        AVCodecContext *codec_ctx;
        if (!dec) {
            av_log(NULL, AV_LOG_ERROR, "Failed to find decoder for stream #%u\n", i);
            return AVERROR_DECODER_NOT_FOUND;
        }
        codec_ctx = avcodec_alloc_context3(dec);
        if (!codec_ctx) {
            av_log(NULL, AV_LOG_ERROR, "Failed to allocate the decoder context for stream #%u\n", i);
            return AVERROR(ENOMEM);
        }
        ret = avcodec_parameters_to_context(codec_ctx, stream->codecpar);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Failed to copy decoder parameters to input decoder context "
                   "for stream #%u\n", i);
            return ret;
        }
        /* Reencode video & audio and remux subtitles etc. */
        if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO
            || codec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
            if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO)
                codec_ctx->framerate = av_guess_frame_rate(ifmt_ctx, stream, NULL);
            /* Open decoder */
            ret = avcodec_open2(codec_ctx, dec, NULL);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Failed to open decoder for stream #%u\n", i);
                return ret;
            }
        }
        stream_ctx[i].dec_ctx = codec_ctx;
    }
    
    av_dump_format(ifmt_ctx, 0, filename, 0);
    return 0;
}


#define B_TEST 0
//http://blog.csdn.net/leixiaohua1020/article/details/26838535
#if !B_TEST
//可参考ffmpeg examples remuxing.c int main(int argc, char **argv)
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
        dec_ctx = stream_ctx[i].dec_ctx;
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVStream *out_stream = avformat_new_stream(ofmt_ctx, NULL);
        if (!out_stream) {
            fprintf(stderr, "Failed allocating output stream\n");
            ret = AVERROR_UNKNOWN;
            return ret;
        }
        
        ret = avcodec_copy_context(out_stream->codec, in_stream->codec);
        if (ret < 0) {
            fprintf(stderr, "Failed to copy context from input to output stream codec context\n");
            return ret;
        }
        out_stream->codec->codec_tag = 0;
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
            out_stream->codec->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
        
          stream_ctx[i].enc_ctx = out_stream->codec;
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
#else
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
        dec_ctx = stream_ctx[i].dec_ctx;
        
        if (dec_ctx->codec_type == AVMEDIA_TYPE_VIDEO
            || dec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
            /* in this example, we choose transcoding to same codec */
            encoder = avcodec_find_encoder(dec_ctx->codec_id);
            if (!encoder) {
                av_log(NULL, AV_LOG_FATAL, "Necessary encoder not found\n");
                return AVERROR_INVALIDDATA;
            }
            enc_ctx = avcodec_alloc_context3(encoder);
            if (!enc_ctx) {
                av_log(NULL, AV_LOG_FATAL, "Failed to allocate the encoder context\n");
                return AVERROR(ENOMEM);
            }
            
            /* In this example, we transcode to same properties (picture size,
             * sample rate etc.). These properties can be changed for output
             * streams easily using filters */
            if (dec_ctx->codec_type == AVMEDIA_TYPE_VIDEO) {
                enc_ctx->height = dec_ctx->height;
                enc_ctx->width = dec_ctx->width;
                enc_ctx->sample_aspect_ratio = dec_ctx->sample_aspect_ratio;
                enc_ctx->framerate = dec_ctx->framerate;
                /* take first format from list of supported formats */
                if (encoder->pix_fmts)
                    enc_ctx->pix_fmt = encoder->pix_fmts[0];
                else
                    enc_ctx->pix_fmt = dec_ctx->pix_fmt;
                /* video time_base can be set to whatever is handy and supported by encoder */
                enc_ctx->time_base = av_inv_q(dec_ctx->framerate);
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
            ret = avcodec_parameters_from_context(out_stream->codecpar, enc_ctx);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Failed to copy encoder parameters to output stream #%u\n", i);
                return ret;
            }
            if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
                enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
            
            out_stream->time_base = enc_ctx->time_base;
            stream_ctx[i].enc_ctx = enc_ctx;
        } else if (dec_ctx->codec_type == AVMEDIA_TYPE_UNKNOWN) {
            av_log(NULL, AV_LOG_FATAL, "Elementary stream #%d is of unknown type, cannot proceed\n", i);
            return AVERROR_INVALIDDATA;
        } else {
            /* if this stream must be remuxed */
            ret = avcodec_parameters_copy(out_stream->codecpar, in_stream->codecpar);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Copying parameters for stream #%u failed\n", i);
                return ret;
            }
            out_stream->time_base = in_stream->time_base;
        }
        
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

#endif

static int init_filter(FilteringContext* fctx, AVCodecContext *dec_ctx,
                      AVCodecContext *enc_ctx, const char *filter_spec)
{
    char args[512];
    int ret = 0;
    AVFilter*buffersrc = NULL;
    AVFilter*buffersink = NULL;
    AVFilterContext*buffersrc_ctx = NULL;
    AVFilterContext*buffersink_ctx = NULL;
    AVFilterInOut*outputs = avfilter_inout_alloc();
    AVFilterInOut*inputs  = avfilter_inout_alloc();
    AVFilterGraph*filter_graph = avfilter_graph_alloc();
    if (!outputs || !inputs || !filter_graph) {
        ret =AVERROR(ENOMEM);
        goto end;
    }
    if (dec_ctx->codec_type == AVMEDIA_TYPE_VIDEO) {
        buffersrc =avfilter_get_by_name("buffer");
        buffersink= avfilter_get_by_name("buffersink");
        if (!buffersrc || !buffersink) {
            av_log(NULL, AV_LOG_ERROR, "filteringsource or sink element not found\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }
        snprintf(args, sizeof(args),
                  "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
                  dec_ctx->width, dec_ctx->height, dec_ctx->pix_fmt,
                  dec_ctx->time_base.num,dec_ctx->time_base.den,
                  dec_ctx->sample_aspect_ratio.num,
                  dec_ctx->sample_aspect_ratio.den);
        ret =avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in",
                                          args, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannotcreate buffer source\n");
            goto end;
        }
        ret =avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out",
                                          NULL, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannotcreate buffer sink\n");
            goto end;
        }
        ret =av_opt_set_bin(buffersink_ctx, "pix_fmts",
                            (uint8_t*)&enc_ctx->pix_fmt, sizeof(enc_ctx->pix_fmt),
                            AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot setoutput pixel format\n");
            goto end;
        }
    } else if(dec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
        buffersrc = avfilter_get_by_name("abuffer");
        buffersink= avfilter_get_by_name("abuffersink");
        if (!buffersrc || !buffersink) {
            av_log(NULL, AV_LOG_ERROR, "filteringsource or sink element not found\n");
            ret =AVERROR_UNKNOWN;
            goto end;
        }
        if (!dec_ctx->channel_layout)
            dec_ctx->channel_layout =
            av_get_default_channel_layout(dec_ctx->channels);
        snprintf(args, sizeof(args),
                  "time_base=%d/%d:sample_rate=%d:sample_fmt=%s:channel_layout=0x%"PRIx64,
                  dec_ctx->time_base.num, dec_ctx->time_base.den,dec_ctx->sample_rate,
                  av_get_sample_fmt_name(dec_ctx->sample_fmt),
                  dec_ctx->channel_layout);
        ret =avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in",
                                          args, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannotcreate audio buffer source\n");
            goto end;
        }
        ret =avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out",
                                          NULL, NULL, filter_graph);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannotcreate audio buffer sink\n");
            goto end;
        }
        ret = av_opt_set_bin(buffersink_ctx, "sample_fmts",
                             (uint8_t*)&enc_ctx->sample_fmt, sizeof(enc_ctx->sample_fmt),
                             AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot setoutput sample format\n");
            goto end;
        }
        ret =av_opt_set_bin(buffersink_ctx, "channel_layouts",
                            (uint8_t*)&enc_ctx->channel_layout,
                            sizeof(enc_ctx->channel_layout),AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot setoutput channel layout\n");
            goto end;
        }
        ret =av_opt_set_bin(buffersink_ctx, "sample_rates",
                            (uint8_t*)&enc_ctx->sample_rate, sizeof(enc_ctx->sample_rate),
                            AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot setoutput sample rate\n");
            goto end;
        }
    } else {
        ret =AVERROR_UNKNOWN;
        goto end;
    }
    /* Endpoints for the filter graph. */
    outputs->name       =av_strdup("in");
    outputs->filter_ctx = buffersrc_ctx;
    outputs->pad_idx    = 0;
    outputs->next       = NULL;
    inputs->name       = av_strdup("out");
    inputs->filter_ctx = buffersink_ctx;
    inputs->pad_idx    = 0;
    inputs->next       = NULL;
    if (!outputs->name || !inputs->name) {
        ret =AVERROR(ENOMEM);
        goto end;
    }
    if ((ret = avfilter_graph_parse_ptr(filter_graph,filter_spec,
                                        &inputs, &outputs, NULL)) < 0)
        goto end;
    if ((ret = avfilter_graph_config(filter_graph, NULL))< 0)
        goto end;
    /* Fill FilteringContext */
    fctx->buffersrc_ctx = buffersrc_ctx;
    fctx->buffersink_ctx = buffersink_ctx;
    fctx->filter_graph= filter_graph;
end:
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    return ret;
}

#define A_TEST 1
#if A_TEST
static int init_filters(char *mark)
{
    const char*filter_spec;
    unsigned int i;
    int ret;
    char filter_str[1024];
    snprintf(filter_str, sizeof(filter_str), "movie=%s[wm];[in][wm]overlay=200:90[out]",mark);
    filter_ctx =(FilteringContext *)av_malloc_array(ifmt_ctx->nb_streams, sizeof(*filter_ctx));
    if (!filter_ctx)
        return AVERROR(ENOMEM);
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        filter_ctx[i].buffersrc_ctx  =NULL;
        filter_ctx[i].buffersink_ctx= NULL;
        filter_ctx[i].filter_graph   =NULL;
        if(!(ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO
             ||ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO))
            continue;
        if (ifmt_ctx->streams[i]->codec->codec_type== AVMEDIA_TYPE_VIDEO)
            filter_spec = filter_str; /* passthrough (dummy) filter for video */
        else
            filter_spec = "anull"; /* passthrough (dummy) filter for audio */  
        ret =init_filter(&filter_ctx[i],stream_ctx[i].dec_ctx,
                         stream_ctx[i].enc_ctx, filter_spec);
        if (ret)  
            return ret;  
    }  
    return 0;  
}

#else
static int init_filters(char *mark)
{
    char args[512];
    int ret = 0;
    AVFilter *buffersrc  = avfilter_get_by_name("buffer");
    AVFilter *buffersink = avfilter_get_by_name("buffersink");
    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *inputs  = avfilter_inout_alloc();
    char filters_descr[1024];
    snprintf(filters_descr, sizeof(filters_descr), "movie=%s[wm];[in][wm]overlay=100:5[out]",mark);
    unsigned int video_stream_index = 0;
     for (int i = 0; i < ifmt_ctx->nb_streams; i++)
     {
          if (ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO)
          {
              video_stream_index = i;
              break;
          }
     }
    
    AVRational time_base = ifmt_ctx->streams[video_stream_index]->time_base;
    enum AVPixelFormat pix_fmts[] = { AV_PIX_FMT_GRAY8, AV_PIX_FMT_NONE };
    
    AVFilterGraph *filter_graph = avfilter_graph_alloc();
    if (!outputs || !inputs || !filter_graph) {
        ret = AVERROR(ENOMEM);
        goto end;
    }
    AVCodecContext *dec_ctx = ifmt_ctx->streams[video_stream_index]->codec;
    /* buffer video source: the decoded frames from the decoder will be inserted here. */
    snprintf(args, sizeof(args),
             "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
             dec_ctx->width, dec_ctx->height, dec_ctx->pix_fmt,
             time_base.num, time_base.den,
             dec_ctx->sample_aspect_ratio.num, dec_ctx->sample_aspect_ratio.den);
    

    AVFilterContext*buffersrc_ctx = NULL;
    AVFilterContext*buffersink_ctx = NULL;
    
    ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in",
                                       args, NULL, filter_graph);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot create buffer source\n");
        goto end;
    }
    
    /* buffer video sink: to terminate the filter chain. */
    ret = avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out",
                                       NULL, NULL, filter_graph);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot create buffer sink\n");
        goto end;
    }
    
    ret = av_opt_set_int_list(buffersink_ctx, "pix_fmts", pix_fmts,
                              AV_PIX_FMT_NONE, AV_OPT_SEARCH_CHILDREN);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot set output pixel format\n");
        goto end;
    }
    
    /*
     * Set the endpoints for the filter graph. The filter_graph will
     * be linked to the graph described by filters_descr.
     */
    
    /*
     * The buffer source output must be connected to the input pad of
     * the first filter described by filters_descr; since the first
     * filter input label is not specified, it is set to "in" by
     * default.
     */
    outputs->name       = av_strdup("in");
    outputs->filter_ctx = buffersrc_ctx;
    outputs->pad_idx    = 0;
    outputs->next       = NULL;
    
    /*
     * The buffer sink input must be connected to the output pad of
     * the last filter described by filters_descr; since the last
     * filter output label is not specified, it is set to "out" by
     * default.
     */
    inputs->name       = av_strdup("out");
    inputs->filter_ctx = buffersink_ctx;
    inputs->pad_idx    = 0;
    inputs->next       = NULL;
    
    if ((ret = avfilter_graph_parse_ptr(filter_graph, filters_descr,
                                        &inputs, &outputs, NULL)) < 0)
        goto end;
    
    if ((ret = avfilter_graph_config(filter_graph, NULL)) < 0)
        goto end;
    
end:
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    
    return ret;
}
#endif

/**
 * Initialize one input frame for writing to the output file.
 * The frame will be exactly frame_size samples large.
 */
static int init_output_frame(AVFrame **frame,
                             AVCodecContext *output_codec_context,
                             int frame_size)
{
    int error;
    
    /** Create a new frame to store the audio samples. */
    if (!(*frame = av_frame_alloc())) {
        fprintf(stderr, "Could not allocate output frame\n");
        return AVERROR_EXIT;
    }
    
    /**
     * Set the frame's parameters, especially its size and format.
     * av_frame_get_buffer needs this to allocate memory for the
     * audio samples of the frame.
     * Default channel layouts based on the number of channels
     * are assumed for simplicity.
     */
    (*frame)->nb_samples     = frame_size;
    (*frame)->channel_layout = output_codec_context->channel_layout;
    (*frame)->format         = output_codec_context->sample_fmt;
    (*frame)->sample_rate    = output_codec_context->sample_rate;
    
    /**
     * Allocate the samples of the created frame. This call will make
     * sure that the audio frame can hold as many samples as specified.
     */
    if ((error = av_frame_get_buffer(*frame, 0)) < 0) {
        fprintf(stderr, "Could allocate output frame samples (error '%s')\n",
                get_error_text(error));
        av_frame_free(frame);
        return error;
    }
    
    return 0;
}


/** Initialize one data packet for reading or writing. */
static void init_packet(AVPacket *packet)
{
    av_init_packet(packet);
    /** Set the packet data and size so that it is recognized as being empty. */
    packet->data = NULL;
    packet->size = 0;
}


static int64_t pts = 0;
/** Encode one frame worth of audio to the output file. */
static int encode_audio_frame(AVFrame *frame,
                              AVFormatContext *output_format_context,
                              AVCodecContext *output_codec_context,
                              int *data_present,unsigned int stream_index)
{
    /** Packet used for temporary storage. */
    AVPacket output_packet;
    int error;
    init_packet(&output_packet);
    
    /** Set a timestamp based on the sample rate for the container. */
    if (frame) {
        frame->pts = pts;
        pts += frame->nb_samples;
        NSLog(@"Audio ======%lld  %d\n",frame->pts,pts);
    }
    
    /**
     * Hally Luya HaliLuya
     * /RTP/RTMP/
     */
    
    
    
    /**
     * Encode the audio frame and store it in the temporary packet.
     * The output audio stream encoder is used to do this.
     */
    if ((error = avcodec_encode_audio2(output_codec_context, &output_packet,
                                       frame, data_present)) < 0) {
        fprintf(stderr, "Could not encode frame (error '%s')\n",
                get_error_text(error));
        av_packet_unref(&output_packet);
        return error;
    }
    
    
    /** Write one audio frame from the temporary packet to the output file. */
    if (*data_present) {
    
        output_packet.stream_index = stream_index;
        av_packet_rescale_ts(&output_packet,
                             output_codec_context->time_base,
                             ofmt_ctx->streams[stream_index]->time_base);
//        if ((error = av_write_frame(output_format_context, &output_packet)) < 0) {
        if((error = av_interleaved_write_frame(output_format_context, &output_packet) < 0)){
            fprintf(stderr, "Could not write frame (error '%s')\n",
                    get_error_text(error));
            av_packet_unref(&output_packet);
            return error;
        }
        
        av_packet_unref(&output_packet);
    }
    
    return 0;
}


static int load_encode_and_write(AVAudioFifo *fifo,
                                 AVFormatContext *output_format_context,
                                 AVCodecContext *output_codec_context,unsigned int stream_index)
{
    /** Temporary storage of the output samples of the frame written to the file. */
    AVFrame *output_frame;
    /**
     * Use the maximum number of possible samples per frame.
     * If there is less than the maximum possible frame size in the FIFO
     * buffer use this number. Otherwise, use the maximum possible frame size
     */
    const int frame_size = FFMIN(av_audio_fifo_size(fifo),
                                 output_codec_context->frame_size);
    int data_written;
    
    /** Initialize temporary storage for one output frame. */
    if (init_output_frame(&output_frame, output_codec_context, frame_size))
        return AVERROR_EXIT;
    
    /**
     * Read as many samples from the FIFO buffer as required to fill the frame.
     * The samples are stored in the frame temporarily.
     */
    if (av_audio_fifo_read(fifo, (void **)output_frame->data, frame_size) < frame_size) {
        fprintf(stderr, "Could not read data from FIFO\n");
        av_frame_free(&output_frame);
        return AVERROR_EXIT;
    }
    
    /** Encode one frame worth of audio samples. */
    if (encode_audio_frame(output_frame, output_format_context,
                           output_codec_context, &data_written,stream_index)) {
        av_frame_free(&output_frame);
        return AVERROR_EXIT;
    }
    av_frame_free(&output_frame);
    return 0;
}



static int encode_write_frame(AVFrame *filt_frame, unsigned int stream_index, int *got_frame) {
    int ret;
    int got_frame_local;
    AVPacket enc_pkt;
    int (*enc_func)(AVCodecContext *, AVPacket *, const AVFrame *, int *) =
    (ifmt_ctx->streams[stream_index]->codecpar->codec_type ==
     AVMEDIA_TYPE_VIDEO) ? avcodec_encode_video2 : avcodec_encode_audio2;
    
    if (!got_frame)
        got_frame = &got_frame_local;
    
    av_log(NULL, AV_LOG_INFO, "Encoding frame\n");
    /* encode filtered frame */
    enc_pkt.data = NULL;
    enc_pkt.size = 0;
    av_init_packet(&enc_pkt);
    ret = enc_func(stream_ctx[stream_index].enc_ctx, &enc_pkt,
                   filt_frame, got_frame);
    av_frame_free(&filt_frame);
    if (ret < 0)
        return ret;
    if (!(*got_frame))
        return 0;
    
    /* prepare packet for muxing */
    enc_pkt.stream_index = stream_index;
    av_packet_rescale_ts(&enc_pkt,
                         stream_ctx[stream_index].enc_ctx->time_base,
                         ofmt_ctx->streams[stream_index]->time_base);
    
    av_log(NULL, AV_LOG_DEBUG, "Muxing frame\n");
    /* mux encoded frame */
    ret = av_interleaved_write_frame(ofmt_ctx, &enc_pkt);
    return ret;
}


//static int encode_write_frame(AVFrame *filt_frame, unsigned int stream_index, int*got_frame) {
//    
//    //AAC 音频处理
//    if(ifmt_ctx->streams[stream_index]->codec->codec_type ==
//       AVMEDIA_TYPE_AUDIO && filt_frame)
//    {
//        if(pts == 0)
//        {
//            pts = filt_frame->pts;
//        }
//
//        const int output_frame_size = stream_ctx[stream_index].enc_ctx->frame_size;
//    
//            if(filt_frame)
//            {
//                add_samples_to_fifo(fifo, filt_frame->extended_data,filt_frame->nb_samples);
//            }
//
//        while (av_audio_fifo_size(fifo) >= output_frame_size ||
//               (filt_frame == NULL && av_audio_fifo_size(fifo) > 0))
//        {
//            if (load_encode_and_write(fifo, ofmt_ctx,
//                                      stream_ctx[stream_index].enc_ctx,stream_index))
//            {
//                if(filt_frame)
//                {
//                    av_frame_free(&filt_frame);
//                    return -1;
//                }
//                else
//                {
//                    return -1;
//                }
//                
//                break;
//            }
//        }
//        if(filt_frame)
//        {
//            av_frame_free(&filt_frame);
//            return 0;
//        }
//    }
//    
//    int ret;
//    int got_frame_local;
//    AVPacket enc_pkt;
//    int (*enc_func)(AVCodecContext *, AVPacket *, const AVFrame *, int*) =
//    (stream_ctx[stream_index].dec_ctx->codec_type ==
//     AVMEDIA_TYPE_VIDEO) ? avcodec_encode_video2 : avcodec_encode_audio2;
//    if (!got_frame)
//        got_frame =&got_frame_local;
//    av_log(NULL,AV_LOG_INFO, "Encoding frame\n");
//    /* encode filtered frame */
//    enc_pkt.data =NULL;
//    enc_pkt.size =0;
//    av_init_packet(&enc_pkt);
//    ret =enc_func(stream_ctx[stream_index].enc_ctx, &enc_pkt,
//                  filt_frame, got_frame);
//    av_frame_free(&filt_frame);
//    if (ret < 0)
//        return ret;
//    if (!(*got_frame))
//        return 0;
//    
////    http://blog.csdn.net/leixiaohua1020/article/details/39802913/
//    /* prepare packet for muxing */
//    enc_pkt.stream_index = stream_index;
//    av_packet_rescale_ts(&enc_pkt,
//                         stream_ctx[stream_index].enc_ctx->time_base,
//                         ofmt_ctx->streams[stream_index]->time_base);
//    if(stream_ctx[stream_index].dec_ctx->codec_type == AVMEDIA_TYPE_VIDEO)
//    {
//         NSLog(@"video ~~~~~~~~%lld\n",enc_pkt.pts);
//    }
//    av_log(NULL,AV_LOG_DEBUG, "Muxing frame\n");
//    /* mux encoded frame */  
////    ret =  av_write_frame(ofmt_ctx, &enc_pkt);
//    
//    av_interleaved_write_frame(ofmt_ctx, &enc_pkt);
//    return ret;
//}

static int flush_encoder(unsigned int stream_index)
{
    int ret;
    int got_frame;
    if(!(stream_ctx[stream_index].enc_ctx->codec->capabilities&
         CODEC_CAP_DELAY))
        return 0;
    while (1) {
        av_log(NULL, AV_LOG_INFO, "Flushingstream #%u encoder\n", stream_index);
        ret =encode_write_frame(NULL, stream_index, &got_frame);
        if (ret < 0)
            break;
        if (!got_frame)
            return 0;
    }
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


/** Add converted input audio samples to the FIFO buffer for later processing. */
static int add_samples_to_fifo(AVAudioFifo *fifo,
                               uint8_t **converted_input_samples,
                               const int frame_size)
{
    int error;
    
    /**
     * Make the FIFO as large as it needs to be to hold both,
     * the old and the new samples.
     */
    if ((error = av_audio_fifo_realloc(fifo, av_audio_fifo_size(fifo) + frame_size)) < 0) {
        fprintf(stderr, "Could not reallocate FIFO\n");
        return error;
    }
    
    /** Store the new samples in the FIFO buffer. */
    if (av_audio_fifo_write(fifo, (void **)converted_input_samples,
                            frame_size) < frame_size) {
        fprintf(stderr, "Could not write data to FIFO\n");
        return AVERROR_EXIT;
    }
    return 0;
}

/** Initialize a FIFO buffer for the audio samples to be encoded. */
static int init_fifo(AVAudioFifo **fifo)
{
    //
    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        if (stream_ctx[i].dec_ctx->codec_type == AVMEDIA_TYPE_AUDIO)
        {
            /** Create the FIFO buffer based on the specified output sample format. */
            if (!(*fifo = av_audio_fifo_alloc(stream_ctx[i].enc_ctx->sample_fmt,
                                              stream_ctx[i].enc_ctx->channels, 1))) {
                fprintf(stderr, "Could not allocate FIFO\n");
                return AVERROR(ENOMEM);
            }
            break;
        }
    }
    return 0;
}
/**
 * filename: input filepath
 * mark: water marker
 * output:
 */
static int water_mark_process(char *filename, char *mark, char *output)
{
    int ret;
    AVPacket packet;
    AVFrame *frame= NULL;
    enum AVMediaType type;
    unsigned int stream_index;
    unsigned int i;
    int got_frame;
    int (*dec_func)(AVCodecContext *, AVFrame *, int *, const AVPacket*);
    
    
    // 初始化filter string
    snprintf(filter_descr, sizeof(filter_descr), "movie=%s[wm];[in][wm]overlay=100:90[out]",mark);
    
    av_register_all();
    avformat_network_init();
#if USEFILTER
    //Register Filter
    avfilter_register_all();
//    buffersrc = avfilter_get_by_name("buffer");
//    buffersink = avfilter_get_by_name("buffersink");
#endif
    
//    //打开文件 初始化协议 各种IO 比如 AVIOContext
//    if ((ret = avformat_open_input(&ifmt_ctx, filename, NULL, NULL)) < 0) {
//        printf( "Cannot open input file\n");
//        return ret;
//    }
//
//    
//    //读取信息 使用合适的解码器 各个流 AVStream的信息
//    if (avformat_find_stream_info(ifmt_ctx, NULL) < 0)
//    {
//        printf("Couldn't find video stream information.£®Œﬁ∑®ªÒ»°¡˜–≈œ¢£©\n");
//        return -1;
//    }
//    
//    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
//        AVStream*stream;
//        AVCodecContext *codec_ctx;
//        stream =ifmt_ctx->streams[i];
//        codec_ctx =stream->codec;
//        /* Reencode video & audio and remux subtitles etc. */
//        if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO
//            ||codec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
//            /* Open decoder */
//            ret =avcodec_open2(codec_ctx,
//                               avcodec_find_decoder(codec_ctx->codec_id), NULL);
//            if (ret < 0) {
//                av_log(NULL, AV_LOG_ERROR, "Failed toopen decoder for stream #%u\n", i);
//                return ret;
//            }
//        }
//    }
//    av_dump_format(ifmt_ctx, 0, filename, 0);

    if ((ret = open_input_file(filename)) < 0)
        goto end;
    //初始化输出
    if ((ret = open_output_file(output)) < 0)
        goto end;
    
    //init AAC fifo
    init_fifo(&fifo);
    
    //初始化filter
    if ((ret = init_filters(mark)) < 0)
        goto end;
    /* read all packets */
    /* read all packets */
    while (1) {
        if ((ret= av_read_frame(ifmt_ctx, &packet)) < 0)
            break;
        stream_index = packet.stream_index;
        type =ifmt_ctx->streams[packet.stream_index]->codec->codec_type;
        av_log(NULL, AV_LOG_DEBUG, "Demuxergave frame of stream_index %u\n",
               stream_index);
        if (filter_ctx[stream_index].filter_graph) {
            av_log(NULL, AV_LOG_DEBUG, "Going toreencode&filter the frame\n");
            frame =av_frame_alloc();
            if (!frame) {
                ret = AVERROR(ENOMEM);
                break;
            }
            //            packet.dts = av_rescale_q_rnd(packet.dts,
            //                                          ifmt_ctx->streams[stream_index]->time_base,
            //                                          ifmt_ctx->streams[stream_index]->codec->time_base,
            //                                          (enum AVRounding)(AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
            //            packet.pts = av_rescale_q_rnd(packet.pts,
            //                                          ifmt_ctx->streams[stream_index]->time_base,
            //                                          ifmt_ctx->streams[stream_index]->codec->time_base,
            //                                          (enum AVRounding)(AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
            
            av_packet_rescale_ts(&packet,
                                 ifmt_ctx->streams[stream_index]->time_base,
                                 stream_ctx[stream_index].dec_ctx->time_base);
            dec_func = (type == AVMEDIA_TYPE_VIDEO) ? avcodec_decode_video2 :
            avcodec_decode_audio4;
            ret = dec_func(stream_ctx[stream_index].dec_ctx, frame,
                           &got_frame, &packet);
            
            if (ret < 0) {
                av_frame_free(&frame);
                av_log(NULL, AV_LOG_ERROR, "Decodingfailed\n");
                break;
            }
            if (got_frame) {
                frame->pts = av_frame_get_best_effort_timestamp(frame);
                //                ret= filter_encode_write_frame(frame, stream_index);
                printf(">>>>>>%lld\n", frame->pts );
                if( frame->pict_type ==     AV_PICTURE_TYPE_I)    ///< Intra
                {
                    printf("------------------->I frame %d  %d\n",frame->coded_picture_number,frame->display_picture_number);
                }
                else if(frame->pict_type == AV_PICTURE_TYPE_P)
                {
                    printf("------------------->P frame %d  %d\n",frame->coded_picture_number,frame->display_picture_number);
                }
                else if(frame->pict_type == AV_PICTURE_TYPE_B)
                {
                    printf("------------------->B frame %d  %d\n",frame->coded_picture_number,frame->display_picture_number);
                }
                
                ret = filter_encode_write_frame(frame, stream_index);
                                av_frame_free(&frame);
                if (ret< 0)
                    goto end;
            } else {
                av_frame_free(&frame);
            }
        }
        else
        {
            /* remux this frame without reencoding */
            //            packet.dts = av_rescale_q_rnd(packet.dts,
            //                                          ifmt_ctx->streams[stream_index]->time_base,
            //                                          ofmt_ctx->streams[stream_index]->time_base,
            //                                          (enum AVRounding)(AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
            //            packet.pts = av_rescale_q_rnd(packet.pts,
            //                                          ifmt_ctx->streams[stream_index]->time_base,
            //                                          ofmt_ctx->streams[stream_index]->time_base,
            //                                          (enum AVRounding)(AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
            
            packet.pts = av_rescale_q_rnd(packet.pts, ifmt_ctx->streams[stream_index]->time_base, ofmt_ctx->streams[stream_index]->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
            packet.dts = av_rescale_q_rnd(packet.dts, ifmt_ctx->streams[stream_index]->time_base, ofmt_ctx->streams[stream_index]->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
            packet.duration = av_rescale_q(packet.duration, ifmt_ctx->streams[stream_index]->time_base, ofmt_ctx->streams[stream_index]->time_base);
            packet.pos = -1;
            
            /* remux this frame without reencoding */
            //            av_packet_rescale_ts(&packet,
            //                                 ifmt_ctx->streams[stream_index]->time_base,
            //                                 ofmt_ctx->streams[stream_index]->time_base);
            //            packet.pos = -1;
            ret =av_interleaved_write_frame(ofmt_ctx, &packet);
            if (ret < 0)
                goto end;
        }
        av_free_packet(&packet);
    }
    
    /* flush filters and encoders */
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        /* flush filter */
        if (!filter_ctx[i].filter_graph)
            continue;
        ret =filter_encode_write_frame(NULL, i);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Flushingfilter failed\n");
            goto end;
        }
        /* flush encoder */
        ret = flush_encoder(i);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Flushingencoder failed\n");
            goto end;
        }
    }
    av_write_trailer(ofmt_ctx);
end:
    av_free_packet(&packet);
    av_frame_free(&frame);
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        avcodec_free_context(&stream_ctx[i].dec_ctx);
        if (ofmt_ctx && ofmt_ctx->nb_streams > i && ofmt_ctx->streams[i] && stream_ctx[i].enc_ctx)
            avcodec_free_context(&stream_ctx[i].enc_ctx);
        if (filter_ctx && filter_ctx[i].filter_graph)
            avfilter_graph_free(&filter_ctx[i].filter_graph);
    }
    av_free(filter_ctx);
    av_free(stream_ctx);
    avformat_close_input(&ifmt_ctx);  
    if (ofmt_ctx &&!(ofmt_ctx->oformat->flags & AVFMT_NOFILE))  
        avio_close(ofmt_ctx->pb);  
    avformat_free_context(ofmt_ctx);  
    if (ret < 0)  
        av_log(NULL, AV_LOG_ERROR, "Erroroccurred\n");  
    return (ret? 1:0);
}
#endif
    
@implementation QNWaterMaker


+ (void)processVideo:(NSString *)vpath withMark:(NSString *)mPath toPath:(NSString *)oPath
{
#if YANG
    water_mark_process(vpath.UTF8String, mPath.UTF8String,oPath.UTF8String);
#endif
}

@end
#pragma clang diagnostic pop
