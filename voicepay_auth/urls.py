from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from drf_spectacular.views import (
    SpectacularAPIView,
    SpectacularSwaggerView,
    SpectacularRedocView,
)
from .api_views import VoiceUserViewSet

# Router for VoiceUser
router = DefaultRouter()
router.register(r"voice-users", VoiceUserViewSet, basename="voiceuser")

urlpatterns = [
    # JWT Token refresh
    path("token/refresh/", TokenRefreshView.as_view(), name="token_refresh"),
    # DRF login/logout
    path("api-auth/", include("rest_framework.urls")),
    # API schema and docs
    path("schema/", SpectacularAPIView.as_view(), name="schema"),
    path(
        "swagger/", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"
    ),
    path("redoc/", SpectacularRedocView.as_view(url_name="schema"), name="redoc"),
    # Router endpoints
    path("", include(router.urls)),
]
