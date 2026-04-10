"""Patch flutter-pi player.c for live video pipeline support.

Fixes three issues with live stream playback (RTSP, HTTP live):
1. PAUSED deadlock: live sources don't produce data in PAUSED state,
   but init waits for video info that only arrives when data flows.
2. Appsink caps conflict: player.c overrides appsink caps with EGL
   formats, breaking negotiation with the pipeline's own caps.
3. Appsink drop: live streams need drop=true to prevent backpressure.

Usage: python3 apply_patch.py
Expects flutter-pi source at /tmp/flutter-pi/
"""

import sys

PLAYER_C = "/tmp/flutter-pi/src/plugins/gstreamer_video_player/player.c"

with open(PLAYER_C, "r") as f:
    src = f.read()

# 1. Remove premature drop=FALSE (drop is set per-pipeline below)
src = src.replace("    gst_app_sink_set_drop(GST_APP_SINK(sink), FALSE);\n", "")

# 2. Skip appsink caps override for custom pipelines — the pipeline
#    string already specifies the output format, and overriding caps
#    can break negotiation with upstream capsfilters.
old_caps = "    gst_app_sink_set_caps(GST_APP_SINK(sink), caps);"
new_caps = """    if (player->pipeline_description == NULL) {
        gst_app_sink_set_caps(GST_APP_SINK(sink), caps);
    }"""
src = src.replace(old_caps, new_caps)

# 3. For custom pipelines, go straight to PLAYING instead of PAUSED.
#    This must happen AFTER the bus fd is registered (sd_event_add_io)
#    so bus messages can be dispatched during the async transition.
old_block = """    LOG_DEBUG("Setting state to paused...\\n");
    state_change_return = gst_element_set_state(GST_ELEMENT(pipeline), GST_STATE_PAUSED);
    if (state_change_return == GST_STATE_CHANGE_NO_PREROLL) {
        LOG_DEBUG("Is Live!\\n");
        player->is_live = true;
    } else {
        LOG_DEBUG("Not live!\\n");
        player->is_live = false;
    }"""

new_block = """    if (player->pipeline_description != NULL) {
        // Custom pipelines (RTSP, HTTP live) — go straight to PLAYING.
        // PAUSED would deadlock: live sources don't produce data until PLAYING,
        // but init waits for video info that only arrives when data flows.
        player->is_live = true;
        gst_base_sink_set_sync(GST_BASE_SINK(sink), FALSE);
        gst_app_sink_set_drop(GST_APP_SINK(sink), TRUE);
        state_change_return = gst_element_set_state(GST_ELEMENT(pipeline), GST_STATE_PLAYING);
    } else {
        LOG_DEBUG("Setting state to paused...\\n");
        state_change_return = gst_element_set_state(GST_ELEMENT(pipeline), GST_STATE_PAUSED);
        if (state_change_return == GST_STATE_CHANGE_NO_PREROLL) {
            LOG_DEBUG("Is Live!\\n");
            player->is_live = true;
        } else {
            LOG_DEBUG("Not live!\\n");
            player->is_live = false;
        }
    }"""
src = src.replace(old_block, new_block)

# Verify patch applied
if "player->pipeline_description != NULL" not in src:
    print("ERROR: Patch failed to apply!", file=sys.stderr)
    sys.exit(1)

with open(PLAYER_C, "w") as f:
    f.write(src)

print("flutter-pi live pipeline patch applied successfully")
