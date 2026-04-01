from django.contrib.auth.models import (
    AbstractBaseUser,
    PermissionsMixin,
    BaseUserManager,
)
from django.db import models


class VoiceUserManager(BaseUserManager):
    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError("The Email field must be set")
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)

        return self.create_user(email, password, **extra_fields)


class VoiceUser(AbstractBaseUser, PermissionsMixin):
    email = models.EmailField(unique=True)
    first_name = models.CharField(max_length=100, blank=True)
    last_name = models.CharField(max_length=100, blank=True)
    voice_embedding = models.BinaryField(null=True, blank=True)  # add this

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    objects = VoiceUserManager()

    USERNAME_FIELD = "email"  # Used for login
    REQUIRED_FIELDS = []  # no full_name field on model

    def __str__(self):
        return self.email
