# Sleep Audio Content Sources

This document tracks the copyright-free audio files used in the Sleep & Wind-Down feature.

## License

All audio files are sourced from the **Internet Archive** under **CC0 (Creative Commons Zero)** or **Public Domain** licenses, which allow free use, modification, and distribution without attribution requirements.

## Uploaded Content

### Soundscapes

| Title                | Tier    | Source                                                                                                                                                           | License           | Duration | File Size | Date Added |
| -------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- | -------- | --------- | ---------- |
| Ocean Waves          | Free    | [Waves 3 - Night Beach Gentle - Internet Archive](https://archive.org/details/relaxingsounds)                                                                    | CC0/Public Domain | 30 min   | 37 MB     | 2026-01-20 |
| Gentle Rain          | Free    | [3 Hours of Gentle Night Rain - Internet Archive](https://archive.org/details/3hoursofgentlenightrainrainsoundsforrelaxingsleepinsomniameditationstudyptsd.rain) | CC0/Public Domain | 30 min   | 43 MB     | 2026-01-20 |
| Forest Night         | Free    | [Soothing Night Time Forest Sounds - Internet Archive](https://archive.org/details/NightSounds_201801)                                                           | CC0/Public Domain | 30 min   | 43 MB     | 2026-01-20 |
| White Noise          | Free    | [60 Minutes Of White Noise - Internet Archive](https://archive.org/details/01-60-minutes-of-white-noise)                                                         | CC0/Public Domain | 30 min   | 24 MB     | 2026-01-20 |
| Thunderstorm         | Premium | [1 Hour Thunderstorm - Internet Archive](https://archive.org/details/1HourThunderstorm)                                                                          | CC0/Public Domain | 30 min   | 38 MB     | 2026-01-20 |
| Campfire             | Premium | [Relaxing Sounds - Fire - Internet Archive](https://archive.org/details/relaxingsounds)                                                                          | CC0/Public Domain | 30 min   | 47 MB     | 2026-01-20 |
| Binaural Sleep Waves | Premium | [Restorative Sleep - Binaural Beats - Internet Archive](https://archive.org/details/RestorativeSleepMusicBinauralBeatsSleepInTheClouds432Hz)                     | CC0/Public Domain | 30 min   | 15 MB     | 2026-01-20 |

### Sleep Stories

| Title                         | Tier         | Source                                                                                                 | License       | Duration | File Size | Date Added |
| ----------------------------- | ------------ | ------------------------------------------------------------------------------------------------------ | ------------- | -------- | --------- | ---------- |
| Jack and His Golden Snuff-Box | Free         | [English Fairy Tales - LibriVox](https://librivox.org/english-fairy-tales-collected-by-joseph-jacobs/) | Public Domain | 19:22    | 19 MB     | 2026-01-20 |
| Whittington and His Cat       | Free         | [English Fairy Tales - LibriVox](https://librivox.org/english-fairy-tales-collected-by-joseph-jacobs/) | Public Domain | 18:12    | 17 MB     | 2026-01-20 |
| Jack the Giant-Killer         | Free         | [English Fairy Tales - LibriVox](https://librivox.org/english-fairy-tales-collected-by-joseph-jacobs/) | Public Domain | 22:55    | 22 MB     | 2026-01-20 |
| The Brave Tin Soldier         | Premium      | [Andersen Fairy Tales - LibriVox](https://librivox.org/fairy-tales-by-hans-christian-andersen/)        | Public Domain | 5:05     | 4.9 MB    | 2026-01-20 |
| The Ugly Duckling             | Premium/Kids | [Andersen Fairy Tales - LibriVox](https://librivox.org/fairy-tales-by-hans-christian-andersen/)        | Public Domain | 6:27     | 6.2 MB    | 2026-01-20 |
| Thumbelina                    | Kids         | [Andersen Fairy Tales - LibriVox](https://librivox.org/fairy-tales-by-hans-christian-andersen/)        | Public Domain | 6:46     | 6.5 MB    | 2026-01-20 |

## Processing

All audio files were:

1. Downloaded from Internet Archive
2. Trimmed to 30 minutes using ffmpeg
3. Compressed to 192 kbps MP3 to fit under Supabase's 50MB file size limit
4. Converted to M4A format for iOS compatibility
5. Uploaded to Supabase Storage bucket `sleep-content`

## Storage Configuration

- **Bucket**: `sleep-content`
- **Access**: Public read
- **File Size Limit**: 500 MB (bucket), 50 MB (project global)
- **Allowed MIME Types**: audio/mp4, audio/mpeg, audio/m4a, audio/wav, audio/aac

## Future Content Needed

The following content from the database still needs audio files:

### Stories (require narration)

- Mountain Lake at Dusk (placeholder - "The Daisy" from LibriVox is only 2:03, needs longer replacement)

## Attribution (Optional but Recommended)

While CC0 licenses don't require attribution, it's good practice to credit creators:

### Soundscapes

- **Ocean Waves**: "Waves 3 - 10h Night Beach Gentle, NO GULLS" from Relaxing Sounds collection via Internet Archive
- **Gentle Rain**: Various contributors via Internet Archive
- **Forest Night**: Various contributors via Internet Archive
- **White Noise**: Various contributors via Internet Archive
- **Thunderstorm**: Robert Wimer via Internet Archive
- **Campfire**: Various contributors via Internet Archive
- **Binaural Sleep Waves**: Various contributors via Internet Archive

### Stories

- **LibriVox Fairy Tales**: Joy Chan (narrator) and various LibriVox volunteers
- **English Fairy Tales** collected by Joseph Jacobs
- **Andersen Fairy Tales** by Hans Christian Andersen

## Resources for Additional Content

- [Internet Archive Audio Collections](https://archive.org/details/audio)
- [Pixabay Sound Effects](https://pixabay.com/sound-effects/) - Royalty-free, no attribution
- [Freesound.org](https://freesound.org/) - CC0 and CC-BY licensed sounds
- [BBC Sound Effects](https://sound-effects.bbcrewind.co.uk/) - Free for personal/educational use

## Notes

- **File format**: iOS prefers M4A/AAC format for efficient playback
- **Bitrate**: 192 kbps is a good balance between quality and file size for ambient sounds
- **Duration**: 30-60 minutes is ideal for sleep sounds (can loop seamlessly)
- **Looping**: Soundscapes should be designed to loop without audible gaps
