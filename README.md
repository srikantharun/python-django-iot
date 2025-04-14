# IoT Platform Architecture Overview

## System Components

1. IoT Devices: Hardware sensors and actuators
2. Data Collection Service: Go-based microservice
3. Web Application: Django-based platform
4. Database: PostgreSQL
5. Message Broker: Redis for real-time data

## Architecture Diagram

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
