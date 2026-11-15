"""Local-only Jarvis voice bridge backend (never calls a paid speech API)."""
from __future__ import annotations

import io
import os
import textwrap
import wave
from typing import List

import httpx

from openjarvis.core.registry import TTSRegistry
from openjarvis.speech.tts import TTSBackend, TTSResult

LOCAL_VOICE_URL = f"http://127.0.0.1:{int(os.environ.get('OPENJARVIS_VOICE_PORT', '4701'))}"


@TTSRegistry.register("jarvis_local")
class JarvisLocalTTSBackend(TTSBackend):
    """Calls a separately running, loopback-only local voice synthesizer."""

    backend_id = "jarvis_local"

    def available_voices(self) -> List[str]:
        return ["jarvis-local"]

    def health(self) -> bool:
        try:
            reply = httpx.get(f"{LOCAL_VOICE_URL}/health", timeout=1.5)
            reply.raise_for_status()
            return reply.json().get("ready") is True
        except (httpx.HTTPError, ValueError, TypeError, AttributeError):
            return False

    def synthesize(
        self,
        text: str,
        *,
        voice_id: str = "",
        speed: float = 1.0,
        output_format: str = "mp3",
    ) -> TTSResult:
        if not isinstance(text, str) or not text.strip():
            raise ValueError("No speech text provided")
        if len(text) > 600:
            chunks = textwrap.wrap(text, width=600, break_long_words=True)
            output = io.BytesIO()
            with wave.open(output, "wb") as combined:
                for index, chunk in enumerate(chunks):
                    part = self.synthesize(chunk, voice_id=voice_id, speed=speed, output_format=output_format)
                    with wave.open(io.BytesIO(part.audio), "rb") as segment:
                        if index == 0:
                            combined.setparams(segment.getparams())
                        combined.writeframes(segment.readframes(segment.getnframes()))
            with wave.open(io.BytesIO(output.getvalue()), "rb") as clip:
                return TTSResult(audio=output.getvalue(), format="wav", sample_rate=clip.getframerate(),
                                 duration_seconds=clip.getnframes()/clip.getframerate(),
                                 voice_id=part.voice_id, metadata=part.metadata)
        try:
            reply = httpx.post(
                f"{LOCAL_VOICE_URL}/speak",
                json={"text": text},
                timeout=httpx.Timeout(180.0, connect=2.0),
            )
            reply.raise_for_status()
        except httpx.HTTPError:
            raise RuntimeError(f"Local Jarvis voice service unavailable at {LOCAL_VOICE_URL}") from None
        audio = reply.content
        if not audio.startswith(b"RIFF") or len(audio) < 44:
            raise RuntimeError("Local Jarvis voice service returned invalid WAV audio")
        try:
            with wave.open(io.BytesIO(audio), "rb") as wav:
                sample_rate = wav.getframerate()
                duration = wav.getnframes() / sample_rate
                if wav.getnchannels() not in (1, 2) or wav.getsampwidth() not in (1, 2, 3, 4):
                    raise ValueError("Unexpected WAV format")
        except (wave.Error, ValueError, ZeroDivisionError):
            raise RuntimeError("Local Jarvis voice service returned corrupt WAV data") from None
        return TTSResult(
            audio=audio,
            format="wav",
            sample_rate=sample_rate,
            duration_seconds=duration,
            voice_id="jarvis-local",
            metadata={
                "backend": "jarvis_local",
                "engine": reply.headers.get("X-Jarvis-Voice-Backend", "offline"),
            },
        )
