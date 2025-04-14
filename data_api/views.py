from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from devices.models import Device, SensorReading
from .serializers import DeviceSerializer, SensorReadingSerializer

class DeviceViewSet(viewsets.ModelViewSet):
    """API endpoint for devices"""
    permission_classes = [IsAuthenticated]
    serializer_class = DeviceSerializer
    
    def get_queryset(self):
        return Device.objects.filter(owner=self.request.user)

class SensorReadingViewSet(viewsets.ModelViewSet):
    """API endpoint for sensor readings"""
    permission_classes = [IsAuthenticated]
    serializer_class = SensorReadingSerializer
    
    def get_queryset(self):
        device_id = self.request.query_params.get('device_id')
        if device_id:
            return SensorReading.objects.filter(
                device__device_id=device_id,
                device__owner=self.request.user
            ).order_by('-timestamp')
        return SensorReading.objects.filter(
            device__owner=self.request.user
        ).order_by('-timestamp')
