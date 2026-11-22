"""Generate ticket 12's sample media: python -m tools.content.sample.generate_media.

No Python packages needed. With no ffmpeg, use Flutter's documented sample
video, as ticket 12 permits. The tone, posters and captions are original.
"""

import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import urllib.request
import wave

from .draw_images import save_png

HERE = Path(__file__).resolve().parent
VIDEO_URL = "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4"


def tone(path, seconds=8):
    rate = 16000
    with wave.open(str(path), "wb") as out:
        out.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        out.writeframes(b"".join(struct.pack("<h", round(16000 * math.sin(2 * math.pi * 440 * i / rate)))
                                 for i in range(rate * seconds)))


def main():
    folder = HERE / "sample-media"
    video = folder / "cards" / "sample-video"
    audio = folder / "cards" / "sample-tone"
    video.mkdir(parents=True, exist_ok=True)
    audio.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        subprocess.run([ffmpeg, "-y", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24",
                        "-t", "8", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-movflags", "+faststart", str(video / "video.mp4")], check=True)
        visual = "A silent, generated pattern changes color."
    else:
        urllib.request.urlretrieve(VIDEO_URL, video / "video.mp4")
        visual = "A butterfly moves its wings in a silent Flutter sample video."
    tone(audio / "audio.wav")
    for target in [video, audio]:
        save_png(str(target / "poster.png"), 320, 180,
                 lambda x, y: (15 + x // 4, 110 + y // 4, 120))
    for target, first, second in [
        (video, "[Silent sample video]", visual),
        (audio, "[A steady tone]", "[The tone continues; there is no speech]"),
    ]:
        (target / "captions.vtt").write_text(
            f"WEBVTT\n\n00:00.000 --> 00:03.000\n{first}\n\n00:03.000 --> 00:08.000\n{second}\n",
            encoding="utf-8")
    cards = []
    for cid, fmt, title, media, transcript in [
        ("sample-video", "video", "A short sample video", "video.mp4", visual),
        ("sample-tone", "audio", "A sample tone", "audio.wav", "A steady 440 Hz tone for eight seconds. There is no speech."),
    ]:
        cards.append({"id": cid, "format": fmt, "title": title,
                      "front": "Sample media for testing play, pause, captions and resume.",
                      "media": f"cards/{cid}/{media}", "poster": f"cards/{cid}/poster.png",
                      "captions": f"cards/{cid}/captions.vtt", "transcript": transcript,
                      "duration_seconds": 8, "media_alt": "A teal gradient sample poster."})
    (folder / "source.json").write_text(json.dumps({
        "id": "sample-media", "kind": "other", "is_sample": True, "status": "published",
        "title": "Media player checks (sample)", "topics": ["physics"],
        "description": "Test fixtures only. The fallback butterfly clip is Flutter's documented video_player example; all other media is generated locally.",
        "discover_cards": cards, "practice_cards": [],
    }, indent=2) + "\n", encoding="utf-8")
    assert (video / "video.mp4").stat().st_size > 0
    with wave.open(str(audio / "audio.wav")) as check:
        assert check.getnframes() == check.getframerate() * 8
    print("Generated sample-media: video, tone, two posters and two VTT files.")


if __name__ == "__main__":
    main()
