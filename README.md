# IoT Platform

A comprehensive Django-based web platform for managing IoT devices with real-time data monitoring and visualization.

## System Architecture

This platform combines Django's powerful web framework with Go's high-performance capabilities for efficient IoT data collection:

```
+---------------+      +--------------------+      +-------------------+
| IoT Devices   |----->| Data Collection    |----->| Message Broker    |
| (Hardware)    |      | (Go Microservice)  |      | (Redis)           |
+---------------+      +--------------------+      +--------+----------+
                                                           |
                                                           v
+---------------+      +--------------------+      +-------------------+
| Web Frontend  |<-----| Django Web App     |<-----| Database          |
| (HTML/JS/CSS) |      | (Python)           |      | (PostgreSQL)      |
+---------------+      +--------------------+      +-------------------+
```

## Features

- **Device Management**: Register, monitor, and manage IoT devices
- **Real-time Data**: WebSocket integration for live data updates
- **Data Visualization**: Interactive charts for sensor readings
- **REST API**: Complete API for device communication
- **Authentication**: Secure user authentication system
- **Admin Interface**: Django admin for data management

## Installation

### Prerequisites

- Python 3.8+
- Redis server
- PostgreSQL (optional, SQLite works for development)

### Setup Instructions

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/iot-platform.git
   cd iot-platform
   ```

2. Create a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Configure environment variables (or use .env file):
   ```
   DATABASE_URL=postgres://user:password@localhost:5432/iot_platform
   REDIS_HOST=localhost
   REDIS_PORT=6379
   REDIS_PASSWORD=
   SECRET_KEY=your-secret-key
   ```

5. Run migrations:
   ```bash
   python manage.py migrate
   ```

6. Load sample data (optional):
   ```bash
   python manage.py loaddata devices/fixtures/sample_data.json
   ```

7. Create a superuser:
   ```bash
   python manage.py createsuperuser
   ```

8. Run the development server:
   ```bash
   python manage.py runserver
   ```

9. *Note: The Go data collection service code is not included in this repository. You would need to implement it separately following the architecture diagram.*

## Project Structure

```
iot_platform/
├── iot_platform/          # Main project folder
│   ├── settings.py        # Project settings
│   ├── urls.py            # URL routing
│   ├── asgi.py            # ASGI for WebSockets
│   └── wsgi.py            # WSGI for web server
├── devices/               # Django app for devices
│   ├── models.py          # Data models
│   ├── views.py           # View functions/classes
│   ├── urls.py            # App-specific URLs
│   ├── consumers.py       # WebSocket consumers
│   ├── templates/         # HTML templates
│   └── static/            # Static files
├── data_api/              # Django app for API
│   ├── views.py           # API views
│   ├── serializers.py     # DRF serializers
│   └── urls.py            # API URLs
# Note: The Go data collection service would be a separate repository
└── manage.py              # Django command-line tool
```

## API Documentation

### Authentication

The API uses token authentication. To obtain a token:

```http
POST /api/auth/token/
Content-Type: application/json

{
  "username": "your_username",
  "password": "your_password"
}
```

### Devices Endpoints

- `GET /api/devices/` - List all devices
- `POST /api/devices/` - Create a new device
- `GET /api/devices/{id}/` - Get device details
- `PUT /api/devices/{id}/` - Update device
- `DELETE /api/devices/{id}/` - Delete device

### Sensor Readings Endpoints

- `GET /api/readings/` - List all readings
- `GET /api/readings/?device_id=xyz` - Get readings for specific device
- `POST /api/readings/` - Submit new sensor reading

Example sensor reading submission:
```json
{
  "device_id": "device-123",
  "temperature": 23.5,
  "humidity": 45.2,
  "pressure": 1013.2,
  "voltage": 3.3,
  "custom_data": {"light_level": 342}
}
```

## WebSocket Integration

Connect to the WebSocket endpoint to receive real-time updates:

```javascript
const deviceSocket = new WebSocket(
    'ws://' + window.location.host + '/ws/devices/'
);

deviceSocket.onmessage = function(e) {
    const data = JSON.parse(e.data);
    // Process real-time data
};
```

## Data Collection Service (To Be Implemented)

A Go-based data collection service would be needed to complete this architecture. This service should provide an endpoint for devices to send data, such as:

```
POST http://your-server:8080/api/data

{
  "device_id": "device-123",
  "temperature": 23.5,
  "humidity": 45.2
}
```

This component would be responsible for:
1. Receiving data from IoT devices
2. Publishing to Redis for real-time updates
3. Forwarding to Django's REST API for storage

For a sample implementation, see the architecture diagram at the top of this README.

## Development

### Running Tests

```bash
python manage.py test
```

### Code Style

This project follows PEP 8 standards. You can check your code with:

```bash
flake8 .
```

## Production Deployment

For production deployment, consider:

1. Using a proper web server (Nginx, Apache)
2. Setting up HTTPS
3. Using a process manager (Gunicorn, uWSGI)
4. Configuring proper database settings
5. Setting environment variables for secrets

A Docker Compose file is provided for easier deployment.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
