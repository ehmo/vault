# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Plan: Speed up video import by skipping unnecessary transcoding

## Context
Single 335MB video takes 82 seconds to import. The bottleneck is HEVC re-encoding at 4 Mbps. Most iPhone videos are already HEVC at 1080p — they just have higher bitrate (8-25 Mbps). Re-encoding these from 15 Mbps to 4 Mbps yields diminishing storage savings at massive time cost.

AVAssetExportSession was considered but has no bitrate control — keeping manual AVAssetReader/Writer.

##...

### Prompt 2

Review all code you have written for technical, implementation and logical bugs. I want you to pay exceptional attention to all code this code could've aletered or impacted. When you are satisfied with the results, write comprehensive not shallow tests thaat verify this implementation going forward and catch any changes to the behavior.

