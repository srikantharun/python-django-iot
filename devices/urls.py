from django.urls import path
from . import views

urlpatterns = [
    path('', views.dashboard, name='dashboard'),
    path('device/<str:device_id>/', views.device_detail, name='device_detail'),
]
