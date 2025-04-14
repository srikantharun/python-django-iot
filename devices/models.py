from django.db import models
from django.contrib.auth.models import User

class Device(models.Model):
    name = models.CharField(max_length=100)
    device_id = models.CharField(max_length=50, unique=True)
    location = models.CharField(max_length=200, blank=True)
    type = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    owner = models.ForeignKey(User, on_delete=models.CASCADE)
    last_seen = models.DateTimeField(null=True, blank=True)
    
    def __str__(self):
        return f"{self.name} ({self.device_id})"

class SensorReading(models.Model):
    device = models.ForeignKey(Device, on_delete=models.CASCADE)
    timestamp = models.DateTimeField(auto_now_add=True)
    temperature = models.FloatField(null=True, blank=True)
    humidity = models.FloatField(null=True, blank=True)
    pressure = models.FloatField(null=True, blank=True)
    voltage = models.FloatField(null=True, blank=True)
    custom_data = models.JSONField(null=True, blank=True)
    
    class Meta:
        indexes = [
            models.Index(fields=['device', 'timestamp']),
        ]
