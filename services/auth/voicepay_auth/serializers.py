from rest_framework import serializers
from .models import VoiceUser

from resemblyzer import preprocess_wav, VoiceEncoder
import numpy as np
import io
import soundfile as sf


class VoiceUserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    voice_sample = serializers.FileField(write_only=True)  # Accept raw voice file

    class Meta:
        model = VoiceUser
        fields = ["id", "first_name", "last_name", "email", "password", "voice_sample"]

    def create(self, validated_data):
        voice_file = validated_data.pop("voice_sample")

        # Read the uploaded file as bytes and convert to WAV format
        audio_bytes = voice_file.read()
        wav, sr = sf.read(io.BytesIO(audio_bytes))

        wav = preprocess_wav(wav)
        encoder = VoiceEncoder()
        embedding = encoder.embed_utterance(wav)
        user = VoiceUser.objects.create_user(
            first_name=validated_data.get("first_name"),
            last_name=validated_data.get("last_name"),
            email=validated_data.get("email"),
            password=validated_data.get("password"),
            voice_embedding=embedding.astype(np.float32).tobytes(),  # Store as binary
        )
        return user
