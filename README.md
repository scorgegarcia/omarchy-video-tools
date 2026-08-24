# Omarchy Video Tools

![Preview](https://github.com/scorgegarcia/omarchy-video-tools/blob/main/preview.png?raw=true)

A small, themed Omarchy 4 / Quickshell panel for simple video editing.

Drop a video into the panel, preview it, mark a trim range, draw a crop area,
and export the result with FFmpeg. You can also click the drop area to choose a
video through the native file picker.

## Features

- Drag-and-drop video loading
- In-panel playback
- Trim start and end markers
- Crop selection by dragging over the preview
- Export to `<original-name>-edited.mp4`
- Uses Omarchy shell colors and font
- Localized for English, Spanish, Portuguese, French, German, Italian,
  Japanese, Korean, Chinese, and Russian
- Follows the system language via `LANGUAGE`, `LANG`, or `LC_MESSAGES`

## Requirements

- Omarchy 4 with the Quickshell shell
- `ffmpeg`, `ffprobe`, Python 3, and Qt Multimedia

## Install

```bash
omarchy plugin add https://github.com/scorgegarcia/omarchy-video-tools --enable
```

Open it with `Super + Shift + V`, or move the mouse over the clock and click
the small video icon that appears beside the inactive indicators. You can also
run:

```bash
omarchy shell shell summon jvi.video-tools '{}'
```

## Remove

```bash
omarchy plugin remove jvi.video-tools --yes
```

## License

MIT. See [LICENSE](LICENSE).
