from django.contrib import admin
from .models import Device, SensorReading

@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ('name', 'device_id', 'type', 'is_active', 'last_seen', 'owner')
    list_filter = ('is_active', 'type')
    search_fields = ('name', 'device_id', 'owner__username')
    readonly_fields = ('last_seen',)

@admin.register(SensorReading)
class SensorReadingAdmin(admin.ModelAdmin):
    list_display = ('device', 'timestamp', 'temperature', 'humidity', 'pressure', 'voltage')
    list_filter = ('device',)
    date_hierarchy = 'timestamp'
