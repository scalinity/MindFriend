# Complete Sleep Content Sources & Implementation Guide

This document provides copyright-free audio sources for ALL sleep content in the database.

## ✅ Already Uploaded (Active)

| Title        | Duration | Source                                                                                                                                     | Status  |
| ------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------- |
| Ocean Waves  | 30 min   | [Deep Fathom Ocean](https://archive.org/details/deep-fathom-ocean-ambient-music-underwater-sounds-1-hour)                                  | ✅ Live |
| Gentle Rain  | 30 min   | [3 Hours Gentle Night Rain](https://archive.org/details/3hoursofgentlenightrainrainsoundsforrelaxingsleepinsomniameditationstudyptsd.rain) | ✅ Live |
| Forest Night | 30 min   | [Soothing Night Time Forest](https://archive.org/details/NightSounds_201801)                                                               | ✅ Live |

## 📋 Soundscapes - Ready to Upload

### Free Tier

| Title       | Source                                                                                | License           | Download URL                            |
| ----------- | ------------------------------------------------------------------------------------- | ----------------- | --------------------------------------- |
| White Noise | [60 Minutes Of White Noise](https://archive.org/details/01-60-minutes-of-white-noise) | CC0/Public Domain | `60 minutes of white noise.mp3` (137MB) |

### Premium Tier

| Title                | Source                                                                                                                    | License           | Download URL                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------- | ----------------- | --------------------------------------------------------------------- |
| Thunderstorm         | [1 Hour Thunderstorm](https://archive.org/details/1HourThunderstorm)                                                      | CC0/Public Domain | `1 Hour Thunderstorm.mp3`                                             |
| Campfire             | [Relaxing Sounds - Fire](https://archive.org/details/relaxingsounds)                                                      | CC0/Public Domain | `FIRE 2 3h Blazing Fireplace.mp3` or `FIRE 3 4h Roaring Campfire.mp3` |
| Binaural Sleep Waves | [Restorative Sleep - Binaural Beats](https://archive.org/details/RestorativeSleepMusicBinauralBeatsSleepInTheClouds432Hz) | CC0/Public Domain | `Pure Delta Waves (2.5 Hz) Anxiety Relief - 1hr Binaural Beats.mp3`   |

## 📖 Sleep Stories - LibriVox Public Domain

The database specifies custom story titles ("Rainy Night in the Forest", "The Sleepy Village", etc.) that don't exist as pre-narrated content. You have three options:

### Option 1: Use Existing LibriVox Fairy Tales (Recommended for MVP)

Replace custom stories with these public domain narrated tales:

#### Adult/General Stories (Free Tier)

| Original Title            | Replacement                   | Duration | Narrator | Source                                                                                      |
| ------------------------- | ----------------------------- | -------- | -------- | ------------------------------------------------------------------------------------------- |
| Rainy Night in the Forest | Jack and His Golden Snuff-Box | 19:22    | Joy Chan | [English Fairy Tales](https://librivox.org/english-fairy-tales-collected-by-joseph-jacobs/) |
| The Sleepy Village        | Whittington and His Cat       | 18:12    | Joy Chan | [English Fairy Tales](https://librivox.org/english-fairy-tales-collected-by-joseph-jacobs/) |
| Mountain Lake at Dusk     | The Daisy                     | 2:03     | Various  | [Andersen Fairy Tales](https://librivox.org/fairy-tales-by-hans-christian-andersen/)        |
| The Midnight Train        | Jack the Giant-Killer         | 22:55    | Joy Chan | [English Fairy Tales](https://librivox.org/english-fairy-tales-collected-by-joseph-jacobs/) |

#### Premium Stories

| Original Title        | Replacement           | Duration | Narrator | Source                                                                               |
| --------------------- | --------------------- | -------- | -------- | ------------------------------------------------------------------------------------ |
| The Lighthouse Keeper | The Brave Tin Soldier | 5:05     | Various  | [Andersen Fairy Tales](https://librivox.org/fairy-tales-by-hans-christian-andersen/) |
| Autumn in the Orchard | The Ugly Duckling     | 6:27     | Various  | [Andersen Fairy Tales](https://librivox.org/fairy-tales-by-hans-christian-andersen/) |

#### Kids Stories

| Original Title   | Replacement       | Duration | Narrator | Source                                                                               |
| ---------------- | ----------------- | -------- | -------- | ------------------------------------------------------------------------------------ |
| The Sleepy Bear  | Thumbelina        | 6:46     | Various  | [Andersen Fairy Tales](https://librivox.org/fairy-tales-by-hans-christian-andersen/) |
| Starlight Dreams | The Ugly Duckling | 6:27     | Various  | [Andersen Fairy Tales](https://librivox.org/fairy-tales-by-hans-christian-andersen/) |

**LibriVox Download Instructions:**

1. Visit the LibriVox page for the collection
2. Click on individual story links
3. Download MP3 files from Archive.org
4. Process as needed (trim, adjust volume, add intro/outro music)

### Option 2: Create Custom Narrations with AI Text-to-Speech

Use AI TTS services to narrate the custom story scripts:

**Recommended Services:**

- [ElevenLabs](https://elevenlabs.io/) - High-quality, natural-sounding voices ($5-22/month)
- [Play.ht](https://play.ht/) - Good quality, affordable ($19-99/month)
- [Murf.ai](https://murf.ai/) - Professional voice library ($19-99/month)
- [Google Cloud Text-to-Speech](https://cloud.google.com/text-to-speech) - WaveNet voices (pay-per-use)

**Process:**

1. Write the story script (see database descriptions)
2. Generate audio with slow, calming narration
3. Add background ambient sounds (rain, forest, etc.)
4. Export as MP3 at 192kbps

**Legal Note:** Generated AI voices are typically royalty-free for commercial use, but check each service's license.

### Option 3: Hire Voice Actors (Professional Quality)

Platforms for hiring narrators:

- [Fiverr](https://fiverr.com/) - $50-200 per story
- [Voices.com](https://voices.com/) - Professional voice talent
- [Upwork](https://upwork.com/) - Freelance narrators

**Requirements:**

- Request commercial rights
- Specify slow, soothing delivery for sleep content
- Provide detailed script and mood guidance
- Request WAV format for highest quality

## 🔄 Processing Workflow

All audio files should be processed before upload:

```bash
# Trim to desired length (30 minutes for soundscapes)
ffmpeg -i input.mp3 -t 1800 -b:a 192k output.mp3

# Normalize volume
ffmpeg -i input.mp3 -af loudnorm=I=-16:LRA=11:TP=-1.5 -b:a 192k output.mp3

# Fade in/out for smooth looping
ffmpeg -i input.mp3 -af "afade=t=in:ss=0:d=3,afade=t=out:st=1797:d=3" -b:a 192k output.mp3
```

## 📤 Upload Instructions

1. **Process audio files** (see workflow above)
2. **Upload to Supabase Storage:**
   ```bash
   supabase storage --experimental cp /path/to/file.mp3 ss:///sleep-content/soundscapes/filename.m4a --linked
   ```
3. **Update database to mark as active:**
   ```sql
   UPDATE sleep_content
   SET is_active = true
   WHERE title = 'Content Title';
   ```

## 📝 Alternative Free Audio Sources

If Archive.org downloads are difficult:

### Soundscapes

- [Freesound.org](https://freesound.org/) - CC0 and CC-BY sounds, requires account
- [BBC Sound Effects](https://sound-effects.bbcrewind.co.uk/) - 16,000+ effects, personal/educational use
- [Zapsplat](https://www.zapsplat.com/) - Royalty-free, requires attribution
- [YouTube Audio Library](https://studio.youtube.com/channel/UC/music) - Royalty-free music and SFX

### Stories

- [Storynory](https://www.storynory.com/) - Original audio stories for kids (some CC-BY-NC)
- [Loyal Books](http://www.loyalbooks.com/) - Public domain audiobooks
- [Project Gutenberg](https://www.gutenberg.org/) - Public domain texts (combine with TTS)

## ⚖️ License Compliance

All sources listed are either:

- **Public Domain** - No restrictions
- **CC0 (Creative Commons Zero)** - No attribution required
- **CC-BY** - Attribution required (see source)

When using CC-BY content, add attribution in app settings or about page.

## 🎯 Implementation Priority

1. **Phase 1** (MVP): Upload 4 remaining soundscapes (white noise, thunderstorm, campfire, binaural)
2. **Phase 2**: Replace story titles in database with LibriVox equivalents
3. **Phase 3**: Create custom AI narrations or hire voice actors for original stories

## 📊 Database Updates Needed

To use LibriVox stories, update the `sleep_content` table:

```sql
-- Example: Replace "Rainy Night in the Forest" with LibriVox story
UPDATE sleep_content
SET
    title = 'Jack and His Golden Snuff-Box',
    description = 'A classic English fairy tale about a young man who inherits a magical snuff-box.',
    narrator = 'Joy Chan (LibriVox)',
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/jack-golden-snuff-box.m4a',
    duration_seconds = 1162
WHERE title = 'Rainy Night in the Forest';
```

## 🔗 Quick Reference Links

**Sources:**

- [Archive.org Audio](https://archive.org/details/audio)
- [LibriVox](https://librivox.org/)
- [Freesound](https://freesound.org/)
- [Pixabay Audio](https://pixabay.com/sound-effects/)

**Tools:**

- [FFmpeg](https://ffmpeg.org/) - Audio processing
- [Audacity](https://www.audacityteam.org/) - Audio editing (GUI)
- [ElevenLabs](https://elevenlabs.io/) - AI narration
