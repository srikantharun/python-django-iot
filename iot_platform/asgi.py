import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
import devices.routing

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'iot_platform.settings')

application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": AuthMiddlewareStack(
        URLRouter(
            devices.routing.websocket_urlpatterns
        )
    ),
})
