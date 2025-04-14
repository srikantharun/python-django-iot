from django.shortcuts import render, get_object_or_404
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse
from django.utils import timezone
from django.db.models import Max

from .models import Device, SensorReading

@login_required
def dashboard(request):
    """Main dashboard view showing all devices and their status"""
    devices = Device.objects.filter(owner=request.user)
    return render(request, 'devices/dashboard.html', {'devices': devices})

@login_required
def device_detail(request, device_id):
    """Detailed view for a specific device"""
    device = get_object_or_404(Device, device_id=device_id, owner=request.user)
    
    # Get latest readings
    latest_reading = SensorReading.objects.filter(device=device).order_by('-timestamp').first()
    
    # Get historical data (last 24 hours)
    yesterday = timezone.now() - timezone.timedelta(days=1)
    historical_data = SensorReading.objects.filter(
        device=device,
        timestamp__gte=yesterday
    ).order_by('timestamp')
    
    return render(request, 'devices/device_detail.html', {
        'device': device,
        'latest_reading': latest_reading,
        'historical_data': historical_data,
    })
