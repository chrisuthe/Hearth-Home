#include "sendspin_audio_plugin.h"

#include <pulse/error.h>
#include <pulse/simple.h>

#include <cstring>
#include <string>
#include <vector>

// Plugin state held as a simple struct.
struct SendspinAudioState {
  pa_simple* pa = nullptr;
  int sample_rate = 0;
  int channels = 0;
  int bit_depth = 0;
  double volume = 1.0;
  bool muted = false;
};

static SendspinAudioState g_state;

// Apply software volume to PCM data in-place.
// Supports 16-bit and 8-bit PCM. 24-bit and 32-bit could be added later.
static void apply_volume(uint8_t* data, size_t length, int bit_depth,
                         double volume, bool muted) {
  if (muted) {
    memset(data, (bit_depth == 8) ? 128 : 0, length);
    return;
  }
  if (volume >= 1.0) {
    return;
  }
  if (volume <= 0.0) {
    memset(data, (bit_depth == 8) ? 128 : 0, length);
    return;
  }

  if (bit_depth == 16) {
    size_t sample_count = length / 2;
    int16_t* samples = reinterpret_cast<int16_t*>(data);
    for (size_t i = 0; i < sample_count; i++) {
      samples[i] = static_cast<int16_t>(samples[i] * volume);
    }
  } else if (bit_depth == 8) {
    // 8-bit PCM is unsigned, centered at 128.
    for (size_t i = 0; i < length; i++) {
      int val = static_cast<int>(data[i]) - 128;
      val = static_cast<int>(val * volume);
      data[i] = static_cast<uint8_t>(val + 128);
    }
  }
  // For other bit depths, pass through unmodified.
}

static void handle_initialize(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);

  FlValue* sr_val = fl_value_lookup_string(args, "sampleRate");
  FlValue* ch_val = fl_value_lookup_string(args, "channels");
  FlValue* bd_val = fl_value_lookup_string(args, "bitDepth");

  if (sr_val == nullptr || ch_val == nullptr || bd_val == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS",
                                     "Missing sampleRate, channels, or bitDepth",
                                     nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  int64_t sample_rate = fl_value_get_int(sr_val);
  int64_t channels = fl_value_get_int(ch_val);
  int64_t bit_depth = fl_value_get_int(bd_val);

  // Clean up any previous connection.
  if (g_state.pa != nullptr) {
    pa_simple_free(g_state.pa);
    g_state.pa = nullptr;
  }

  pa_sample_format_t format;
  if (bit_depth == 16) {
    format = PA_SAMPLE_S16LE;
  } else if (bit_depth == 8) {
    format = PA_SAMPLE_U8;
  } else if (bit_depth == 24) {
    format = PA_SAMPLE_S24LE;
  } else if (bit_depth == 32) {
    format = PA_SAMPLE_S32LE;
  } else {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS",
                                     "Unsupported bit depth",
                                     nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  pa_sample_spec spec = {};
  spec.format = format;
  spec.rate = static_cast<uint32_t>(sample_rate);
  spec.channels = static_cast<uint8_t>(channels);

  int pa_error = 0;
  pa_simple* pa = pa_simple_new(
      nullptr,             // Use default server
      "Hearth",            // Application name
      PA_STREAM_PLAYBACK,
      nullptr,             // Use default device
      "Hearth Sendspin",   // Stream description
      &spec,
      nullptr,             // Default channel map
      nullptr,             // Default buffering attributes
      &pa_error);

  if (pa == nullptr) {
    std::string msg = "pa_simple_new failed: ";
    msg += pa_strerror(pa_error);
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("PULSE_ERROR", msg.c_str(), nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_state.pa = pa;
  g_state.sample_rate = static_cast<int>(sample_rate);
  g_state.channels = static_cast<int>(channels);
  g_state.bit_depth = static_cast<int>(bit_depth);
  g_state.volume = 1.0;
  g_state.muted = false;

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_start(FlMethodCall* method_call) {
  // PulseAudio simple API starts playback on first write; this is a no-op.
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_stop(FlMethodCall* method_call) {
  if (g_state.pa != nullptr) {
    int pa_error = 0;
    pa_simple_drain(g_state.pa, &pa_error);
    // Drain errors are non-fatal; we still report success.
  }

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_write_samples(FlMethodCall* method_call) {
  if (g_state.pa == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("NOT_INITIALIZED",
                                     "Audio not initialized", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* data_val = fl_value_lookup_string(args, "data");
  if (data_val == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS",
                                     "Missing 'data' key", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  const uint8_t* data = fl_value_get_uint8_list(data_val);
  size_t length = fl_value_get_length(data_val);

  if (length == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_int(0)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // Copy data so we can apply volume in-place.
  std::vector<uint8_t> buffer(data, data + length);
  apply_volume(buffer.data(), buffer.size(), g_state.bit_depth,
               g_state.volume, g_state.muted);

  int pa_error = 0;
  int ret = pa_simple_write(g_state.pa, buffer.data(), buffer.size(),
                            &pa_error);
  if (ret < 0) {
    std::string msg = "pa_simple_write failed: ";
    msg += pa_strerror(pa_error);
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("PULSE_ERROR", msg.c_str(), nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  int bytes_per_frame = (g_state.channels * g_state.bit_depth) / 8;
  int64_t frames_written = 0;
  if (bytes_per_frame > 0) {
    frames_written = static_cast<int64_t>(length) /
                     static_cast<int64_t>(bytes_per_frame);
  }

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_int(frames_written)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_set_volume(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* vol_val = fl_value_lookup_string(args, "volume");
  if (vol_val == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS",
                                     "Missing 'volume' key", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_state.volume = fl_value_get_float(vol_val);

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_set_muted(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* muted_val = fl_value_lookup_string(args, "muted");
  if (muted_val == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS",
                                     "Missing 'muted' key", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_state.muted = fl_value_get_bool(muted_val);

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_dispose(FlMethodCall* method_call) {
  if (g_state.pa != nullptr) {
    pa_simple_drain(g_state.pa, nullptr);
    pa_simple_free(g_state.pa);
    g_state.pa = nullptr;
  }
  g_state.sample_rate = 0;
  g_state.channels = 0;
  g_state.bit_depth = 0;
  g_state.volume = 1.0;
  g_state.muted = false;

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void method_call_handler(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  (void)channel;
  (void)user_data;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "initialize") == 0) {
    handle_initialize(method_call);
  } else if (strcmp(method, "start") == 0) {
    handle_start(method_call);
  } else if (strcmp(method, "stop") == 0) {
    handle_stop(method_call);
  } else if (strcmp(method, "writeSamples") == 0) {
    handle_write_samples(method_call);
  } else if (strcmp(method, "setVolume") == 0) {
    handle_set_volume(method_call);
  } else if (strcmp(method, "setMuted") == 0) {
    handle_set_muted(method_call);
  } else if (strcmp(method, "dispose") == 0) {
    handle_dispose(method_call);
  } else {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

void sendspin_audio_plugin_register(FlPluginRegistry* registry) {
  FlPluginRegistrar* registrar = fl_plugin_registry_get_registrar_for_plugin(
      registry, "SendspinAudioPlugin");
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view == nullptr) {
    return;
  }

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, "com.hearth/sendspin_audio", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_handler, nullptr, nullptr);
}
