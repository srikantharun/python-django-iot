import json
import redis
import asyncio
from channels.generic.websocket import AsyncWebsocketConsumer
from django.conf import settings
from asgiref.sync import sync_to_async
from .models import Device

class DeviceConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for real-time device data"""
    
    async def connect(self):
        """Handle WebSocket connection"""
        self.user = self.scope["user"]
        
        # Anonymous users can't connect
        if not self.user.is_authenticated:
            await self.close()
            return
            
        # Accept the connection
        await self.accept()
        
        # Create Redis connection
        self.redis = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            db=settings.REDIS_DB,
            password=settings.REDIS_PASSWORD,
        )
        
        # Start Redis pubsub listener
        self.pubsub = self.redis.pubsub()
        
        # Get all device IDs that belong to the user
        user_devices = await self.get_user_devices()
        
        # Subscribe to device-specific channels
        for device_id in user_devices:
            self.pubsub.subscribe(f"device:{device_id}")
            
        # Also subscribe to all devices channel
        self.pubsub.subscribe("devices:all")
        
        # Start background task to listen for messages
        self.listener_task = asyncio.create_task(self.redis_listener())
    
    @sync_to_async
    def get_user_devices(self):
        """Get all device IDs that belong to the user"""
        return list(Device.objects.filter(owner=self.user).values_list('device_id', flat=True))
    
    async def redis_listener(self):
        """Listen for messages from Redis and forward to WebSocket"""
        while True:
            message = self.pubsub.get_message(ignore_subscribe_messages=True)
            if message:
                data = json.loads(message["data"])
                
                # Check if user owns this device (security check)
                user_devices = await self.get_user_devices()
                if data.get("device_id") in user_devices:
                    # Send to WebSocket
                    await self.send(text_data=json.dumps(data))
            
            # Small sleep to prevent CPU hogging
            await asyncio.sleep(0.01)
    
    async def disconnect(self, close_code):
        """Handle WebSocket disconnection"""
        # Cancel listener task
        if hasattr(self, 'listener_task'):
            self.listener_task.cancel()
            
        # Unsubscribe and close Redis connection
        if hasattr(self, 'pubsub'):
            self.pubsub.unsubscribe()
            self.pubsub.close()
            
        if hasattr(self, 'redis'):
            self.redis.close()
