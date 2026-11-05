// Decodes the first frame at or after a time and prints a grid of 10-bit plane samples (block means), for comparing
// two encodes of one film. Output lines: "x y Y U V" per block. Build: frame_grid.sh.
#include <stdio.h>
#include <stdlib.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavutil/pixdesc.h>

int main(int argc, char **argv) {
	if (argc < 3) { fprintf(stderr, "usage: frame_grid <file> <seconds> [cols rows frames]\n"); return 2; }
	double at = atof(argv[2]);
	int cols = argc > 3 ? atoi(argv[3]) : 48, rows = argc > 4 ? atoi(argv[4]) : 27;
	int frames = argc > 5 ? atoi(argv[5]) : 1;
	AVFormatContext *fc = NULL;
	if (avformat_open_input(&fc, argv[1], NULL, NULL) < 0) { fprintf(stderr, "open failed\n"); return 1; }
	avformat_find_stream_info(fc, NULL);
	int vi = av_find_best_stream(fc, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
	AVStream *st = fc->streams[vi];
	const AVCodec *dec = avcodec_find_decoder(st->codecpar->codec_id);
	AVCodecContext *cc = avcodec_alloc_context3(dec);
	avcodec_parameters_to_context(cc, st->codecpar);
	cc->thread_count = 8;
	if (avcodec_open2(cc, dec, NULL) < 0) { fprintf(stderr, "decoder failed\n"); return 1; }
	int64_t ts = (int64_t)(at / av_q2d(st->time_base));
	av_seek_frame(fc, vi, ts, AVSEEK_FLAG_BACKWARD);
	AVPacket *pkt = av_packet_alloc();
	AVFrame *fr = av_frame_alloc();
	int done = 0;
	while (!done && av_read_frame(fc, pkt) >= 0) {
		if (pkt->stream_index != vi) { av_packet_unref(pkt); continue; }
		avcodec_send_packet(cc, pkt);
		av_packet_unref(pkt);
		while (!done && avcodec_receive_frame(cc, fr) >= 0) {
			if (fr->pts < ts) { av_frame_unref(fr); continue; }
			const AVPixFmtDescriptor *d = av_pix_fmt_desc_get(fr->format);
			int bits = d->comp[0].depth, sx = d->log2_chroma_w, sy = d->log2_chroma_h;
			printf("# pts %lld (%.3f s) %dx%d fmt %s bits %d\n", (long long)fr->pts, fr->pts * av_q2d(st->time_base),
					fr->width, fr->height, d->name, bits);
			int bw = fr->width / cols, bh = fr->height / rows;
			for (int by = 0; by < rows; by++) {
				for (int bx = 0; bx < cols; bx++) {
					double sum[3] = {0, 0, 0};
					long n[3] = {0, 0, 0};
					for (int y = by * bh; y < (by + 1) * bh; y++) {
						for (int x = bx * bw; x < (bx + 1) * bw; x++) {
							if (bits > 8) sum[0] += ((uint16_t *)(fr->data[0] + y * fr->linesize[0]))[x];
							else sum[0] += fr->data[0][y * fr->linesize[0] + x];
							n[0]++;
							if ((x & ((1 << sx) - 1)) == 0 && (y & ((1 << sy) - 1)) == 0) {
								int cx = x >> sx, cy = y >> sy;
								for (int p = 1; p < 3; p++) {
									if (bits > 8) sum[p] += ((uint16_t *)(fr->data[p] + cy * fr->linesize[p]))[cx];
									else sum[p] += fr->data[p][cy * fr->linesize[p] + cx];
									n[p]++;
								}
							}
						}
					}
					printf("%d %d %.2f %.2f %.2f\n", bx, by, sum[0] / n[0], sum[1] / n[1], sum[2] / n[2]);
				}
			}
			if (--frames <= 0) done = 1;
			av_frame_unref(fr);
		}
	}
	return 0;
}
