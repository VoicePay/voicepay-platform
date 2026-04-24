from django.contrib import admin
from django.http import JsonResponse
from rest_framework import permissions
from drf_yasg.views import get_schema_view
from drf_yasg import openapi
from django.urls import path, include


def health(request):
    return JsonResponse({"status": "ok"})


schema_view = get_schema_view(
    openapi.Info(
        title="VoicePay API",
        default_version="v1",
        description="API for voice authentication in payments",
        terms_of_service="https://www.google.com/policies/terms/",
        contact=openapi.Contact(email="contact@snippets.local"),
        license=openapi.License(name="BSD License"),
    ),
    public=True,
    permission_classes=[permissions.AllowAny],
)

urlpatterns = [
    path("health/", health),
    path("admin/", admin.site.urls),
    path("", include("django_prometheus.urls")),
    path("", include("voicepay_auth.urls")),
    path(
        "swagger/",
        schema_view.with_ui("swagger", cache_timeout=0),
        name="schema-swagger-ui",
    ),
    path("redoc/", schema_view.with_ui("redoc", cache_timeout=0), name="schema-redoc"),
    path("swagger.json", schema_view.without_ui(cache_timeout=0), name="schema-json"),
]
