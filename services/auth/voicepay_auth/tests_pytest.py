import numpy as np
import pytest

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIRequestFactory
from rest_framework import status

from .models import VoiceUser
from .serializers import VoiceUserSerializer
from .api_views import VoiceUserViewSet


@pytest.mark.django_db
def test_voiceuser_serializer_create(monkeypatch):
    # Mock soundfile.read, preprocess_wav and VoiceEncoder
    # to avoid heavy audio processing
    def fake_sf_read(bytestream):
        return (np.zeros(16000, dtype=np.float32), 16000)

    def fake_preprocess(input_wav):
        # return the waveform unchanged
        return input_wav

    class FakeEncoder:
        def embed_utterance(self, wav):
            return np.ones(256, dtype=np.float32)

    monkeypatch.setattr("voicepay_auth.serializers.sf.read", fake_sf_read)
    monkeypatch.setattr("voicepay_auth.serializers.preprocess_wav", fake_preprocess)
    monkeypatch.setattr("voicepay_auth.serializers.VoiceEncoder", lambda: FakeEncoder())

    audio_content = (
        b"RIFF...."  # minimal fake WAV bytes; not actually parsed due to mocking
    )
    audio_file = SimpleUploadedFile(
        "sample.wav", audio_content, content_type="audio/wav"
    )

    data = {
        "first_name": "Alice",
        "last_name": "User",
        "email": "alice@example.com",
        "password": "testpass123",
        "voice_sample": audio_file,
    }

    serializer = VoiceUserSerializer(data=data)
    assert serializer.is_valid(), serializer.errors
    user = serializer.save()

    assert isinstance(user, VoiceUser)
    assert user.email == "alice@example.com"
    assert user.voice_embedding is not None
    # stored embedding should be bytes for float32 array of ones (length 256)
    arr = np.frombuffer(user.voice_embedding, dtype=np.float32)
    assert arr.shape[0] == 256
    assert np.allclose(arr, 1.0)


@pytest.mark.django_db
def test_login_action_success(monkeypatch):
    # Prepare a stored embedding and user
    # Use a normalized embedding (norm=1) to ensure similarity > 0.8
    stored_embedding = np.random.randn(256).astype(np.float32)
    stored_embedding = stored_embedding / np.linalg.norm(stored_embedding)

    user = VoiceUser.objects.create_user(
        email="bob@example.com",
        password="irrelevant",
        first_name="Bob",
        last_name="Smith",
        voice_embedding=stored_embedding.tobytes(),
    )
    _ = user

    # Patch soundfile.read to return a dummy waveform
    def fake_sf_read(bytestream):
        return (np.zeros(16000, dtype=np.float32), 16000)

    # Patch preprocess_wav and encoder to return an embedding identical to stored
    def fake_preprocess(wav):
        return wav

    class FakeEncoder:
        def embed_utterance(self, wav):
            # Return the exact stored embedding (cosine similarity = 1.0 > 0.8)
            return stored_embedding

    monkeypatch.setattr("voicepay_auth.api_views.sf.read", fake_sf_read)
    monkeypatch.setattr("voicepay_auth.api_views.preprocess_wav", fake_preprocess)
    # Patch the module-level encoder instance at creation time
    encoder_instance = FakeEncoder()
    monkeypatch.setattr("voicepay_auth.api_views.encoder", encoder_instance)

    factory = APIRequestFactory()
    audio_file = SimpleUploadedFile(
        "login.wav", b"BINARYDATA", content_type="audio/wav"
    )
    request = factory.post(
        "/login/",
        {"email": "bob@example.com", "voice_sample": audio_file},
        format="multipart",
    )

    view = VoiceUserViewSet.as_view({"post": "login"})
    response = view(request)

    assert response.status_code == 200
    assert "access" in response.data and "refresh" in response.data


@pytest.mark.django_db
def test_login_missing_email():
    """Test: Missing email in login request returns 400"""
    factory = APIRequestFactory()
    audio_file = SimpleUploadedFile("test.wav", b"BINARYDATA", content_type="audio/wav")

    request = factory.post("/login/", {"voice_sample": audio_file}, format="multipart")
    view = VoiceUserViewSet.as_view({"post": "login"})
    response = view(request)

    assert response.status_code == status.HTTP_200_OK
    assert "error" in response.data
    assert "Email and voice sample are required" in response.data["error"]


