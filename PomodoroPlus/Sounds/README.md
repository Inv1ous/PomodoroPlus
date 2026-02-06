# Bundled Sounds

This folder contains the default sound files bundled with PomodoroPlus.

## Required Sound Files

Place the following audio files (MP3 format recommended) in this folder:

1. `chime.mp3` - A pleasant chime sound (default for all events)
2. `bell.mp3` - A bell tone 
3. `gentle.mp3` - A gentle notification sound
4. `alert.mp3` - A more attention-grabbing alert

## Getting Sound Files

You can use any royalty-free or licensed sound files. Some sources:

- **System Sounds**: Copy sounds from `/System/Library/Sounds/` on macOS
- **Free Sound Libraries**: freesound.org, soundbible.com, etc.
- **Create Your Own**: Use GarageBand or other audio software

## Supported Formats

- MP3 (recommended)
- M4A
- WAV

## Converting System Sounds

macOS system sounds are in AIFF format. To convert to MP3:

```bash
# Using ffmpeg
ffmpeg -i /System/Library/Sounds/Glass.aiff chime.mp3
ffmpeg -i /System/Library/Sounds/Ping.aiff bell.mp3
ffmpeg -i /System/Library/Sounds/Breeze.aiff gentle.mp3
ffmpeg -i /System/Library/Sounds/Sosumi.aiff alert.mp3
```

Or use `afconvert` (built into macOS):

```bash
afconvert -f mp4f -d aac /System/Library/Sounds/Glass.aiff chime.m4a
```

## Note

If sound files are missing, the app will fall back to the system beep sound.
