from django.utils import timezone
from rest_framework import serializers
from devices.models import Device, SensorReading

class DeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = ['id', 'name', 'device_id', 'location', 'type', 'is_active', 'last_seen']
        read_only_fields = ['owner']
    
    def create(self, validated_data):
        # Set the owner to the current user
        validated_data['owner'] = self.context['request'].user
        return super().create(validated_data)

class SensorReadingSerializer(serializers.ModelSerializer):
    device_id = serializers.CharField(write_only=True)
    
    class Meta:
        model = SensorReading
        fields = ['id', 'device', 'device_id', 'timestamp', 'temperature', 
                  'humidity', 'pressure', 'voltage', 'custom_data']
        read_only_fields = ['device']
    
    def create(self, validated_data):
        # Get the device based on device_id
        device_id = validated_data.pop('device_id')
        try:
            device = Device.objects.get(device_id=device_id)
            # Update last_seen timestamp
            device.last_seen = validated_data.get('timestamp') or timezone.now()
            device.save()
        except Device.DoesNotExist:
            raise serializers.ValidationError({"device_id": "Device with this ID does not exist"})
        
        # Add the device to the validated data
        validated_data['device'] = device
        return super().create(validated_data)
