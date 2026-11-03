// Remuxes a file (no transcoding) and adds container metadata the ffmpeg command line can't set: stereo 3D, spherical
// projection, and chapters. For MediaSource tests (features_test.gd); built and run by make-feature-files.sh against the
// remux-only FFmpeg of build/ffmpeg-build.sh tool.
//
//   meta_remux IN OUT [--stereo=sbs|tb|2d] [--invert] [--projection=equirect|vr180|cubemap] [--chapters=N] [--duration=S]
//
// Use an MP4 (or TS) input: Matroska stores no DTS, which the muxers need for B-frame video.
//
// MKV keeps subtitle streams; MP4 gets the first video and audio stream only (st3d/sv3d are written in "unofficial" mode).

#include <libavformat/avformat.h>
#include <libavutil/spherical.h>
#include <libavutil/stereo3d.h>

#include <stdio.h>
#include <string.h>

static int fail(const char *what, int err) {
	char text[128];
	av_strerror(err, text, sizeof(text));
	fprintf(stderr, "meta_remux: %s: %s\n", what, text);
	return 1;
}

int main(int argc, char **argv) {
	if (argc < 3) {
		fprintf(stderr, "usage: meta_remux IN OUT [--stereo=sbs|tb|2d] [--invert] [--projection=equirect|vr180|cubemap] [--chapters=N] [--duration=S]\n");
		return 2;
	}
	const char *in_path = argv[1];
	const char *out_path = argv[2];
	const char *stereo = NULL;
	const char *projection = NULL;
	int invert = 0;
	int chapter_count = 0;
	double max_seconds = 0.0;
	for (int i = 3; i < argc; i++) {
		if (!strncmp(argv[i], "--stereo=", 9)) {
			stereo = argv[i] + 9;
		} else if (!strcmp(argv[i], "--invert")) {
			invert = 1;
		} else if (!strncmp(argv[i], "--projection=", 13)) {
			projection = argv[i] + 13;
		} else if (!strncmp(argv[i], "--chapters=", 11)) {
			chapter_count = atoi(argv[i] + 11);
		} else if (!strncmp(argv[i], "--duration=", 11)) {
			max_seconds = atof(argv[i] + 11);
		} else {
			fprintf(stderr, "meta_remux: unknown option %s\n", argv[i]);
			return 2;
		}
	}

	AVFormatContext *in = NULL;
	int r = avformat_open_input(&in, in_path, NULL, NULL);
	if (r < 0) {
		return fail(in_path, r);
	}
	if ((r = avformat_find_stream_info(in, NULL)) < 0) {
		return fail("stream info", r);
	}
	AVFormatContext *out = NULL;
	if ((r = avformat_alloc_output_context2(&out, NULL, NULL, out_path)) < 0) {
		return fail(out_path, r);
	}
	const int mp4 = !strcmp(out->oformat->name, "mp4") || !strcmp(out->oformat->name, "mov");
	out->strict_std_compliance = FF_COMPLIANCE_UNOFFICIAL;

	int *map = av_calloc(in->nb_streams, sizeof(int));
	int have_video = 0, have_audio = 0;
	for (unsigned i = 0; i < in->nb_streams; i++) {
		const AVCodecParameters *par = in->streams[i]->codecpar;
		map[i] = -1;
		if (par->codec_type == AVMEDIA_TYPE_VIDEO && !have_video) {
			have_video = 1;
		} else if (par->codec_type == AVMEDIA_TYPE_AUDIO && !have_audio) {
			have_audio = 1;
		} else if (par->codec_type == AVMEDIA_TYPE_SUBTITLE && !mp4) {
		} else {
			continue;
		}
		AVStream *stream = avformat_new_stream(out, NULL);
		avcodec_parameters_copy(stream->codecpar, par);
		stream->codecpar->codec_tag = 0;
		stream->time_base = in->streams[i]->time_base;
		av_dict_copy(&stream->metadata, in->streams[i]->metadata, 0);
		stream->disposition = in->streams[i]->disposition;
		map[i] = stream->index;
		if (par->codec_type != AVMEDIA_TYPE_VIDEO) {
			continue;
		}
		if (stereo) {
			size_t size = 0;
			AVStereo3D *data = av_stereo3d_alloc_size(&size);
			data->type = !strcmp(stereo, "tb") ? AV_STEREO3D_TOPBOTTOM : (!strcmp(stereo, "2d") ? AV_STEREO3D_2D : AV_STEREO3D_SIDEBYSIDE);
			data->flags = invert ? AV_STEREO3D_FLAG_INVERT : 0;
			av_packet_side_data_add(&stream->codecpar->coded_side_data, &stream->codecpar->nb_coded_side_data, AV_PKT_DATA_STEREO3D, data, size, 0);
		}
		if (projection) {
			size_t size = 0;
			AVSphericalMapping *data = av_spherical_alloc(&size);
			if (!strcmp(projection, "cubemap")) {
				data->projection = AV_SPHERICAL_CUBEMAP;
			} else if (!strcmp(projection, "vr180")) {
				// The middle half of the full sphere's width: 180 degrees across, 180 down.
				data->projection = AV_SPHERICAL_EQUIRECTANGULAR_TILE;
				data->bound_left = 0x40000000u;
				data->bound_right = 0x40000000u;
			} else {
				data->projection = AV_SPHERICAL_EQUIRECTANGULAR;
			}
			data->yaw = 90 << 16;
			av_packet_side_data_add(&stream->codecpar->coded_side_data, &stream->codecpar->nb_coded_side_data, AV_PKT_DATA_SPHERICAL, data, size, 0);
		}
	}

	if (chapter_count > 0) {
		// Evenly spaced over the duration, titled "Chapter N".
		const int64_t total = max_seconds > 0.0 ? (int64_t)(max_seconds * AV_TIME_BASE) : (in->duration > 0 ? in->duration : 60 * AV_TIME_BASE);
		out->chapters = av_calloc(chapter_count, sizeof(AVChapter *));
		for (int i = 0; i < chapter_count; i++) {
			AVChapter *chapter = av_mallocz(sizeof(AVChapter));
			chapter->id = i + 1;
			chapter->time_base = (AVRational){ 1, 1000 };
			chapter->start = total / 1000 * i / chapter_count;
			chapter->end = total / 1000 * (i + 1) / chapter_count;
			char title[32];
			snprintf(title, sizeof(title), "Chapter %d", i + 1);
			av_dict_set(&chapter->metadata, "title", title, 0);
			out->chapters[i] = chapter;
		}
		out->nb_chapters = chapter_count;
	}

	if (!(out->oformat->flags & AVFMT_NOFILE) && (r = avio_open(&out->pb, out_path, AVIO_FLAG_WRITE)) < 0) {
		return fail(out_path, r);
	}
	if ((r = avformat_write_header(out, NULL)) < 0) {
		return fail("write header", r);
	}
	AVPacket *packet = av_packet_alloc();
	while (av_read_frame(in, packet) >= 0) {
		const int target = map[packet->stream_index];
		const AVStream *source = in->streams[packet->stream_index];
		const int64_t first = source->start_time != AV_NOPTS_VALUE ? source->start_time : 0;
		if (target >= 0 && max_seconds > 0.0 && packet->dts != AV_NOPTS_VALUE && (packet->dts - first) * av_q2d(source->time_base) > max_seconds) {
			av_packet_unref(packet);
			continue;
		}
		if (target < 0) {
			av_packet_unref(packet);
			continue;
		}
		av_packet_rescale_ts(packet, in->streams[packet->stream_index]->time_base, out->streams[target]->time_base);
		packet->stream_index = target;
		packet->pos = -1;
		if ((r = av_interleaved_write_frame(out, packet)) < 0) {
			return fail("write", r);
		}
	}
	av_write_trailer(out);
	av_packet_free(&packet);
	if (!(out->oformat->flags & AVFMT_NOFILE)) {
		avio_closep(&out->pb);
	}
	avformat_free_context(out);
	avformat_close_input(&in);
	av_free(map);
	printf("meta_remux: %s\n", out_path);
	return 0;
}