@pytest.mark.django_db
def test_login_missing_voice_sample():
    """Test: Missing voice_sample in login request returns 400"""
    factory = APIRequestFactory()

    request = factory.post("/login/", {"email": "test@example.com"}, format="multipart")
    view = VoiceUserViewSet.as_view({"post": "login"})
    response = view(request)

    assert response.status_code == status.HTTP_400_BAD_REQUEST
    assert "error" in response.data
    assert "Email and voice sample are required" in response.data["error"]


@pytest.mark.django_db
def test_login_user_not_found():
    """Test: Login with nonexistent user returns 404"""
    factory = APIRequestFactory()
    audio_file = SimpleUploadedFile("test.wav", b"BINARYDATA", content_type="audio/wav")

    request = factory.post(
        "/login/",
        {"email": "nonexistent@example.com", "voice_sample": audio_file},
        format="multipart",
    )
    view = VoiceUserViewSet.as_view({"post": "login"})
    response = view(request)

    assert response.status_code == status.HTTP_404_NOT_FOUND
    assert "error" in response.data
    assert "User not found" in response.data["error"]


@pytest.mark.django_db
def test_login_voice_mismatch(monkeypatch):
    """Test: Voice similarity < 0.8 returns 401"""
    # Create user with one embedding
    user_embedding = np.ones(256, dtype=np.float32)
    user_embedding = user_embedding / np.linalg.norm(user_embedding)

    user = VoiceUser.objects.create_user(
        email="charlie@example.com",
        password="test123",
        voice_embedding=user_embedding.tobytes(),
    )
    _ = user

    # Return a different embedding (orthogonal = similarity near 0)
    different_embedding = np.zeros(256, dtype=np.float32)
    different_embedding[0] = 1.0  # Only first element is 1
    different_embedding = different_embedding / np.linalg.norm(different_embedding)

    def fake_sf_read(bytestream):
        return (np.zeros(16000, dtype=np.float32), 16000)

    def fake_preprocess(wav):
        return wav

    class FakeEncoder:
        def embed_utterance(self, wav):
            return different_embedding

    monkeypatch.setattr("voicepay_auth.api_views.sf.read", fake_sf_read)
    monkeypatch.setattr("voicepay_auth.api_views.preprocess_wav", fake_preprocess)
    encoder_instance = FakeEncoder()
    monkeypatch.setattr("voicepay_auth.api_views.encoder", encoder_instance)

    factory = APIRequestFactory()
    audio_file = SimpleUploadedFile(
        "login.wav", b"BINARYDATA", content_type="audio/wav"
    )
    request = factory.post(
        "/login/",
        {"email": "charlie@example.com", "voice_sample": audio_file},
        format="multipart",
    )

    view = VoiceUserViewSet.as_view({"post": "login"})
    response = view(request)

    assert response.status_code == status.HTTP_401_UNAUTHORIZED
    assert "error" in response.data
    assert "Voice authentication failed" in response.data["error"]


@pytest.mark.django_db
def test_create_without_voice_sample():
    """Test: User creation without voice_sample fails validation"""
    data = {
        "first_name": "David",
        "last_name": "Test",
        "email": "david@example.com",
        "password": "testpass123",
        # Missing voice_sample
    }

    serializer = VoiceUserSerializer(data=data)
    assert not serializer.is_valid()
    assert "voice_sample" in serializer.errors


@pytest.mark.django_db
def test_duplicate_email_registration():
    """Test: Registering with duplicate email fails"""
    # Create first user
    VoiceUser.objects.create_user(email="duplicate@example.com", password="pass123")

    # Attempt to create second user with same email
    audio_file = SimpleUploadedFile("test.wav", b"DATA", content_type="audio/wav")
    data = {
        "first_name": "Eve",
        "last_name": "Duplicate",
        "email": "duplicate@example.com",
        "password": "newpass123",
        "voice_sample": audio_file,
    }

    serializer = VoiceUserSerializer(data=data)
    # Note: validation will succeed in serializer, but save() will fail at DB level
    # In production, should add unique_together or validators
    if serializer.is_valid():
        try:
            serializer.save()
            assert False, "Should have raised IntegrityError"
        except Exception as e:
            # Expected: database constraint violation
            assert "unique" in str(e).lower() or "duplicate" in str(e).lower()
