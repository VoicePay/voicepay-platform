import io
import logging
import numpy as np
import soundfile as sf
from resemblyzer import VoiceEncoder, preprocess_wav
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import VoiceUser
from .serializers import VoiceUserSerializer
from rest_framework_simplejwt.tokens import RefreshToken

logger = logging.getLogger(__name__)

encoder = VoiceEncoder()


class VoiceUserViewSet(viewsets.ModelViewSet):
    queryset = VoiceUser.objects.all()
    serializer_class = VoiceUserSerializer

    def create(self, request, *args, **kwargs):
        audio_file = request.FILES.get("voice_sample")
        if not audio_file:
            logger.warning("User registration attempted without voice sample")
            return Response(
                {"error": "Voice sample file is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # Let the serializer handle embedding creation
        return super().create(request, *args, **kwargs)

    @action(detail=False, methods=["post"])
    def login(self, request):
        email = request.data.get("email")
        audio_file = request.FILES.get("voice_sample")

        if not email or not audio_file:
            logger.warning("Login attempted with missing email or voice sample")
            return Response(
                {"error": "Email and voice sample are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            user = VoiceUser.objects.get(email=email)
        except VoiceUser.DoesNotExist:
            logger.warning(
                "Login attempted for non-existent user", extra={"email": email}
            )
            return Response(
                {"error": "User not found."}, status=status.HTTP_404_NOT_FOUND
            )

        wav, sr = sf.read(io.BytesIO(audio_file.read()))
        embedding = encoder.embed_utterance(preprocess_wav(wav))
        stored_embedding = np.frombuffer(user.voice_embedding, dtype=np.float32)
        similarity = np.dot(embedding, stored_embedding) / (
            np.linalg.norm(embedding) * np.linalg.norm(stored_embedding)
        )
        if similarity > 0.8:
            logger.info("Voice login successful", extra={"email": email})
            refresh = RefreshToken.for_user(user)
            return Response(
                {
                    "message": "Login successful.",
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                },
                status=status.HTTP_200_OK,
            )

        logger.warning("Voice authentication failed", extra={"email": email})
        return Response(
            {"error": "Voice authentication failed."},
            status=status.HTTP_401_UNAUTHORIZED,
        )
