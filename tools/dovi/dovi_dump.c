// Decodes frames of a Dolby Vision file until one carries DOVI metadata, then prints the RPU's colour block and
// a summary of its reshaping (mapping) per component. Build: see dovi_dump.sh.
#include <stdio.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/frame.h>

static void print_mat(const char *name, const AVRational *m) {
	printf("%s:\n", name);
	for (int i = 0; i < 3; i++)
		printf("  %12.8f %12.8f %12.8f\n", av_q2d(m[i * 3]), av_q2d(m[i * 3 + 1]), av_q2d(m[i * 3 + 2]));
}

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage: dovi_dump <file> [frames]\n"); return 2; }
	int want = argc > 2 ? atoi(argv[2]) : 3;
	AVFormatContext *fc = NULL;
	if (avformat_open_input(&fc, argv[1], NULL, NULL) < 0) { fprintf(stderr, "open failed\n"); return 1; }
	avformat_find_stream_info(fc, NULL);
	int vi = av_find_best_stream(fc, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
	AVStream *st = fc->streams[vi];
	const AVCodec *dec = avcodec_find_decoder(st->codecpar->codec_id);
	AVCodecContext *cc = avcodec_alloc_context3(dec);
	avcodec_parameters_to_context(cc, st->codecpar);
	cc->thread_count = 4;
	if (avcodec_open2(cc, dec, NULL) < 0) { fprintf(stderr, "decoder failed\n"); return 1; }
	AVPacket *pkt = av_packet_alloc();
	AVFrame *fr = av_frame_alloc();
	int shown = 0;
	while (shown < want && av_read_frame(fc, pkt) >= 0) {
		if (pkt->stream_index != vi) { av_packet_unref(pkt); continue; }
		avcodec_send_packet(cc, pkt);
		av_packet_unref(pkt);
		while (avcodec_receive_frame(cc, fr) >= 0) {
			AVFrameSideData *sd = av_frame_get_side_data(fr, AV_FRAME_DATA_DOVI_METADATA);
			printf("frame pts %lld fmt %d %dx%d range %d prim %d trc %d space %d dovi %s\n", (long long)fr->pts,
					fr->format, fr->width, fr->height, fr->color_range, fr->color_primaries, fr->color_trc,
					fr->colorspace, sd ? "yes" : "no");
			if (sd && shown < want) {
				const AVDOVIMetadata *m = (const AVDOVIMetadata *)sd->data;
				const AVDOVIRpuDataHeader *h = av_dovi_get_header(m);
				const AVDOVIDataMapping *map = av_dovi_get_mapping(m);
				const AVDOVIColorMetadata *c = av_dovi_get_color(m);
				printf("rpu: profile %d bl_video_full_range %d bl_bit_depth %d el_bit_depth %d vdr_bit_depth %d "
						"coef_log2_denom %d disable_residual %d el_spatial_resampling %d\n",
						h->rpu_type, h->bl_video_full_range_flag, h->bl_bit_depth, h->el_bit_depth,
						h->vdr_rpu_profile, h->coef_log2_denom, h->disable_residual_flag,
						h->el_spatial_resampling_filter_flag);
				printf("color: dm_metadata_id %d scene_refresh %d signal_eotf %d signal_eotf_param0 %d "
						"signal_eotf_param1 %d signal_eotf_param2 %d signal_bit_depth %d signal_color_space %d "
						"signal_chroma_format %d signal_full_range %d\n", c->dm_metadata_id, c->scene_refresh_flag,
						c->signal_eotf, c->signal_eotf_param0, c->signal_eotf_param1, c->signal_eotf_param2,
						c->signal_bit_depth, c->signal_color_space, c->signal_chroma_format, c->signal_full_range_flag);
				print_mat("ycc_to_rgb_matrix", c->ycc_to_rgb_matrix);
				printf("ycc_to_rgb_offset: %f %f %f\n", av_q2d(c->ycc_to_rgb_offset[0]),
						av_q2d(c->ycc_to_rgb_offset[1]), av_q2d(c->ycc_to_rgb_offset[2]));
				print_mat("rgb_to_lms_matrix", c->rgb_to_lms_matrix);
				printf("source_min_pq %d source_max_pq %d source_diagonal %d\n", c->source_min_pq, c->source_max_pq,
						c->source_diagonal);
				printf("mapping: vdr_rpu_id %d mapping_color_space %d mapping_chroma_format_idc %d nlq_method %d "
						"num_x_partitions %d num_y_partitions %d\n", map->vdr_rpu_id, map->mapping_color_space,
						map->mapping_chroma_format_idc, map->nlq_method_idc, map->num_x_partitions,
						map->num_y_partitions);
				for (int comp = 0; comp < 3; comp++) {
					const AVDOVIReshapingCurve *rc = &map->curves[comp];
					printf("  comp %d: %d pivots:", comp, rc->num_pivots);
					for (int i = 0; i < rc->num_pivots; i++) printf(" %d", rc->pivots[i]);
					printf("\n");
					for (int i = 0; i < rc->num_pivots - 1; i++) {
						if (rc->mapping_idc[i] == AV_DOVI_MAPPING_POLYNOMIAL) {
							printf("    piece %d poly order %d:", i, rc->poly_order[i]);
							for (int k = 0; k <= rc->poly_order[i]; k++)
								printf(" %f", (double)rc->poly_coef[i][k] / (double)(1LL << h->coef_log2_denom));
							printf("\n");
						} else {
							printf("    piece %d MMR order %d constant %f\n", i, rc->mmr_order[i],
									(double)rc->mmr_constant[i] / (double)(1LL << h->coef_log2_denom));
						}
					}
				}
				shown++;
			}
			av_frame_unref(fr);
		}
	}
	return 0;
}
