# Mothership

The Mothership is the central coordination service for the Trade Gang ecosystem. It acts as a command and control hub, managing communication between various components like data workers (e.g., cf-worker, cf-worker-upbit) and other services (e.g., killer-whale).

## Key Responsibilities

- **Orchestration**: Coordinates tasks and workflows across the distributed system.
- **Communication Relay**: Facilitates message passing between different services using protocols defined in `relay.py`.
- **Proxy Management**: Handles dynamic proxy configuration and updates via `proxy_catcher.py`.
- **Cloudflare Integration**: Interfaces with Cloudflare services as defined in `cloudflare.py`.
- **Deployment**: Provides deployment scripts (`deploy.sh`, `docker.sh`) and containerization support (Dockerfile, docker-compose.yaml) for easy setup and scaling.

## Core Files

- `main.py`: Entry point for the Mothership service.
- `relay.py`: Defines communication protocols and message handling logic.
- `proxy_catcher.py`: Manages proxy configurations and updates.
- `cloudflare.py`: Contains integration logic with Cloudflare services.
- `all_pb2.py`: Generated Protocol Buffer code for service communication.

## Getting Started

1. Ensure dependencies are installed (refer to root `package.json` or `devbox.json`).
2. Configure environment variables as needed.
3. Run the service using `python main.py` or use the provided Docker setup.
